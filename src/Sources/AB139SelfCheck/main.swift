import Foundation
import ApplicationRuntime
import CursorACPAdapter
import SessionDomain
import SessionStore
import ProtectedStore

@main
struct AB139SelfCheck {
    private static func fail(_ stage: String) -> Never {
        FileHandle.standardError.write(Data("AB139SelfCheck failed: \(stage)\n".utf8))
        exit(EXIT_FAILURE)
    }

    static func main() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab139-self-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { fail("temporary-directory") }
        let configuration = ProtectedStoreConfiguration(databaseURL: root.appendingPathComponent("state.sqlite"), keychainAccount: "ab139-self-check-\(UUID().uuidString)")
        let transport = CursorACPFixtureTransport()
        await transport.enqueue(["jsonrpc": "2.0", "id": "cursor-acp-1", "result": ["protocolVersion": "1.0", "authenticated": true]])
        await transport.enqueue(["jsonrpc": "2.0", "id": "cursor-acp-2", "result": ["sessionId": "self-check-native"]])
        await transport.enqueue(["jsonrpc": "2.0", "method": "permission/request", "params": ["sessionId": "self-check-native", "eventId": "permission-event", "requestId": "permission-request", "permissions": ["allow-once", "allow-always", "reject-once"]]])
        let store: SessionStore
        do { store = try SessionStore(protectedStore: ProtectedStore(configuration: configuration)) } catch { fail("initial-protected-store") }
        let runtime = ApplicationRuntime(store: store, idGenerator: { "self-check" }, clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        let adapter = CursorACPAdapter(port: runtime, transport: transport, integrationInstanceID: .init("self-check"), clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        guard case .compatible = await adapter.negotiate(productVersion: "fixture") else { fail("initial-negotiation") }
        guard case .success(let identity) = await adapter.startControlledSession() else { fail("session-new") }
        let request = GuidedAttentionRequestID(productNamespace: CursorACPContract.productNamespace, nativeSessionID: identity.nativeSessionID, nativeAttentionRequestID: "permission-request")
        guard await adapter.waitForAttention(request) else { fail("post-new-permission-reader") }
        guard (await runtime.cursorACPAttentionRequests()).contains(where: { $0.id == request }) else { fail("runtime-attention-projection") }
        guard case .dispatched = await adapter.submit(requestID: request, action: .allow, attemptID: "attempt"), (await runtime.cursorACPActionAttempts()).count == 1 else { fail("typed-permission-submit") }
        // Model a process boundary immediately after the durably recorded
        // dispatch handoff and before a documented ACP acknowledgement.
        guard let handoff = (await runtime.cursorACPActionAttempts()).first else { fail("persisted-handoff") }
        let inFlight = ActionAttempt(id: handoff.id, requestID: handoff.requestID, owner: handoff.owner, action: handoff.action, leaseID: nil, reservedAt: handoff.reservedAt, outcome: .dispatching, rejectionReason: nil, dispatchCount: 1)
        // Stop/await the original reader before opening the same protected
        // database directly for the crash-boundary fixture state.
        await adapter.shutdown()
        do { try ProtectedStore(configuration: configuration).commitCursorACPActionState(.init(attempts: [inFlight])) } catch { fail("persist-inflight-crash-boundary") }
        // Reopen from protected persistence: the created ID remains eligible
        // for load, the unrelated native-looking ID does not, and the one
        // handoff remains indeterminate rather than replayable.
        let reopenedStore: SessionStore
        do { reopenedStore = try SessionStore(protectedStore: ProtectedStore(configuration: configuration)) } catch { fail("reopen-protected-store") }
        let reopenedRuntime = ApplicationRuntime(store: reopenedStore, idGenerator: { "reopened-snapshot" }, clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        let reloadTransport = CursorACPFixtureTransport()
        await reloadTransport.enqueue(["jsonrpc": "2.0", "id": "cursor-acp-1", "result": ["protocolVersion": "1.0", "authenticated": true]])
        let reopenedAdapter = CursorACPAdapter(port: reopenedRuntime, transport: reloadTransport, integrationInstanceID: .init("self-check"), clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        guard case .compatible = await reopenedAdapter.negotiate(productVersion: "fixture") else { fail("reopen-negotiation") }
        let restoredLoad = await reopenedAdapter.loadControlledSession(identity)
        let unrelated = await reopenedAdapter.loadControlledSession(.init(productNamespace: CursorACPContract.productNamespace, nativeSessionID: .init("cursor-ide-existing")))
        let restoredAttempts = await reopenedRuntime.cursorACPActionAttempts()
        guard restoredLoad else { fail("reopen-recorded-load") }
        guard !unrelated else { fail("reopen-unrelated-load-refused") }
        guard restoredAttempts.count == 1, restoredAttempts[0].outcome == .indeterminate, restoredAttempts[0].dispatchCount == 1, restoredAttempts[0].leaseID == nil else { fail("reopen-indeterminate-no-lease") }
        await reloadTransport.finish()
        await reopenedAdapter.waitForReaderTermination()
        guard case .degraded(.processExited) = await reopenedAdapter.currentHealth() else { fail("explicit-fixture-eof-degradation") }
        exit(EXIT_SUCCESS)
    }
}
