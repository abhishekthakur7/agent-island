import Foundation
import CursorHooksAdapter
import ClaudeCodeAdapter
import ApplicationRuntime
import SessionStore
import SessionDomain

@main struct AB138SelfCheck {
    static func main() async {
        let fixture = CommandLine.arguments.dropFirst().first
        let store = SessionStore()
        let runtime = ApplicationRuntime(store: store, idGenerator: { "ab138-negotiation" }, clock: { Date(timeIntervalSince1970: 400) })
        let installation = IntegrationInstanceID("ab138-self-check")
        let auth = ClaudeIPCAuthenticator(secret: "ab138-self-check-secret")
        let subject = CursorHooksAdapter(port: runtime, integrationInstanceID: installation, helperID: "ab138-helper", authenticator: auth, evidence: .init(productVersion: "1.7.2", reviewedCursorVersions: ["1.7.2"]))
        guard case .compatible = await subject.negotiate(), let fixture, let data = try? Data(contentsOf: URL(fileURLWithPath: fixture)) else { exit(1) }
        var passed = true
        for line in data.split(separator: 10) where !line.isEmpty {
            let outcome = await subject.receive(Data(line))
            if case .delivered = outcome {} else { passed = false }
        }
        let sessions = await store.workingSetProjections()
        let child = sessions.values.flatMap(\.subagentRuns).contains { $0.nativeSubagentRunID == "fixture-child" && $0.ownerNativeTurnID == "generation-2" }
        let privateSentinels = sessions.description.contains("private@example") || sessions.description.contains("transcript_path")
        let ambiguous = await subject.receive(Data("{\"conversation_id\":\"fixture-conversation-a\",\"generation_id\":\"generation-9\",\"hook_event_name\":\"subagentStop\",\"cursor_version\":\"1.7.2\",\"status\":\"completed\"}".utf8))
        if case .degraded(let diagnostic) = ambiguous { passed = passed && diagnostic.reason == .unresolvedSubagentStop } else { passed = false }
        await subject.reportHelperLoss()
        passed = passed && sessions.count == 2 && child && !privateSentinels
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab138-install-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let hooks = root.appendingPathComponent(".cursor/hooks.json")
            try Data("{\"version\":1,\"unrelated\":true}".utf8).write(to: hooks)
            let helper = root.appendingPathComponent("helper")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            let scope = IntegrationInstallationScope(kind: .customPath, identifier: "test-ab138", path: hooks)
            let installer = CursorHooksInstallationCoordinator()
            let plan = installer.makePlan(id: "ab138", installationID: installation, scope: scope, helperPath: helper, evidence: .init(productVersion: "1.7.2", reviewedCursorVersions: ["1.7.2"]))
            if let manifest = installer.apply(installer.approve(plan, personIdentifier: "self-check"), helperPath: helper, evidence: .init(productVersion: "1.7.2", reviewedCursorVersions: ["1.7.2"])).manifest {
                passed = passed && installer.verify(manifest, helperPath: helper).status == .applied && installer.remove(manifest, helperPath: helper).status == .applied
            } else { passed = false }
        } catch { passed = false }
        print(passed ? "AB-138 replay PASS canonical-facts installation-ready privacy-safe" : "AB-138 replay FAIL")
        exit(passed ? 0 : 1)
    }
}
