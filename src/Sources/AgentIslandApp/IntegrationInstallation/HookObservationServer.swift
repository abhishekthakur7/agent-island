import Darwin
import Foundation
import ClaudeCodeAdapter

/// The three independently configured Product hook endpoints.  These names
/// are fixed by the app; a helper never chooses a socket location.
enum HookObservationProduct: String, CaseIterable, Sendable {
    case claude
    case codex
    case cursor

    var socketFileName: String { "\(rawValue)-hooks.sock" }
}

/// A one-way, app-owned AICH observation endpoint.  It deliberately accepts
/// no reply bytes and owns no configuration installation state.
final class HookObservationServer: @unchecked Sendable {
    typealias FrameHandler = @Sendable (Data) async -> Void

    let product: HookObservationProduct
    let appOwnedRoot: URL
    let frameHandler: FrameHandler
    var endpointURL: URL { appOwnedRoot.appendingPathComponent(product.socketFileName) }

    private let lock = NSLock()
    private var listenerFD: Int32 = -1
    private var acceptTask: Task<Void, Never>?
    private var endpointReceipt: HookObservationSocketReceipt?
    private var activeConnections: [UUID: Int32] = [:]
    private let maximumConnections = 32
    private let readTimeout: TimeInterval = 2

    init(product: HookObservationProduct, appOwnedRoot: URL, frameHandler: @escaping FrameHandler) {
        self.product = product
        self.appOwnedRoot = appOwnedRoot.standardizedFileURL
        self.frameHandler = frameHandler
    }

    var activeConnectionCount: Int { lock.withLock { activeConnections.count } }

    /// Creates the private root and starts accepting only complete bounded
    /// AICH frames. A previous endpoint is removed only if it is the exact
    /// user-owned socket at this product's fixed path.
    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listenerFD < 0 else { return }

