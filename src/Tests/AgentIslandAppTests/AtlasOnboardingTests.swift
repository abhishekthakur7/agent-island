import XCTest
@testable import AgentIslandApp

final class AtlasOnboardingTests: XCTestCase {
    func testLifecycleIsResumableAndActionsAreIdempotent() {
        var state = AtlasOnboardingState.initial
        state.start()
        XCTAssertEqual(state.lifecycle, .active)
        state.start()
        XCTAssertEqual(state.step, .aggregation)
        state.next()
        XCTAssertTrue(state.completedSteps.contains(.aggregation))
        XCTAssertEqual(state.step, .completionAwareness)
        state.skip()
        XCTAssertEqual(state.lifecycle, .deferred)
        state.skip()
        XCTAssertEqual(state.lifecycle, .deferred)
        state.resume()
        XCTAssertEqual(state.lifecycle, .active)
        state.back()
        XCTAssertEqual(state.step, .aggregation)
    }

    func testNextAtLastStepCompletesAndCompletionIsIdempotent() {
        var state = AtlasOnboardingState(lifecycle: .active, step: .hostFallback, completedSteps: [.aggregation, .completionAwareness])
        state.next()
        XCTAssertTrue(state.completedSteps.contains(.hostFallback))
        XCTAssertEqual(state.step, .setupAndDisplay)
        state.next()
        XCTAssertEqual(state.lifecycle, .completed)
        state.complete()
        XCTAssertEqual(state, state.reducing(.complete))
        state.back()
        XCTAssertEqual(state.lifecycle, .completed)
    }

    func testUnknownSchemaNormalizesToOnboardingOnlyInitialState() {
        let unknown = AtlasOnboardingState(schemaVersion: 2, lifecycle: .active, step: .display)
        XCTAssertEqual(unknown.normalized(), .initial)
    }
}
