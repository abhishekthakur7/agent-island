import XCTest
import Foundation
@testable import ClaudeCodeAdapter
import SessionDomain
import ApplicationRuntime

final class ClaudeCodeAdapterTests: XCTestCase {
    private func snapshot() -> NegotiationSnapshot {
        let records = ClaudeCodeIntegration.allObservationCapabilities.map {
            CapabilityRecord(id: $0, direction: .observe, availability: .available)
        } + [CapabilityRecord(id: WellKnownCapability.configuration, direction: .configure, availability: .available)]
        let request = NegotiationRequest(
            integrationInstanceID: IntegrationInstanceID("ab134-installation"),
            adapterKind: ClaudeCodeIntegration.adapterKind,
            adapterBuildVersion: ClaudeCodeIntegration.adapterBuildVersion,
            productNamespace: ClaudeCodeIntegration.productNamespace,
            integrationMode: ClaudeCodeIntegration.integrationMode,
            offeredContractVersion: ContractVersion(major: 1, minor: 0),
            requestedCapabilities: records.map(\.id),
            catalogRevision: ClaudeCodeIntegration.catalogRevision,
            productVersion: "1.0.0",
            interfaceVersion: ClaudeCodeIntegration.interfaceVersion,
            requestedCapabilityRecords: records
        )
        guard case .compatible(let result) = SessionDomainNegotiator.negotiate(request, id: NegotiationSnapshotID("ab134-snapshot"), negotiatedAt: Date(timeIntervalSince1970: 100)) else { fatalError("fixture negotiation") }
        return result
    }

    func testCapabilityCatalogIsObservationOnly() {
        XCTAssertTrue(ClaudeCodeIntegration.allObservationCapabilities.contains(ClaudeCodeIntegration.observationCapability))
        XCTAssertFalse(ClaudeCodeIntegration.allObservationCapabilities.contains(WellKnownCapability.sessionAction))
    }

    func testVersionEvidenceFailsClosedForUnknownAndNewerVersions() {
        XCTAssertEqual(ClaudeHooksVersionEvidence(productVersion: "not-a-version").support, .unknown)
        XCTAssertEqual(ClaudeHooksVersionEvidence(productVersion: "2.0.0").support, .newerThanReviewed)
        XCTAssertFalse(ClaudeHooksVersionEvidence(productVersion: "2.0.0").isObservationCompatible)
        XCTAssertEqual(ClaudeHooksVersionEvidence(productVersion: "1.0.0", interfaceVersion: "hooks-v2").support, .unsupported)
    }

