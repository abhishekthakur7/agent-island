import Foundation
import XCTest
@testable import AgentIslandApp
@testable import SessionDomain

final class AtlasSettingsRepositoryTests: XCTestCase {
    func testDefaultsAreExplicitAndRoundTripInAnIsolatedSuite() {
        let suite = "AtlasSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AtlasSettingsRepository(defaults: defaults, namespace: "test.atlas")

        XCTAssertEqual(repository.general, .default)
        XCTAssertEqual(repository.selectedDestination, .general)
        XCTAssertEqual(repository.general.launchBehavior, .manual)
        XCTAssertTrue(repository.general.expandOnHover)
        XCTAssertTrue(repository.general.collapseOnPointerExit)
        XCTAssertTrue(repository.general.suppressWhenExactHostForeground)
        XCTAssertTrue(repository.general.hideInFullScreen)
        XCTAssertTrue(repository.general.hideWhenNoActiveSession)
        XCTAssertTrue(repository.general.revealOnCompletion)
        XCTAssertTrue(repository.general.revealOnAttention)
        XCTAssertEqual(repository.general.clickBehavior, .inspectExpand)
    }

    func testSelectedDestinationAndGeneralPreferencesPersistByNamespace() {
        let suite = "AtlasSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AtlasSettingsRepository(defaults: defaults, namespace: "test.atlas")
        var general = first.general
        general.launchBehavior = .atLogin
        general.clickBehavior = .jumpBack
        general.hideWhenNoActiveSession = false
        first.general = general
        first.selectedDestination = .diagnostics

        let second = AtlasSettingsRepository(defaults: defaults, namespace: "test.atlas")
        XCTAssertEqual(second.general, general)
        XCTAssertEqual(second.selectedDestination, .diagnostics)
        XCTAssertNil(defaults.object(forKey: "other.atlas.general.expandOnHover"))
    }

    func testUnknownOnboardingSchemaResetsOnlyOnboarding() throws {
        let suite = "AtlasSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AtlasSettingsRepository(defaults: defaults, namespace: "test.atlas")
        repository.selectedDestination = .maintenance
        var general = repository.general
        general.hideInFullScreen = false
        repository.general = general
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 99, "lifecycle": "active", "step": 2])
        defaults.set(data, forKey: "test.atlas.onboarding")

        XCTAssertEqual(repository.loadOnboarding(), .initial)
        XCTAssertEqual(repository.selectedDestination, .maintenance)
        XCTAssertFalse(repository.general.hideInFullScreen)
    }

    func testIntegrationIntentAndEvidenceRoundTripAsIndependentFields() throws {
        let suite = "AtlasSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AtlasSettingsRepository(defaults: defaults, namespace: "test.atlas")
        let codex = AtlasIntegrationState(
            kind: .codexCLI,
            enabledIntent: true,
            detected: true,
            evidence: AtlasIntegrationEvidence(health: .degraded, freshness: .current),
            capabilities: [.observation],
            affectedCapability: .observation
        )

        repository.saveIntegrations([codex])
        let loaded = repository.loadIntegrations().first { $0.kind == .codexCLI }
        XCTAssertEqual(loaded?.enabledIntent, true)
        XCTAssertEqual(loaded?.summary, .degraded)

        var evidenceOnly = try XCTUnwrap(loaded)
        evidenceOnly.apply(evidence: AtlasIntegrationEvidence(health: .healthy, freshness: .current))
        XCTAssertTrue(evidenceOnly.enabledIntent)
    }

    func testShortcutBindingsPersistAndMasterDisablePreservesMapping() {
        let suite = "AtlasSettingsRepositoryTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AtlasSettingsRepository(defaults: defaults, namespace: "test.atlas")
        let binding = ShortcutBinding(key: PhysicalKey(0), modifiers: [.option])
        var preferences = repository.shortcuts
        XCTAssertEqual(preferences.registry.setBinding(binding, for: .toggleOverlay), .valid)
        repository.shortcuts = preferences

        var disabled = repository.shortcuts
        disabled.registry.setMasterEnabled(false)
        repository.shortcuts = disabled

        let loaded = repository.shortcuts
        XCTAssertFalse(loaded.registry.masterEnabled)
        XCTAssertTrue(loaded.registry.activeBindings.isEmpty)
        XCTAssertEqual(loaded.registry.bindings[.toggleOverlay], binding)
    }

    @MainActor
    func testNativeRegistrationFailureKeepsPriorBindingAndRecordsCollisionEvidence() {
        let suite = "AtlasShortcutRegistrationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AtlasSettingsRepository(defaults: defaults, namespace: "test.atlas")
        let model = AtlasSettingsModel(
            repository: repository,
            shortcutInputSourceResolver: { ShortcutInputSource(identifier: "azerty", localizedName: "French", keyCodeLabels: [0: "Q"]) }
        )
        model.setShortcutRegistrationHandler { preferences in
            let replacement = ShortcutBinding(key: PhysicalKey(1), modifiers: [.option])
            if preferences.registry.bindings[.toggleOverlay] == replacement {
                return .rejected(.registeredCollision, .unavailable("OS-owned collision"), replacement)
            }
            return .accepted(.active)
        }

        let prior = ShortcutBinding(key: PhysicalKey(0), modifiers: [.option])
        XCTAssertEqual(model.setShortcut(prior, for: .toggleOverlay), .valid)
        let replacement = ShortcutBinding(key: PhysicalKey(1), modifiers: [.option])
        XCTAssertEqual(model.setShortcut(replacement, for: .toggleOverlay), .rejected(.registeredCollision))
        XCTAssertEqual(model.shortcuts.registry.bindings[.toggleOverlay], prior)
        XCTAssertTrue(model.shortcuts.registry.registeredCollisions.contains(replacement))
        XCTAssertEqual(repository.shortcuts.registry.bindings[.toggleOverlay], prior)
        XCTAssertEqual(model.shortcutInputSource.label(for: PhysicalKey(0)), "Q")
        XCTAssertEqual(model.shortcutRegistrationStatus, .unavailable("OS-owned collision"))
    }
}
