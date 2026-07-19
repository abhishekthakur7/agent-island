import XCTest
@testable import NativeIslandOverlay

/// Headless OW-1, OW-3/4, OW-9/10, OW-12, and OW-14 regression coverage.
/// AppKit panel creation and event monitors are intentionally outside these
/// tests; this is the deterministic policy contract they render.
final class OverlayStateMachineTests: XCTestCase {
    func testAutomaticRevealFocusesWithoutKeyboardEngagement() {
        var machine = OverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))

        machine.reduce(.automaticReveal)

        XCTAssertEqual(machine.state.presentation, .focused)
        XCTAssertFalse(machine.state.keyboardEngaged)
        XCTAssertTrue(machine.state.hasVisibleHitRegions)
        XCTAssertTrue(machine.state.hasVisibleAccessibilityRegions)
    }

    func testHoverExitIsReversibleAndCannotCollapseAGuardedInteraction() {
        var machine = OverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.hoverEntered)
        XCTAssertEqual(machine.state.presentation, .expanded)

        machine.reduce(.setInteractionGuard(true))
        machine.reduce(.hoverExited)
        XCTAssertEqual(machine.state.presentation, .expanded)

        machine.reduce(.setInteractionGuard(false))
        machine.reduce(.hoverExited)
        XCTAssertEqual(machine.state.presentation, .collapsed)
        XCTAssertTrue(machine.state.hasVisibleHitRegions)
        XCTAssertTrue(machine.state.hasVisibleAccessibilityRegions)
    }

    func testCollapseAndKeyboardReleaseNeverLeaveInvisibleInputOrAccessibilityRegions() {
        var machine = OverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.engageKeyboard)
        XCTAssertEqual(machine.state.presentation, .expanded)
        XCTAssertTrue(machine.state.keyboardEngaged)

        machine.reduce(.collapse)

        XCTAssertEqual(machine.state.presentation, .collapsed)
        XCTAssertFalse(machine.state.keyboardEngaged)
        XCTAssertTrue(machine.state.hasVisibleHitRegions)
        XCTAssertTrue(machine.state.hasVisibleAccessibilityRegions)
    }

    func testSelectedDisplayLossWithdrawsInsteadOfMigratingAndReconnectRestoresOnlyCollapsed() {
        var machine = OverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.automaticReveal)
        machine.reduce(.engageKeyboard)

        machine.reduce(.displayLost)

        XCTAssertEqual(machine.state.presentation, .withdrawn)
        XCTAssertFalse(machine.state.selectedDisplayAvailable)
        XCTAssertFalse(machine.state.keyboardEngaged)
        XCTAssertFalse(machine.state.hasVisibleHitRegions)
        XCTAssertFalse(machine.state.hasVisibleAccessibilityRegions)

        machine.reduce(.displayReconnected)

        XCTAssertEqual(machine.state.presentation, .collapsed)
        XCTAssertTrue(machine.state.selectedDisplayAvailable)
        XCTAssertFalse(machine.state.keyboardEngaged)
        XCTAssertTrue(machine.state.hasVisibleHitRegions)
    }

    func testFullscreenSuppressionWithdrawsAllRegionsAndPolicyReleaseRestoresCollapsed() {
        var machine = OverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.automaticReveal)

        machine.reduce(.setFullscreenSuppressed(true))

        XCTAssertEqual(machine.state.presentation, .withdrawn)
        XCTAssertFalse(machine.state.hasVisibleHitRegions)
        XCTAssertFalse(machine.state.hasVisibleAccessibilityRegions)

        machine.reduce(.setFullscreenSuppressed(false))

        XCTAssertEqual(machine.state.presentation, .collapsed)
        XCTAssertTrue(machine.state.hasVisibleHitRegions)
        XCTAssertTrue(machine.state.hasVisibleAccessibilityRegions)
    }

    func testRepeatedSleepWakeIsAColdResumeWithoutStaleFocusOrRevealReplay() {
        var machine = OverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))

        for _ in 0..<3 {
            machine.reduce(.automaticReveal)
            machine.reduce(.engageKeyboard)
            machine.reduce(.sleep)

            XCTAssertEqual(machine.state.presentation, .withdrawn)
            XCTAssertFalse(machine.state.keyboardEngaged)
            XCTAssertFalse(machine.state.hasVisibleHitRegions)
            XCTAssertFalse(machine.state.hasVisibleAccessibilityRegions)

            machine.reduce(.wake(displayAvailable: true))
            XCTAssertEqual(machine.state.presentation, .collapsed)
            XCTAssertTrue(machine.state.selectedDisplayAvailable)
            XCTAssertFalse(machine.state.keyboardEngaged)
            XCTAssertTrue(machine.state.hasVisibleHitRegions)
        }
    }

    func testWakeWithoutSelectedDisplayRemainsWithdrawn() {
        var machine = OverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.sleep)
        machine.reduce(.wake(displayAvailable: false))

        XCTAssertEqual(machine.state.presentation, .withdrawn)
        XCTAssertFalse(machine.state.selectedDisplayAvailable)
        XCTAssertFalse(machine.state.hasVisibleHitRegions)
        XCTAssertFalse(machine.state.hasVisibleAccessibilityRegions)
    }

    func testTerminationWithdrawsInputAndAccessibilityBeforePanelTeardown() {
        var machine = OverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.engageKeyboard)

        machine.reduce(.terminate)

        XCTAssertEqual(machine.state.presentation, .withdrawn)
        XCTAssertFalse(machine.state.keyboardEngaged)
        XCTAssertFalse(machine.state.hasVisibleHitRegions)
        XCTAssertFalse(machine.state.hasVisibleAccessibilityRegions)
    }
}
