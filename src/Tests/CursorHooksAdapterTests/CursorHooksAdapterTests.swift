import XCTest
@testable import CursorHooksAdapter
import SessionDomain

final class CursorHooksAdapterTests: XCTestCase {
    private let installation = IntegrationInstanceID("cursor-installation")
    private let evidence = CursorHooksContractEvidence(productVersion: "1.7.2", reviewedCursorVersions: ["1.7.2"])
    private func hook(_ name: String, conversation: String = "conversation", generation: String = "generation", extra: String = "") -> Data {
        Data("{\"conversation_id\":\"\(conversation)\",\"generation_id\":\"\(generation)\",\"hook_event_name\":\"\(name)\",\"cursor_version\":\"1.7.2\"\(extra)}".utf8)
    }

    func testConcurrentConversationsGenerationsLifecycleActivityCompactionAndNestedChild() async {
        let adapter = CursorHooksAdapter(integrationInstanceID: installation, evidence: evidence)
        await adapter.activateAfterInstallation()
        let startA = await adapter.receive(hook("sessionStart", conversation: "a", generation: "one")); XCTAssertNotNil(result(startA))
        let startB = await adapter.receive(hook("sessionStart", conversation: "b", generation: "one")); XCTAssertNotNil(result(startB))
        let activity = await adapter.receive(hook("preToolUse", conversation: "a", generation: "two")); XCTAssertNotNil(result(activity))
        let compact = await adapter.receive(hook("preCompact", conversation: "a", generation: "three")); XCTAssertNotNil(result(compact))
        let shell = await adapter.receive(hook("afterShellExecution", conversation: "a", generation: "four")); XCTAssertNotNil(result(shell))
        let child = await adapter.receive(hook("subagentStart", conversation: "a", generation: "five", extra: ",\"subagent_id\":\"child\",\"parent_conversation_id\":\"a\"")); XCTAssertNotNil(result(child))
        let end = await adapter.receive(hook("sessionEnd", conversation: "b", generation: "two")); guard let projection = result(end) else { return XCTFail("expected projection") }
        XCTAssertEqual(projection.sessions.count, 2)
        XCTAssertEqual(projection.sessions.map(\.nestedChildCount).max(), 1)
        XCTAssertEqual(projection.dispatchCount, 0)
        XCTAssertTrue(projection.ordering.contains("no documented event ID"))
    }

    func testNegativeFailuresAreFailOpenDegradedAndNeverCloseGuesswork() async {
        let adapter = CursorHooksAdapter(integrationInstanceID: installation, evidence: evidence)
        let orphan = await adapter.receive(hook("sessionStart")); XCTAssertEqual(reason(orphan), .orphanBeforeActivation)
        await adapter.activateAfterInstallation()
        let malformed = await adapter.receive(Data("bad".utf8)); XCTAssertEqual(reason(malformed), .malformedEnvelope)
        let oversize = await adapter.receive(Data(repeating: 0, count: CursorHookEnvelope.maximumBytes + 1)); XCTAssertEqual(reason(oversize), .oversizedEnvelope)
        let incompatible = Data("{\"conversation_id\":\"conversation\",\"generation_id\":\"other\",\"hook_event_name\":\"sessionStart\",\"cursor_version\":\"9.9.9\"}".utf8)
        let version = await adapter.receive(incompatible); XCTAssertEqual(reason(version), .unsupportedVersion)
        _ = await adapter.receive(hook("sessionStart", generation: "one"))
        let duplicate = await adapter.receive(hook("sessionStart", generation: "one")); XCTAssertEqual(reason(duplicate), .duplicateOrCollision)
        let ambiguousStop = await adapter.receive(hook("subagentStop", generation: "two", extra: ",\"status\":\"completed\"")); XCTAssertEqual(reason(ambiguousStop), .unresolvedSubagentStop)
        let gap = await adapter.reportWeakOrderingGap(); XCTAssertEqual(reason(gap), .deliveryGap)
        let timeout = await adapter.reportHelperFailure(.timeout); XCTAssertEqual(reason(timeout), .timeout)
    }

    func testExactVersionGateAttentionAndLeakSentinels() async {
        let adapter = CursorHooksAdapter(integrationInstanceID: installation, evidence: evidence)
        await adapter.activateAfterInstallation()
        let incompatible = Data("{\"conversation_id\":\"secret\",\"generation_id\":\"turn\",\"hook_event_name\":\"sessionStart\",\"cursor_version\":\"1.7.3\",\"user_email\":\"private@example.test\",\"transcript_path\":\"/private\"}".utf8)
        let outcome = await adapter.receive(incompatible); XCTAssertEqual(reason(outcome), .unsupportedVersion)
        let presentation = CursorAttentionPresentation()
        XCTAssertEqual(presentation.dispatchCount, 0)
        XCTAssertTrue(presentation.availability.contains("Cursor"))
        XCTAssertTrue(presentation.jumpBackLevel.contains("App-only"))
    }

    func testInstallVerifyDisableRepairRemovePreservesUnrelatedJSONC() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("hooks.jsonc")
        let original = "{\n  // preserve this\n  \"version\": 1,\n  \"unrelated\": { \"order\": 7 }\n}\n"
        try Data(original.utf8).write(to: path)
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "selected", path: path)
        let helper = URL(fileURLWithPath: CursorHooksIntegration.helperExecutablePath)
        let coordinator = CursorHooksInstallationCoordinator()
        let plan = coordinator.makePlan(id: "plan", installationID: installation, scope: scope, helperPath: helper, evidence: evidence)
        XCTAssertEqual(plan.compatibility, .compatible)
        let applied = coordinator.apply(coordinator.approve(plan, personIdentifier: "person"), helperPath: helper, evidence: evidence)
        guard let manifest = applied.manifest else { return XCTFail("expected manifest") }
        XCTAssertEqual(applied.status, .applied)
        let text = try String(contentsOf: path)
        XCTAssertTrue(text.contains("// preserve this")); XCTAssertTrue(text.contains("\"unrelated\": { \"order\": 7 }")); XCTAssertTrue(text.contains("\"command\"")); XCTAssertFalse(text.contains("failClosed"))
        XCTAssertEqual(coordinator.verify(manifest, helperPath: helper).status, .applied)
        XCTAssertEqual(coordinator.disable(manifest, helperPath: helper).status, .applied)
        XCTAssertEqual(coordinator.remove(manifest, helperPath: helper).status, .partial) // manifest entries were already disabled; no unowned removal
        XCTAssertEqual(coordinator.repair(id: "repair", installationID: installation, scope: scope, helperPath: helper, evidence: evidence).action, .repair)
    }

    private func result(_ outcome: CursorHookIntakeOutcome) -> CursorObservationProjection? { if case .delivered(let value) = outcome { return value }; return nil }
    private func reason(_ outcome: CursorHookIntakeOutcome) -> CursorHookRejection? { switch outcome { case .degraded(let diagnostic), .unavailable(let diagnostic): return diagnostic.reason; case .delivered: return nil } }
}
