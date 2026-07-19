import CoreGraphics
import XCTest
@testable import AgentIslandApp

final class IslandOverlayModelsTests: XCTestCase {
    func testAmbientRevealAndHoverNeverEngageKeyboard() {
        var machine = IslandOverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))

        machine.reduce(.automaticReveal)
        XCTAssertEqual(machine.state.presentation, .focused)
        XCTAssertFalse(machine.state.keyboardEngaged)

        machine.reduce(.hoverEntered)
        XCTAssertEqual(machine.state.presentation, .expanded)
        XCTAssertFalse(machine.state.keyboardEngaged)
    }

    func testKeyboardEngagementHasExplicitReleaseAndCollapseRemovesIt() {
        var machine = IslandOverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.engageKeyboard)
        XCTAssertEqual(machine.state.presentation, .expanded)
        XCTAssertTrue(machine.state.keyboardEngaged)

        machine.reduce(.releaseKeyboard)
        XCTAssertFalse(machine.state.keyboardEngaged)
        machine.reduce(.collapse)
        XCTAssertEqual(machine.state.presentation, .collapsed)
        XCTAssertTrue(machine.state.hasVisibleRegions)
    }

    func testSelectedDisplayLossAndQuietSceneWithdrawAllVisibleRegions() {
        var machine = IslandOverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.engageKeyboard)
        machine.reduce(.displayLost)
        XCTAssertEqual(machine.state.presentation, .withdrawn)
        XCTAssertFalse(machine.state.keyboardEngaged)
        XCTAssertFalse(machine.state.hasVisibleRegions)

        machine.reduce(.displayReconnected)
        XCTAssertEqual(machine.state.presentation, .collapsed)
        machine.reduce(.setQuietSceneSuppressed(true))
        XCTAssertEqual(machine.state.presentation, .withdrawn)
        XCTAssertFalse(machine.state.hasVisibleRegions)

        machine.reduce(.setQuietSceneSuppressed(false))
        XCTAssertEqual(machine.state.presentation, .collapsed)
        XCTAssertFalse(machine.state.keyboardEngaged)
    }

    func testSleepAndTerminationCannotRestoreStaleOverlayAuthority() {
        var machine = IslandOverlayStateMachine()
        machine.reduce(.launch(displayAvailable: true))
        machine.reduce(.engageKeyboard)
        machine.reduce(.sleep)
        XCTAssertEqual(machine.state.presentation, .withdrawn)
        XCTAssertFalse(machine.state.hasVisibleRegions)

        machine.reduce(.wake(displayAvailable: true))
        XCTAssertEqual(machine.state.presentation, .collapsed)
        XCTAssertFalse(machine.state.keyboardEngaged)
        machine.reduce(.terminate)
        XCTAssertEqual(machine.state.presentation, .withdrawn)
        XCTAssertFalse(machine.state.hasVisibleRegions)
    }

    func testBuiltInNotchReserveHasNoHitRegionAndGeometryClampsToSafeBounds() {
        let display = CGRect(x: 40, y: 20, width: 640, height: 620)
        let safe = display.insetBy(dx: 12, dy: 6)
        let geometry = IslandOverlayGeometry.make(usableFrame: display, isBuiltIn: true, presentation: .expanded)

        XCTAssertGreaterThanOrEqual(geometry.frame.minX, safe.minX)
        XCTAssertLessThanOrEqual(geometry.frame.maxX, safe.maxX)
        XCTAssertGreaterThanOrEqual(geometry.frame.minY, safe.minY)
        XCTAssertLessThanOrEqual(geometry.frame.maxY, safe.maxY)
        XCTAssertEqual(geometry.hitRegions.count, 2)
        let protectedPoint = CGPoint(x: geometry.hitRegions[0].maxX + geometry.protectedGap / 2, y: geometry.frame.height / 2)
        XCTAssertFalse(geometry.hitRegions.contains { $0.contains(protectedPoint) })
    }

    func testExternalDisplayIsASingleVisibleInteractiveSurface() {
        let geometry = IslandOverlayGeometry.make(
            usableFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            isBuiltIn: false,
            presentation: .collapsed
        )
        XCTAssertEqual(geometry.protectedGap, 0)
        XCTAssertEqual(geometry.hitRegions, [CGRect(origin: .zero, size: geometry.frame.size)])
    }
}
