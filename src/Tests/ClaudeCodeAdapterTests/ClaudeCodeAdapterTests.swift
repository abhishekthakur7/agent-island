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

    func testVersionEvidenceAcceptsAnyProductVersionAndGatesOnlyOnInterface() {
        // Work with whatever Claude Code version is installed — the documented
        // contract is identified by interfaceVersion, not the CLI release. Only
        // an interfaceVersion mismatch is unsupported.
        XCTAssertEqual(ClaudeHooksVersionEvidence(productVersion: "not-a-version").support, .known)
        XCTAssertEqual(ClaudeHooksVersionEvidence(productVersion: "2.0.0").support, .known)
        XCTAssertTrue(ClaudeHooksVersionEvidence(productVersion: "2.0.0").isObservationCompatible)
        XCTAssertEqual(ClaudeHooksVersionEvidence(productVersion: "1.0.0", interfaceVersion: "hooks-v2").support, .unsupported)
    }

    func testDerivedCredentialIsDeterministicIdentityBoundAndNonEmpty() {
        let installation = IntegrationInstanceID("agent-island-claude-user-v1")
        // The app and the separate helper binary each create their own store;
        // the whole point of the derived credential is that they agree with no
        // shared Keychain read, so simulate both sides with distinct instances.
        let appSide = DerivedClaudeHookCredentialStore()
        let helperSide = DerivedClaudeHookCredentialStore()

        let appSecret = appSide.secret(for: installation, helperID: "helper-a")
        let helperSecret = helperSide.secret(for: installation, helperID: "helper-a")
        XCTAssertEqual(appSecret, helperSecret)
        XCTAssertEqual(appSecret?.count, 32)
        XCTAssertEqual(appSecret?.isEmpty, false)

        // Identity binding: a different installation or helper yields a
        // different secret, so a frame minted for one tuple cannot authenticate
        // against another.
        XCTAssertNotEqual(appSecret, appSide.secret(for: installation, helperID: "helper-b"))
        XCTAssertNotEqual(appSecret, appSide.secret(for: IntegrationInstanceID("other"), helperID: "helper-a"))
    }

    func testDerivedCredentialAuthenticatesHelperFrameEndToEnd() throws {
        let installation = IntegrationInstanceID("agent-island-claude-user-v1")
        let store = DerivedClaudeHookCredentialStore()
        // Helper side builds the frame from its independently derived secret.
        let helperAuth = ClaudeIPCAuthenticator(secret: store.secret(for: installation, helperID: "helper-a")!)
        let payload = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s\",\"event_id\":\"e\",\"sequence\":1}".utf8)
        let issued = Date(timeIntervalSince1970: 200)
        let message = ClaudeHookIPCMessage(installationID: installation, helperID: "helper-a", nonce: UUID().uuidString, payload: payload, issuedAt: issued, authenticator: helperAuth)

        // App side re-derives the same secret and accepts the frame; a frame
        // bound to a different helper fails the identity check.
        let appAuth = ClaudeIPCAuthenticator(secret: store.secret(for: installation, helperID: "helper-a")!)
        XCTAssertTrue(message.isAuthenticated(using: appAuth, expectedInstallationID: installation, expectedHelperID: "helper-a", receivedAt: issued))
        let otherAuth = ClaudeIPCAuthenticator(secret: store.secret(for: installation, helperID: "helper-b")!)
        XCTAssertFalse(message.isAuthenticated(using: otherAuth, expectedInstallationID: installation, expectedHelperID: "helper-a", receivedAt: issued))
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

        let childData = Data("{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"sess-a\",\"event_id\":\"child-stop\",\"subagent_run_id\":\"child-1\",\"parent_turn_id\":\"turn-1\",\"result\":{\"status\":\"completed\"}}".utf8)
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
        XCTAssertEqual(discovery.state, .notConfigured)
        XCTAssertFalse(discovery.safeToMutate) // no negotiated configuration grant
        let health = ClaudeIntegrationHealth(enabledIntent: true, lastReason: .unauthenticated, observedAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(health.redactedDiagnostic.scope.owner, .integration)
        XCTAssertEqual(health.redactedDiagnostic.reason, .permissionDenied)
    }

    func testJSONExactEntryPreservesJSONCAndRemovesOnlyReceiptEntry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab134-jsonc-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("settings.jsonc")
        let original = "{\r\n  // keep this comment\r\n  \"other\": [1, 2],\r\n  \"hooks\": {\r\n    \"SessionStart\": [\r\n      {\"type\": \"command\", \"command\": \"upstream\"}\r\n    ],\r\n  },\r\n  \"unknown\": {\"x\": true}\r\n}\r\n"
        try Data(original.utf8).write(to: config)
        let entry = ClaudeJSONHookEditor.entry(helperPath: root.appendingPathComponent("helper"))
        let before = ExactEntryEditor.snapshot(at: config)
        let receipt = try ClaudeJSONHookEditor.add(entry: entry, at: config, expected: before.fingerprint)
        let added = try XCTUnwrap(String(data: ExactEntryEditor.snapshot(at: config).content ?? Data(), encoding: .utf8))
        XCTAssertTrue(added.contains("// keep this comment")); XCTAssertTrue(added.contains("\r\n")); XCTAssertTrue(added.contains(entry.selector.marker))
        _ = try ClaudeJSONHookEditor.remove(receipt: receipt, event: .sessionStart, at: config, expected: ExactEntryEditor.snapshot(at: config).fingerprint)
        XCTAssertEqual(String(data: ExactEntryEditor.snapshot(at: config).content ?? Data(), encoding: .utf8), original)
    }

    func testJSONRemovalHandlesCommentedArrayPositionsOrFailsWithoutMutation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab134-json-removal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("settings.jsonc")
        let entry = ClaudeJSONHookEditor.entry(helperPath: root.appendingPathComponent("helper"))
        let rendered = entry.selector.renderedLine
        let fixtures: [(String, String, Bool)] = [
            ("[\r\n  /* before */\r\n  \(rendered) /* after */,\r\n]", "[\r\n  /* before */\r\n   /* after */\r\n]", true),
            ("[\(rendered), /* keep */ {\"upstream\":1}]", "[ /* keep */ {\"upstream\":1}]", true),
            ("[{\"before\":1} /* keep */, \(rendered), /* keep */ {\"after\":2}]", "[{\"before\":1} /* keep */,  /* keep */ {\"after\":2}]", true),
            ("[{\"before\":1}, /* before owned */ \(rendered) /* tail */]", "[{\"before\":1} /* before owned */  /* tail */]", true),
            ("[\(rendered) /* adjacent to comma */, {\"upstream\":1}]", "[ /* adjacent to comma */ {\"upstream\":1}]", true)
        ]
        for (array, expected, supported) in fixtures {
            let source = "{\r\n  \"hooks\": {\r\n    \"SessionStart\": \(array)\r\n  }\r\n}\r\n"
            try Data(source.utf8).write(to: config)
            let snapshot = ExactEntryEditor.snapshot(at: config)
            let receipt = ExactEntryReceipt(selector: entry.selector, path: config.path, sourceFingerprint: snapshot.fingerprint)
            if supported {
                _ = try ClaudeJSONHookEditor.remove(receipt: receipt, event: .sessionStart, at: config, expected: snapshot.fingerprint)
                let actual = try XCTUnwrap(String(data: ExactEntryEditor.snapshot(at: config).content ?? Data(), encoding: .utf8))
                XCTAssertEqual(actual, "{\r\n  \"hooks\": {\r\n    \"SessionStart\": \(expected)\r\n  }\r\n}\r\n")
            }
        }
        let ambiguous = "{\"hooks\":{\"SessionStart\":[\(rendered),\(rendered)]}}"
        try Data(ambiguous.utf8).write(to: config)
        let snapshot = ExactEntryEditor.snapshot(at: config)
        let receipt = ExactEntryReceipt(selector: entry.selector, path: config.path, sourceFingerprint: snapshot.fingerprint)
        XCTAssertThrowsError(try ClaudeJSONHookEditor.remove(receipt: receipt, event: .sessionStart, at: config, expected: snapshot.fingerprint)) { error in
            XCTAssertEqual(error as? ClaudeJSONHookEditor.EditorError, .ambiguous)
        }
        XCTAssertEqual(ExactEntryEditor.snapshot(at: config).content, snapshot.content)
    }

    func testJSONExactEntryRoundTripPreservesMode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab134-json-mode-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("settings.jsonc")
        let original = "{\r\n  \"hooks\": {\r\n    \"SessionStart\": [\r\n      {\"type\":\"command\",\"command\":\"upstream\"}, // trailing\r\n    ]\r\n  }\r\n}\r\n"
        try Data(original.utf8).write(to: config)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o640)], ofItemAtPath: config.path)
        let entry = ClaudeJSONHookEditor.entry(helperPath: root.appendingPathComponent("helper"))
        let receipt = try ClaudeJSONHookEditor.add(entry: entry, at: config, expected: ExactEntryEditor.snapshot(at: config).fingerprint)
        XCTAssertEqual(ExactEntryEditor.snapshot(at: config).fingerprint.permissionBits, 0o640)
        _ = try ClaudeJSONHookEditor.remove(receipt: receipt, event: .sessionStart, at: config, expected: ExactEntryEditor.snapshot(at: config).fingerprint)
        XCTAssertEqual(ExactEntryEditor.snapshot(at: config).content, Data(original.utf8))
        XCTAssertEqual(ExactEntryEditor.snapshot(at: config).fingerprint.permissionBits, 0o640)
    }

    func testJSONInstallationCreatesPrivateExecutableHelper() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab134-helper-mode-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("settings.json")
        try Data("{\"hooks\":{}}".utf8).write(to: config)
        let helper = root.appendingPathComponent("helper")
        let coordinator = ClaudeCodeInstallationCoordinator()
        let negotiated = snapshot()
        let plan = coordinator.makePlan(id: "private-helper", installationID: IntegrationInstanceID("installation"), scope: IntegrationInstallationScope(kind: .customPath, identifier: "selected", path: config), helperPath: helper, snapshot: negotiated)
        let approval = try coordinator.approve(plan, personIdentifier: "person")
        let result = coordinator.apply(approval, currentSnapshot: negotiated, helperPath: helper)
        XCTAssertEqual(result.status, .applied)
        XCTAssertEqual(ExactEntryEditor.snapshot(at: helper).fingerprint.permissionBits, 0o700)
    }

    func testJSONEditorRejectsAmbiguousAndInvalidSourcesWithoutMutation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab134-json-invalid-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("settings.json")
        let entry = ClaudeJSONHookEditor.entry(helperPath: root.appendingPathComponent("helper"))

        let sources: [(Data, ClaudeJSONHookEditor.EditorError)] = [
            (Data("{\"hooks\":{},\"hooks\":{}}".utf8), .ambiguous),
            (Data("{ // comments are JSONC only\n\"hooks\":{}}".utf8), .commentsInJSON),
            (Data([0x7B, 0xFF, 0x7D]), .invalidUTF8),
            (Data("[]".utf8), .unsupported)
        ]
        for (source, expected) in sources {
            try source.write(to: config)
            let before = ExactEntryEditor.snapshot(at: config).content
            XCTAssertThrowsError(try ClaudeJSONHookEditor.add(entry: entry, at: config)) { error in
                XCTAssertEqual(error as? ClaudeJSONHookEditor.EditorError, expected)
            }
            XCTAssertEqual(ExactEntryEditor.snapshot(at: config).content, before)
        }
    }

    func testClaudeInstallationPlanCoversEveryDocumentedHookWithExactSelectors() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab134-plan-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("settings.json")
        try Data("{\"hooks\":{}}".utf8).write(to: config)
        let helper = root.appendingPathComponent("helper")
        let plan = ClaudeCodeInstallationCoordinator().makePlan(id: "plan", installationID: IntegrationInstanceID("installation"), scope: IntegrationInstallationScope(kind: .customPath, identifier: "selected", path: config), helperPath: helper, snapshot: snapshot())
        XCTAssertEqual(plan.entries.count, ClaudeHookName.allCases.count)
        XCTAssertEqual(Set(plan.entries.map(\.key)).count, plan.entries.count)
        XCTAssertTrue(plan.entries.allSatisfy { $0.marker.hasPrefix(ClaudeJSONHookEditor.markerPrefix) })
    }

    func testHelperFramingAuthenticatesBoundedPayloadAndEndpointPolicy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab134-endpoint-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let endpointURL = root.appendingPathComponent("endpoint")
        try Data().write(to: endpointURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: endpointURL.path)
        let transport = ClaudeInMemoryHookIPCTransport()
        let runtime = ClaudeHookHelperRuntime(installationID: IntegrationInstanceID("i"), helperID: "h", authenticator: ClaudeIPCAuthenticator(secret: "s"), endpoint: ClaudeLocalEndpoint(path: endpointURL, appOwnedRoot: root))
        let payload = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s\",\"event_id\":\"e\"}".utf8)
        let message = try await runtime.forward(stdin: payload, transport: transport)
        XCTAssertTrue(message.isAuthenticated(using: ClaudeIPCAuthenticator(secret: "s"), expectedInstallationID: IntegrationInstanceID("i"), expectedHelperID: "h", receivedAt: message.issuedAt))
        let frames = await transport.frames
        let frame = try XCTUnwrap(frames.first)
        XCTAssertEqual(try ClaudeHookIPCFrame.decode(frame).payload, payload)
        XCTAssertThrowsError(try ClaudeHookHelperRuntime(installationID: IntegrationInstanceID("i"), helperID: "h", credentialStore: InMemoryClaudeHookCredentialStore(secret: nil), endpoint: ClaudeLocalEndpoint(path: endpointURL, appOwnedRoot: root))) { error in
            XCTAssertEqual(error as? ClaudeHookHelperError, .credentialMissing)
        }
    }

    func testHelperForwardPropagatesEndpointAvailabilityFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab134-missing-endpoint-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ClaudeHookHelperRuntime(installationID: IntegrationInstanceID("i"), helperID: "h", authenticator: ClaudeIPCAuthenticator(secret: "s"), endpoint: ClaudeLocalEndpoint(path: root.appendingPathComponent("missing"), appOwnedRoot: root))
        do {
            _ = try await runtime.forward(stdin: Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"s\",\"event_id\":\"e\"}".utf8), transport: ClaudeInMemoryHookIPCTransport())
            XCTFail("missing endpoint must fail")
        } catch {
            XCTAssertEqual(error as? ClaudeHookHelperError, .endpointUnavailable)
        }
    }

    func testSynchronousActionHelperUsesSeparateTypedRoundTripAndWritesOnlyExactResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab135-action-endpoint-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let endpointURL = root.appendingPathComponent("endpoint")
        try Data().write(to: endpointURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: endpointURL.path)
        let runtime = ClaudeHookHelperRuntime(installationID: IntegrationInstanceID("i"), helperID: "h", authenticator: ClaudeIPCAuthenticator(secret: "s"), endpoint: ClaudeLocalEndpoint(path: endpointURL, appOwnedRoot: root))
        let payload = Data("{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s\",\"event_id\":\"e\",\"tool_use_id\":\"tool\",\"tool_name\":\"ExitPlanMode\",\"tool_input\":{\"plan\":\"x\"}}".utf8)
        let transport = ClaudeInMemoryHookActionIPCTransport(echoedResponse: .preToolAllow(updatedInput: Data("{\"plan\":\"x\",\"approved\":true}".utf8)), authenticator: ClaudeIPCAuthenticator(secret: "s"))
        let output = try await runtime.respondToAction(stdin: payload, deadline: Date().addingTimeInterval(1), transport: transport)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        XCTAssertEqual((decoded["hookSpecificOutput"] as? [String: Any])?["permissionDecision"] as? String, "allow")
        XCTAssertEqual((await transport.requests).count, 1)
    }

    #if canImport(Network)
    func testIPCCompletionGateIsOneShotAcrossEarlyFinishAndCompletion() async throws {
        let early = ClaudeIPCCompletionGate()
        early.finish(.failure(ClaudeHookHelperError.transportFailure))
        early.armTimeout(after: 0)
        do {
            try await awaitGate(early)
            XCTFail("early failure must resume the later-installed continuation")
        } catch {
            XCTAssertEqual(error as? ClaudeHookHelperError, .transportFailure)
        }

        let gate = ClaudeIPCCompletionGate()
        let waiter = Task { try await self.awaitGate(gate) }
        await Task.yield()
        gate.armTimeout(after: 60)
        gate.finish(.success(()))
        gate.finish(.failure(ClaudeHookHelperError.transportTimeout))
        try await waiter.value
    }

    private func awaitGate(_ gate: ClaudeIPCCompletionGate) async throws {
        try await withCheckedThrowingContinuation { continuation in gate.install(continuation) }
    }
    #endif

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
        let otherSession = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"sess-b\",\"event_id\":\"start\",\"sequence\":1}".utf8)
        let otherReport = await adapter.ingest(ClaudeHookIPCMessage(installationID: installation, helperID: "helper-a", nonce: "other-session", payload: otherSession, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth), at: Date(timeIntervalSince1970: 400))
        XCTAssertTrue(otherReport.accepted, "same Product event IDs are scoped by native session owner")
        let crossOwner = ClaudeHookIPCMessage(installationID: IntegrationInstanceID("other"), helperID: "helper-a", nonce: "cross-owner", payload: payload, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth)
        let crossOwnerReport = await adapter.ingest(crossOwner, at: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(crossOwnerReport.rejection, .crossOwner)
        await adapter.reportHelperLoss(at: Date(timeIntervalSince1970: 401))
        let health = await adapter.health
        XCTAssertEqual(health.helperReachability, .unavailable)
    }

    func testLiveChildLineageRejectsOrphanAndCrossParentStops() async {
        let runtime = ApplicationRuntime(store: SessionStore(), idGenerator: { "generated" }, clock: { Date(timeIntervalSince1970: 400) })
        let installation = IntegrationInstanceID("child-installation")
        let auth = ClaudeIPCAuthenticator(secret: "child-secret")
        let adapter = ClaudeCodeAdapter(port: runtime, integrationInstanceID: installation, helperID: "helper-child", authenticator: auth)
        _ = await adapter.negotiate(version: ClaudeHooksVersionEvidence(productVersion: "1.0.0", observedAt: Date(timeIntervalSince1970: 400)), at: Date(timeIntervalSince1970: 400))
        _ = await adapter.setEnabledIntent(true, at: Date(timeIntervalSince1970: 400))
        let start = Data("{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"sess\",\"event_id\":\"child-start\",\"subagent_run_id\":\"child\",\"parent_turn_id\":\"parent\"}".utf8)
        let started = await adapter.ingest(ClaudeHookIPCMessage(installationID: installation, helperID: "helper-child", nonce: "child-start", payload: start, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth), at: Date(timeIntervalSince1970: 400))
        XCTAssertTrue(started.accepted)
        let orphan = Data("{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"sess\",\"event_id\":\"orphan\",\"subagent_run_id\":\"missing\",\"parent_turn_id\":\"parent\",\"result\":{\"status\":\"completed\"}}".utf8)
        XCTAssertEqual((await adapter.ingest(ClaudeHookIPCMessage(installationID: installation, helperID: "helper-child", nonce: "orphan", payload: orphan, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth), at: Date(timeIntervalSince1970: 400))).rejection, .unprovenChildStop)
        let crossParent = Data("{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"sess\",\"event_id\":\"cross\",\"subagent_run_id\":\"child\",\"parent_turn_id\":\"other\",\"result\":{\"status\":\"completed\"}}".utf8)
        XCTAssertEqual((await adapter.ingest(ClaudeHookIPCMessage(installationID: installation, helperID: "helper-child", nonce: "cross", payload: crossParent, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth), at: Date(timeIntervalSince1970: 400))).rejection, .unprovenChildStop)
        await adapter.reportHelperLoss(at: Date(timeIntervalSince1970: 401))
        let stale = Data("{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"sess\",\"event_id\":\"stale\",\"subagent_run_id\":\"child\",\"parent_turn_id\":\"parent\",\"result\":{\"status\":\"completed\"}}".utf8)
        XCTAssertEqual((await adapter.ingest(ClaudeHookIPCMessage(installationID: installation, helperID: "helper-child", nonce: "stale", payload: stale, issuedAt: Date(timeIntervalSince1970: 401), authenticator: auth), at: Date(timeIntervalSince1970: 401))).rejection, .unprovenChildStop)
    }

    func testHookEnvelopeRejectsDuplicateIdentityKeys() {
        let duplicate = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"first\",\"session_id\":\"second\",\"event_id\":\"event\"}".utf8)
        XCTAssertThrowsError(try ClaudeHookEnvelope.decode(duplicate)) { error in
            XCTAssertEqual(error as? ClaudeHookRejection, .malformedEnvelope)
        }
    }
}
