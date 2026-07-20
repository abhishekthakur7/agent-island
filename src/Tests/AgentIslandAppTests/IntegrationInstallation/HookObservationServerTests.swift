import Darwin
import Foundation
import XCTest
import ClaudeCodeAdapter
import SessionDomain
@testable import AgentIslandApp

final class HookObservationServerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-island-hook-observation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    func testReceivesCompleteFrameAtFixedEndpointAndCleansUpExactSocket() async throws {
        let collector = HookObservationFrameCollector()
        let server = HookObservationServer(product: .codex, appOwnedRoot: temporaryDirectory) { frame in
            await collector.append(frame)
        }
        try server.start()
        let endpoint = temporaryDirectory.appendingPathComponent("codex-hooks.sock")
        XCTAssertTrue(FileManager.default.fileExists(atPath: endpoint.path))
        XCTAssertEqual(try permissions(of: temporaryDirectory), 0o700)
        XCTAssertEqual(try permissions(of: endpoint), 0o600)

        let authenticator = ClaudeIPCAuthenticator(secret: Data("test-secret".utf8))
        let message = ClaudeHookIPCMessage(
            installationID: .init("installation"),
            helperID: "helper",
            nonce: "nonce",
            payload: Data("{}".utf8),
            authenticator: authenticator
        )
        let frame = try ClaudeHookIPCFrame.encode(message)
        try send(frame, inTwoWritesTo: endpoint.path)

        let received = try await eventually { await collector.firstFrame() }
        XCTAssertEqual(received, frame)

        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: endpoint.path))
    }

    func testRefusesForeignOrNonSocketExistingEndpoint() throws {
        let endpoint = temporaryDirectory.appendingPathComponent("claude-hooks.sock")
        FileManager.default.createFile(atPath: endpoint.path, contents: Data("not a socket".utf8))
        let server = HookObservationServer(product: .claude, appOwnedRoot: temporaryDirectory) { _ in }

        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? HookObservationServerError, .endpointUntrusted)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: endpoint.path))
    }

    private func permissions(of url: URL) throws -> UInt16 {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw POSIXError(.ENOENT) }
        return UInt16(value.st_mode & 0o7777)
    }

    private func send(_ frame: Data, inTwoWritesTo path: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENOTCONN) }
        defer { _ = close(fd) }
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
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1))
            }
        }
        guard connected == 0 else { throw POSIXError(.ENOTCONN) }
        let split = min(5, frame.count)
        try writeAll(frame.prefix(split), to: fd)
        try writeAll(frame.dropFirst(split), to: fd)
    }

    private func writeAll<C: Collection>(_ bytes: C, to fd: Int32) throws where C.Element == UInt8 {
        let data = Data(bytes)
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), data.count - offset) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw POSIXError(.EIO) }
            offset += count
        }
    }

    private func eventually<T>(_ value: @escaping @Sendable () async -> T?) async throws -> T {
        for _ in 0..<100 {
            if let found = await value() { return found }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HookObservationTestError.timedOut
    }
}

private actor HookObservationFrameCollector {
    private var frames: [Data] = []
    func append(_ frame: Data) { frames.append(frame) }
    func firstFrame() -> Data? { frames.first }
}

private enum HookObservationTestError: Error { case timedOut }
