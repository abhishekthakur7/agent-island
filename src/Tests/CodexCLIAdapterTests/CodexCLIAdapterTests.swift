import XCTest
import CodexCLIAdapter
import SessionDomain
import ClaudeCodeAdapter

final class CodexCLIAdapterTests: XCTestCase {
    private func snapshot() -> NegotiationSnapshot {
        let id = IntegrationInstanceID("codex-install")
        let request = NegotiationRequest(integrationInstanceID: id, adapterKind: CodexCLIIntegration.adapterKind, adapterBuildVersion: "test", productNamespace: CodexCLIIntegration.productNamespace, integrationMode: CodexCLIIntegration.integrationMode, offeredContractVersion: .init(major: 1, minor: 0), requestedCapabilities: [WellKnownCapability.sessionObservation, CodexCLIIntegration.observationCapability], catalogRevision: "test", requestedCapabilityRecords: [CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available), CapabilityRecord(id: CodexCLIIntegration.observationCapability, direction: .observe, availability: .available)])
        guard case .compatible(let value) = SessionDomainNegotiator.negotiate(request, id: .init("snapshot"), negotiatedAt: .init(timeIntervalSince1970: 1)) else { fatalError() }; return value
    }
    func testAllDocumentedEventsNormalizeWithoutContent() throws {
        let names = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact", "PostCompact", "Activity"]
        for (index, name) in names.enumerated() {
            let data = Data("{\"hook_event_name\":\"\(name)\",\"session_id\":\"s\",\"event_id\":\"e\(index)\",\"turn_id\":\"t\",\"sequence\":\(index)}".utf8)
            let hook = try CodexHookEnvelope.decode(data)
            guard case .success(let result) = CodexHookNormalizer.normalize(hook, snapshot: snapshot(), installationID: .init("codex-install")) else { return XCTFail(name) }
            XCTAssertTrue(result.events.allSatisfy { $0.classification == .operationalMetadata })
        }
    }
    func testStopAndChildRequireExplicitNativeEvidence() throws {
        let missing = try CodexHookEnvelope.decode(Data("{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"event_id\":\"e\"}".utf8))
        guard case .failure(.missingStopEvidence) = CodexHookNormalizer.normalize(missing, snapshot: snapshot(), installationID: .init("codex-install")) else { return XCTFail("Stop without source outcome must remain unresolved") }
        let start = try CodexHookEnvelope.decode(Data("{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"s\",\"event_id\":\"a\",\"subagent_id\":\"c\",\"parent_turn_id\":\"p\"}".utf8))
        guard case .success(let child) = CodexHookNormalizer.normalize(start, snapshot: snapshot(), installationID: .init("codex-install")) else { return XCTFail() }
        XCTAssertEqual(child.events.first?.ownership?.nativeTurnID, "p")
    }
    func testPermissionIsCueOnlyAndNativeIdentityIsExact() throws {
        let hook = try CodexHookEnvelope.decode(Data("{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"native-a\",\"event_id\":\"e\",\"turn_id\":\"t\"}".utf8))
        guard case .success(let value) = CodexHookNormalizer.normalize(hook, snapshot: snapshot(), installationID: .init("codex-install")) else { return XCTFail() }
        XCTAssertEqual(value.permissionCue?.sessionIdentity.nativeSessionID.rawValue, "native-a")
        XCTAssertEqual(value.permissionCue?.guidedResponseAvailable, false)
    }
    func testInteractionContentRequiresExplicitLocalPresentationConsent() throws {
        let hook = try CodexHookEnvelope.decode(Data("{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s\",\"event_id\":\"e\",\"turn_id\":\"t\",\"command\":\"SECRET\"}".utf8))
        guard case .success(let defaultValue) = CodexHookNormalizer.normalize(hook, snapshot: snapshot(), installationID: .init("codex-install")), case .success(let optedIn) = CodexHookNormalizer.normalize(hook, snapshot: snapshot(), installationID: .init("codex-install"), contentConsent: .init(localPresentationEnabled: true)) else { return XCTFail() }
        XCTAssertNil(defaultValue.protectedContent)
        XCTAssertEqual(optedIn.protectedContent?.classification, .interactionContent)
        XCTAssertTrue(optedIn.events.allSatisfy { $0.classification == .operationalMetadata })
    }
    func testExactEntrySetupPreservesUnrelatedTextAndRemovalNeedsManifest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml"); try Data("profile = \"keep\"\n# comment\n".utf8).write(to: config)
        let helper = root.appendingPathComponent("helper")
        let selector = CodexCLIInstallationCoordinator().selector(helperPath: helper)
        let before = ExactEntryEditor.snapshot(at: config)
        let receipt = try ExactEntryEditor.add(selector: selector, at: config, expected: before.fingerprint)
        XCTAssertTrue(String(data: ExactEntryEditor.snapshot(at: config).content!, encoding: .utf8)!.contains("# comment"))
        _ = try ExactEntryEditor.remove(receipt: receipt, at: config, expected: ExactEntryEditor.snapshot(at: config).fingerprint)
        XCTAssertEqual(ExactEntryEditor.snapshot(at: config).content, before.content)
    }
    func testPrivateCodexFilesAreNotAnAdapterInput() {
        XCTAssertFalse(String(reflecting: CodexCLIAdapter.self).contains("CODEX_HOME"))
    }
}
