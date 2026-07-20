import Foundation
import ClaudeCodeAdapter
import SessionStore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// App-owned, fail-closed Unix-domain endpoint for action callbacks.  It is
/// deliberately separate from AB-134 observation frames and only accepts one
/// AICA request before retaining the connection as a one-shot reply channel.
public final class ClaudeUnixDomainActionServer: @unchecked Sendable {
    public let endpoint: ClaudeLocalEndpoint
    private let listener: ClaudeActionRequestListener
    private let lock = NSLock()
    private var socketFD: Int32 = -1
    private var acceptTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var framingConnections = 0
    private let maximumFramingConnections = 32

    public init(endpoint: ClaudeLocalEndpoint, listener: ClaudeActionRequestListener) {
        self.endpoint = endpoint
        self.listener = listener
    }

    /// Endpoint setup is intentionally owned by the app, never the helper.
    /// Existing entries are removed only after they prove to be a secure,
    /// app-owned socket at this exact fixed action endpoint.
    public func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard socketFD < 0 else { return }
        try prepareRootAndEndpoint()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClaudeHookHelperError.endpointUnavailable }
        do {
            var address = try unixAddress(endpoint.path)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, unixAddressLength(endpoint.path)) }
            }
            guard result == 0, chmod(endpoint.path, 0o600) == 0, listen(fd, 16) == 0 else {
                _ = close(fd); throw ClaudeHookHelperError.endpointUnavailable
            }
            guard case .success = endpoint.validate() else { _ = close(fd); try? FileManager.default.removeItem(atPath: endpoint.path); throw ClaudeHookHelperError.endpointUntrusted }
            socketFD = fd
            acceptTask = Task.detached(priority: .utility) { [weak self] in await self?.acceptLoop(fd) }
            expiryTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    await self?.listener.expire(at: Date())
                }
            }
        } catch {
            _ = close(fd)
            throw error
        }
    }

    /// Stopping a listener is an incarnation boundary: no connection, nonce,
    /// or lease is recovered by a later listener instance.
    public func stop() async {
        let state = lock.withLock { () -> (Int32, Task<Void, Never>?, Task<Void, Never>?) in
            let fd = socketFD; socketFD = -1
            let acceptTask = self.acceptTask; self.acceptTask = nil
            let expiryTask = self.expiryTask; self.expiryTask = nil
            return (fd, acceptTask, expiryTask)
        }
        let (fd, acceptTask, expiryTask) = state
        expiryTask?.cancel(); acceptTask?.cancel()
        if fd >= 0 { _ = systemClose(fd) }
        try? FileManager.default.removeItem(atPath: endpoint.path)
        await listener.retireAll(reason: .helperUnavailable)
    }

    private func acceptLoop(_ fd: Int32) async {
        while !Task.isCancelled {
            let client = accept(fd, nil, nil)
            if client < 0 { break }
            let admitted = lock.withLock { () -> Bool in
                guard framingConnections < maximumFramingConnections else { return false }
                framingConnections += 1
                return true
            }
            guard admitted else { _ = systemClose(client); continue }
            Task.detached(priority: .userInitiated) { [listener] in
                defer { self.lock.withLock { self.framingConnections -= 1 } }
                let channel = ClaudeUnixDomainActionReplyChannel(fd: client)
                guard let frame = ClaudeUnixDomainActionServer.readFrame(from: client),
                      let request = try? ClaudeHookActionIPCFrame.decode(frame, as: ClaudeHelperActionRequest.self)
                else { await channel.close(); return }
                let accepted = await listener.receive(request, channel: channel)
                if !accepted { await channel.close() }
            }
        }
    }

    private func prepareRootAndEndpoint() throws {
        let root = URL(fileURLWithPath: endpoint.appOwnedRoot)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: root.path)
        guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.standardizedFileURL.path else { throw ClaudeHookHelperError.endpointUntrusted }
        if FileManager.default.fileExists(atPath: endpoint.path) {
            guard case .success = endpoint.validate(),
                  (try? FileManager.default.attributesOfItem(atPath: endpoint.path)[.type] as? FileAttributeType) == .typeSocket
            else { throw ClaudeHookHelperError.endpointUntrusted }
            try FileManager.default.removeItem(atPath: endpoint.path)
        }
    }

    private func unixAddress(_ path: String) throws -> sockaddr_un {
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else { throw ClaudeHookHelperError.endpointUnavailable }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strncpy($0, source, capacity - 1) }
            }
        }
        return address
    }

    private func unixAddressLength(_ path: String) -> socklen_t { socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1) }

    private static func readFrame(from fd: Int32) -> Data? {
        let headerSize = 9
        guard let header = readExactly(fd, count: headerSize), header.prefix(4) == Data([0x41, 0x49, 0x43, 0x41]), header[4] == 1 else { return nil }
        let length = header[5..<9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= UInt32(ClaudeHookIPCFrame.maxFrameBytes), let body = readExactly(fd, count: Int(length)) else { return nil }
        return header + body
    }

    private static func readExactly(_ fd: Int32, count: Int) -> Data? {
        var data = Data(); data.reserveCapacity(count)
        while data.count < count {
            var buffer = [UInt8](repeating: 0, count: count - data.count)
            let received = buffer.withUnsafeMutableBytes { systemRead(fd, $0.baseAddress!, $0.count) }
            guard received > 0 else { return nil }
            data.append(buffer, count: Int(received))
        }
        return data
    }
}

