import XCTest
@testable import AgentIslandApp
@testable import SessionDomain

final class AtlasDiagnosticsTests: XCTestCase {
    func testRenderedDiagnosticsAreClosedAndAllowlisted() {
        let state = AtlasIntegrationState(
            kind: .claudeCode,
            enabledIntent: true,
            detected: true,
            evidence: AtlasIntegrationEvidence(health: .degraded, freshness: .stale),
            capabilities: [.action],
            affectedCapability: .action
        )
        let record = AtlasDiagnosticsSanitizer.render(integration: state)
        XCTAssertEqual(record.component, .integration)
        XCTAssertEqual(record.outcome, .degraded)
        XCTAssertEqual(record.reason, .capabilityDegraded)
        XCTAssertEqual(record.affectedCapability, .action)
        XCTAssertEqual(AtlasDiagnosticsSanitizer.sanitize(record), record)
    }

    func testHealthyRecordContainsNoArbitraryPayloadField() {
        let record = AtlasDiagnosticsSanitizer.render(
            integration: AtlasIntegrationState(kind: .codexCLI, enabledIntent: true, detected: true, evidence: AtlasIntegrationEvidence(health: .healthy, freshness: .current))
        )
        let mirrorLabels = Mirror(reflecting: record).children.compactMap(\.label)
        XCTAssertFalse(mirrorLabels.contains("path"))
        XCTAssertFalse(mirrorLabels.contains("token"))
        XCTAssertFalse(mirrorLabels.contains("payload"))
        XCTAssertEqual(record.outcome, .accepted)
        XCTAssertEqual(record.reason, .deliveryVerified)
    }

    func testDetectedButDisabledReportsIntentRatherThanMissingDetection() {
        let record = AtlasDiagnosticsSanitizer.render(
            integration: AtlasIntegrationState(kind: .cursor, detected: true)
        )
        XCTAssertEqual(record.outcome, .filtered)
        XCTAssertEqual(record.reason, .intentDisabled)
    }

    func testSnapshotDiagnosticRedactsIdentityAndReportsInterfaceChange() {
        let snapshot = NegotiationSnapshot(
            id: NegotiationSnapshotID("raw-external-id-must-not-render"),
            contractVersion: ContractVersion(major: 1, minor: 0),
            adapterKind: "fixture",
            adapterBuildVersion: "1",
            productNamespace: ProductNamespace("claude-code"),
            integrationInstanceID: IntegrationInstanceID("instance-secret"),
            integrationMode: "hooks",
            capabilities: [CapabilityRecord(id: WellKnownCapability.sessionAction, direction: .act, availability: .interfaceChanged)],
            negotiatedAt: Date(timeIntervalSince1970: 200),
            probeEvidence: NegotiationProbeEvidence(compatibility: .interfaceChanged, setup: .loaded, observedAt: Date(timeIntervalSince1970: 200)),
            compatibility: .interfaceChanged
        )
        let record = AtlasDiagnostics.render(snapshot: snapshot)
        XCTAssertEqual(record.reason, .interfaceChanged)
        XCTAssertEqual(record.outcome, .failed)
        XCTAssertEqual(record.affectedCapability, .action)
        let mirrorLabels = Mirror(reflecting: record).children.compactMap(\.label)
        XCTAssertFalse(mirrorLabels.contains("snapshotID"))
        XCTAssertFalse(mirrorLabels.contains("instance-secret"))
    }
}
