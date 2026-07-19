import XCTest
@testable import AgentIslandApp

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
}
