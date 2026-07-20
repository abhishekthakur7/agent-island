import Foundation
import SessionDomain
#if canImport(Network)
import Network
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(Security)
import Security
#endif

/// Framed local IPC is deliberately transport-agnostic so the helper can be
/// exercised without a live socket. Production composition supplies the
/// app-owned Unix-domain transport; tests use the in-memory implementation.
public enum ClaudeHookHelperError: Error, Codable, Equatable, Sendable {
    case emptyAuthenticator
    case oversizedStdin
    case malformedJSON
    case endpointUnavailable
    case endpointUntrusted
    case frameTooLarge
    case transportTimeout
    case transportFailure
    case credentialMissing
    case credentialInvalid
}

/// The app provisions one short-lived Keychain generic-password entry per
/// installation/helper tuple. The documented hook launcher never contains the
/// secret; a missing, wrong, or rotated entry fails closed at helper startup.
public protocol ClaudeHookCredentialStore: Sendable {
    func secret(for installationID: IntegrationInstanceID, helperID: String) -> Data?
}

public struct InMemoryClaudeHookCredentialStore: ClaudeHookCredentialStore, Sendable {
    private let value: Data?
    private let owner: String?
    public init(secret: Data?, installationID: IntegrationInstanceID? = nil, helperID: String? = nil) {
        self.value = secret
        self.owner = installationID.map { "\($0.rawValue)/\(helperID ?? "")" }
    }
    public func secret(for installationID: IntegrationInstanceID, helperID: String) -> Data? {
        guard let owner else { return value }
        return owner == "\(installationID.rawValue)/\(helperID)" ? value : nil
    }
}

#if canImport(Security)
public struct KeychainClaudeHookCredentialStore: ClaudeHookCredentialStore, Sendable {
    public static let service = "com.agent-island.claude-hooks"
    public init() {}
    public func secret(for installationID: IntegrationInstanceID, helperID: String) -> Data? {
        let account = "\(installationID.rawValue)/\(helperID)"
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return (item as? Data).flatMap { $0.isEmpty ? nil : $0 }
    }

    public func save(secret: Data, for installationID: IntegrationInstanceID, helperID: String) throws {
        guard !secret.isEmpty else { throw ClaudeHookHelperError.credentialInvalid }
        let account = "\(installationID.rawValue)/\(helperID)"
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: account]
        let attributes: [CFString: Any] = [kSecValueData: secret]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { let add: [CFString: Any] = query.merging(attributes) { _, new in new }.merging([kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { _, new in new }; guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw ClaudeHookHelperError.credentialInvalid } }
        else if status != errSecSuccess { throw ClaudeHookHelperError.credentialInvalid }
    }
}
#endif

public struct ClaudeLocalEndpoint: Codable, Hashable, Sendable {
    public let path: String
    public let appOwnedRoot: String
    public let expectedOwnerUID: UInt32?

    public init(path: URL, appOwnedRoot: URL, expectedOwnerUID: UInt32? = nil) {
        self.path = path.path; self.appOwnedRoot = appOwnedRoot.standardizedFileURL.path; self.expectedOwnerUID = expectedOwnerUID ?? Self.currentUID
    }

    private static var currentUID: UInt32 {
        #if canImport(Darwin) || canImport(Glibc)
        return UInt32(getuid())
        #else
        return 0
        #endif
    }

