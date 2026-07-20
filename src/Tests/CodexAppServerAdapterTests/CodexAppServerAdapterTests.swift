import XCTest
import Foundation
import CodexAppServerAdapter
import SessionDomain
import AdapterPort
import SessionStore

final class CodexAppServerAdapterTests: XCTestCase {
    private func frame(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object) + Data([0x0A])
    }

    private func ready(_ adapter: CodexAppServerAdapter, transport: Transport) async throws {
        guard case .success = await adapter.connect(ownership: .startedByAgentIsland, transport: transport, liveSchemaDigest: CodexAppServerContract.schemaDigest) else { throw NSError(domain: "AB137", code: 1) }
        try await adapter.receive(stdout: frame(["jsonrpc": "2.0", "id": "initialize:1", "result": [:]]))
        let health = await adapter.health()
        XCTAssertEqual(health.state, .ready)
    }
    func testSchemaRequiresLiveDigestAndNeverUsesHooksAuthority() {
        XCTAssertFalse(CodexSchemaValidation.validate(manifest: .init(), liveDigest: nil))
        XCTAssertTrue(CodexSchemaValidation.validate(manifest: .init(), liveDigest: CodexAppServerContract.schemaDigest))
        XCTAssertNotEqual(CodexAppServerContract.productNamespace.rawValue, "codex-cli")
        XCTAssertEqual(CodexAppServerContract.integrationMode, "codex.appServer.childProcessStdio")
    }

    func testHandshakeIsExactlyOnceAndWrongResponseFails() async {
        let transport = Transport()
        let adapter = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: Discovery())
        guard case .success(let epoch) = await adapter.connect(ownership: .startedByAgentIsland, transport: transport, liveSchemaDigest: CodexAppServerContract.schemaDigest) else { return XCTFail() }
        XCTAssertEqual(epoch, 1)
        try? await adapter.receive(stdout: frame(["jsonrpc": "2.0", "id": "initialize:1", "result": [:]]))
        let readyHealth = await adapter.health()
        XCTAssertEqual(readyHealth.state, .ready)
        try? await adapter.receive(stdout: frame(["jsonrpc": "2.0", "id": "initialize:1", "result": [:]]))
        let failedHealth = await adapter.health()
        let writes = await transport.writes
        XCTAssertEqual(failedHealth.failure, .wrongHandshake)
        XCTAssertEqual(writes, 2, "initialize plus exactly one initialized notification")
    }

    func testBoundedFrameAndDisconnectRetireRoutes() async {
        let transport = Transport()
        let adapter = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: Discovery(), limits: .init(maxFrameBytes: 8, maxBufferBytes: 32, maxNesting: 2, maxPendingRequests: 2))
        _ = await adapter.connect(ownership: .startedByAgentIsland, transport: transport, liveSchemaDigest: CodexAppServerContract.schemaDigest)
        await adapter.receive(stdout: Data(repeating: 65, count: 9) + Data([10]))
        let failedHealth = await adapter.health()
        XCTAssertEqual(failedHealth.failure, .oversizedFrame)
        await adapter.disconnect()
        let disconnectedHealth = await adapter.health()
        XCTAssertEqual(disconnectedHealth.state, .disconnected)
    }

    func testPrematureAndMalformedFramesFailClosed() async throws {
        let early = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: Discovery())
        await early.receive(stdout: try frame(["jsonrpc": "2.0", "method": "thread/started", "params": [:]]))
        let earlyHealth = await early.health()
        XCTAssertEqual(earlyHealth.failure, .prematureMessage)

        let transport = Transport(); let malformed = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: Discovery())
        _ = await malformed.connect(ownership: .startedByAgentIsland, transport: transport, liveSchemaDigest: CodexAppServerContract.schemaDigest)
        await malformed.receive(stdout: Data("not-json\n".utf8))
        let malformedHealth = await malformed.health()
        XCTAssertEqual(malformedHealth.failure, .malformedJSONRPC)
    }

    func testReconnectUsesNewEpochAndRequiresIndependentHandshake() async throws {
        let transport = Transport(); let adapter = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: Discovery())
        try await ready(adapter, transport: transport)
        await adapter.disconnect()
        guard case .success(let second) = await adapter.connect(ownership: .explicitlyResumedByAgentIsland, transport: transport, liveSchemaDigest: CodexAppServerContract.schemaDigest) else { return XCTFail() }
        XCTAssertEqual(second, 2)
        let initializingHealth = await adapter.health()
        XCTAssertEqual(initializingHealth.state, .initializing)
        try await adapter.receive(stdout: frame(["jsonrpc": "2.0", "id": "initialize:2", "result": [:]]))
        let readyHealth = await adapter.health()
        XCTAssertEqual(readyHealth.state, .ready)
    }

    func testSchemaDoesNotOfferInventedApprovalOrExperimentalControls() {
        let manifest = CodexSchemaManifest()
        XCTAssertFalse(manifest.stableMethods.contains("approval/respond"))
        XCTAssertFalse(manifest.stableMethods.contains("turn/input"))
        XCTAssertFalse(manifest.stableNotificationMethods.contains("item/plan/delta"))
        XCTAssertFalse(manifest.stableMethods.contains("experimentalFeature/enablement/set"))
    }

    func testNotificationWithoutExactNativeEventIdentityIsUnresolvedNotCompletion() async throws {
        let transport = Transport(); let port = Port(); let adapter = CodexAppServerAdapter(intake: port, attempts: ActionAttemptStore(), discovery: Discovery())
        try await ready(adapter, transport: transport)
        try await adapter.receive(stdout: frame(["jsonrpc": "2.0", "method": "turn/completed", "params": ["threadId": "thread", "turnId": "turn"]]))
        let health = await adapter.health()
        XCTAssertTrue(health.unresolvedGap)
        let deliveries = await port.deliveries
        XCTAssertEqual(deliveries, 0, "missing source identity cannot manufacture completion")
    }

    func testApprovalWithoutDocumentedDeadlineStaysUnavailableAndEmitsNoResponse() async throws {
        let transport = Transport(); let adapter = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: Discovery())
        try await ready(adapter, transport: transport)
        try await adapter.receive(stdout: frame(["jsonrpc": "2.0", "id": "server-request", "method": "item/commandExecution/requestApproval", "params": ["threadId": "thread", "turnId": "turn", "itemId": "item", "startedAtMs": 1]]))
        let health = await adapter.health()
        XCTAssertTrue(health.unresolvedGap)
        guard case .rejected = await adapter.respondApproval(tuple: "missing", allow: true, attemptID: "attempt") else { return XCTFail("unproven approval must not dispatch") }
        let writes = await transport.writes
        XCTAssertEqual(writes, 2, "only initialize and initialized are allowed")
    }

    func testDiscoveryAndSchemaFailuresDoNotCreateLiveConnection() async {
        let unavailable = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: UnavailableCodexExecutableDiscovery())
        guard case .failure(.executableUnavailable) = await unavailable.connect(ownership: .startedByAgentIsland, transport: Transport(), liveSchemaDigest: CodexAppServerContract.schemaDigest) else { return XCTFail() }
        let mismatch = CodexAppServerAdapter(intake: Port(), attempts: ActionAttemptStore(), discovery: Discovery())
        guard case .failure(.schemaMismatch) = await mismatch.connect(ownership: .startedByAgentIsland, transport: Transport(), liveSchemaDigest: "wrong") else { return XCTFail() }
    }
}

private actor Discovery: CodexExecutableDiscovering {
    func discoverCodexExecutable() async -> CodexExecutableEvidence? { .init(path: "/fixture/codex", version: "1.0.0") }
}

private actor Transport: CodexAppServerTransport {
    var writes = 0
    func write(_ bytes: Data) async throws { writes += 1 }
    func close() async {}
}

private actor Port: AdapterIntakePort {
    var deliveries = 0
    func negotiate(_ request: NegotiationRequest) async -> NegotiationOutcome {
        SessionDomainNegotiator.negotiate(request, id: .init("fixture-snapshot"), negotiatedAt: .init(timeIntervalSince1970: 1))
    }
    func deliver(_ envelope: RawEventEnvelope) async -> IntakeOutcome { deliveries += 1; return .committed(ledgerRevision: Int64(deliveries)) }
    func reportObservationBoundary(_ report: ObservationBoundaryReport) async -> IntakeOutcome { .rejected(.unknownNegotiationSnapshot) }
}
