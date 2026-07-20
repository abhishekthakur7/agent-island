import XCTest
import Foundation
@testable import SessionDomain

final class IntegrationInstallationTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ab125-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var selector: ExactEntrySelector {
        ExactEntrySelector(key: "hooks", renderedLine: "hooks = agent-island # agent-island:hooks", marker: "agent-island:hooks")
    }

    private func configurationSnapshot() -> NegotiationSnapshot {
        let request = NegotiationRequest(integrationInstanceID: IntegrationInstanceID("i"), adapterKind: "fixture", adapterBuildVersion: "1", productNamespace: ProductNamespace("fixture"), integrationMode: "hooks", offeredContractVersion: ContractVersion(major: 1, minor: 0), requestedCapabilities: [], requestedCapabilityRecords: [CapabilityRecord(id: WellKnownCapability.configuration, direction: .configure, availability: .available, scope: .installation)], productVersion: "1", interfaceVersion: "v1")
        guard case .compatible(let snapshot) = SessionDomainNegotiator.negotiate(request, id: NegotiationSnapshotID("snapshot"), negotiatedAt: Date(timeIntervalSince1970: 1)) else { fatalError("fixture negotiation") }
        return snapshot
    }

    func testReadOnlyDiscoveryAndLosslessExactEntryApplication() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("custom.conf")
        let original = "# keep this comment\nunknown = untouched\n"
        try Data(original.utf8).write(to: path)
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "selected", path: path)
        let coordinator = IntegrationInstallationCoordinator()
        let before = coordinator.discover(installationID: IntegrationInstanceID("i"), product: ProductNamespace("fixture"), integrationMode: "hooks", scope: scope, selector: selector)
        XCTAssertEqual(before.state, .notConfigured)
        XCTAssertFalse(before.safeToMutate) // discovery has no negotiated configuration capability
        let snapshot = configurationSnapshot()
        let plan = coordinator.makePlan(id: "plan", installationID: IntegrationInstanceID("i"), product: ProductNamespace("fixture"), integrationMode: "hooks", scope: scope, selector: selector, snapshot: snapshot, now: Date(timeIntervalSince1970: 100))
        let approval = try coordinator.approve(plan, personIdentifier: "person", at: Date(timeIntervalSince1970: 101))
        let revalidation = IntegrationInstallationRevalidation(sourceFingerprint: plan.sourceFingerprint, product: plan.product, productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion)
        let result = coordinator.apply(approval, revalidation: revalidation, now: Date(timeIntervalSince1970: 102))
        XCTAssertEqual(result.status, .applied)
        XCTAssertTrue(String(data: try Data(contentsOf: path), encoding: .utf8)!.hasPrefix(original))
        XCTAssertEqual(result.manifest?.entries.count, 1)
    }

    func testSymlinkRetargetAndExternalEditExpirePlanWithoutWrite() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.conf")
        let second = root.appendingPathComponent("second.conf")
        let link = root.appendingPathComponent("selected.conf")
        try Data("# first\n".utf8).write(to: first)
        try Data("# second\n".utf8).write(to: second)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: first.path)
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "selected", path: link)
        let coordinator = IntegrationInstallationCoordinator()
        let snapshot = configurationSnapshot()
        let plan = coordinator.makePlan(id: "stale", installationID: IntegrationInstanceID("i"), product: ProductNamespace("fixture"), integrationMode: "hooks", scope: scope, selector: selector, snapshot: snapshot, now: Date(timeIntervalSince1970: 100))
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: second.path)
        let approval = try coordinator.approve(plan, personIdentifier: "person", at: Date(timeIntervalSince1970: 101))
        let current = ExactEntryEditor.snapshot(at: link)
        let revalidation = IntegrationInstallationRevalidation(sourceFingerprint: plan.sourceFingerprint, product: plan.product, productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion)
        let result = coordinator.apply(approval, revalidation: revalidation, now: Date(timeIntervalSince1970: 102))
        XCTAssertEqual(result.status, .stale)
        XCTAssertEqual(current.fingerprint.symlinkTarget, second.path)
        XCTAssertEqual(try String(contentsOf: second), "# second\n")
    }

    func testDuplicateLossyPolicyAndInterruptedWritesAreHonest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("config")
        try Data("# agent-island:hooks\n# agent-island:hooks\n".utf8).write(to: path)
        XCTAssertThrowsError(try ExactEntryEditor.add(selector: selector, at: path)) { XCTAssertEqual($0 as? ExactEntryEditorError, .ambiguous) }
        XCTAssertThrowsError(try ExactEntryEditor.add(selector: selector, at: path, policy: .denied)) { XCTAssertEqual($0 as? ExactEntryEditorError, .policyDenied) }
        try Data([0, 1, 2]).write(to: path)
        XCTAssertThrowsError(try ExactEntryEditor.add(selector: selector, at: path)) { XCTAssertEqual($0 as? ExactEntryEditorError, .unsupported) }
        try Data("# unrelated\n".utf8).write(to: path)
        XCTAssertThrowsError(try ExactEntryEditor.add(selector: selector, at: path, options: ExactEntryWriteOptions(interruption: .afterReplace))) { XCTAssertEqual($0 as? ExactEntryEditorError, .interrupted) }
        XCTAssertTrue(String(data: try Data(contentsOf: path), encoding: .utf8)!.contains(selector.renderedLine))
    }

    func testDisableDoesNotRemoveSetupAndRemovalReportsResidual() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("config")
        try Data("# unrelated\n".utf8).write(to: path)
        let scope = IntegrationInstallationScope(identifier: "selected", path: path)
        let coordinator = IntegrationInstallationCoordinator()
        let snapshot = configurationSnapshot()
        let plan = coordinator.makePlan(id: "plan", installationID: IntegrationInstanceID("i"), product: ProductNamespace("fixture"), integrationMode: "hooks", scope: scope, selector: selector, snapshot: snapshot, now: Date(timeIntervalSince1970: 100))
        let approval = try coordinator.approve(plan, personIdentifier: "person", at: Date(timeIntervalSince1970: 101))
        let result = coordinator.apply(approval, revalidation: IntegrationInstallationRevalidation(sourceFingerprint: plan.sourceFingerprint, product: plan.product, productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion), now: Date(timeIntervalSince1970: 102))
        guard let manifest = result.manifest, let installation = result.installation else { return XCTFail("manifest expected") }
        XCTAssertFalse(coordinator.disable(installation).enabledIntent)
        XCTAssertTrue(String(data: try Data(contentsOf: path), encoding: .utf8)!.contains(selector.renderedLine))
        try Data((String(data: try Data(contentsOf: path), encoding: .utf8)! + "\nexternal = edit\n").utf8).write(to: path)
        let removalPlan = coordinator.makeRemovalPlan(id: "remove", installationID: installation.id, manifest: manifest, snapshot: snapshot, now: Date(timeIntervalSince1970: 200))
        let removalApproval = try coordinator.approve(removalPlan, personIdentifier: "person", at: Date(timeIntervalSince1970: 201))
        let report = coordinator.remove(removalApproval, manifest: manifest, now: Date(timeIntervalSince1970: 202))
        XCTAssertEqual(report.outcome, .notRemoved)
        XCTAssertTrue(String(data: try Data(contentsOf: path), encoding: .utf8)!.contains(selector.renderedLine))
    }
}
