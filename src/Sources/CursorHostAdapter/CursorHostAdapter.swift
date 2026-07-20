import Foundation
import SessionDomain
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Cursor's public terminal API does not expose a durable terminal identity
/// or cross-window enumeration. These opaque values exist only inside one
/// connected extension endpoint incarnation; they are never names, PIDs,
/// titles, paths, layout coordinates, or deep links.
public struct CursorExtensionEndpointIncarnation: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
}

public struct CursorLiveTerminalReference: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
}

/// The transport authenticates this proof before it reaches the adapter. The
/// adapter retains neither this proof nor any credential after registration.
public struct CursorExtensionAuthenticationProof: Hashable, Sendable, Codable {
    public let keyID: String
    public let proof: Data
    public init(keyID: String, proof: Data) { self.keyID = keyID; self.proof = proof }
    public var isPresent: Bool { !keyID.isEmpty && !proof.isEmpty }
}

public enum CursorHostContract {
    public static let extensionProtocolVersion = 1
    public static let integrationMode = "cursor-extension-live-terminal-v1"
    public static let adapterKind = "cursor-host-extension"
}

/// Explicit, authenticated extension evidence for a live integrated terminal.
/// `sessionIdentity` is the Product-owned owner that the extension observed;
/// a caller cannot associate a reference with another Agent Session.
public struct CursorExtensionLiveTerminalRegistration: Hashable, Sendable, Codable {
    public let endpointID: String
    public let incarnation: CursorExtensionEndpointIncarnation
    public let protocolVersion: Int
    public let cursorVersion: String
    public let sessionIdentity: AgentSessionIdentity
    public let terminalReference: CursorLiveTerminalReference
    public let authentication: CursorExtensionAuthenticationProof

    public init(endpointID: String, incarnation: CursorExtensionEndpointIncarnation, protocolVersion: Int = CursorHostContract.extensionProtocolVersion, cursorVersion: String, sessionIdentity: AgentSessionIdentity, terminalReference: CursorLiveTerminalReference, authentication: CursorExtensionAuthenticationProof) {
        self.endpointID = endpointID; self.incarnation = incarnation; self.protocolVersion = protocolVersion
        self.cursorVersion = cursorVersion; self.sessionIdentity = sessionIdentity
        self.terminalReference = terminalReference; self.authentication = authentication
    }
}

/// Native Agent/Composer source evidence deliberately has no terminal
/// reference. It can establish only a historical Cursor native-thread context.
public struct CursorExtensionNativeThreadRegistration: Hashable, Sendable, Codable {
    public let endpointID: String
    public let incarnation: CursorExtensionEndpointIncarnation
    public let protocolVersion: Int
    public let cursorVersion: String
    public let sessionIdentity: AgentSessionIdentity
    public let authentication: CursorExtensionAuthenticationProof

    public init(endpointID: String, incarnation: CursorExtensionEndpointIncarnation, protocolVersion: Int = CursorHostContract.extensionProtocolVersion, cursorVersion: String, sessionIdentity: AgentSessionIdentity, authentication: CursorExtensionAuthenticationProof) {
        self.endpointID = endpointID; self.incarnation = incarnation; self.protocolVersion = protocolVersion
        self.cursorVersion = cursorVersion; self.sessionIdentity = sessionIdentity; self.authentication = authentication
    }
}

/// A short-lived binding to the extension's in-memory terminal object. It is
/// intentionally insufficient after extension reload, disconnect, or process
/// restart: a newly connected endpoint must never recreate it from metadata.
public struct CursorExtensionEndpointBinding: Hashable, Sendable, Codable {
    public let endpointID: String
    public let incarnation: CursorExtensionEndpointIncarnation
    public let protocolVersion: Int
    public let cursorVersion: String
    public let sessionIdentity: AgentSessionIdentity
    public let terminalReference: CursorLiveTerminalReference?

    public init(endpointID: String, incarnation: CursorExtensionEndpointIncarnation, protocolVersion: Int, cursorVersion: String, sessionIdentity: AgentSessionIdentity, terminalReference: CursorLiveTerminalReference?) {
        self.endpointID = endpointID; self.incarnation = incarnation; self.protocolVersion = protocolVersion
        self.cursorVersion = cursorVersion; self.sessionIdentity = sessionIdentity; self.terminalReference = terminalReference
    }
}

public struct CursorExtensionEndpointStatus: Hashable, Sendable, Codable {
    public let endpointID: String
    public let incarnation: CursorExtensionEndpointIncarnation
    public let protocolVersion: Int
    public let cursorVersion: String
    public let authenticated: Bool
    public let connected: Bool
    public let applicationAvailable: Bool
    /// Count is for the exact opaque reference requested, never an enumerable
    /// terminal list. Values other than one fail closed.
    public let matchingLiveReferenceCount: Int

