import XCTest
import Foundation
import SessionDomain
@testable import AgentIslandApp

final class SessionHistoryViewTests: XCTestCase {
    @MainActor
    func testHistoryViewModelBoundsInspectionAndKeepsDeletionLocal() {
        let model = SessionHistoryViewModel()
        let summaries = (0..<150).map { index in
            let identity = AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("s\(index)"))
            return SessionHistorySummary(identity: identity, displayTitle: "Session \(index)", visibleLifecycle: .completed, creationDate: Date(timeIntervalSince1970: Double(index)), orderingSource: .localFirstObservedTime, factCount: index + 1, hasRecap: false)
        }
        model.replace(with: summaries)
        XCTAssertEqual(model.summaries.count, SessionHistoryViewModel.maximumVisibleEntries)
        let preview = model.scopePreview(for: model.summaries[0].identity)
        XCTAssertTrue(preview?.contains("does not delete the Agent Product session") == true)
    }
}

