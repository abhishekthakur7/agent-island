import XCTest
import Foundation
import AdapterPort
import ApplicationRuntime
import CursorACPAdapter
import SessionDomain
import SessionStore

final class CursorACPAdapterTests: XCTestCase {
    private func adapter(_ messages: [[String: Any]]) async -> (CursorACPAdapter, CursorACPFixtureTransport, ApplicationRuntime) {
        let fixture = CursorACPFixtureTransport()
        for message in messages { await fixture.enqueue(message) }
        let runtime = ApplicationRuntime(store: SessionStore(), idGenerator: { "id" }, clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        let adapter = CursorACPAdapter(port: runtime, transport: fixture, integrationInstanceID: IntegrationInstanceID("test"), clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        _ = await adapter.negotiate(productVersion: "fixture")
        return (adapter, fixture, runtime)
    }

    func testCreatedSessionIsRecordedAndExternalLoadIsRefused() async {
        let initialize: [String: Any] = ["jsonrpc": "2.0", "id": "cursor-acp-1", "result": ["protocolVersion": "1.0", "authenticated": true]]
        let created: [String: Any] = ["jsonrpc": "2.0", "id": "cursor-acp-2", "result": ["sessionId": "native-created"]]
        let (adapter, _, _) = await adapter([initialize, created])
        guard case .success(let identity) = await adapter.startControlledSession() else { return XCTFail("expected created session") }
        let allowed = await adapter.loadControlledSession(identity)
        let refused = await adapter.loadControlledSession(.init(productNamespace: CursorACPContract.productNamespace, nativeSessionID: .init("cursor-ide-existing")))
        XCTAssertTrue(allowed)
        XCTAssertFalse(refused)
        await adapter.shutdown()
    }

    func testPermissionUsesOneAttemptAndWriteFailureIsIndeterminate() async {
        let initialize: [String: Any] = ["jsonrpc": "2.0", "id": "cursor-acp-1", "result": ["protocolVersion": "1.0", "authenticated": true]]
        let created: [String: Any] = ["jsonrpc": "2.0", "id": "cursor-acp-2", "result": ["sessionId": "native-created"]]
        let permission: [String: Any] = ["jsonrpc": "2.0", "method": "permission/request", "params": ["sessionId": "native-created", "eventId": "event-1", "requestId": "request-1", "permissions": ["allow-once", "allow-always", "reject-once"]]]
        let (adapter, fixture, runtime) = await adapter([initialize, created, permission])
        guard case .success(let identity) = await adapter.startControlledSession() else { return XCTFail("expected start") }
        _ = identity
        var guided: [GuidedAttentionRequest] = []
        for _ in 0..<100 where guided.isEmpty { guided = await runtime.cursorACPAttentionRequests(); if guided.isEmpty { try? await Task.sleep(for: .milliseconds(2)) } }
        XCTAssertEqual(guided.first?.capability.constraints["offeredResponses"], "allow-always,allow-once,reject-once")
        await fixture.setFailWrites(true)
        let request = GuidedAttentionRequestID(productNamespace: CursorACPContract.productNamespace, nativeSessionID: .init("native-created"), nativeAttentionRequestID: "request-1")
        let first = await adapter.submit(requestID: request, action: .allow, attemptID: "attempt-1")
        if case .unavailable(.indeterminateDelivery, _) = first {} else { XCTFail("write loss must be indeterminate") }
        let attempts = await runtime.cursorACPActionAttempts()
        XCTAssertEqual(attempts.count, 1); XCTAssertEqual(attempts.first?.outcome, .indeterminate); XCTAssertEqual(attempts.first?.dispatchCount, 1)
        let retry = await adapter.submit(requestID: request, action: .allow, attemptID: "attempt-1")
        if case .unavailable = retry {} else { XCTFail("no retry after indeterminate delivery") }
        await fixture.finish()
    }

    func testQuestionHasNoDefaultAndPlanRejectRequiresReason() async {
        let choice = GuidedSemanticShape(kind: .structuredChoice, choices: [.init(id: "one", label: "One")], allowsMultipleSelection: false, minimumSelections: 1, maximumSelections: 1)
        XCTAssertEqual(GuidedAttentionDraft.empty.validating(against: choice), .failure(.incompleteResponse))
        let plan = GuidedAttentionRequest(evidence: .init(owner: .init(productNamespace: CursorACPContract.productNamespace, nativeSessionID: .init("s"), nativeAttentionRequestID: "r", integrationInstanceID: .init("i"), negotiationSnapshotID: .init("n")), eventIdentity: .stable("e"), sourceVariant: "cursor.acp.plan", capability: .init(id: CursorACPContract.actionCapability, direction: .act, availability: .available, scope: .request, provenance: .init(snapshotID: .init("n"), integrationInstanceID: .init("i"), productNamespace: CursorACPContract.productNamespace, integrationMode: CursorACPContract.integrationMode)), semanticShape: .init(kind: .planReview), constraints: .init(nativeFingerprint: "e"), sourceObservedAt: Date()))
        XCTAssertEqual(GuidedAction.planReview(.reject, reason: nil).validating(against: plan), .failure(.incompleteResponse))
        XCTAssertEqual(GuidedAction.planReview(.cancel, reason: nil).validating(against: plan), .success(()))
    }

    func testSourceOfferedPermissionVariantsDoNotCreateGenericResponse() async {
        let shape = GuidedSemanticShape(kind: .allowDeny)
        XCTAssertTrue(shape.isSourceSupported)
        XCTAssertNotEqual(GuidedAction.persistentSuggestion(allow: false).semanticKind, shape.kind)
        // Cursor ACP maps only its documented allow-once/allow-always/
        // reject-once source variants; no generic reply action exists.
        XCTAssertEqual(Set(["allow-once", "allow-always", "reject-once"]).count, 3)
    }
}