    public init(endpointID: String, incarnation: CursorExtensionEndpointIncarnation, protocolVersion: Int, cursorVersion: String = "unknown", authenticated: Bool, connected: Bool, applicationAvailable: Bool, matchingLiveReferenceCount: Int) {
        self.endpointID = endpointID; self.incarnation = incarnation; self.protocolVersion = protocolVersion
        self.cursorVersion = cursorVersion; self.authenticated = authenticated; self.connected = connected
        self.applicationAvailable = applicationAvailable; self.matchingLiveReferenceCount = max(0, matchingLiveReferenceCount)
    }
}

/// A separately observed workspace/file proof. It names neither a terminal
/// nor a native Cursor thread, and therefore never upgrades navigation to an
/// exact surface.
public struct CursorWorkspaceFileProof: Hashable, Sendable, Codable {
    public let sessionIdentity: AgentSessionIdentity
    public let workspaceID: String
    public let fileID: String?
    public init(sessionIdentity: AgentSessionIdentity, workspaceID: String, fileID: String? = nil) {
        self.sessionIdentity = sessionIdentity; self.workspaceID = workspaceID; self.fileID = fileID
    }
}

public enum CursorExtensionEndpointFailure: String, Error, Hashable, Sendable, Codable {
    case endpointUnavailable
    case unauthenticated
    case incompatibleProtocol
    case registrationRejected
    case terminalUnavailable
    case dispatchRejected
    case malformedResponse
}

/// The only Cursor extension boundary used by this adapter. It has explicit
/// registration, exact-reference revalidation, and reveal messages. It has no
/// enumeration, deep-link, click, key, accessibility, or terminal-input API.
public protocol CursorExtensionEndpointClient: Sendable {
    func registerLiveTerminal(_ registration: CursorExtensionLiveTerminalRegistration) -> Result<CursorExtensionEndpointBinding, CursorExtensionEndpointFailure>
    func registerNativeThread(_ registration: CursorExtensionNativeThreadRegistration) -> Result<CursorExtensionEndpointBinding, CursorExtensionEndpointFailure>
    func status(for binding: CursorExtensionEndpointBinding) -> Result<CursorExtensionEndpointStatus, CursorExtensionEndpointFailure>
    func workspaceFileProof(for binding: CursorExtensionEndpointBinding, sessionIdentity: AgentSessionIdentity) -> Result<CursorWorkspaceFileProof?, CursorExtensionEndpointFailure>
    func revealLiveTerminal(_ binding: CursorExtensionEndpointBinding) -> Result<Void, CursorExtensionEndpointFailure>
    func revealWorkspaceOrFile(_ proof: CursorWorkspaceFileProof, through binding: CursorExtensionEndpointBinding) -> Result<Void, CursorExtensionEndpointFailure>
}

/// Wire representation for a connected extension message channel. The app
/// composition will supply a mutually authenticated transport in the public
/// registration phase; this production client deliberately does not invent a
/// local terminal object or use a URL as a return route.
public enum CursorExtensionEndpointMessage: Hashable, Sendable, Codable {
    case registerLiveTerminal(CursorExtensionLiveTerminalRegistration)
    case registerNativeThread(CursorExtensionNativeThreadRegistration)
    case status(CursorExtensionEndpointBinding)
    case workspaceFileProof(CursorExtensionEndpointBinding, AgentSessionIdentity)
    case revealLiveTerminal(CursorExtensionEndpointBinding)
    case revealWorkspaceOrFile(CursorWorkspaceFileProof, CursorExtensionEndpointBinding)
}

public enum CursorExtensionEndpointMessageResponse: Hashable, Sendable, Codable {
    case binding(CursorExtensionEndpointBinding)
    case status(CursorExtensionEndpointStatus)
    case workspaceFileProof(CursorWorkspaceFileProof?)
    case acknowledged
}

public protocol CursorExtensionMessageTransport: Sendable {
    func exchange(_ message: CursorExtensionEndpointMessage) -> Result<CursorExtensionEndpointMessageResponse, CursorExtensionEndpointFailure>
}

/// One explicit local endpoint supplied by the installed Cursor extension.
/// Its credential is setup-only sensitive material and is intentionally not
/// Codable, logged, included in diagnostics, or persisted by this adapter.
public struct CursorExtensionLocalEndpoint: Sendable {
    public let socketPath: String
    public let credential: Data
    public init(socketPath: String, credential: Data) { self.socketPath = socketPath; self.credential = credential }
    public var isUsable: Bool { !socketPath.isEmpty && !credential.isEmpty && socketPath.utf8.count < 100 }
}