    func testAuthenticatedNonceAndBoundedHookDecode() throws {
        let auth = ClaudeIPCAuthenticator(secret: "fixture-secret")
        let payload = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"sess-a\",\"event_id\":\"event-a\",\"sequence\":1}".utf8)
        let issued = Date(timeIntervalSince1970: 200)
        let message = ClaudeHookIPCMessage(installationID: IntegrationInstanceID("ab134-installation"), helperID: "helper-a", nonce: "nonce-a", payload: payload, issuedAt: issued, authenticator: auth)
        XCTAssertTrue(message.isAuthenticated(using: auth, expectedInstallationID: IntegrationInstanceID("ab134-installation"), expectedHelperID: "helper-a"))
        let hook = try ClaudeHookEnvelope.decode(payload)
        XCTAssertEqual(hook.nativeSessionID, "sess-a")
        XCTAssertThrowsError(try ClaudeHookEnvelope.decode(Data(repeating: 1, count: SessionDomainValidator.maxPayloadBytes + 1)))
    }

    func testDocumentedLifecycleAndStopSemanticsNormalizeWithoutContinuityFabrication() throws {
        let evidence = Date(timeIntervalSince1970: 300)
        let startData = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"sess-a\",\"event_id\":\"start\",\"sequence\":1,\"model\":\"model-a\",\"cwd\":\"/private/project\",\"transcript_path\":\"/private/transcript\",\"prompt_id\":\"prompt-a\"}".utf8)
        let start = try ClaudeHookEnvelope.decode(startData)
        guard case .success(let startObservation) = ClaudeHookNormalizer.normalize(start, snapshot: snapshot(), integrationInstanceID: IntegrationInstanceID("ab134-installation"), receiptTime: evidence) else { return XCTFail("start should normalize") }
        XCTAssertEqual(startObservation.events.count, 2)
        XCTAssertNotEqual(startObservation.events[0].eventIdentity, startObservation.events[1].eventIdentity)
        XCTAssertNotNil(startObservation.events[0].sourceCursor)
        XCTAssertNil(startObservation.events[1].sourceCursor)
        XCTAssertEqual(startObservation.attributedContext.model, "model-a")
        XCTAssertEqual(startObservation.attributedContext.transcriptPath, "/private/transcript")

        let backgroundData = Data("{\"hook_event_name\":\"Stop\",\"session_id\":\"sess-a\",\"event_id\":\"stop-bg\",\"background_task_count\":1}".utf8)
        let background = try ClaudeHookEnvelope.decode(backgroundData)
        guard case .success(let backgroundObservation) = ClaudeHookNormalizer.normalize(background, snapshot: snapshot(), integrationInstanceID: IntegrationInstanceID("ab134-installation"), receiptTime: evidence) else { return XCTFail("background stop should normalize") }
        XCTAssertEqual(backgroundObservation.events.first?.activityKind, .waiting)

        let endData = Data("{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"sess-a\",\"event_id\":\"end\"}".utf8)
        let end = try ClaudeHookEnvelope.decode(endData)
        guard case .success(let endObservation) = ClaudeHookNormalizer.normalize(end, snapshot: snapshot(), integrationInstanceID: IntegrationInstanceID("ab134-installation"), receiptTime: evidence) else { return XCTFail("session end should normalize") }
        XCTAssertEqual(endObservation.events.first?.family, .observationBoundary)
        XCTAssertNil(endObservation.events.first?.activityKind)
    }

    func testQuestionPlanNotificationChildAndProtectedContent() throws {
        let questionData = Data("{\"hook_event_name\":\"AskUserQuestion\",\"session_id\":\"sess-a\",\"event_id\":\"q\",\"request_id\":\"request-q\",\"questions\":[{\"question\":\"SECRET_PROMPT\",\"options\":[{\"label\":\"SECRET_OPTION\"},{\"label\":\"Other\"}]}]}".utf8)
        let question = try ClaudeHookEnvelope.decode(questionData)
        guard case .success(let observation) = ClaudeHookNormalizer.normalize(question, snapshot: snapshot(), integrationInstanceID: IntegrationInstanceID("ab134-installation"), receiptTime: Date()) else { return XCTFail("question should normalize") }
        XCTAssertEqual(observation.question?.semanticShape.kind, .structuredChoice)
        XCTAssertEqual(observation.protectedContent?.classification, .interactionContent)
        XCTAssertEqual(observation.question?.semanticShape.choices.first?.label, "Option 1")

        let unsupportedData = Data("{\"hook_event_name\":\"AskUserQuestion\",\"session_id\":\"sess-a\",\"event_id\":\"q-free\",\"request_id\":\"request-free\",\"questions\":[{\"question\":\"free text\"}]}".utf8)
        let unsupported = try ClaudeHookEnvelope.decode(unsupportedData)
        guard case .failure(.unsupportedResponseSemantics) = ClaudeHookNormalizer.normalize(unsupported, snapshot: snapshot(), integrationInstanceID: IntegrationInstanceID("ab134-installation"), receiptTime: Date()) else { return XCTFail("unsupported free text must use Host fallback") }

        let childData = Data("{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"sess-a\",\"event_id\":\"child-stop\",\"subagent_run_id\":\"child-1\",\"result\":{\"status\":\"ok\"}}".utf8)
        let child = try ClaudeHookEnvelope.decode(childData)
        guard case .success(let childObservation) = ClaudeHookNormalizer.normalize(child, snapshot: snapshot(), integrationInstanceID: IntegrationInstanceID("ab134-installation"), receiptTime: Date()) else { return XCTFail("proven child stop should normalize") }
        XCTAssertEqual(childObservation.events.first?.activityKind, .completed)

        let notificationData = Data("{\"hook_event_name\":\"Notification\",\"session_id\":\"sess-a\",\"event_id\":\"notice\"}".utf8)
        let notification = try ClaudeHookEnvelope.decode(notificationData)
        guard case .success(let cue) = ClaudeHookNormalizer.normalize(notification, snapshot: snapshot(), integrationInstanceID: IntegrationInstanceID("ab134-installation"), receiptTime: Date()) else { return XCTFail("notification should cue only") }
        XCTAssertNotNil(cue.cue)
        XCTAssertTrue(cue.events.isEmpty)
    }

    func testExactConfigurationFailsClosedForNestedClaudeJSONAndRedactedDiagnostics() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab134-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("settings.json")
        try Data("{\n  \"hooks\": []\n}\n".utf8).write(to: config)
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "selected", path: config)
        let discovery = ClaudeCodeInstallationCoordinator().discover(installationID: IntegrationInstanceID("i"), scope: scope, helperPath: root.appendingPathComponent("helper"))
        XCTAssertEqual(discovery.state, .unsupported)
        XCTAssertFalse(discovery.safeToMutate)
        let health = ClaudeIntegrationHealth(enabledIntent: true, lastReason: .unauthenticated, observedAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(health.redactedDiagnostic.scope.owner, .integration)
        XCTAssertEqual(health.redactedDiagnostic.reason, .permissionDenied)
    }

    func testAdapterIntakeRejectsAuthCrossOwnerReplayAndRetainsIPCDegradation() async {
        let runtime = ApplicationRuntime(store: SessionStore(), idGenerator: { "generated" }, clock: { Date(timeIntervalSince1970: 400) })
        let installation = IntegrationInstanceID("ab134-installation")
        let auth = ClaudeIPCAuthenticator(secret: "fixture-secret")
        let adapter = ClaudeCodeAdapter(port: runtime, integrationInstanceID: installation, helperID: "helper-a", authenticator: auth)
        guard case .compatible = await adapter.negotiate(version: ClaudeHooksVersionEvidence(productVersion: "1.0.0", observedAt: Date(timeIntervalSince1970: 400)), at: Date(timeIntervalSince1970: 400)) else { return XCTFail("known version should negotiate") }
        _ = await adapter.setEnabledIntent(true, at: Date(timeIntervalSince1970: 400))
        let payload = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"sess-a\",\"event_id\":\"start\",\"sequence\":1}".utf8)
        let unauthenticated = ClaudeHookIPCMessage(installationID: installation, helperID: "helper-a", nonce: "bad-auth", payload: payload, issuedAt: Date(timeIntervalSince1970: 400), authenticationTag: "bad")
        let unauthenticatedReport = await adapter.ingest(unauthenticated, at: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(unauthenticatedReport.rejection, .unauthenticated)
        let accepted = await adapter.ingest(ClaudeHookIPCMessage(installationID: installation, helperID: "helper-a", nonce: "good-auth", payload: payload, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth), at: Date(timeIntervalSince1970: 400))
        XCTAssertTrue(accepted.accepted)
        let duplicate = await adapter.ingest(ClaudeHookIPCMessage(installationID: installation, helperID: "helper-a", nonce: "duplicate-event", payload: payload, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth), at: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(duplicate.rejection, .duplicateEvent)
        let crossOwner = ClaudeHookIPCMessage(installationID: IntegrationInstanceID("other"), helperID: "helper-a", nonce: "cross-owner", payload: payload, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth)
        let crossOwnerReport = await adapter.ingest(crossOwner, at: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(crossOwnerReport.rejection, .crossOwner)
        await adapter.reportHelperLoss(at: Date(timeIntervalSince1970: 401))
        let health = await adapter.health
        XCTAssertEqual(health.helperReachability, .unavailable)
    }
}