        try prepareEndpoint()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HookObservationServerError.endpointUnavailable }
        do {
            var address = try unixAddress(for: endpointURL.path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, unixAddressLength(for: endpointURL.path))
                }
            }
            guard bound == 0, chmod(endpointURL.path, 0o600) == 0,
                  let receipt = HookObservationSocketReceipt.at(endpointURL), isSecureEndpoint(receipt),
                  listen(fd, 16) == 0
            else { throw HookObservationServerError.endpointUnavailable }
            listenerFD = fd
            endpointReceipt = receipt
            acceptTask = Task.detached(priority: .utility) { [weak self] in self?.acceptLoop(fd) }
        } catch {
            _ = close(fd)
            // `bind` may have created a socket before a later setup step
            // failed. Its receipt is still required before cleanup.
            if let receipt = HookObservationSocketReceipt.at(endpointURL) { removeEndpointIfExact(receipt) }
            throw error
        }
    }

    /// Stops future accepts, wakes bounded readers, and removes only this
    /// listener incarnation's exact filesystem entry.
    func stop() {
        let state = lock.withLock { () -> (Int32, Task<Void, Never>?, HookObservationSocketReceipt?, [Int32]) in
            let fd = listenerFD
            listenerFD = -1
            let task = acceptTask
            acceptTask = nil
            let receipt = endpointReceipt
            endpointReceipt = nil
            return (fd, task, receipt, Array(activeConnections.values))
        }
        let (fd, task, receipt, connections) = state
        task?.cancel()
        if fd >= 0 { _ = close(fd) }
        // A worker retains ownership of the final close, avoiding descriptor
        // reuse races while still waking a blocked poll/read promptly.
        for connection in connections { _ = shutdown(connection, SHUT_RDWR) }
        if let receipt { removeEndpointIfExact(receipt) }
    }

    deinit { stop() }

    private func acceptLoop(_ fd: Int32) {
        while !Task.isCancelled {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            let id = UUID()
            let admitted = lock.withLock { () -> Bool in
                guard listenerFD == fd, activeConnections.count < maximumConnections else { return false }
                activeConnections[id] = client
                return true
            }
            guard admitted else { _ = close(client); continue }
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { _ = close(client); return }
                defer {
                    _ = close(client)
                    _ = self.lock.withLock { self.activeConnections.removeValue(forKey: id) }
                }
                guard let frame = self.readFrame(from: client, deadline: Date().addingTimeInterval(self.readTimeout)) else { return }
                await self.frameHandler(frame)
            }
        }
    }

    private func prepareEndpoint() throws {
        if let existing = HookObservationFileStatus.at(appOwnedRoot) {
            guard existing.isDirectory, existing.owner == getuid() else {
                throw HookObservationServerError.endpointUntrusted
            }
        }
        try FileManager.default.createDirectory(
            at: appOwnedRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        guard let created = HookObservationFileStatus.at(appOwnedRoot), created.isDirectory,
              created.owner == getuid(), chmod(appOwnedRoot.path, 0o700) == 0, isSecureRoot else {
            throw HookObservationServerError.endpointUntrusted
        }
        guard endpointURL.deletingLastPathComponent().standardizedFileURL == appOwnedRoot else {
            throw HookObservationServerError.endpointUntrusted
        }
        guard HookObservationFileStatus.at(endpointURL) == nil else {
            guard let existing = HookObservationSocketReceipt.at(endpointURL), isSecureEndpoint(existing) else {
                throw HookObservationServerError.endpointUntrusted
            }
            removeEndpointIfExact(existing)
            guard !FileManager.default.fileExists(atPath: endpointURL.path) else {
                throw HookObservationServerError.endpointUntrusted
            }
            return
        }
    }

    private var isSecureRoot: Bool {
        guard appOwnedRoot.resolvingSymlinksInPath().standardizedFileURL == appOwnedRoot,
              let status = HookObservationFileStatus.at(appOwnedRoot), status.isDirectory,
              status.owner == getuid(), status.mode == 0o700
        else { return false }
        return true
    }

    private func isSecureEndpoint(_ receipt: HookObservationSocketReceipt) -> Bool {
        guard let status = HookObservationFileStatus.at(endpointURL), status.isSocket,
              status.owner == getuid(), status.mode == 0o600,
              HookObservationSocketReceipt.at(endpointURL) == receipt
        else { return false }
        return true
    }

    private func removeEndpointIfExact(_ receipt: HookObservationSocketReceipt) {
        // Receipt equality prevents cleanup from intentionally removing a
        // later listener's endpoint after a stop/restart or replacement.
        guard HookObservationSocketReceipt.at(endpointURL) == receipt else { return }
        _ = unlink(endpointURL.path)
    }

    private func unixAddress(for path: String) throws -> sockaddr_un {
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw HookObservationServerError.endpointUnavailable
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    _ = strncpy($0, source, capacity - 1)
                }
            }
        }
        return address
    }

    private func unixAddressLength(for path: String) -> socklen_t {
        socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
    }

    private func readFrame(from fd: Int32, deadline: Date) -> Data? {
        let headerSize = ClaudeHookIPCFrame.magic.count + 1 + 4
        guard let header = readExactly(fd, count: headerSize, deadline: deadline),
              header.prefix(ClaudeHookIPCFrame.magic.count) == ClaudeHookIPCFrame.magic,
              header[ClaudeHookIPCFrame.magic.count] == ClaudeHookIPCFrame.version
        else { return nil }
        let lengthOffset = ClaudeHookIPCFrame.magic.count + 1
        let length = header[lengthOffset..<(lengthOffset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= UInt32(ClaudeHookIPCFrame.maxFrameBytes),
              let body = readExactly(fd, count: Int(length), deadline: deadline)
        else { return nil }
        let frame = header + body
        // Decode before the injected handler. This makes the server's routing
        // boundary a complete, valid AICH frame rather than arbitrary bytes.
        guard (try? ClaudeHookIPCFrame.decode(frame)) != nil else { return nil }
        return frame
    }

    private func readExactly(_ fd: Int32, count: Int, deadline: Date) -> Data? {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard waitForRead(fd, deadline: deadline) else { return nil }
            var buffer = [UInt8](repeating: 0, count: count - data.count)
            let received = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            if received < 0, errno == EINTR { continue }
            guard received > 0 else { return nil }
            data.append(buffer, count: Int(received))
        }
        return data
    }

    private func waitForRead(_ fd: Int32, deadline: Date) -> Bool {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(min(remaining * 1_000, Double(Int32.max)))
            let result = poll(&descriptor, 1, max(1, milliseconds))
            if result < 0, errno == EINTR { continue }
            guard result > 0 else { return false }
            return (descriptor.revents & (Int16(POLLIN) | Int16(POLLERR) | Int16(POLLHUP) | Int16(POLLNVAL))) != 0
        }
    }
}

enum HookObservationServerError: Error, Equatable { case endpointUnavailable, endpointUntrusted }

private struct HookObservationFileStatus {
    let mode: mode_t
    let owner: uid_t
    let fileType: mode_t

    static func at(_ url: URL) -> Self? {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return nil }
        return Self(mode: value.st_mode & 0o7777, owner: value.st_uid, fileType: value.st_mode & S_IFMT)
    }

    var isDirectory: Bool { fileType == S_IFDIR }
    var isSocket: Bool { fileType == S_IFSOCK }
}

private struct HookObservationSocketReceipt: Equatable {
    let device: UInt64
    let inode: UInt64

    static func at(_ url: URL) -> Self? {
        var value = stat()
        guard lstat(url.path, &value) == 0, (value.st_mode & S_IFMT) == S_IFSOCK else { return nil }
        return Self(device: UInt64(value.st_dev), inode: UInt64(value.st_ino))
    }
}
