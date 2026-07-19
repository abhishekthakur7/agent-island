import XCTest
@testable import AgentIslandApp

final class AtlasIntegrationModelsTests: XCTestCase {
    func testDetectionDoesNotEnableIntentAndDerivesSafeStep() {
        var state = AtlasIntegrationState(kind: .codexCLI, detected: true)
        XCTAssertFalse(state.enabledIntent)
        XCTAssertEqual(state.summary, .detectedNotEnabled)
        XCTAssertEqual(state.safeNextStep, .enableIntent)
        state.apply(evidence: AtlasIntegrationEvidence(health: .healthy, freshness: .current))
        XCTAssertFalse(state.enabledIntent)
        XCTAssertEqual(state.summary, .detectedNotEnabled)
    }

    func testEvidenceUpdatesNeverModifyEnabledIntent() {
        var state = AtlasIntegrationState(kind: .claudeCode, enabledIntent: true, detected: true)
        state.apply(evidence: AtlasIntegrationEvidence(health: .degraded, freshness: .stale), capabilities: [.observation], affectedCapability: .observation)
        XCTAssertTrue(state.enabledIntent)
        XCTAssertEqual(state.summary, .degraded)
        XCTAssertEqual(state.safeNextStep, .repair)
        XCTAssertEqual(state.affectedCapability, .observation)
    }

    func testAuthenticationAndCapabilitiesRemainSeparateFromHealth() {
        let state = AtlasIntegrationState(
            kind: .cursor,
            enabledIntent: true,
            detected: true,
            authentication: .required,
            evidence: AtlasIntegrationEvidence(health: .healthy, freshness: .current),
            capabilities: [.navigation]
        )
        XCTAssertEqual(state.summary, .authenticationRequired)
        XCTAssertEqual(state.safeNextStep, .authenticate)
        XCTAssertEqual(state.health, .healthy)
        XCTAssertEqual(state.capabilities, [.navigation])
    }

    func testDuplicatePersistedKindsNormalizeWithoutTrapping() {
        let disabled = AtlasIntegrationState(kind: .codexCLI, enabledIntent: false)
        let enabled = AtlasIntegrationState(kind: .codexCLI, enabledIntent: true)
        let normalized = AtlasIntegrationState.normalizedCollection([disabled, enabled])
        XCTAssertEqual(normalized.count, AtlasIntegrationKind.allCases.count)
        XCTAssertEqual(normalized.first { $0.kind == .codexCLI }?.enabledIntent, true)
    }
}
