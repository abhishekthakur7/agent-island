import XCTest
import Foundation
import CodexAppServerAdapter
import SessionDomain
import AdapterPort
import SessionStore

final class CodexAppServerAdapterTests: XCTestCase {
    private func frame(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) + Data([10]) }
    private func adapter(_ port: Port = Port(), attempts: ActionAttemptStore = ActionAttemptStore()) -> CodexAppServerAdapter { CodexAppServerAdapter(intake: port, attempts: attempts, discovery: Discovery(), schemaProbe: Schema()) }
    private func ready(_ adapter: CodexAppServerAdapter, _ transport: Transport) async throws {
        guard case .success = await adapter.connectForTesting(ownership: .startedByAgentIsland, transport: transport) else { throw NSError(domain: "AB137", code: 1) }
        try await adapter.receive(stdout: frame(["jsonrpc": "2.0", "id": "initialize:1", "result": [:]]))
        let health = await adapter.health(); XCTAssertEqual(health.state, .ready)
    }

    func testSchemaIsGeneratedEvidenceNotCallerInputAndHooksStaySeparate() async {
        XCTAssertFalse(CodexSchemaValidation.validate(manifest: .init(), evidence: nil))
        XCTAssertTrue(CodexSchemaValidation.validate(manifest: .init(), evidence: .init(executable: .init(path: "/fixture/codex", version: "codex-cli 0.144.6"), digest: CodexAppServerContract.schemaDigest)))
        XCTAssertNotEqual(CodexAppServerContract.productNamespace.rawValue, "codex-cli")
        XCTAssertEqual(CodexAppServerContract.integrationMode, "codex.appServer.childProcessStdio")
        let failing = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: Discovery(), schemaProbe: DriftSchema())
        guard case .failure(.schemaMismatch) = await failing.connectForTesting(ownership: .startedByAgentIsland, transport: Transport()) else { return XCTFail() }
    }

    func testHandshakeIsExactlyOnceAndReadyResponsesAreNotHandshakeFailures() async throws {
        let transport = Transport(); let value = adapter()
        try await ready(value, transport)
        let resumeID = await value.resumeThread(threadID: "thread-1", attemptID: "resume")
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "id": resumeID!, "result": ["thread": ["id": "thread-1"]]]))
        let id = await value.archiveThread(threadID: "thread-1", attemptID: "archive")
        XCTAssertNotNil(id)
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "id": id!, "result": [:]]))
        let readyHealth = await value.health(); XCTAssertEqual(readyHealth.state, .ready)
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "id": "initialize:1", "result": [:]]))
        let failedHealth = await value.health(); XCTAssertEqual(failedHealth.failure, .wrongHandshake)
    }

    func testActualThreadTurnAndItemShapesPreserveOwnershipWithoutSyntheticEventID() async throws {
        let port = Port(); let transport = Transport(); let value = adapter(port)
        try await ready(value, transport)
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "method": "thread/started", "params": ["thread": ["id": "thread-1", "status": "active", "updatedAt": 7]]]))
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "method": "turn/started", "params": ["threadId": "thread-1", "turn": ["id": "turn-1", "status": "inProgress", "startedAt": 8]]]))
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "method": "item/completed", "params": ["threadId": "thread-1", "turnId": "turn-1", "completedAtMs": 9, "item": ["id": "item-1", "type": "agentMessage", "text": "protected"]]]))
        let envelopes = await port.envelopes
        XCTAssertEqual(envelopes.count, 4)
        XCTAssertEqual(envelopes[0].family, .sessionDeclared)
        XCTAssertEqual(envelopes[1].activityKind, .started)
        XCTAssertEqual(envelopes[2].ownership?.nativeTurnID, "turn-1")
        XCTAssertEqual(envelopes[3].family, .sessionActivity)
        XCTAssertEqual(envelopes[3].classification, .interactionContent)
    }

    func testPlanAndOutputAreProtectedActivityNotCompletionAndUnknownNotificationOnlyDegrades() async throws {
        let port = Port(); let transport = Transport(); let value = adapter(port)
        try await ready(value, transport)
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "method": "turn/plan/updated", "params": ["threadId": "thread", "turnId": "turn", "plan": [["step": "secret"]]]]))
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "method": "future/unknown", "params": [:]]))
        let envelopes = await port.envelopes; let health = await value.health()
        XCTAssertEqual(envelopes.first?.classification, .interactionContent)
        XCTAssertTrue(health.unresolvedGap)
        XCTAssertEqual(health.state, .ready)
    }

    func testControlsRequireDirectThreadAndAreBoundedAndReconnectInvalidates() async throws {
        let transport = Transport(); let value = adapter()
        try await ready(value, transport)
        let missingOwner = await value.interruptTurn(threadID: "", turnID: "turn", attemptID: "missing")
        let unowned = await value.interruptTurn(threadID: "thread", turnID: "turn", attemptID: "unowned")
        let resumeID = await value.resumeThread(threadID: "thread", attemptID: "resume")
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "id": resumeID!, "result": ["thread": ["id": "thread"]]]))
        let accepted = await value.interruptTurn(threadID: "thread", turnID: "turn", attemptID: "interrupt")
        XCTAssertNil(missingOwner)
        XCTAssertNil(unowned)
        XCTAssertNotNil(resumeID)
        XCTAssertNotNil(accepted)
        await value.disconnect()
        let afterDisconnect = await value.archiveThread(threadID: "thread", attemptID: "after"); let disconnected = await value.health()
        XCTAssertNil(afterDisconnect)
        XCTAssertEqual(disconnected.state, .disconnected)
    }

    func testControlAttemptIsSingleWriteAndResponseIsOnlyAcceptance() async throws {
        let attempts = ActionAttemptStore(); let transport = Transport()
        let value = CodexAppServerAdapter(intake: Port(), attempts: attempts, discovery: Discovery(), schemaProbe: Schema())
        try await ready(value, transport)
        let resume = await value.resumeThread(threadID: "thread", attemptID: "resume")
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "id": resume!, "result": ["thread": ["id": "thread"]]]))
        let interrupt = await value.interruptTurn(threadID: "thread", turnID: "turn", attemptID: "interrupt")
        XCTAssertNotNil(interrupt)
        let duplicate = await value.interruptTurn(threadID: "thread", turnID: "turn", attemptID: "interrupt")
        XCTAssertNil(duplicate)
        let pending = await attempts.attempt(for: "interrupt")
        XCTAssertEqual(pending?.outcome, .dispatching)
        XCTAssertEqual(pending?.dispatchCount, 1)
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "id": interrupt!, "result": [:]]))
        let accepted = await attempts.attempt(for: "interrupt")
        XCTAssertEqual(accepted?.outcome, .acceptedByProduct)
        let writes = await transport.writes
        XCTAssertEqual(writes, 4)
    }

    func testSourceApprovalUsesSameJSONRPCIDAndOneUseLease() async throws {
        let attempts = ActionAttemptStore(); let transport = Transport()
        let value = CodexAppServerAdapter(intake: Port(), attempts: attempts, discovery: Discovery(), schemaProbe: Schema())
        try await ready(value, transport)
        try await value.receive(stdout: frame(["jsonrpc": "2.0", "id": "approval-rpc", "method": "item/commandExecution/requestApproval", "params": ["threadId": "thread", "turnId": "turn", "itemId": "item", "startedAtMs": 1]]))
        let routes = await value.approvalRouteIDs()
        let route = try XCTUnwrap(routes.first)
        guard case .dispatched(let dispatched) = await value.respondApproval(route: route, allow: true, attemptID: "approval") else { return XCTFail() }
        XCTAssertEqual(dispatched.outcome, .acceptedByProduct)
        guard case .rejected = await value.respondApproval(route: route, allow: true, attemptID: "approval") else { return XCTFail("route is one use") }
        let writes = await transport.writes
        XCTAssertEqual(writes, 3)
    }

    func testBoundsAndPrematureFramesFailClosed() async throws {
        let value = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: Discovery(), schemaProbe: Schema(), limits: .init(maxFrameBytes: 8, maxBufferBytes: 32, maxNesting: 2, maxPendingRequests: 2))
        _ = await value.connectForTesting(ownership: .startedByAgentIsland, transport: Transport())
        await value.receive(stdout: Data(repeating: 65, count: 9) + Data([10]))
        let failed = await value.health(); XCTAssertEqual(failed.failure, .oversizedFrame)
        let early = adapter(); await early.receive(stdout: try frame(["jsonrpc": "2.0", "method": "thread/started", "params": [:]]))
        let premature = await early.health(); XCTAssertEqual(premature.failure, .prematureMessage)
    }
}

