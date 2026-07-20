import CoreGraphics
import Foundation
import XCTest
@testable import AgentIslandApp
import SessionDomain
import PresentationRuntime

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

    @MainActor
    func testSelectedDisplayPersistsThroughAtlasModelAndRepository() {
        let suite = "AB132ModelDisplay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AtlasSettingsRepository(defaults: defaults, namespace: "ab132")
        let model = AtlasSettingsModel(repository: repository)
        model.updateDisplay { $0.selectedDisplayID = "stable-display-uuid" }
        let restarted = AtlasSettingsModel(repository: repository)
        XCTAssertEqual(restarted.display.selectedDisplayID, "stable-display-uuid")
    }

    @MainActor
    func testPreviewStartsUnavailableUntilAnExplicitDisplayIsSelected() {
        let suite = "AB132PreviewInitial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AtlasSettingsModel(repository: AtlasSettingsRepository(defaults: defaults, namespace: "ab132"))
        XCTAssertFalse(model.preview.selectedDisplayAvailable)
        XCTAssertEqual(model.preview.unavailableDisplayLabel, "No display selected")
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

    func testNilOrUnavailableExplicitSelectionNeverMigratesToAnotherDisplay() {
        XCTAssertNil(IslandOverlayController.validatedExplicitSelection(persistedID: nil, availableIDs: ["main", "external"]))
        XCTAssertNil(IslandOverlayController.validatedExplicitSelection(persistedID: "missing", availableIDs: ["main", "external"]))
        XCTAssertEqual(
            IslandOverlayController.validatedExplicitSelection(persistedID: "external", availableIDs: ["main", "external"]),
            "external"
        )

        var machine = IslandOverlayStateMachine()
        machine.reduce(.launch(displayAvailable: false))
        XCTAssertEqual(machine.state.presentation, .withdrawn)
        XCTAssertEqual(machine.state.displayAvailability, .selectionUnavailable)
    }

    func testPointerExitPolicyPreservesInteractionAndKeyboardGuards() {
        XCTAssertFalse(IslandOverlayController.shouldCollapseAfterPointerExit(collapseOnPointerExit: false, interactionGuard: false, keyboardEngaged: false))
        XCTAssertFalse(IslandOverlayController.shouldCollapseAfterPointerExit(collapseOnPointerExit: true, interactionGuard: true, keyboardEngaged: false))
        XCTAssertFalse(IslandOverlayController.shouldCollapseAfterPointerExit(collapseOnPointerExit: true, interactionGuard: false, keyboardEngaged: true))
        XCTAssertTrue(IslandOverlayController.shouldCollapseAfterPointerExit(collapseOnPointerExit: true, interactionGuard: false, keyboardEngaged: false))
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

    @MainActor
    func testLiveAvailabilityBridgeUpdatesPreviewWithoutPersistingDisplaySettings() {
        let suite = "AB132PreviewBridge.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AtlasSettingsRepository(defaults: defaults, namespace: "ab132")
        let model = AtlasSettingsModel(repository: repository)
        let before = model.display

        model.updatePreviewDisplayAvailability(available: false, label: "Studio display")
        XCTAssertFalse(model.preview.selectedDisplayAvailable)
        XCTAssertEqual(model.preview.unavailableDisplayLabel, "Studio display")
        model.updatePreviewDisplayAvailability(available: true, label: nil)
        XCTAssertTrue(model.preview.selectedDisplayAvailable)
        XCTAssertNil(model.preview.unavailableDisplayLabel)
        XCTAssertEqual(model.display, before, "availability bridge must not persist Display preferences")
    }

    func testCompletionHeightAndContentScaleAffectOverlayGeometryAndPreviewMetrics() {
        let small = AtlasDisplayPreferences(contentSize: .small, completionCardHeight: 120, maximumPanelHeight: 900)
        let large = AtlasDisplayPreferences(contentSize: .large, completionCardHeight: 500, maximumPanelHeight: 900)
        let smallGeometry = IslandOverlayGeometry.make(usableFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080), isBuiltIn: false, presentation: .expanded, settings: small)
        let largeGeometry = IslandOverlayGeometry.make(usableFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080), isBuiltIn: false, presentation: .expanded, settings: large)
        XCTAssertGreaterThan(largeGeometry.frame.height, smallGeometry.frame.height)
        XCTAssertEqual(AtlasPreviewPresentationMetrics(display: large).completionCardHeight, 500)
        XCTAssertGreaterThan(AtlasPreviewPresentationMetrics(display: large).contentScale, AtlasPreviewPresentationMetrics(display: small).contentScale)
    }

    func testOptionalMetadataRemainsAbsentInCurrentProjection() {
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("session"))
        let projection = SessionProjection(
            identity: identity,
            execution: .waiting,
            observation: .fresh,
            displayTitle: nil,
            hostLabel: nil,
            sourceLastUpdated: nil,
            ledgerRevision: 1
        )
        let card = AgentSessionCardSnapshot(projection: projection)
        XCTAssertNil(card.displayTitle)
        XCTAssertNil(card.hostLabel)
        XCTAssertNil(card.sourceLastUpdated)
        XCTAssertTrue(card.subagentRuns.isEmpty)
    }

    func testGeneralDefaultsRemainLocalPresentationOnly() {
        let defaults = AtlasGeneralPreferences.default
        XCTAssertTrue(defaults.hideWhenNoActiveSession)
        XCTAssertTrue(defaults.suppressWhenExactHostForeground)
        XCTAssertEqual(defaults.clickBehavior, .inspectExpand)
    }
}
