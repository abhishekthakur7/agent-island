import SwiftUI
import XCTest
@testable import AgentIslandApp

final class AtlasSettingsWindowRestorationTests: XCTestCase {
    @MainActor
    func testRestorationReconstructsAStandardIndependentSettingsWindow() throws {
        let coordinator = AtlasSettingsWindowCoordinator { AnyView(EmptyView()) }
        var restoredWindow: NSWindow?
        coordinator.restoreSettingsWindow { window, error in
            XCTAssertNil(error)
            restoredWindow = window
        }

        let window = try XCTUnwrap(restoredWindow)
        XCTAssertEqual(window.identifier, AtlasSettingsWindowCoordinator.restorationIdentifier)
        XCTAssertEqual(window.level, .normal)
        XCTAssertTrue(window.isRestorable)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.restorationClass === AtlasSettingsWindowRestorer.self)
        window.close()
    }
}