private struct CursorEndpointWireRequest: Codable { let credential: Data; let message: CursorExtensionEndpointMessage }
private struct CursorEndpointWireResponse: Codable { let response: CursorExtensionEndpointMessageResponse?; let failure: CursorExtensionEndpointFailure? }

/// Synchronous, request-scoped Unix-domain transport to the extension-owned
/// listener. The extension process—not Agent Island—owns live VS Code
/// Terminal objects. Every message carries the setup credential and has a
/// bounded frame; endpoint loss is a normal fail-closed result.
public final class CursorExtensionUnixSocketTransport: @unchecked Sendable, CursorExtensionMessageTransport {
    private let endpoint: CursorExtensionLocalEndpoint
    private let maximumFrameBytes = 64 * 1024
    public init(endpoint: CursorExtensionLocalEndpoint) { self.endpoint = endpoint }

    public func exchange(_ message: CursorExtensionEndpointMessage) -> Result<CursorExtensionEndpointMessageResponse, CursorExtensionEndpointFailure> {
        guard endpoint.isUsable, let request = try? JSONEncoder().encode(CursorEndpointWireRequest(credential: endpoint.credential, message: message)), request.count <= maximumFrameBytes else { return .failure(.endpointUnavailable) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { return .failure(.endpointUnavailable) }; defer { _ = close(fd) }
        guard var address = address(for: endpoint.socketPath) else { return .failure(.endpointUnavailable) }
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sa_family_t>.size + endpoint.socketPath.utf8.count + 1)) } }
        guard connected == 0, writeFrame(request, to: fd), let reply = readFrame(from: fd), let decoded = try? JSONDecoder().decode(CursorEndpointWireResponse.self, from: reply) else { return .failure(.endpointUnavailable) }
        if let response = decoded.response { return .success(response) }
        return .failure(decoded.failure ?? .malformedResponse)
    }

    private func address(for path: String) -> sockaddr_un? {
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else { return nil }
        var value = sockaddr_un(); value.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: value.sun_path)
        path.withCString { source in withUnsafeMutablePointer(to: &value.sun_path) { target in target.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strncpy($0, source, capacity - 1) } } }
        return value
    }
    private func writeFrame(_ body: Data, to fd: Int32) -> Bool {
        var data = Data(); var length = UInt32(body.count).bigEndian; withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }; data.append(body)
        return data.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) == data.count }
    }
    private func readFrame(from fd: Int32) -> Data? {
        var header = [UInt8](repeating: 0, count: 4); guard read(fd, &header, 4) == 4 else { return nil }
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }; guard length <= maximumFrameBytes else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(length)); guard read(fd, &bytes, bytes.count) == bytes.count else { return nil }; return Data(bytes)
    }
}

/// Production client seam for the authenticated, versioned extension message
/// endpoint. The actual IPC listener/extension contribution is intentionally
/// composed later; this type is safe to register because all unsafe fallback
/// mechanisms are absent from its surface.
public final class CursorExtensionMessageClient: @unchecked Sendable, CursorExtensionEndpointClient {
    private let transport: any CursorExtensionMessageTransport
    public init(transport: any CursorExtensionMessageTransport) { self.transport = transport }

    public func registerLiveTerminal(_ registration: CursorExtensionLiveTerminalRegistration) -> Result<CursorExtensionEndpointBinding, CursorExtensionEndpointFailure> {
        guard registration.protocolVersion == CursorHostContract.extensionProtocolVersion, registration.authentication.isPresent else { return .failure(registration.authentication.isPresent ? .incompatibleProtocol : .unauthenticated) }
        return binding(from: transport.exchange(.registerLiveTerminal(registration)))
    }

    public func registerNativeThread(_ registration: CursorExtensionNativeThreadRegistration) -> Result<CursorExtensionEndpointBinding, CursorExtensionEndpointFailure> {
        guard registration.protocolVersion == CursorHostContract.extensionProtocolVersion, registration.authentication.isPresent else { return .failure(registration.authentication.isPresent ? .incompatibleProtocol : .unauthenticated) }
        return binding(from: transport.exchange(.registerNativeThread(registration)))
    }

