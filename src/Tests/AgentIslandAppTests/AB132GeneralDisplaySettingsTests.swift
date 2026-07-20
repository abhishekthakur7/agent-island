import CoreGraphics
import Foundation
import XCTest
@testable import AgentIslandApp

final class AB132GeneralDisplaySettingsTests: XCTestCase {
    func testDisplayDefaultsRoundTripAndRestart() {
        let suite = "AB132Display.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AtlasSettingsRepository(defaults: defaults, namespace: "ab132")
        XCTAssertEqual(first.display, .default)
        let value = AtlasDisplayPreferences(
            selectedDisplayID: "display-uuid",
            collapsedLayout: .detailed,
            contentSize: .large,
            maximumPanelWidth: 1_140,
            maximumPanelHeight: 680,
            completionCardHeight: 310,
            showProjectMetadata: true,
            showWorktreeMetadata: true,
            showModelMetadata: true,
            showSubagentRunMetadata: true,
            showActivityMetadata: true
        )
        first.display = value
        let restarted = AtlasSettingsRepository(defaults: defaults, namespace: "ab132")
        XCTAssertEqual(restarted.display, value)
        XCTAssertEqual(restarted.display.selectedDisplayID, "display-uuid")
    }

    func testDisplayValidationAndGeometryClampForBuiltInAndExternalForms() {
        let invalid = AtlasDisplayPreferences(maximumPanelWidth: .infinity, maximumPanelHeight: -10, completionCardHeight: .nan)
        XCTAssertEqual(invalid.maximumPanelWidth, 820)
        XCTAssertEqual(invalid.maximumPanelHeight, 80)
        XCTAssertEqual(invalid.completionCardHeight, 220)

        let bounds = AtlasVisibleBounds(minX: 40, minY: 20, width: 640, height: 620)
        let builtIn = invalid.clamped(to: bounds, isBuiltIn: true)
        XCTAssertGreaterThanOrEqual(builtIn.x, bounds.minX + 12)
        XCTAssertLessThanOrEqual(builtIn.x + builtIn.width, bounds.maxX - 12)
        XCTAssertGreaterThan(builtIn.protectedGap, 0)
        let external = invalid.clamped(to: AtlasVisibleBounds(width: 1_920, height: 1_080), isBuiltIn: false)
        XCTAssertEqual(external.protectedGap, 0)
        XCTAssertFalse(external.isBuiltIn)
    }

    func testSelectionSwitchEndsEngagementAndReconnectsCollapsedAfterRevalidation() {
        var machine = IslandOverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.engageKeyboard)
        let before = machine.state.transitionRevision
        machine.reduce(.displayLost)
        XCTAssertFalse(machine.state.hasVisibleRegions)
        XCTAssertFalse(machine.state.keyboardEngaged)
        XCTAssertEqual(machine.state.displayAvailability, .selectionUnavailable)
        XCTAssertGreaterThan(machine.state.transitionRevision, before)
        machine.reduce(.displayRevalidated(available: true))
        XCTAssertEqual(machine.state.presentation, .collapsed)
        XCTAssertFalse(machine.state.keyboardEngaged)
        XCTAssertEqual(machine.state.displayAvailability, .available)
    }

    func testPreviewDisplayAndGeneralChangesOnlyClosedLocalTrace() {
        let router = AtlasPreviewRouter()
        router.send(.setDisplay(AtlasDisplayPreferences(collapsedLayout: .detailed, contentSize: .large)))
        router.send(.setSelectedDisplayAvailability(available: false, label: "Studio display"))
        router.send(.revealAttention)
        XCTAssertEqual(router.state.display.collapsedLayout, .detailed)
        XCTAssertEqual(router.state.display.contentSize, .large)
        XCTAssertFalse(router.state.isVisible)
        XCTAssertFalse(router.state.selectedDisplayAvailable)
        XCTAssertEqual(router.state.unavailableDisplayLabel, "Studio display")
        XCTAssertEqual(router.trace, [.previewStateChanged, .previewStateChanged])
    }

    func testGeneralDefaultsRemainLocalPresentationOnly() {
        let defaults = AtlasGeneralPreferences.default
        XCTAssertTrue(defaults.hideWhenNoActiveSession)
        XCTAssertTrue(defaults.suppressWhenExactHostForeground)
        XCTAssertEqual(defaults.clickBehavior, .inspectExpand)
    }
}
