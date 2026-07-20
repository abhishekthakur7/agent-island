import XCTest
import CodexCLIAdapter
import SessionDomain
import AdapterPort
import ClaudeCodeAdapter

final class CodexCLIAdapterTests: XCTestCase {
    private let installation = IntegrationInstanceID("codex-install")

    private func snapshot() -> NegotiationSnapshot {
        let request = NegotiationRequest(integrationInstanceID: installation, adapterKind: CodexCLIIntegration.adapterKind, adapterBuildVersion: "test", productNamespace: CodexCLIIntegration.productNamespace, integrationMode: CodexCLIIntegration.integrationMode, offeredContractVersion: .init(major: 1, minor: 0), requestedCapabilities: [WellKnownCapability.sessionObservation, CodexCLIIntegration.observationCapability, CodexCLIIntegration.configurationCapability], catalogRevision: "test", requestedCapabilityRecords: [CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available), CapabilityRecord(id: CodexCLIIntegration.observationCapability, direction: .observe, availability: .available), CapabilityRecord(id: CodexCLIIntegration.configurationCapability, direction: .configure, availability: .available, scope: .installation)])
        guard case .compatible(let value) = SessionDomainNegotiator.negotiate(request, id: .init("snapshot"), negotiatedAt: .init(timeIntervalSince1970: 1)) else { fatalError() }
        return value
    }

    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/CodexCLIAdapter/\(name)"))
    }

    func testIndependentLifecycleFixtureNormalizesEveryDocumentedHook() throws {
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("independent-lifecycle.json")) as? [[String: Any]])
        XCTAssertEqual(document.count, CodexHookName.allCases.count)
        for row in document {
            let data = try JSONSerialization.data(withJSONObject: row)
            let hook = try CodexHookEnvelope.decode(data)
            let result = CodexHookNormalizer.normalize(hook, snapshot: snapshot(), installationID: installation)
            guard case .success(let observation) = result else { return XCTFail("fixture hook \(hook.name) must normalize") }
            XCTAssertTrue(observation.events.allSatisfy { $0.classification == .operationalMetadata })
            XCTAssertEqual(observation.events.first?.sourceCursor?.scope, "codex-session:independent-session")
        }
    }

    func testPermissionCueHasNoActionAuthorityOrTextResponsePath() throws {
        let hook = try CodexHookEnvelope.decode(Data("{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"native-a\",\"event_id\":\"e\",\"turn_id\":\"t\",\"sequence\":1}".utf8))
        guard case .success(let observation) = CodexHookNormalizer.normalize(hook, snapshot: snapshot(), installationID: installation) else { return XCTFail() }
        XCTAssertEqual(observation.permissionCue?.sessionIdentity.nativeSessionID.rawValue, "native-a")
        XCTAssertEqual(observation.permissionCue?.guidedResponseAvailable, false)
        XCTAssertTrue(CodexCLIIntegration.allActionCapabilities.isEmpty)
        XCTAssertFalse(CodexCLIIntegration.allObservationCapabilities.contains(WellKnownCapability.sessionAction))
    }

    func testClassifiedContentNeverLeaksIntoFactsOrUnconsentedOutput() throws {
        let secret = "DO_NOT_EXPORT_COMMAND"
        let hook = try CodexHookEnvelope.decode(Data("{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s\",\"event_id\":\"e\",\"turn_id\":\"t\",\"sequence\":1,\"command\":\"\(secret)\",\"operational_id\":\"never-retained\"}".utf8))
        guard case .success(let unconsented) = CodexHookNormalizer.normalize(hook, snapshot: snapshot(), installationID: installation), case .success(let consented) = CodexHookNormalizer.normalize(hook, snapshot: snapshot(), installationID: installation, contentConsent: .init(localPresentationEnabled: true)) else { return XCTFail() }
        XCTAssertNil(unconsented.protectedContent)
        XCTAssertEqual(String(data: consented.protectedContent?.bytes ?? Data(), encoding: .utf8), secret)
        let factBytes = try JSONEncoder().encode(consented.events)
        XCTAssertFalse(String(decoding: factBytes, as: UTF8.self).contains(secret))
        XCTAssertFalse(String(decoding: consented.protectedContent?.bytes ?? Data(), as: UTF8.self).contains("operational_id"))
        XCTAssertFalse(CodexIntegrationHealth(enabledIntent: true, reason: .quarantinedInput).redactedDiagnostic.contains(secret))
    }

    func testQuarantineRejectsUntrustedInputWithoutDeliveryOrReplayState() async throws {
        let port = RecordingPort(snapshot: snapshot())
        let auth = ClaudeIPCAuthenticator(secret: "fixture")
        let adapter = CodexCLIAdapter(port: port, integrationInstanceID: installation, helperID: "helper", authenticator: auth)
        _ = await adapter.negotiate(version: .init(productVersion: "1.0", documentedHooksAvailable: true))
        await adapter.setEnabledIntent(true)
        let payload = Data("{\"hook_event_name\":\"Unknown\",\"session_id\":\"s\",\"event_id\":\"e\",\"sequence\":1}".utf8)
        let bad = ClaudeHookIPCMessage(installationID: installation, helperID: "helper", nonce: "same-nonce", payload: payload, issuedAt: Date(), authenticator: auth)
        guard case .quarantined(let first) = await adapter.ingestOutcome(bad) else { return XCTFail("unknown must quarantine") }
        XCTAssertEqual(first.reason, .unsupportedHook)
        XCTAssertEqual(await port.deliveries, 0)
        let goodPayload = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s\",\"event_id\":\"e2\",\"sequence\":1}".utf8)
        let good = ClaudeHookIPCMessage(installationID: installation, helperID: "helper", nonce: "same-nonce", payload: goodPayload, issuedAt: Date(), authenticator: auth)
        guard case .delivered = await adapter.ingestOutcome(good) else { return XCTFail("quarantined nonce must not poison later valid input") }
        XCTAssertEqual(await port.deliveries, 2)
        let crossOwner = ClaudeHookIPCMessage(installationID: .init("other"), helperID: "helper", nonce: "cross", payload: goodPayload, issuedAt: Date(), authenticator: auth)
        guard case .quarantined(let cross) = await adapter.ingestOutcome(crossOwner) else { return XCTFail() }
        XCTAssertEqual(cross.reason, .crossOwner)
        XCTAssertEqual(await port.deliveries, 2)
    }

    func testReplayDuplicateMalformedOversizedAndDisabledAreQuarantined() async throws {
        let port = RecordingPort(snapshot: snapshot()); let auth = ClaudeIPCAuthenticator(secret: "fixture")
        let adapter = CodexCLIAdapter(port: port, integrationInstanceID: installation, helperID: "helper", authenticator: auth)
        let data = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s\",\"event_id\":\"e\",\"sequence\":1}".utf8)
        let disabled = ClaudeHookIPCMessage(installationID: installation, helperID: "helper", nonce: "n0", payload: data, issuedAt: Date(), authenticator: auth)
        guard case .quarantined(let value) = await adapter.ingestOutcome(disabled) else { return XCTFail() }; XCTAssertEqual(value.reason, .disabled)
        _ = await adapter.negotiate(version: .init(productVersion: "1.0", documentedHooksAvailable: true)); await adapter.setEnabledIntent(true)
        let valid = ClaudeHookIPCMessage(installationID: installation, helperID: "helper", nonce: "n1", payload: data, issuedAt: Date(), authenticator: auth)
        _ = await adapter.ingestOutcome(valid)
        guard case .quarantined(let duplicate) = await adapter.ingestOutcome(valid) else { return XCTFail() }; XCTAssertTrue([CodexHookRejection.replayedNonce, .duplicateEvent].contains(duplicate.reason))
        let malformed = ClaudeHookIPCMessage(installationID: installation, helperID: "helper", nonce: "n2", payload: Data("{".utf8), issuedAt: Date(), authenticator: auth)
        guard case .quarantined(let malformedResult) = await adapter.ingestOutcome(malformed) else { return XCTFail() }; XCTAssertEqual(malformedResult.reason, .malformedEnvelope)
        let large = ClaudeHookIPCMessage(installationID: installation, helperID: "helper", nonce: "n3", payload: Data(repeating: 1, count: SessionDomainValidator.maxPayloadBytes + 1), issuedAt: Date(), authenticator: auth)
        guard case .quarantined(let oversized) = await adapter.ingestOutcome(large) else { return XCTFail() }; XCTAssertEqual(oversized.reason, .oversizedEnvelope)
        XCTAssertEqual(await port.deliveries, 2)
    }

    func testSourceOrderGapAndReorderingRemainUnresolved() throws {
        let identity = AgentSessionIdentity(productNamespace: CodexCLIIntegration.productNamespace, nativeSessionID: .init("s"))
        func fact(_ receipt: Int64, _ cursor: Int64, _ activity: SessionActivityKind) -> NormalizedEventFact {
            .init(receiptOrdinal: receipt, identity: identity, integrationInstanceID: installation, negotiationSnapshotID: .init("n"), eventIdentity: .stable("e\(receipt)"), family: .sessionActivity, sourceVariant: "codex.fixture", activityKind: activity, boundaryReason: nil, classification: .operationalMetadata, occurrenceTime: nil, receiptTime: Date(), displayTitle: nil, hostLabel: nil, sourceCursor: .init(scope: "codex-session:s", value: cursor))
        }
        let gap = SessionReducer.reduce(history: [fact(1, 1, .working), fact(2, 3, .completed)], ledgerRevision: 2)
        XCTAssertEqual(gap.execution, .unresolved); XCTAssertEqual(gap.observation, .gap)
        let reordered = SessionReducer.reduce(history: [fact(1, 2, .completed), fact(2, 1, .working)], ledgerRevision: 2)
        XCTAssertEqual(reordered.execution, .unresolved)
    }

    func testAdapterRequiresSourceStartBaselineAndExactTerminalRedelivery() async throws {
        let port = RecordingPort(snapshot: snapshot()); let auth = ClaudeIPCAuthenticator(secret: "fixture")
        let adapter = CodexCLIAdapter(port: port, integrationInstanceID: installation, helperID: "helper", authenticator: auth)
        _ = await adapter.negotiate(version: .init(productVersion: "1.0", documentedHooksAvailable: true)); await adapter.setEnabledIntent(true)
        func message(_ nonce: String, _ body: String) -> ClaudeHookIPCMessage { .init(installationID: installation, helperID: "helper", nonce: nonce, payload: Data(body.utf8), issuedAt: Date(), authenticator: auth) }
        let stop3 = message("stop-3", #"{"hook_event_name":"Stop","session_id":"s","event_id":"stop-3","sequence":3,"status":"completed"}"#)
        guard case .unresolved(let first) = await adapter.ingestOutcome(stop3) else { return XCTFail("stop-first must be unresolved") }
        XCTAssertEqual(first.reason, .missingBaseline)
        XCTAssertEqual(await port.terminalDeliveries, 0)
        XCTAssertEqual(await port.reconciliationDeliveries, 1)
        guard case .delivered = await adapter.ingestOutcome(message("start-1", #"{"hook_event_name":"SessionStart","session_id":"s","event_id":"start-1","sequence":1}"#)) else { return XCTFail("source baseline must deliver") }
        guard case .unresolved(let gap) = await adapter.ingestOutcome(stop3) else { return XCTFail("gap must be unresolved") }
        XCTAssertEqual(gap.reason, .sourceGap); XCTAssertEqual(await port.terminalDeliveries, 0)
        guard case .delivered = await adapter.ingestOutcome(message("activity-2", #"{"hook_event_name":"Activity","session_id":"s","event_id":"activity-2","sequence":2}"#)) else { return XCTFail("missing source event must deliver") }
        XCTAssertEqual(await port.terminalDeliveries, 0, "later continuity cannot fabricate the withheld terminal")
        guard case .delivered = await adapter.ingestOutcome(stop3) else { return XCTFail("only exact terminal redelivery may complete") }
        XCTAssertEqual(await port.terminalDeliveries, 1)
    }

    func testHealthNeverClaimsTerminalAndCoversDegradation() async {
        let port = RecordingPort(snapshot: snapshot()); let adapter = CodexCLIAdapter(port: port, integrationInstanceID: installation, helperID: "helper", authenticator: .init(secret: "s"))
        await adapter.setEnabledIntent(true); await adapter.reportTimeout(); XCTAssertEqual(await adapter.health().reason, .transportTimeout)
        await adapter.reportConfiguration(reason: .duplicateDefinition); XCTAssertEqual(await adapter.health().reason, .duplicateDefinition)
        await adapter.reportConfiguration(reason: .configurationDrift); XCTAssertEqual(await adapter.health().reason, .configurationDrift)
        _ = await adapter.negotiate(version: .init(productVersion: "", documentedHooksAvailable: false)); XCTAssertEqual(await adapter.health().reason, .unsupportedVersion)
    }

    func testFreshPlanApprovalApplyVerifyAndExactRemovalPreserveTOML() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml"); let original = "# keep\nprofile = \"safe\"\n[profiles.work]\nmode = \"read-only\"\n"; try Data(original.utf8).write(to: config)
        let coordinator = CodexCLIInstallationCoordinator(runtimeContract: CodexFixtureHookRuntimeContract()); let scope = IntegrationInstallationScope(kind: .customPath, identifier: "selected", path: config); let plan = coordinator.makePlan(id: "fresh", installationID: installation, scope: scope, helperPath: root.appendingPathComponent("helper"), snapshot: snapshot())
        XCTAssertFalse(plan.entries.contains { $0.renderedLine.hasPrefix("notify") }); XCTAssertEqual(plan.entries.count, CodexHookName.allCases.count)
        let approval = try coordinator.approve(plan, personIdentifier: "person")
        let applied = coordinator.apply(approval, currentSnapshot: snapshot()); XCTAssertEqual(applied.status, .applied)
        let manifest = try XCTUnwrap(applied.manifest); let helper = root.appendingPathComponent("helper")
        XCTAssertTrue(String(decoding: ExactEntryEditor.snapshot(at: config).content ?? Data(), as: UTF8.self).contains("[profiles.work]")); XCTAssertEqual(ExactEntryEditor.snapshot(at: helper).fingerprint.permissionBits, 0o700)
        let bootstrap = String(decoding: try Data(contentsOf: helper), as: UTF8.self); XCTAssertTrue(bootstrap.contains("AGENT_ISLAND_INSTALLATION_ID='codex-install'")); XCTAssertTrue(bootstrap.contains("AGENT_ISLAND_CODEX_OBSERVATION_ONLY=1")); XCTAssertTrue(bootstrap.contains("CodexHookHelper")); XCTAssertFalse(bootstrap.contains("claude-actions.sock"))
        let removalPlan = coordinator.makeRemovalPlan(id: "remove", installationID: installation, manifest: manifest, snapshot: snapshot())
        let removal = coordinator.remove(try coordinator.approve(removalPlan, personIdentifier: "person"), manifest: manifest)
        XCTAssertEqual(removal.status, .removed); XCTAssertEqual(ExactEntryEditor.snapshot(at: config).content, Data(original.utf8)); XCTAssertFalse(FileManager.default.fileExists(atPath: helper.path))
    }

    func testExistingOrDuplicateReviewedHookDefinitionRequiresManualRemedyWithoutMutation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml"); let original = "hooks.SessionStart = [\"outside-helper\"]\n"; try Data(original.utf8).write(to: config)
        let coordinator = CodexCLIInstallationCoordinator(runtimeContract: CodexFixtureHookRuntimeContract()); let plan = coordinator.makePlan(id: "ambiguous", installationID: installation, scope: .init(kind: .customPath, identifier: "selected", path: config), helperPath: root.appendingPathComponent("helper"), snapshot: snapshot())
        XCTAssertEqual(plan.compatibility, .incompatible)
        XCTAssertTrue(plan.manualRemedy.contains("manual"))
        XCTAssertEqual(ExactEntryEditor.snapshot(at: config).content, Data(original.utf8))
    }

    func testDiscoveryExaminesEveryOwnedHookSelector() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml"); try Data("hooks.Stop = [\"outside-helper\"]\n".utf8).write(to: config)
        let coordinator = CodexCLIInstallationCoordinator(runtimeContract: CodexFixtureHookRuntimeContract())
        let discovery = coordinator.discover(installationID: installation, scope: .init(kind: .customPath, identifier: "selected", path: config), helperPath: root.appendingPathComponent("helper"), snapshot: snapshot())
        XCTAssertEqual(discovery.state, .externalCandidate); XCTAssertFalse(discovery.safeToMutate)
    }

    func testHelperContractPathSafetyAndApplyRollbackFailClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml"); try Data("# keep\n".utf8).write(to: config)
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "selected", path: config)
        let coordinator = CodexCLIInstallationCoordinator(runtimeContract: CodexFixtureHookRuntimeContract())
        let unsafe = coordinator.makePlan(id: "unsafe", installationID: installation, scope: scope, helperPath: root.appendingPathComponent("bad\"path"), snapshot: snapshot())
        XCTAssertEqual(unsafe.compatibility, .interfaceChanged); XCTAssertTrue(unsafe.entries.isEmpty)
        let helper = root.appendingPathComponent("helper")
        let plan = coordinator.makePlan(id: "rollback", installationID: installation, scope: scope, helperPath: helper, snapshot: snapshot())
        let approval = try coordinator.approve(plan, personIdentifier: "person")
        try Data("# changed\n".utf8).write(to: config)
        let rollback = coordinator.apply(approval, currentSnapshot: snapshot())
        XCTAssertEqual(rollback.status, .stale); XCTAssertFalse(FileManager.default.fileExists(atPath: helper.path), "created helper must roll back when configuration cannot apply")
        let fresh = coordinator.makePlan(id: "changed-helper", installationID: installation, scope: scope, helperPath: helper, snapshot: snapshot())
        try Data("not bootstrap".utf8).write(to: helper)
        let changed = coordinator.apply(try coordinator.approve(fresh, personIdentifier: "person"), currentSnapshot: snapshot())
        XCTAssertEqual(changed.reason, .sourceChanged)
        try FileManager.default.removeItem(at: helper); try FileManager.default.createSymbolicLink(atPath: helper.path, withDestinationPath: config.path)
        let symlink = coordinator.apply(try coordinator.approve(fresh, personIdentifier: "person"), currentSnapshot: snapshot())
        XCTAssertEqual(symlink.reason, .symlinkChanged)
    }

    func testUnprovenRuntimeContractNeverPlansOrApplies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml"); try Data().write(to: config)
        let plan = CodexCLIInstallationCoordinator().makePlan(id: "unproven", installationID: installation, scope: .init(kind: .customPath, identifier: "selected", path: config), helperPath: root.appendingPathComponent("helper"), snapshot: snapshot())
        XCTAssertEqual(plan.compatibility, .interfaceChanged)
        XCTAssertEqual(CodexCLIInstallationCoordinator().apply(try CodexCLIInstallationCoordinator().approve(plan, personIdentifier: "person"), currentSnapshot: snapshot()).status, .blocked)
    }
}

private actor RecordingPort: AdapterIntakePort {
    let accepted: NegotiationSnapshot
    var deliveries = 0
    var terminalDeliveries = 0
    var reconciliationDeliveries = 0
    init(snapshot: NegotiationSnapshot) { accepted = snapshot }
    func negotiate(_ request: NegotiationRequest) async -> NegotiationOutcome { .compatible(accepted) }
    func deliver(_ envelope: RawEventEnvelope) async -> IntakeOutcome { deliveries += 1; if envelope.family == .reconciliation { reconciliationDeliveries += 1 }; if envelope.activityKind == .completed || envelope.activityKind == .failed || envelope.activityKind == .stopped { terminalDeliveries += 1 }; return .committed(ledgerRevision: Int64(deliveries)) }
    func reportObservationBoundary(_ report: ObservationBoundaryReport) async -> IntakeOutcome { deliveries += 1; return .committed(ledgerRevision: Int64(deliveries)) }
}
