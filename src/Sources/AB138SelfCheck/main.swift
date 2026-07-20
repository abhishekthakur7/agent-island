import Foundation
import CursorHooksAdapter
import ClaudeCodeAdapter
import ApplicationRuntime
import SessionStore
import SessionDomain

/// Executable, authenticated AB-138 fixture replay. Version 1.7.2 is only a
/// reviewed fixture value; production remains unavailable without live proof.
@main struct AB138SelfCheck {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2,
              let lifecycle = try? Data(contentsOf: URL(fileURLWithPath: arguments[0])),
              let negatives = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])) else { exit(1) }
        var passed = true
        let installation = IntegrationInstanceID("ab138-self-check")
        let auth = ClaudeIPCAuthenticator(secret: "ab138-self-check-secret")
        func makeRuntime() -> (CursorHooksAdapter, CursorHooksReceiver, SessionStore) {
            let store = SessionStore()
            let runtime = ApplicationRuntime(store: store, idGenerator: { UUID().uuidString }, clock: { Date(timeIntervalSince1970: 400) })
            let adapter = CursorHooksAdapter(port: runtime, integrationInstanceID: installation, helperID: "ab138-helper", authenticator: auth, evidence: .init(productVersion: "1.7.2", reviewedCursorVersions: ["1.7.2"]))
            return (adapter, CursorHooksReceiver(adapter: adapter), store)
        }
        func frame(_ payload: Data, nonce: String, owner: IntegrationInstanceID = installation, helper: String = "ab138-helper") -> Data? {
            try? ClaudeHookIPCFrame.encode(.init(installationID: owner, helperID: helper, nonce: nonce, payload: payload, issuedAt: Date(), authenticator: auth))
        }
        func isDelivered(_ value: CursorHookIntakeOutcome) -> Bool { if case .delivered = value { return true }; return false }
        func isDegraded(_ value: CursorHookIntakeOutcome) -> Bool { if case .degraded = value { return true }; return false }
        func payload(_ name: String, _ conversation: String = "fixture-a", _ generation: String = "g") -> Data { Data("{\"conversation_id\":\"\(conversation)\",\"generation_id\":\"\(generation)\",\"hook_event_name\":\"\(name)\",\"cursor_version\":\"1.7.2\"}".utf8) }

        // Positive lifecycle and same-looking conversations travel only via frames.
        let (adapter, receiver, store) = makeRuntime()
        guard case .compatible = await adapter.negotiate() else { exit(1) }
        for (index, line) in lifecycle.split(separator: 10).enumerated() where !line.isEmpty {
            guard let wrapped = frame(Data(line), nonce: "positive-\(index)") else { passed = false; continue }
            let outcome = await receiver.receive(frame: wrapped)
            passed = passed && isDelivered(outcome)
        }
        let sessions = await store.workingSetProjections()
        let privateSentinels = ["private@example", "transcript_path", "workspace-secret", "command-secret", "response-secret", "thought-secret"]
        passed = passed && sessions.count == 2 && !privateSentinels.contains { sessions.description.contains($0) }

        // Every named negative fixture is loaded and replayed through the same receiver.
        let cases = (try? JSONSerialization.jsonObject(with: negatives) as? [[String: Any]]) ?? []
        passed = passed && !cases.isEmpty
        for item in cases {
            guard let name = item["case"] as? String else { passed = false; continue }
            let (negativeAdapter, negativeReceiver, negativeStore) = makeRuntime()
            let objectPayload: Data? = {
                if let text = item["payload"] as? String { return Data(text.utf8) }
                if let object = item["payload"] { return try? JSONSerialization.data(withJSONObject: object) }
                if let count = item["payload_bytes"] as? Int { return Data(repeating: 0, count: count) }
                return nil
            }()
            switch name {
            case "orphan-before-activation":
                guard let objectPayload, let wrapped = frame(objectPayload, nonce: "negative-orphan") else { passed = false; continue }
                let outcome = await negativeReceiver.receive(frame: wrapped)
                passed = passed && isDegraded(outcome)
            case "oversize":
                _ = await negativeAdapter.negotiate()
                let outcome = await negativeReceiver.receive(frame: Data(repeating: 0, count: CursorHookEnvelope.maximumBytes + 1))
                let empty = await negativeStore.workingSetProjections().isEmpty
                passed = passed && isDegraded(outcome) && empty
            case "malformed-duplicate-key", "incompatible-cursor-version":
                _ = await negativeAdapter.negotiate()
                guard let objectPayload, let wrapped = frame(objectPayload, nonce: "negative-\(name)") else { passed = false; continue }
                let outcome = await negativeReceiver.receive(frame: wrapped)
                let empty = await negativeStore.workingSetProjections().isEmpty
                passed = passed && (name == "incompatible-cursor-version" ? !isDelivered(outcome) : isDegraded(outcome)) && empty
            case "weak-duplicate-collision-gap":
                _ = await negativeAdapter.negotiate()
                let start = frame(payload("sessionStart", "fixture-a", "g1"), nonce: "collision-start")!
                let first = frame(Data("{\"conversation_id\":\"fixture-a\",\"generation_id\":\"g3\",\"hook_event_name\":\"sessionEnd\",\"cursor_version\":\"1.7.2\",\"status\":\"completed\"}".utf8), nonce: "collision-one")!
                let second = frame(Data("{\"conversation_id\":\"fixture-a\",\"generation_id\":\"g3\",\"hook_event_name\":\"sessionEnd\",\"cursor_version\":\"1.7.2\",\"status\":\"failed\"}".utf8), nonce: "collision-two")!
                _ = await negativeReceiver.receive(frame: start); _ = await negativeReceiver.receive(frame: first)
                let collision = await negativeReceiver.receive(frame: second)
                let projection = await negativeStore.workingSetProjections().values.first
                passed = passed && isDegraded(collision) && projection?.execution == .unresolved
            case "ambiguous-subagent-stop":
                _ = await negativeAdapter.negotiate(); _ = await negativeReceiver.receive(frame: frame(payload("sessionStart"), nonce: "child-start")!)
                guard let objectPayload, let wrapped = frame(objectPayload, nonce: "child-stop") else { passed = false; continue }
                let outcome = await negativeReceiver.receive(frame: wrapped)
                let projection = await negativeStore.workingSetProjections().values.first
                passed = passed && isDegraded(outcome) && projection?.subagentRuns.isEmpty == true
            case "window-close", "shell-failure":
                _ = await negativeAdapter.negotiate(); _ = await negativeReceiver.receive(frame: frame(payload("sessionStart"), nonce: "working-start")!)
                guard let objectPayload, let wrapped = frame(objectPayload, nonce: "working-\(name)") else { passed = false; continue }
                _ = await negativeReceiver.receive(frame: wrapped)
                let projection = (await negativeStore.workingSetProjections()).values.first
                if name == "window-close" { passed = passed && projection?.execution.isTerminal == false && projection?.observation == .unavailable }
                else { passed = passed && projection?.execution == .working }
            default: passed = false
            }
        }

        // Receiver authentication, malformed-frame, replay, transport loss, and old epoch events.
        let (secureAdapter, secureReceiver, secureStore) = makeRuntime(); _ = await secureAdapter.negotiate()
        let start = frame(payload("sessionStart", "secure", "one"), nonce: "secure-start")!
        let accepted = await secureReceiver.receive(frame: start)
        let replay = await secureReceiver.receive(frame: start)
        let cross = await secureReceiver.receive(frame: frame(payload("sessionStart", "cross", "one"), nonce: "cross", owner: .init("other"))!)
        let malformed = await secureReceiver.receive(frame: Data("not-a-frame".utf8))
        await secureReceiver.transportLost()
        let oldEpoch = await secureReceiver.receive(frame: frame(payload("preToolUse", "secure", "two"), nonce: "old-epoch")!)
        _ = await secureAdapter.negotiate()
        let reconnectOld = await secureReceiver.receive(frame: frame(payload("preToolUse", "secure", "two"), nonce: "reconnect-old")!)
        let secureProjection = await secureStore.workingSetProjections().values.first
        passed = passed && isDelivered(accepted) && isDegraded(replay) && isDegraded(cross) && isDegraded(malformed) && isDegraded(oldEpoch) && isDegraded(reconnectOld) && secureProjection?.observation == .unavailable

        // Installation needs an explicitly proven test runtime contract.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab138-install-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".cursor"), withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
            let hooks = root.appendingPathComponent(".cursor/hooks.json"); try Data("{\"version\":1,\"unrelated\":true}".utf8).write(to: hooks)
            let helper = root.appendingPathComponent("helper"); try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            let scope = IntegrationInstallationScope(kind: .customPath, identifier: "test-ab138", path: hooks)
            let installer = CursorHooksInstallationCoordinator(runtimeContract: CursorFixtureHookRuntimeContract())
            let proof = CursorHooksContractEvidence(productVersion: "1.7.2", reviewedCursorVersions: ["1.7.2"])
            let plan = installer.makePlan(id: "ab138", installationID: installation, scope: scope, helperPath: helper, evidence: proof)
            if let manifest = installer.apply(installer.approve(plan, personIdentifier: "self-check"), helperPath: helper, evidence: proof).manifest { passed = passed && manifest.verification?.probeSucceeded == true && installer.verify(manifest, helperPath: helper).status == .applied && installer.remove(manifest, helperPath: helper).status == .applied } else { passed = false }
        } catch { passed = false }
        print(passed ? "AB-138 replay PASS authenticated-positive-negative runtime-proven privacy-safe" : "AB-138 replay FAIL")
        exit(passed ? 0 : 1)
    }
}