    public func validate() -> Result<Void, ClaudeHookHelperError> {
        let endpointURL = URL(fileURLWithPath: path).standardizedFileURL
        let rootURL = URL(fileURLWithPath: appOwnedRoot).standardizedFileURL
        let endpoint = endpointURL.path
        let root = rootURL.path
        guard endpoint != root,
              endpoint.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { return .failure(.endpointUntrusted) }
        let fm = FileManager.default
        // Reject a symlink at the root, endpoint, or any ancestor. A lexical
        // prefix check alone permits a Product-controlled symlink to escape an
        // otherwise app-owned directory.
        guard rootURL.resolvingSymlinksInPath().standardizedFileURL.path == root,
              endpointURL.resolvingSymlinksInPath().standardizedFileURL.path == endpoint,
              let rootAttributes = try? fm.attributesOfItem(atPath: root),
              (rootAttributes[.type] as? FileAttributeType) == .typeDirectory else { return .failure(.endpointUntrusted) }
        guard let rootMode = rootAttributes[.posixPermissions] as? NSNumber,
              (rootMode.uint16Value & 0o022) == 0 else { return .failure(.endpointUntrusted) }
        if let expectedOwnerUID {
            guard let rootOwner = rootAttributes[.ownerAccountID] as? NSNumber,
                  rootOwner.uint32Value == expectedOwnerUID else { return .failure(.endpointUntrusted) }
        }
        guard let attrs = try? fm.attributesOfItem(atPath: path), let mode = attrs[.posixPermissions] as? NSNumber else { return .failure(.endpointUnavailable) }
        guard (mode.uint16Value & 0o022) == 0 else { return .failure(.endpointUntrusted) }
        if let expectedOwnerUID {
            guard let actual = attrs[.ownerAccountID] as? NSNumber, actual.uint32Value == expectedOwnerUID else { return .failure(.endpointUntrusted) }
        }
        guard (try? fm.destinationOfSymbolicLink(atPath: path)) == nil else { return .failure(.endpointUntrusted) }
        return .success(())
    }
}

public protocol ClaudeHookIPCTransport: Sendable {
    func send(frame: Data, timeout: TimeInterval) async throws
}

public struct ClaudeHookIPCFrame: Sendable {
    public static let magic = Data([0x41, 0x49, 0x43, 0x48]) // AICH
    public static let version: UInt8 = 1
    public static let maxFrameBytes = SessionDomainValidator.maxPayloadBytes + 4096

    public static func encode(_ message: ClaudeHookIPCMessage) throws -> Data {
        let body = try JSONEncoder().encode(message)
        guard body.count <= maxFrameBytes else { throw ClaudeHookHelperError.frameTooLarge }
        var frame = Data(magic); frame.append(version)
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(body); return frame
    }

    public static func decode(_ frame: Data) throws -> ClaudeHookIPCMessage {
        guard frame.count >= magic.count + 5, frame.prefix(magic.count) == magic, frame[magic.count] == version else { throw ClaudeHookHelperError.transportFailure }
        let lengthOffset = magic.count + 1
        let length = frame[lengthOffset..<(lengthOffset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard Int(length) <= SessionDomainValidator.maxPayloadBytes + 4096, frame.count == lengthOffset + 4 + Int(length) else { throw ClaudeHookHelperError.frameTooLarge }
        do {
            let message = try JSONDecoder().decode(ClaudeHookIPCMessage.self, from: frame.suffix(Int(length)))
            guard message.payload.count <= SessionDomainValidator.maxPayloadBytes else { throw ClaudeHookHelperError.oversizedStdin }
            return message
        } catch let error as ClaudeHookHelperError { throw error } catch { throw ClaudeHookHelperError.malformedJSON }
    }
}

public actor ClaudeInMemoryHookIPCTransport: ClaudeHookIPCTransport {
    public private(set) var frames: [Data] = []
    public init() {}
    public func send(frame: Data, timeout: TimeInterval) async throws { guard frame.count <= ClaudeHookIPCFrame.maxFrameBytes else { throw ClaudeHookHelperError.frameTooLarge }; frames.append(frame) }
}

#if canImport(Network)
/// Production transport: an app-owned Unix-domain endpoint. Network.framework
/// performs peer-local delivery; endpoint ownership/permissions are checked
/// before the connection is opened.
public final class ClaudeUnixDomainHookIPCTransport: ClaudeHookIPCTransport, @unchecked Sendable {
    public let endpoint: ClaudeLocalEndpoint
    public init(endpoint: ClaudeLocalEndpoint) { self.endpoint = endpoint }

    public func send(frame: Data, timeout: TimeInterval) async throws {
        switch endpoint.validate() {
        case .success: break
        case .failure(let error): throw error
        }
        guard let kind = try? FileManager.default.attributesOfItem(atPath: endpoint.path)[.type] as? FileAttributeType, kind == .typeSocket else { throw ClaudeHookHelperError.endpointUnavailable }
        let connection = NWConnection(to: .unix(path: endpoint.path), using: .tcp)
        let completion = ClaudeIPCCompletion(connection: connection)
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                completion.install(continuation)
                completion.timeout(after: timeout)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.send(content: frame, completion: .contentProcessed { error in
                            if let error { completion.finish(.failure(error)) }
                            else { completion.finish(.success(())) }
                        })
                    case .failed(let error): completion.finish(.failure(error))
                    case .cancelled: completion.finish(.failure(ClaudeHookHelperError.transportFailure))
                    default: break
                    }
                }
                connection.start(queue: .global(qos: .utility))
            }
        }, onCancel: {
            completion.finish(.failure(ClaudeHookHelperError.transportFailure))
        })
    }
}