    public func status(for binding: CursorExtensionEndpointBinding) -> Result<CursorExtensionEndpointStatus, CursorExtensionEndpointFailure> {
        guard binding.protocolVersion == CursorHostContract.extensionProtocolVersion else { return .failure(.incompatibleProtocol) }
        switch transport.exchange(.status(binding)) { case .success(.status(let value)): return .success(value); case .success: return .failure(.malformedResponse); case .failure(let error): return .failure(error) }
    }

    public func workspaceFileProof(for binding: CursorExtensionEndpointBinding, sessionIdentity: AgentSessionIdentity) -> Result<CursorWorkspaceFileProof?, CursorExtensionEndpointFailure> {
        switch transport.exchange(.workspaceFileProof(binding, sessionIdentity)) { case .success(.workspaceFileProof(let value)): return .success(value); case .success: return .failure(.malformedResponse); case .failure(let error): return .failure(error) }
    }

    public func revealLiveTerminal(_ binding: CursorExtensionEndpointBinding) -> Result<Void, CursorExtensionEndpointFailure> { acknowledge(transport.exchange(.revealLiveTerminal(binding))) }
    public func revealWorkspaceOrFile(_ proof: CursorWorkspaceFileProof, through binding: CursorExtensionEndpointBinding) -> Result<Void, CursorExtensionEndpointFailure> { acknowledge(transport.exchange(.revealWorkspaceOrFile(proof, binding))) }

    private func binding(from result: Result<CursorExtensionEndpointMessageResponse, CursorExtensionEndpointFailure>) -> Result<CursorExtensionEndpointBinding, CursorExtensionEndpointFailure> {
        switch result { case .success(.binding(let value)): return .success(value); case .success: return .failure(.malformedResponse); case .failure(let error): return .failure(error) }
    }
    private func acknowledge(_ result: Result<CursorExtensionEndpointMessageResponse, CursorExtensionEndpointFailure>) -> Result<Void, CursorExtensionEndpointFailure> {
        switch result { case .success(.acknowledged): return .success(()); case .success: return .failure(.malformedResponse); case .failure(let error): return .failure(error) }
    }
}

public enum CursorApplicationState: Hashable, Sendable { case available, unavailable }
public protocol CursorApplicationClient: Sendable {
    func status() -> CursorApplicationState
    func activate() -> Result<Void, CursorExtensionEndpointFailure>
}

/// App-only navigation is deliberately separate from the extension endpoint.
/// The app implementation is registered later; it must activate Cursor by its
/// application identity and cannot accept a URL/deep link or terminal target.
public final class CursorApplicationClientUnavailable: @unchecked Sendable, CursorApplicationClient {
    public init() {}
    public func status() -> CursorApplicationState { .unavailable }
    public func activate() -> Result<Void, CursorExtensionEndpointFailure> { .failure(.endpointUnavailable) }
}

/// Production app-only fallback. It activates only an already-running Cursor
/// application by bundle identity; it neither opens a URL nor accepts a
/// workspace, file, terminal, window, keyboard, or pointer target.
public final class CursorNSWorkspaceApplicationClient: @unchecked Sendable, CursorApplicationClient {
    public static let cursorBundleIdentifier = "com.todesktop.230313mzl4w4u92"
    private let bundleIdentifier: String
    public init(bundleIdentifier: String = CursorNSWorkspaceApplicationClient.cursorBundleIdentifier) { self.bundleIdentifier = bundleIdentifier }

    public func status() -> CursorApplicationState {
        #if canImport(AppKit)
        return runningApplication == nil ? .unavailable : .available
        #else
        return .unavailable
        #endif
    }

    public func activate() -> Result<Void, CursorExtensionEndpointFailure> {
        #if canImport(AppKit)
        guard let application = runningApplication else { return .failure(.endpointUnavailable) }
        return application.activate(options: []) ? .success(()) : .failure(.dispatchRejected)
        #else
        return .failure(.endpointUnavailable)
        #endif
    }

    #if canImport(AppKit)
    private var runningApplication: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }
    #endif
}

public final class CursorHostContextCapture: @unchecked Sendable {
    private let endpoint: any CursorExtensionEndpointClient
    public init(endpoint: any CursorExtensionEndpointClient) { self.endpoint = endpoint }

    public func captureLiveTerminal(id: HostContextID, sessionIdentity: AgentSessionIdentity, integrationInstanceID: IntegrationInstanceID, integrationMode: String = CursorHostContract.integrationMode, registration: CursorExtensionLiveTerminalRegistration, at date: Date) -> Result<HostContextAssociation, CursorExtensionEndpointFailure> {
        captureLiveTerminalContext(id: id, sessionIdentity: sessionIdentity, integrationInstanceID: integrationInstanceID, integrationMode: integrationMode, registration: registration, at: date).map(\.association)
    }

