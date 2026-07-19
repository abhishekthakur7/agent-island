import CoreGraphics
import XCTest
@testable import NativeIslandOverlay

/// Synthetic safe frames make the selected-display/notch contract testable
/// without creating an NSScreen, NSPanel, or accessibility process.
final class OverlayGeometryTests: XCTestCase {
    func testBuiltInCollapsedGeometryReservesProtectedCenterFromAllHitRegions() {
        let geometry = OverlayGeometry.make(
            usableFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            isBuiltIn: true,
            presentation: .collapsed
        )

        XCTAssertTrue(geometry.isBuiltIn)
        XCTAssertEqual(geometry.hitRegions.count, 2)
        XCTAssertGreaterThanOrEqual(geometry.protectedGap, 32)
        XCTAssertLessThanOrEqual(geometry.protectedGap, 136)

        let left = try! XCTUnwrap(geometry.hitRegions.first)
        let right = try! XCTUnwrap(geometry.hitRegions.last)
        let protectedCenter = CGRect(
            x: left.maxX,
            y: 0,
            width: geometry.protectedGap,
            height: geometry.frame.height
        )

        XCTAssertEqual(right.minX, protectedCenter.maxX, accuracy: 0.001)
        XCTAssertFalse(left.intersects(protectedCenter))
        XCTAssertFalse(right.intersects(protectedCenter))
        XCTAssertFalse(geometry.hitRegions.contains { $0.contains(CGPoint(x: protectedCenter.midX, y: protectedCenter.midY)) })
    }

    func testExternalDisplayUsesOneVisibleHitRegionWithNoFictitiousNotchGap() {
        let geometry = OverlayGeometry.make(
            usableFrame: CGRect(x: 100, y: 50, width: 1_920, height: 1_080),
            isBuiltIn: false,
            presentation: .collapsed
        )

        XCTAssertFalse(geometry.isBuiltIn)
        XCTAssertEqual(geometry.protectedGap, 0)
        XCTAssertEqual(geometry.hitRegions, [CGRect(origin: .zero, size: geometry.frame.size)])
        XCTAssertTrue(geometry.hitRegions[0].contains(CGPoint(x: geometry.frame.midX - geometry.frame.minX, y: geometry.frame.midY - geometry.frame.minY)))
    }

    func testFocusedGeometryIsClampedInsideSelectedDisplaySafeBounds() {
        let selectedDisplay = CGRect(x: 40, y: 20, width: 640, height: 620)
        let safeBounds = selectedDisplay.insetBy(dx: 12, dy: 6)
        let geometry = OverlayGeometry.make(
            usableFrame: selectedDisplay,
            isBuiltIn: true,
            presentation: .focused
        )

        XCTAssertGreaterThanOrEqual(geometry.frame.minX, safeBounds.minX)
        XCTAssertLessThanOrEqual(geometry.frame.maxX, safeBounds.maxX)
        XCTAssertGreaterThanOrEqual(geometry.frame.minY, safeBounds.minY)
        XCTAssertLessThanOrEqual(geometry.frame.maxY, safeBounds.maxY)
        XCTAssertEqual(geometry.frame.maxY, safeBounds.maxY, accuracy: 0.001)
        XCTAssertTrue(geometry.hitRegions.allSatisfy { $0.minX >= 0 && $0.maxX <= geometry.frame.width })
    }
}