/// Network callbacks may report ready, send completion, failure, cancellation,
/// and timeout concurrently. This one-shot gate is the only continuation owner.
private final class ClaudeIPCCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(connection: NWConnection) { self.connection = connection }

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
    }

    func timeout(after seconds: TimeInterval) {
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.finish(.failure(ClaudeHookHelperError.transportTimeout))
        }
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()
        guard let continuation else { return }
        timeoutTask?.cancel()
        connection.cancel()
        continuation.resume(with: result)
    }
}
#endif

/// Validates hook stdin, creates a fresh authenticated nonce envelope, and
/// sends exactly one length-framed message to an app-owned endpoint. It never
/// logs or persists the payload, secret, endpoint path, or command text.
public struct ClaudeHookHelperRuntime: Sendable {
    public let installationID: IntegrationInstanceID
    public let helperID: String
    public let authenticator: ClaudeIPCAuthenticator
    public let endpoint: ClaudeLocalEndpoint
    public let clockSkew: TimeInterval
    public let timeout: TimeInterval

    public init(installationID: IntegrationInstanceID, helperID: String, authenticator: ClaudeIPCAuthenticator, endpoint: ClaudeLocalEndpoint, clockSkew: TimeInterval = 120, timeout: TimeInterval = 2) {
        self.installationID = installationID; self.helperID = helperID; self.authenticator = authenticator; self.endpoint = endpoint; self.clockSkew = clockSkew; self.timeout = timeout
    }

    public init(installationID: IntegrationInstanceID, helperID: String, credentialStore: any ClaudeHookCredentialStore, endpoint: ClaudeLocalEndpoint, clockSkew: TimeInterval = 120, timeout: TimeInterval = 2) throws {
        guard let secret = credentialStore.secret(for: installationID, helperID: helperID), !secret.isEmpty else { throw ClaudeHookHelperError.credentialMissing }
        self.init(installationID: installationID, helperID: helperID, authenticator: ClaudeIPCAuthenticator(secret: secret), endpoint: endpoint, clockSkew: clockSkew, timeout: timeout)
    }

    @discardableResult
    public func forward(stdin: Data, now: Date = Date(), transport: any ClaudeHookIPCTransport) async throws -> ClaudeHookIPCMessage {
        guard authenticator.isUsable else { throw ClaudeHookHelperError.emptyAuthenticator }
        guard stdin.count <= SessionDomainValidator.maxPayloadBytes else { throw ClaudeHookHelperError.oversizedStdin }
        guard (try? ClaudeHookEnvelope.decode(stdin)) != nil else { throw ClaudeHookHelperError.malformedJSON }
        guard case .success = endpoint.validate() else { throw ClaudeHookHelperError.endpointUntrusted }
        let nonce = UUID().uuidString
        let message = ClaudeHookIPCMessage(installationID: installationID, helperID: helperID, nonce: nonce, payload: stdin, issuedAt: now, authenticator: authenticator)
        let frame = try ClaudeHookIPCFrame.encode(message)
        try await transport.send(frame: frame, timeout: timeout)
        return message
    }
}