    /// The caller retains this pair only in the live composition. Persisting
    /// its association without its binding intentionally downgrades later
    /// attempts to lower fallbacks rather than reconstructing a terminal.
    public func captureLiveTerminalContext(id: HostContextID, sessionIdentity: AgentSessionIdentity, integrationInstanceID: IntegrationInstanceID, integrationMode: String = CursorHostContract.integrationMode, registration: CursorExtensionLiveTerminalRegistration, at date: Date) -> Result<CursorHostCapturedContext, CursorExtensionEndpointFailure> {
        guard registration.sessionIdentity == sessionIdentity else { return .failure(.registrationRejected) }
        switch endpoint.registerLiveTerminal(registration) {
        case .failure(let error): return .failure(error)
        case .success(let binding):
            guard binding.sessionIdentity == sessionIdentity,
                  binding.endpointID == registration.endpointID,
                  binding.incarnation == registration.incarnation,
                  binding.terminalReference == registration.terminalReference,
                  binding.protocolVersion == CursorHostContract.extensionProtocolVersion else { return .failure(.registrationRejected) }
            return .success(.init(association: association(id: id, sessionIdentity: sessionIdentity, integrationInstanceID: integrationInstanceID, integrationMode: integrationMode, binding: binding, locator: .cursorExtensionTerminal(terminalID: registration.terminalReference.rawValue, extensionInstanceID: binding.incarnation.rawValue), evidence: .connectedExtension, at: date), binding: binding))
        }
    }

    public func captureNativeThread(id: HostContextID, sessionIdentity: AgentSessionIdentity, integrationInstanceID: IntegrationInstanceID, integrationMode: String = CursorHostContract.integrationMode, registration: CursorExtensionNativeThreadRegistration, at date: Date) -> Result<HostContextAssociation, CursorExtensionEndpointFailure> {
        captureNativeThreadContext(id: id, sessionIdentity: sessionIdentity, integrationInstanceID: integrationInstanceID, integrationMode: integrationMode, registration: registration, at: date).map(\.association)
    }
    public func captureNativeThreadContext(id: HostContextID, sessionIdentity: AgentSessionIdentity, integrationInstanceID: IntegrationInstanceID, integrationMode: String = CursorHostContract.integrationMode, registration: CursorExtensionNativeThreadRegistration, at date: Date) -> Result<CursorHostCapturedContext, CursorExtensionEndpointFailure> {
        guard registration.sessionIdentity == sessionIdentity else { return .failure(.registrationRejected) }
        switch endpoint.registerNativeThread(registration) {
        case .failure(let error): return .failure(error)
        case .success(let binding):
            guard binding.sessionIdentity == sessionIdentity, binding.terminalReference == nil,
                  binding.endpointID == registration.endpointID, binding.incarnation == registration.incarnation,
                  binding.protocolVersion == CursorHostContract.extensionProtocolVersion else { return .failure(.registrationRejected) }
            return .success(.init(association: association(id: id, sessionIdentity: sessionIdentity, integrationInstanceID: integrationInstanceID, integrationMode: integrationMode, binding: binding, locator: .cursorNativeThread, evidence: .connectedExtension, at: date).historical(), binding: binding))
        }
    }

    private func association(id: HostContextID, sessionIdentity: AgentSessionIdentity, integrationInstanceID: IntegrationInstanceID, integrationMode: String, binding: CursorExtensionEndpointBinding, locator: HostLocator, evidence: HostEvidenceKind, at date: Date) -> HostContextAssociation {
        HostContextAssociation(id: id, sessionIdentity: sessionIdentity, host: .cursor, hostVersion: binding.cursorVersion, integrationInstanceID: integrationInstanceID, integrationMode: integrationMode, incarnation: .init(binding.incarnation.rawValue), locator: locator, provenance: .init(host: .cursor, hostVersion: binding.cursorVersion, endpointID: binding.endpointID, evidence: evidence, observedAt: date, sourceID: CursorHostContract.adapterKind), validity: .live, firstObservedAt: date, lastValidatedAt: date)
    }
}

/// Live-only composition input. The binding is never a durable locator and is
/// discarded on endpoint loss, reload, terminal closure, or app restart.
public struct CursorHostCapturedContext: Hashable, Sendable {
    public let association: HostContextAssociation
    public let binding: CursorExtensionEndpointBinding
    public init(association: HostContextAssociation, binding: CursorExtensionEndpointBinding) { self.association = association; self.binding = binding }
}

