import XCTest
@testable import AgentIslandApp

final class AtlasPreviewIsolationTests: XCTestCase {
    func testRouterHasOnlyPreviewStateChangedTraceAndNoExternalServiceSurface() {
        var router = AtlasPreviewRouter()
        router.send(.hoverEntered)
        XCTAssertEqual(router.trace, [.previewStateChanged])
        XCTAssertTrue(router.state.isExpanded)
        router.send(.hoverExited)
        XCTAssertEqual(router.trace, [.previewStateChanged, .previewStateChanged])
        XCTAssertFalse(router.state.isExpanded)
    }

    func testPreviewUsesPendingGeneralValuesAndRemainsEphemeral() {
        let noReveal = AtlasGeneralPreferences(revealOnCompletion: false)
        var state = AtlasPreviewState(general: noReveal)
        state = AtlasPreviewReducer.reduce(state, action: .revealCompletion)
        XCTAssertFalse(state.isVisible)
        state = AtlasPreviewReducer.reduce(state, action: .setGeneral(.default))
        state = AtlasPreviewReducer.reduce(state, action: .revealCompletion)
        XCTAssertTrue(state.isVisible)
    }

    func testFilterPreviewChangesOnlyClosedPreviewState() {
        let router = AtlasPreviewRouter()
        router.send(.toggleCompletionFilter)
        router.send(.revealCompletion)

        XCTAssertFalse(router.state.includesCompletion)
        XCTAssertFalse(router.state.isVisible)
        XCTAssertEqual(router.trace, [.previewStateChanged])
    }
}
