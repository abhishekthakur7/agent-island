import XCTest
@testable import AgentIslandApp
@testable import SessionDomain

final class AB133ShortcutCompositionTests: XCTestCase {
    func testProductionCompositionGatesSafeActionUntilGuidedSourceIsLive() {
        var registry = ShortcutRegistry()
        XCTAssertEqual(
            registry.setBinding(ShortcutBinding(key: PhysicalKey(2), modifiers: [.option]), for: .safeAction(.allow)),
            .valid
        )

        XCTAssertTrue(IslandOverlayController.safeActionRegistrationUnavailable(registry: registry, hasLiveGuidedSource: false))
        XCTAssertFalse(IslandOverlayController.safeActionRegistrationUnavailable(registry: registry, hasLiveGuidedSource: true))
        XCTAssertFalse(IslandOverlayController.safeActionRegistrationUnavailable(registry: ShortcutRegistry(), hasLiveGuidedSource: false))

        let native = IslandOverlayController.nativeShortcutRegistry(from: registry, hasLiveGuidedSource: false)
        XCTAssertNil(native.bindings[.safeAction(.allow)], "safe-action intent is persisted but not sent to Carbon without a source")
    }

    @MainActor
    func testSafeActionMappingPersistsAsInertWhileSourceIsUnavailable() {
        let suite = "AB133InertShortcut.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AtlasSettingsRepository(defaults: defaults, namespace: "ab133")
        let model = AtlasSettingsModel(repository: repository)
        model.setShortcutRegistrationHandler { _ in
            .accepted(.unavailable(IslandOverlayController.safeActionSourceUnavailableReason))
        }

        XCTAssertEqual(
            model.setShortcut(ShortcutBinding(key: PhysicalKey(2), modifiers: [.option]), for: .safeAction(.allow)),
            .valid,
            "missing Guided source must not make the person's mapping uneditable"
        )
        XCTAssertEqual(model.shortcuts.registry.bindings[.safeAction(.allow)]?.key, PhysicalKey(2))
        XCTAssertEqual(repository.shortcuts.registry.bindings[.safeAction(.allow)]?.key, PhysicalKey(2))
        if case .unavailable(let reason) = model.shortcutRegistrationStatus {
            XCTAssertTrue(reason.contains("live Guided workflow source"))
        } else {
            XCTFail("safe-action capability should be reported unavailable")
        }
    }

    func testShortcutInvocationAnnouncementDeduplicatesAndClearsOnWithdrawal() {
        var ledger = ShortcutInvocationAnnouncementLedger()
        let unavailable = ShortcutGuidedRouteFailure.noLiveRequest.humanReadableDescription
        XCTAssertEqual(ledger.publish(unavailable), unavailable)
        XCTAssertNil(ledger.publish(unavailable), "repeated feedback must not retrigger VoiceOver")

        ledger.clear()
        XCTAssertEqual(ledger.publish(unavailable), unavailable, "withdrawal clears the dedupe boundary")
    }

    func testWithdrawnOverlayStateHasNoVisibleOrAccessibleRegions() {
        var machine = IslandOverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.engageKeyboard)
        XCTAssertTrue(machine.state.hasVisibleRegions)
        machine.reduce(.displayLost)
        XCTAssertFalse(machine.state.hasVisibleRegions)
        XCTAssertFalse(machine.state.keyboardEngaged)
    }

    func testUnavailableSafeActionUsesNativeHostFallbackLanguage() {
        XCTAssertTrue(ShortcutGuidedRouteFailure.noLiveRequest.humanReadableDescription.contains("native Host"))
        XCTAssertTrue(ShortcutGuidedRouteFailure.guidedWorkflowUnavailable.humanReadableDescription.contains("native Host"))
        XCTAssertTrue(ShortcutGuidedRouteFailure.capabilityUnavailable.humanReadableDescription.contains("native Host"))
    }
}