public enum CursorHostDiagnosticReason: String, Hashable, Sendable, Codable {
    case exactLiveTerminal
    case nativeThreadNeverExact
    case endpointDisconnected
    case extensionReloaded
    case terminalClosed
    case duplicateLiveReference
    case protocolIncompatible
    case workspaceOrFileProven
    case appOnly
    case unavailable
}

public struct CursorHostNavigationDiagnostic: Hashable, Sendable, Codable {
    public let associationID: HostContextID
    public let reason: CursorHostDiagnosticReason
    public let achievedLevels: Set<HostNavigationLevel>
    public init(associationID: HostContextID, reason: CursorHostDiagnosticReason, achievedLevels: Set<HostNavigationLevel>) { self.associationID = associationID; self.reason = reason; self.achievedLevels = achievedLevels }
}

/// Concrete Cursor Host port. Exact navigation is possible only when this
/// same object still holds an authenticated endpoint binding and the endpoint
/// revalidates one matching live reference immediately before reveal.
public final class CursorHostNavigationPort: @unchecked Sendable, HostNavigationPort {
    private let endpoint: any CursorExtensionEndpointClient
    private let application: any CursorApplicationClient
    private let lock = NSLock()
    private var bindings: [HostContextID: CursorExtensionEndpointBinding] = [:]
    private var workspaceProofs: [HostContextID: CursorWorkspaceFileProof] = [:]
    private var diagnosticsByAssociation: [HostContextID: CursorHostNavigationDiagnostic] = [:]

    public init(endpoint: any CursorExtensionEndpointClient, application: any CursorApplicationClient = CursorNSWorkspaceApplicationClient()) { self.endpoint = endpoint; self.application = application }
    public func retain(_ binding: CursorExtensionEndpointBinding, for associationID: HostContextID) { lock.lock(); bindings[associationID] = binding; lock.unlock() }
    public func retain(_ captured: CursorHostCapturedContext) { retain(captured.binding, for: captured.association.id) }
    public func discardLiveReference(for associationID: HostContextID) { lock.lock(); bindings.removeValue(forKey: associationID); workspaceProofs.removeValue(forKey: associationID); lock.unlock() }
    public func discardAllLiveReferences() { lock.lock(); bindings.removeAll(); workspaceProofs.removeAll(); diagnosticsByAssociation.removeAll(); lock.unlock() }
    public func diagnostic(for associationID: HostContextID) -> CursorHostNavigationDiagnostic? { lock.lock(); defer { lock.unlock() }; return diagnosticsByAssociation[associationID] }

    public func revalidate(_ association: HostContextAssociation, for sessionIdentity: AgentSessionIdentity, negotiation: NegotiationSnapshot?, at date: Date) -> HostNavigationRevalidation {
        guard association.host == .cursor else { return unavailable(association, sessionIdentity, negotiation, date, reason: .unavailable) }
        lock.lock(); let binding = bindings[association.id]; lock.unlock()
        let appAvailable = application.status() == .available
        guard let binding else { return observationResult(association, sessionIdentity, negotiation, date, binding: nil, status: nil, appAvailable: appAvailable, diagnostic: appAvailable ? .appOnly : .unavailable) }
        guard binding.sessionIdentity == association.sessionIdentity else { return unavailable(association, sessionIdentity, negotiation, date, reason: .unavailable) }
        switch endpoint.status(for: binding) {
        case .failure:
            return observationResult(association, sessionIdentity, negotiation, date, binding: binding, status: nil, appAvailable: appAvailable, diagnostic: appAvailable ? .endpointDisconnected : .unavailable)
        case .success(let status):
            return observationResult(association, sessionIdentity, negotiation, date, binding: binding, status: status, appAvailable: appAvailable, diagnostic: diagnostic(for: association, binding: binding, status: status))
        }
    }

    public func navigate(_ target: HostNavigationTarget, at date: Date) -> HostNavigationDispatch {
        guard target.host == .cursor else { return .rejected(.unsupportedHost) }
        lock.lock(); let binding = bindings[target.associationID]; let proof = workspaceProofs[target.associationID]; lock.unlock()
        switch target.level {
        case .exactSurface:
            guard let binding, binding.terminalReference != nil else { return .rejected(.incarnationChanged) }
            // The endpoint must re-resolve the retained live reference during
            // reveal, closing the final race with terminal closure/reload.
            switch endpoint.revealLiveTerminal(binding) { case .success: return .reached; case .failure(.terminalUnavailable): return .rejected(.locatorClosed); case .failure(.incompatibleProtocol): return .rejected(.runtimeVersionChanged); case .failure: return .rejected(.dispatchFailed) }
        case .workspaceOrFile:
            guard let binding, let proof, proof.sessionIdentity == target.sessionIdentity else { return .rejected(.noSeparatelyProvenFallback) }
            switch endpoint.revealWorkspaceOrFile(proof, through: binding) { case .success: return .reached; case .failure: return .rejected(.dispatchFailed) }
        case .appOnly:
            switch application.activate() { case .success: return .reached; case .failure: return .rejected(.hostUnavailable) }
        default: return .rejected(.noSeparatelyProvenFallback)
        }
    }

