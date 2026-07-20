import Foundation
import SessionDomain
import ClaudeCodeAdapter

@main
struct AB144SelfCheck {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let installationID = IntegrationInstanceID("usage-installation")
        let snapshot = NegotiationSnapshot(id: NegotiationSnapshotID("usage-negotiation"), contractVersion: .init(major: 1, minor: 0), adapterKind: "fixture", adapterBuildVersion: "1", productNamespace: ClaudeCodeIntegration.productNamespace, integrationInstanceID: installationID, integrationMode: ClaudeStatusLineBridgeInstallationCoordinator.integrationMode, capabilities: [.init(id: WellKnownCapability.configuration, direction: .configure, availability: .available), .init(id: WellKnownCapability.usageObservation, direction: .observe, availability: .available)], negotiatedAt: now)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab144-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("settings.jsonc")
        let original = "{\n  // preserved\n  \"unknown\": true\n}\n"
        try! Data(original.utf8).write(to: config)
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "fixture", path: config.path)
        let coordinator = ClaudeStatusLineBridgeInstallationCoordinator()
        let plan = coordinator.makePlan(id: "enable", installationID: installationID, scope: scope, snapshot: snapshot, now: now)
        let approval = try! coordinator.approve(plan, personIdentifier: "person", at: now)
        let applied = coordinator.apply(approval, currentSnapshot: snapshot, now: now)
        guard applied.status == .applied, let manifest = applied.manifest, String(data: ExactEntryEditor.snapshot(at: config).content!, encoding: .utf8)!.contains("// preserved") else { fail("apply-preserve") }
        let removal = coordinator.makeRemovalPlan(id: "remove", installationID: installationID, manifest: manifest, snapshot: snapshot, now: now.addingTimeInterval(1))
        let report = coordinator.remove(try! coordinator.approve(removal, personIdentifier: "person", at: now.addingTimeInterval(1)), manifest: manifest, now: now.addingTimeInterval(2))
        guard report.outcome == .removed, ExactEntryEditor.snapshot(at: config).content == Data(original.utf8) else { fail("revert") }
        print("AB144SelfCheck PASS sourced-only usage boundary and Claude Status Line exact-entry apply/verify/revert")
    }
    static func fail(_ value: String) -> Never { FileHandle.standardError.write(Data("AB144SelfCheck failed: \(value)\n".utf8)); exit(EXIT_FAILURE) }
}
