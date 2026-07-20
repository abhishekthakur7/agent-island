import XCTest
@testable import AgentIslandApp
@testable import SessionDomain

final class AB130DiagnosticsAccessibilityTests: XCTestCase {
    func testDiagnosticsAndMaintenanceHaveNonColorOnlyLabels() {
        let evidence = DiagnosticEvidence(operation: .inspect, outcome: .degraded, scope: DiagnosticScope(component: .integration, owner: .integration, capability: .action), reason: .actionUnavailable, occurredAt: Date(timeIntervalSince1970: 10), correlationID: .generated(), safeNextStep: .inspect)
        let model = AtlasDiagnosticsModel(evidence: [evidence])
        XCTAssertTrue(model.accessibilityLabel.contains("diagnostics"))
        XCTAssertTrue(model.accessibilityHint.contains("local"))
        XCTAssertTrue(AtlasDiagnosticAccessibility.label(for: evidence).contains("degraded"))
        XCTAssertTrue(AtlasDiagnosticAccessibility.hint(for: evidence).contains("Safe next step"))

        let maintenance = AtlasMaintenanceModel()
        let destructive = maintenance.action(for: .completeCleanup)
        XCTAssertEqual(destructive.tone, .destructive)
        XCTAssertTrue(destructive.accessibilityLabel.contains("destructive"))
        XCTAssertTrue(destructive.accessibilityHint.contains("scope"))
        XCTAssertTrue(maintenance.action(for: .resetPresentationPreferences).accessibilityLabel.contains("warning"))
    }
}