private actor Discovery: CodexExecutableDiscovering { func discoverCodexExecutable() async -> CodexExecutableEvidence? { .init(path: "/fixture/codex", version: "codex-cli 0.144.6") } }
private actor Schema: CodexSchemaProbing { func generateSchema(for executable: CodexExecutableEvidence) async -> CodexSchemaEvidence? { .init(executable: executable, digest: CodexAppServerContract.schemaDigest) } }
private actor DriftSchema: CodexSchemaProbing { func generateSchema(for executable: CodexExecutableEvidence) async -> CodexSchemaEvidence? { .init(executable: executable, digest: "drift") } }
private actor Transport: CodexAppServerTransport { var writes = 0; func write(_ bytes: Data) async throws { writes += 1 }; func close() async {} }
private actor Port: AdapterIntakePort {
    var envelopes: [RawEventEnvelope] = []
    func negotiate(_ request: NegotiationRequest) async -> NegotiationOutcome { SessionDomainNegotiator.negotiate(request, id: .init("fixture-snapshot"), negotiatedAt: .init(timeIntervalSince1970: 1)) }
    func deliver(_ envelope: RawEventEnvelope) async -> IntakeOutcome { envelopes.append(envelope); return .committed(ledgerRevision: Int64(envelopes.count)) }
    func reportObservationBoundary(_ report: ObservationBoundaryReport) async -> IntakeOutcome { .rejected(.unknownNegotiationSnapshot) }
}
