import XCTest
@testable import NativeIslandOverlay

/// Deterministic checks for the disposable 30-Agent-Session workload used by
/// the feasibility measurements. These deliberately exercise no AppKit UI.
final class FixtureContractTests: XCTestCase {
    func testThirtySessionFixtureHasStableCoverageAndUniqueIdentity() {
        let sessions = FixtureSession.samples

        XCTAssertEqual(sessions.count, 30)
        XCTAssertEqual(Set(sessions.map(\.id)).count, 30)
        XCTAssertEqual(sessions.filter { $0.state == .attention }.count, 6)
        XCTAssertEqual(sessions.filter { $0.state == .working }.count, 12)
        XCTAssertEqual(sessions.filter { $0.state == .complete }.count, 6)
        XCTAssertEqual(sessions.filter { $0.state == .waiting }.count, 6)
        XCTAssertEqual(sessions.filter { $0.childRuns > 0 }.count, 8)
    }

    func testThirtySessionFixtureContainsUsableRepresentativeMetadata() {
        let sessions = FixtureSession.samples

        XCTAssertTrue(sessions.allSatisfy { !$0.title.isEmpty })
        XCTAssertTrue(sessions.allSatisfy { !$0.project.isEmpty })
        XCTAssertTrue(sessions.allSatisfy { !$0.product.isEmpty })
        XCTAssertTrue(sessions.allSatisfy { !$0.host.isEmpty })
        XCTAssertTrue(sessions.allSatisfy { !$0.elapsed.isEmpty })
        XCTAssertGreaterThan(Set(sessions.map(\.project)).count, 1)
        XCTAssertGreaterThan(Set(sessions.map(\.product)).count, 1)
        XCTAssertGreaterThan(Set(sessions.map(\.host)).count, 1)
    }

    func testPresentationStatesRetainTheirExplicitWireNames() {
        XCTAssertEqual(OverlayPresentation.withdrawn.rawValue, "withdrawn")
        XCTAssertEqual(OverlayPresentation.collapsed.rawValue, "collapsed")
        XCTAssertEqual(OverlayPresentation.focused.rawValue, "focused")
        XCTAssertEqual(OverlayPresentation.expanded.rawValue, "expanded")
    }
}
