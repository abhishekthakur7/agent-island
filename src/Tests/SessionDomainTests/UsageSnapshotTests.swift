import XCTest
@testable import SessionDomain

final class UsageSnapshotTests: XCTestCase {
    func testSnapshotKeepsMissingValuesMissingAndRejectsInvalidPercentages() {
        let snapshot = UsageSnapshot(sourceID: "source", provider: "Claude", observedAt: Date(timeIntervalSince1970: 1), resetsAt: nil, usedPercent: 25, remainingPercent: 120)
        XCTAssertEqual(snapshot.usedPercent, 25)
        XCTAssertNil(snapshot.remainingPercent)
        XCTAssertTrue(snapshot.hasSourcedValue)
        XCTAssertNil(UsageValueKind.remaining.value(in: snapshot))
    }

    func testUsagePreferencesDefaultToFollowAndRemaining() {
        XCTAssertEqual(UsageDisplayPreferences.default.valueKind, .remaining)
        XCTAssertEqual(UsageDisplayPreferences.default.providerSelection, .followSelectedActiveSession)
    }
}