/// Concrete production composition.  Setup supplies an already-negotiated,
/// app-local credential configuration; absence or failure is deliberately
/// nonfatal and leaves Claude's native Host path untouched.
public final class ClaudeActionProductionComposition: @unchecked Sendable {
    public let service: ClaudeGuidedActionService
    public let server: ClaudeUnixDomainActionServer

    public init(endpoint: ClaudeLocalEndpoint, configuration: ClaudeActionRequestListener.Configuration, store: ActionAttemptStore = ActionAttemptStore()) {
        let service = ClaudeGuidedActionService(configuration: configuration, store: store)
        self.service = service
        self.server = ClaudeUnixDomainActionServer(endpoint: endpoint, listener: service.listener)
    }

    /// Failure deliberately has no diagnostic payload: endpoint paths,
    /// request bytes, nonces, and credentials are not diagnostic material.
    @discardableResult public func start() -> Bool { (try? server.start()) != nil }
    public func stop() async { await server.stop() }
}

public actor ClaudeUnixDomainActionReplyChannel: ClaudeActionReplyChannel {
    private var fd: Int32
    private var sent = false
    public init(fd: Int32) { self.fd = fd }
    public func send(_ response: ClaudeHelperActionResponse) async -> Bool {
        guard fd >= 0, !sent, let frame = try? ClaudeHookActionIPCFrame.encode(response) else { return false }
        sent = true
        var offset = 0
        while offset < frame.count {
            let wrote = frame.withUnsafeBytes { systemWrite(fd, $0.baseAddress!.advanced(by: offset), frame.count - offset) }
            guard wrote > 0 else { return false }
            offset += Int(wrote)
        }
        return true
    }
    public func close() async { guard fd >= 0 else { return }; _ = systemClose(fd); fd = -1 }
}

private func systemRead(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
    #if canImport(Darwin)
    Darwin.read(fd, buffer, count)
    #else
    Glibc.read(fd, buffer, count)
    #endif
}

private func systemWrite(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
    #if canImport(Darwin)
    Darwin.write(fd, buffer, count)
    #else
    Glibc.write(fd, buffer, count)
    #endif
}

private func systemClose(_ fd: Int32) -> Int32 {
    #if canImport(Darwin)
    Darwin.close(fd)
    #else
    Glibc.close(fd)
    #endif
}
