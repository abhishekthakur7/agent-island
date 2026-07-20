import XCTest
@testable import AgentIslandApp
@testable import SessionDomain

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

    func testDisabledIntentAliasRemainsDistinctFromEvidence() {
        let state = AtlasIntegrationState(kind: .claudeCode, enabledIntent: false, detected: true, evidence: AtlasIntegrationEvidence(health: .healthy, freshness: .current))
        XCTAssertEqual(state.intent, .disabled)
        XCTAssertEqual(state.summary, .disabled)
        XCTAssertEqual(state.safeNextStep, .enableIntent)
        XCTAssertEqual(state.health, .healthy)
    }

    func testSnapshotProjectionKeepsActionAndNavigationIndependent() {
        let snapshot = NegotiationSnapshot(
            id: NegotiationSnapshotID("atlas-snapshot"),
            contractVersion: ContractVersion(major: 1, minor: 0),
            adapterKind: "fixture",
            adapterBuildVersion: "1",
            productNamespace: ProductNamespace("claude-code"),
            integrationInstanceID: IntegrationInstanceID("atlas-instance"),
            integrationMode: "hooks",
            capabilities: [
                CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available),
                CapabilityRecord(id: WellKnownCapability.sessionAction, direction: .act, availability: .unavailable, freshness: .stale, fallback: .nativeHost),
                CapabilityRecord(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: .available)
            ],
            negotiatedAt: Date(timeIntervalSince1970: 100),
            probeEvidence: NegotiationProbeEvidence(setup: .loaded, observedAt: Date(timeIntervalSince1970: 100))
        )
        let state = AtlasIntegrationState(kind: .claudeCode, enabledIntent: true).applying(snapshot: snapshot)
        XCTAssertEqual(state.summary, .degraded)
        XCTAssertTrue(state.capabilities.contains(.observation))
        XCTAssertFalse(state.capabilities.contains(.action))
        XCTAssertTrue(state.capabilities.contains(.navigation))
        XCTAssertEqual(state.affectedCapability, .action)
        XCTAssertEqual(state.healthVector?.evidenceAt, Date(timeIntervalSince1970: 100))
    }
}