    private func observationResult(_ association: HostContextAssociation, _ sessionIdentity: AgentSessionIdentity, _ negotiation: NegotiationSnapshot?, _ date: Date, binding: CursorExtensionEndpointBinding?, status: CursorExtensionEndpointStatus?, appAvailable: Bool, diagnostic: CursorHostDiagnosticReason) -> HostNavigationRevalidation {
        let expectedTerminal = binding?.terminalReference
        let statusMatchesBinding = status.map { $0.endpointID == binding?.endpointID && $0.incarnation == binding?.incarnation } ?? false
        let protocolMatches = status?.protocolVersion == CursorHostContract.extensionProtocolVersion && binding?.protocolVersion == CursorHostContract.extensionProtocolVersion
        let exact = expectedTerminal != nil && status?.authenticated == true && status?.connected == true && statusMatchesBinding && protocolMatches && status?.matchingLiveReferenceCount == 1
        var levels: Set<HostNavigationLevel> = []
        if exact { levels.insert(.exactSurface) }
        if appAvailable { levels.insert(.appOnly) }
        var workspace: CursorWorkspaceFileProof?
        if let binding, case .success(let proof) = endpoint.workspaceFileProof(for: binding, sessionIdentity: sessionIdentity), let proof, proof.sessionIdentity == sessionIdentity, !proof.workspaceID.isEmpty {
            workspace = proof; levels.insert(.workspaceOrFile)
        }
        lock.lock()
        if let workspace { workspaceProofs[association.id] = workspace } else { workspaceProofs.removeValue(forKey: association.id) }
        let state: HostLocatorState
        if diagnostic == .protocolIncompatible || diagnostic == .extensionReloaded { state = .recreated }
        else if diagnostic == .terminalClosed { state = .closed }
        else if diagnostic == .duplicateLiveReference { state = .ambiguous }
        else if diagnostic == .endpointDisconnected { state = .unavailable }
        else { state = .live }
        // Workspace/file and app activation are distinct one-candidate
        // fallbacks. A zero/duplicate terminal-reference count therefore
        // cannot make either non-terminal fallback ambiguous.
        let candidateCount = (workspace != nil || appAvailable) ? 1 : (status?.matchingLiveReferenceCount ?? 0)
        let observation = HostRuntimeObservation(host: .cursor, hostVersion: status?.cursorVersion ?? association.hostVersion, integrationMode: association.integrationMode, endpointID: statusMatchesBinding ? status?.endpointID : nil, incarnation: statusMatchesBinding ? HostIncarnation(status!.incarnation.rawValue) : nil, applicationState: appAvailable ? .available : .endpointLost, locatorState: state, provenLevels: levels, candidateCount: candidateCount, extensionInstanceID: statusMatchesBinding ? status?.incarnation.rawValue : nil, connectedExtensionTerminalID: exact ? expectedTerminal?.rawValue : nil, connectedExtensionTerminal: exact, workspaceOrFileProven: workspace != nil, provenWorkspaceID: workspace?.workspaceID, provenFileID: workspace?.fileID)
        var result = HostNavigationPolicy.revalidate(association: association, sessionIdentity: sessionIdentity, negotiation: negotiation, observation: observation, at: date)
        if diagnostic == .protocolIncompatible { result = replacingReason(result, .runtimeVersionChanged) }
        if diagnostic == .extensionReloaded { result = replacingReason(result, .extensionReloaded) }
        diagnosticsByAssociation[association.id] = .init(associationID: association.id, reason: diagnostic, achievedLevels: result.provenLevels)
        lock.unlock()
        return result
    }

    private func diagnostic(for association: HostContextAssociation, binding: CursorExtensionEndpointBinding, status: CursorExtensionEndpointStatus) -> CursorHostDiagnosticReason {
        guard status.connected else { return .endpointDisconnected }
        guard status.protocolVersion == CursorHostContract.extensionProtocolVersion, binding.protocolVersion == CursorHostContract.extensionProtocolVersion else { return .protocolIncompatible }
        guard status.endpointID == binding.endpointID, status.incarnation == binding.incarnation else { return .extensionReloaded }
        guard binding.terminalReference != nil else { return .nativeThreadNeverExact }
        if status.matchingLiveReferenceCount == 0 { return .terminalClosed }
        if status.matchingLiveReferenceCount != 1 { return .duplicateLiveReference }
        return .exactLiveTerminal
    }

