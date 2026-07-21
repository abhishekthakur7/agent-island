import XCTest
@testable import CursorHooksAdapter
import SessionDomain
import SessionStore
import ApplicationRuntime
import ClaudeCodeAdapter

final class CursorHooksAdapterTests: XCTestCase {
    private let installation = IntegrationInstanceID("cursor-installation")
    private let evidence = CursorHooksContractEvidence(productVersion: "1.7.2")
    private let auth = ClaudeIPCAuthenticator(secret: "cursor-fixture-secret")
    private func hook(_ name: String, conversation: String = "conversation", generation: String = "generation", extra: String = "") -> Data {
        Data("{\"conversation_id\":\"\(conversation)\",\"generation_id\":\"\(generation)\",\"hook_event_name\":\"\(name)\",\"cursor_version\":\"1.7.2\"\(extra)}".utf8)
    }
    private func runtime() -> (ApplicationRuntime, SessionStore) { let store = SessionStore(); return (ApplicationRuntime(store: store, idGenerator: { "cursor-negotiation" }, clock: { Date(timeIntervalSince1970: 400) }), store) }
    private func adapter(_ port: ApplicationRuntime) -> CursorHooksAdapter { CursorHooksAdapter(port: port, integrationInstanceID: installation, helperID: "cursor-helper", authenticator: auth, evidence: evidence) }
    private func delivered(_ outcome: CursorHookIntakeOutcome, file: StaticString = #filePath, line: UInt = #line) { if case .delivered = outcome { return }; XCTFail("expected canonical delivery", file: file, line: line) }
    private func reason(_ outcome: CursorHookIntakeOutcome) -> CursorHookRejection? { switch outcome { case .degraded(let d), .unavailable(let d): d.reason; case .delivered: nil } }
    private func frame(_ payload: Data, nonce: String) -> Data {
        try! ClaudeHookIPCFrame.encode(.init(installationID: installation, helperID: "cursor-helper", nonce: nonce, payload: payload, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth))
    }
    private func oversizedFrame() -> Data {
        var frame = Data(ClaudeHookIPCFrame.magic); frame.append(ClaudeHookIPCFrame.version)
        var length = UInt32(ClaudeHookIPCFrame.maxFrameBytes + 1).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        return frame
    }

    func testCanonicalFactsUseCursorConversationAndGenerationOwners() async {
        let (port, store) = runtime(); let subject = adapter(port); _ = await subject.negotiate()
        delivered(await subject.receiveFixture(hook("sessionStart", conversation: "a", generation: "one")))
        delivered(await subject.receiveFixture(hook("preToolUse", conversation: "a", generation: "two")))
        delivered(await subject.receiveFixture(hook("subagentStart", conversation: "a", generation: "two", extra: ",\"subagent_id\":\"child\",\"parent_conversation_id\":\"a\"")))
        delivered(await subject.receiveFixture(hook("afterShellExecution", conversation: "a", generation: "two", extra: ",\"exit_code\":0")))
        let sessions = await store.workingSetProjections(); let projection = sessions[AgentSessionIdentity(productNamespace: .init("cursor"), nativeSessionID: .init("a"))]
        XCTAssertEqual(sessions.count, 1); XCTAssertEqual(projection?.turns.map(\.nativeTurnID), ["two"])
        XCTAssertEqual(projection?.subagentRuns.first?.nativeSubagentRunID, "child")
        XCTAssertEqual(projection?.subagentRuns.first?.ownerNativeTurnID, "two")
        XCTAssertEqual(projection?.execution, .unresolved, "active child prevents invented terminal session completion")
    }

    func testCompactionTerminalSessionEndAndAmbiguousChildStopAreConservative() async {
        let (port, store) = runtime(); let subject = adapter(port); _ = await subject.negotiate()
        delivered(await subject.receiveFixture(hook("sessionStart")))
        delivered(await subject.receiveFixture(hook("preCompact", generation: "two")))
        XCTAssertEqual((await store.workingSetProjections()).values.first?.observation, .gap)
        XCTAssertEqual(reason(await subject.receiveFixture(hook("subagentStop", generation: "three", extra: ",\"status\":\"completed\""))), .unresolvedSubagentStop)
        XCTAssertEqual(reason(await subject.receiveFixture(hook("stop", generation: "four", extra: ",\"status\":\"mystery\""))), .ambiguousOwnership)
        delivered(await subject.receiveFixture(hook("sessionEnd", generation: "five", extra: ",\"reason\":\"window_close\"")))
        let projection = (await store.workingSetProjections()).values.first
        XCTAssertFalse(projection!.execution.isTerminal); XCTAssertEqual(projection?.observation, .unavailable)
    }

    func testAuthenticatedReceiverRejectsReplayCrossOwnerAndTransportLoss() async {
        let (port, store) = runtime(); let subject = adapter(port); _ = await subject.negotiate()
        let payload = hook("sessionStart", conversation: "secure")
        let accepted = ClaudeHookIPCMessage(installationID: installation, helperID: "cursor-helper", nonce: "n1", payload: payload, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth)
        let receiver = CursorHooksReceiver(adapter: subject)
        delivered(await receiver.receive(frame: try! ClaudeHookIPCFrame.encode(accepted), at: Date(timeIntervalSince1970: 400)))
        XCTAssertEqual(reason(await receiver.receive(frame: try! ClaudeHookIPCFrame.encode(accepted), at: Date(timeIntervalSince1970: 400))), .duplicateOrCollision)
        let cross = ClaudeHookIPCMessage(installationID: .init("other"), helperID: "cursor-helper", nonce: "n2", payload: payload, issuedAt: Date(timeIntervalSince1970: 400), authenticator: auth)
        XCTAssertEqual(reason(await receiver.receive(frame: try! ClaudeHookIPCFrame.encode(cross), at: Date(timeIntervalSince1970: 400))), .unavailable)
        XCTAssertEqual(reason(await receiver.receive(frame: Data("malformed".utf8), at: Date(timeIntervalSince1970: 400))), .transportFailure)
        await receiver.transportLost(at: Date(timeIntervalSince1970: 401))
        XCTAssertEqual((await store.workingSetProjections()).values.first?.observation, .unavailable)
        XCTAssertEqual(reason(await subject.receiveFixture(payload)), .orphanBeforeActivation)
    }

    func testMalformedVersionPrivacyAndAttentionAreFailOpen() async {
        let (port, store) = runtime(); let subject = adapter(port); _ = await subject.negotiate()
        XCTAssertEqual(reason(await subject.receiveFixture(Data("bad".utf8))), .malformedEnvelope)
        XCTAssertEqual(reason(await subject.receiveFixture(Data(repeating: 0, count: CursorHookEnvelope.maximumBytes + 1))), .oversizedEnvelope)
        // Any installed Cursor version is accepted — a differing cursor_version
        // is delivered (works with whatever is available), and the private
        // email is never retained in the projection.
        delivered(await subject.receiveFixture(Data("{\"conversation_id\":\"secret\",\"generation_id\":\"turn\",\"hook_event_name\":\"sessionStart\",\"cursor_version\":\"1.7.3\",\"user_email\":\"private@example.test\"}".utf8)))
        XCTAssertFalse((await store.workingSetProjections()).description.contains("private@example"))
        let attention = CursorAttentionPresentation(); XCTAssertEqual(attention.dispatchCount, 0); XCTAssertTrue(attention.jumpBackLevel.contains("App-only"))
    }

    func testInstallationLifecycleExactOwnershipAndEligibility() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-hooks-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let cursor = root.appendingPathComponent(".cursor"); try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        let path = cursor.appendingPathComponent("hooks.json"); let original = "{\n  \"version\": 1,\n  \"unrelated\": { \"order\": 7 }\n}\n"; try Data(original.utf8).write(to: path)
        let helper = root.appendingPathComponent("helper"); try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "test-selected", path: path); let coordinator = CursorHooksInstallationCoordinator(runtimeContract: CursorFixtureHookRuntimeContract())
        XCTAssertEqual(coordinator.discover(installationID: installation, scope: scope, helperPath: helper, evidence: evidence).state, .notConfigured)
        let plan = coordinator.makePlan(id: "plan", installationID: installation, scope: scope, helperPath: helper, evidence: evidence); guard let manifest = coordinator.apply(coordinator.approve(plan, personIdentifier: "person"), helperPath: helper, evidence: evidence).manifest else { return XCTFail("expected manifest") }
        XCTAssertTrue(try String(contentsOf: path).contains("\"unrelated\": { \"order\": 7 }")); XCTAssertEqual(coordinator.verify(manifest, helperPath: helper).status, .applied)
        XCTAssertEqual(coordinator.disable(manifest, helperPath: helper).status, .applied)
        let plan2 = coordinator.makePlan(id: "re-enable", installationID: installation, scope: scope, helperPath: helper, evidence: evidence); guard let manifest2 = coordinator.apply(coordinator.approve(plan2, personIdentifier: "person"), helperPath: helper, evidence: evidence).manifest else { return XCTFail("expected fresh manifest") }
        XCTAssertEqual(coordinator.remove(manifest2, helperPath: helper).status, .applied)
        let bad = IntegrationInstallationScope(kind: .customPath, identifier: "test-selected", path: root.appendingPathComponent("hooks.jsonc")); XCTAssertEqual(coordinator.makePlan(id: "bad", installationID: installation, scope: bad, helperPath: helper, evidence: evidence).compatibility, .interfaceChanged)
    }

    func testOnlyCommittedSessionStartActivatesItsCurrentEpoch() async {
        let (port, store) = runtime(); let subject = adapter(port); _ = await subject.negotiate()
        XCTAssertEqual(reason(await subject.receiveFixture(hook("preToolUse", conversation: "orphan"))), .orphanBeforeActivation)
        XCTAssertTrue((await store.workingSetProjections()).isEmpty)
        delivered(await subject.receiveFixture(hook("sessionStart", conversation: "one")))
        delivered(await subject.receiveFixture(hook("sessionStart", conversation: "two")))
        delivered(await subject.receiveFixture(hook("preToolUse", conversation: "one", generation: "two")))
        await subject.reportHelperLoss()
        _ = await subject.negotiate()
        XCTAssertEqual(reason(await subject.receiveFixture(hook("preToolUse", conversation: "one", generation: "three"))), .orphanBeforeActivation)
        delivered(await subject.receiveFixture(hook("sessionStart", conversation: "one", generation: "four")))
        XCTAssertEqual((await store.workingSetProjections()).count, 2)
    }

    func testToolAndShellOutcomesRemainWorkingAndHaveOnlyBoundedSemantics() async {
        let (port, store) = runtime(); let subject = adapter(port); _ = await subject.negotiate()
        delivered(await subject.receiveFixture(hook("sessionStart", conversation: "outcomes")))
        delivered(await subject.receiveFixture(hook("afterShellExecution", conversation: "outcomes", generation: "shell-ok", extra: ",\"exit_code\":0")))
        delivered(await subject.receiveFixture(hook("afterShellExecution", conversation: "outcomes", generation: "shell-fail", extra: ",\"exit_code\":1")))
        delivered(await subject.receiveFixture(hook("postToolUseFailure", conversation: "outcomes", generation: "tool", extra: ",\"command\":\"command-secret\",\"error\":\"response-secret\"")))
        let projection = (await store.workingSetProjections()).values.first
        XCTAssertEqual(projection?.execution, .working)
        XCTAssertFalse(projection!.execution.isTerminal)
        XCTAssertFalse(String(describing: projection).contains("command-secret"))
        XCTAssertFalse(String(describing: projection).contains("response-secret"))
    }

    func testUnprovenRuntimeNeverPlansOrApplies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-unproven-\(UUID().uuidString)"); try FileManager.default.createDirectory(at: root.appendingPathComponent(".cursor"), withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let hooks = root.appendingPathComponent(".cursor/hooks.json"); try Data("{\"version\":1}".utf8).write(to: hooks)
        let helper = root.appendingPathComponent("helper"); try Data("#!/bin/sh\n".utf8).write(to: helper); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "test-unproven", path: hooks)
        let coordinator = CursorHooksInstallationCoordinator()
        let plan = coordinator.makePlan(id: "unproven", installationID: installation, scope: scope, helperPath: helper, evidence: evidence)
        XCTAssertNotEqual(plan.compatibility, .compatible)
        XCTAssertNil(coordinator.apply(coordinator.approve(plan, personIdentifier: "person"), helperPath: helper, evidence: evidence).manifest)
    }

    func testWeakClaimsKeepSemanticCollisionAndNeverRetainRawContent() async {
        let (port, store) = runtime()
        guard case let .compatible(snapshot) = await port.negotiate(CursorHooksAdapter(port: port, integrationInstanceID: installation, helperID: "cursor-helper", authenticator: auth, evidence: evidence).negotiationRequest()) else { return XCTFail("expected negotiation") }
        func envelope(_ variant: String) -> RawEventEnvelope {
            .init(negotiationSnapshotID: snapshot.id, integrationInstanceID: installation, contractVersion: snapshot.contractVersion, productNamespace: "cursor", nativeSessionID: "weak", eventIdentity: .weak("same-key"), family: .sessionActivity, sourceVariant: variant, activityKind: .working, classification: .operationalMetadata, payloadByteSize: 0, ownership: .init(nativeTurnID: "turn"), integrationMode: CursorHooksIntegration.integrationMode, capabilityID: CursorHooksIntegration.observationCapability, capabilityDirection: .observe, capabilityRevision: 1)
        }
        let succeeded = envelope("cursor.hook.afterShellExecution.succeeded")
        XCTAssertEqual(await store.intake(succeeded, receiptTime: Date()), .committed(ledgerRevision: 1))
        XCTAssertEqual(await store.intake(succeeded, receiptTime: Date()), .duplicateIgnored(ledgerRevision: 1))
        XCTAssertEqual(await store.intake(envelope("cursor.hook.afterShellExecution.failed"), receiptTime: Date()), .committed(ledgerRevision: 2))
        let projection = (await store.workingSetProjections()).values.first
        XCTAssertEqual(projection?.execution, .unresolved)
        XCTAssertEqual(projection?.observation, .gap)
        XCTAssertFalse(String(describing: await store.diagnostics).contains("command-secret"))
    }

    func testCanonicalGapSubagentStopAndHelperHealthAreConservative() async {
        let (port, store) = runtime(); let subject = adapter(port); let receiver = CursorHooksReceiver(adapter: subject); _ = await subject.negotiate()
        delivered(await receiver.receive(frame: frame(hook("sessionStart", conversation: "health", generation: "one"), nonce: "health-start")))
        XCTAssertEqual(reason(await subject.reportWeakOrderingGap()), .deliveryGap)
        XCTAssertEqual((await store.workingSetProjections()).values.first?.observation, .gap)
        delivered(await receiver.receive(frame: frame(hook("subagentStart", conversation: "health", generation: "two", extra: ",\"subagent_id\":\"known\",\"parent_conversation_id\":\"health\""), nonce: "health-child")))
        XCTAssertEqual(reason(await receiver.receive(frame: frame(hook("subagentStop", conversation: "health", generation: "two", extra: ",\"status\":\"completed\""), nonce: "health-stop"))), .unresolvedSubagentStop)
        var projection = (await store.workingSetProjections()).values.first
        XCTAssertEqual(projection?.subagentRuns.map(\.nativeSubagentRunID), ["known"])
        XCTAssertFalse(projection!.subagentRuns[0].execution.isTerminal)
        XCTAssertEqual(projection?.execution, .unresolved)
        XCTAssertEqual(reason(await subject.reportHelperFailure(.timeout)), .timeout)
        XCTAssertEqual((await store.workingSetProjections()).values.first?.observation, .gap)
        XCTAssertEqual(reason(await subject.reportHelperFailure(.transportFailure)), .transportFailure)
        projection = (await store.workingSetProjections()).values.first
        XCTAssertEqual(projection?.observation, .unavailable)
        XCTAssertEqual(projection?.execution, .unresolved)
    }

    func testFramedOversizeAndMalformedFramesHaveExactRejections() async {
        let (port, store) = runtime(); let subject = adapter(port); let receiver = CursorHooksReceiver(adapter: subject); _ = await subject.negotiate()
        // The encoder rejects the base64-expanded 65,537-byte payload; this
        // explicit header exercises the framed decoder's size rejection.
        XCTAssertEqual(reason(await receiver.receive(frame: oversizedFrame())), .oversizedEnvelope)
        XCTAssertEqual(reason(await receiver.receive(frame: Data("not-a-frame".utf8))), .transportFailure)
        XCTAssertTrue((await store.workingSetProjections()).isEmpty)
    }

    func testInstallationFailurePreflightAndLifecycleMatrix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-install-matrix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".cursor"), withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let hooks = root.appendingPathComponent(".cursor/hooks.json"); let helper = root.appendingPathComponent("helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let coordinator = CursorHooksInstallationCoordinator(runtimeContract: CursorFixtureHookRuntimeContract())
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "test-matrix", path: hooks)
        func plan(_ id: String) -> IntegrationInstallationPlan { coordinator.makePlan(id: id, installationID: installation, scope: scope, helperPath: helper, evidence: evidence) }

        // New-file creation uses the selected safe parent, then removal while enabled is exact.
        let initial = plan("new")
        guard let manifest = coordinator.apply(coordinator.approve(initial, personIdentifier: "person"), helperPath: helper, evidence: evidence).manifest else { return XCTFail("new-file apply") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: hooks.path))
        XCTAssertEqual(coordinator.remove(manifest, helperPath: helper).status, .applied)

        try Data("{\"version\":1,\"unrelated\":true}".utf8).write(to: hooks); try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: hooks.path)
        let drift = plan("drift"); try Data("{\"version\":1,\"changed\":true}".utf8).write(to: hooks)
        XCTAssertEqual(coordinator.apply(coordinator.approve(drift, personIdentifier: "person"), helperPath: helper, evidence: evidence).status, .stale)
        XCTAssertEqual(try String(contentsOf: hooks), "{\"version\":1,\"changed\":true}")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: hooks.path)[.posixPermissions] as? NSNumber)?.intValue, 0o640)

        try Data("{\"version\":1,\"hooks\":{\"sessionStart\":[{\"command\":\"x # agent-island:cursor-hooks-observation:v1:sessionStart\"},{\"command\":\"y # agent-island:cursor-hooks-observation:v1:sessionStart\"}]}}".utf8).write(to: hooks)
        let collisionBefore = try Data(contentsOf: hooks)
        XCTAssertEqual(coordinator.apply(coordinator.approve(plan("collision"), personIdentifier: "person"), helperPath: helper, evidence: evidence).status, .blocked)
        XCTAssertEqual(try Data(contentsOf: hooks), collisionBefore, "marker collision preflight has no partial writes")

        try Data("{\"version\":1,\"version\":1}".utf8).write(to: hooks)
        let malformedBefore = try Data(contentsOf: hooks)
        XCTAssertEqual(coordinator.apply(coordinator.approve(plan("duplicate-key"), personIdentifier: "person"), helperPath: helper, evidence: evidence).status, .blocked)
        XCTAssertEqual(try Data(contentsOf: hooks), malformedBefore)
        try Data("{\"version\":1,".utf8).write(to: hooks)
        let invalidBefore = try Data(contentsOf: hooks)
        XCTAssertNotEqual(coordinator.apply(coordinator.approve(plan("malformed"), personIdentifier: "person"), helperPath: helper, evidence: evidence).status, .applied)
        XCTAssertEqual(try Data(contentsOf: hooks), invalidBefore)
        try FileManager.default.removeItem(at: hooks); try FileManager.default.createSymbolicLink(at: hooks, withDestinationURL: helper)
        XCTAssertNotEqual(coordinator.apply(coordinator.approve(plan("symlink"), personIdentifier: "person"), helperPath: helper, evidence: evidence).status, .applied)
        try FileManager.default.removeItem(at: hooks); try Data("{\"version\":1}".utf8).write(to: hooks)
        XCTAssertEqual(coordinator.apply(coordinator.approve(plan("policy"), personIdentifier: "person"), helperPath: helper, evidence: evidence, policy: .denied).reason, .policyDenied)

        guard let enabled = coordinator.apply(coordinator.approve(plan("enabled"), personIdentifier: "person"), helperPath: helper, evidence: evidence).manifest else { return XCTFail("enabled apply") }
        try Data("{\"version\":1,\"unrelated-drift\":true}".utf8).write(to: hooks)
        XCTAssertEqual(coordinator.verify(enabled, helperPath: helper).status, .degraded)
        // A fresh owned install supports disable and a later explicit re-enable.
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: hooks.path)
        guard let fresh = coordinator.apply(coordinator.approve(plan("fresh"), personIdentifier: "person"), helperPath: helper, evidence: evidence).manifest else { return XCTFail("fresh apply") }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: hooks.path)[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        XCTAssertEqual(coordinator.disable(fresh, helperPath: helper).status, .applied)
        XCTAssertNotNil(coordinator.apply(coordinator.approve(plan("reenable"), personIdentifier: "person"), helperPath: helper, evidence: evidence).manifest)
    }
}