    private func unavailable(_ association: HostContextAssociation, _ sessionIdentity: AgentSessionIdentity, _ negotiation: NegotiationSnapshot?, _ date: Date, reason: CursorHostDiagnosticReason) -> HostNavigationRevalidation {
        observationResult(association, sessionIdentity, negotiation, date, binding: nil, status: nil, appAvailable: false, diagnostic: reason)
    }

    private func replacingReason(_ value: HostNavigationRevalidation, _ reason: HostNavigationRevalidationReason) -> HostNavigationRevalidation {
        .init(associationID: value.associationID, sessionIdentity: value.sessionIdentity, host: value.host, integrationMode: value.integrationMode, capabilityID: value.capabilityID, capabilityRevision: value.capabilityRevision, permission: value.permission, locatorState: value.locatorState, incarnation: value.incarnation, provenLevels: value.provenLevels, candidateCount: value.candidateCount, evaluatedAt: value.evaluatedAt, ownershipMatches: value.ownershipMatches, hostMatches: value.hostMatches, modeMatches: value.modeMatches, capabilityGranted: value.capabilityGranted, permissionGranted: value.permissionGranted, locatorMatches: value.locatorMatches, incarnationMatches: value.incarnationMatches, reason: reason)
    }
}

/// App-root composition for currently connected Cursor extension evidence.
/// It deliberately keeps bindings only in memory and routes only Cursor
/// associations, leaving iTerm2 and every other Host implementation intact.
@MainActor
public final class CursorHostNavigationComposition {
    private var evidence = HostContextEvidenceStore()
    private var negotiations: [IntegrationInstanceID: NegotiationSnapshot] = [:]
    private let port: CursorHostNavigationPort
    public private(set) var attempts: [JumpBackAttemptRecord] = []

    public init(port: CursorHostNavigationPort) { self.port = port }
    public func record(_ captured: CursorHostCapturedContext) { evidence.record(captured.association); port.retain(captured) }
    public func recordNative(_ association: HostContextAssociation, binding: CursorExtensionEndpointBinding) { guard association.host == .cursor else { return }; evidence.record(association); port.retain(binding, for: association.id) }
    public func register(navigationNegotiation snapshot: NegotiationSnapshot) { negotiations[snapshot.integrationInstanceID] = snapshot }
    public func associations(for identity: AgentSessionIdentity) -> [HostContextAssociation] { evidence.associations(for: identity) }
    public func disconnect(associationID: HostContextID, reason: HostContextInvalidationReason = .endpointLost, at date: Date = Date()) { port.discardLiveReference(for: associationID); evidence.invalidate(associationID, reason: reason, at: date) }
    public func invalidateAllLocators(reason: HostContextInvalidationReason, at date: Date = Date()) {
        port.discardAllLiveReferences()
        evidence.invalidateAll(reason: reason, at: date)
    }
    public func jumpBack(for identity: AgentSessionIdentity, at date: Date = Date()) -> JumpBackOutcome {
        let candidates = evidence.associations(for: identity).filter { $0.host == .cursor && negotiations[$0.integrationInstanceID] != nil }
        guard candidates.count == 1, let candidate = candidates.first, let negotiation = negotiations[candidate.integrationInstanceID] else {
            let outcome = JumpBackOutcome(sessionIdentity: identity, host: .cursor, qualifier: .unavailable, occurredAt: date, reason: candidates.isEmpty ? .noAssociation : .ambiguous(level: .exactSurface))
            attempts.append(.init(attemptID: "", sessionIdentity: identity, trigger: .explicitPersonAction, candidateAssociationID: nil, candidateLocator: nil, outcome: outcome)); return outcome
        }
        let attempt = JumpBackCoordinator(evidence: .init([candidate]), port: port).attempt(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: date))
        attempts.append(attempt)
        if let diagnostic = port.diagnostic(for: candidate.id), diagnostic.reason == .endpointDisconnected || diagnostic.reason == .extensionReloaded || diagnostic.reason == .terminalClosed || diagnostic.reason == .protocolIncompatible { disconnect(associationID: candidate.id, reason: diagnostic.reason == .terminalClosed ? .locatorClosed : .extensionReloaded, at: date) }
        return attempt.outcome
    }
}
