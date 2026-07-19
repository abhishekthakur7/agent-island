import XCTest
import Foundation
@testable import SessionDomain

final class ReducerTests: XCTestCase {
    private let identity = AgentSessionIdentity(
        productNamespace: ProductNamespace("claude-code"),
        nativeSessionID: NativeSessionID("sess_1")
    )
    private let integrationInstanceID = IntegrationInstanceID("instance-1")
    private let snapshotID = NegotiationSnapshotID("snapshot-1")
    private let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)

    private func fact(
        ordinal: Int64,
        family: EventFamily,
        activityKind: SessionActivityKind? = nil,
        boundaryReason: ObservationBoundaryReason? = nil,
        eventID: String
    ) -> NormalizedEventFact {
        NormalizedEventFact(
            receiptOrdinal: ordinal,
            identity: identity,
            integrationInstanceID: integrationInstanceID,
            negotiationSnapshotID: snapshotID,
            eventIdentity: .stable(eventID),
            family: family,
            sourceVariant: "claudeCode.\(family.rawValue)",
            activityKind: activityKind,
            boundaryReason: boundaryReason,
            classification: .operationalMetadata,
            occurrenceTime: nil,
            receiptTime: fixedDate,
            displayTitle: nil,
            hostLabel: nil
        )
    }

    func testWorkingToWaitingToCompleted() {
        let history = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, eventID: "e1"),
            fact(ordinal: 2, family: .sessionActivity, activityKind: .waiting, eventID: "e2"),
            fact(ordinal: 3, family: .sessionActivity, activityKind: .completed, eventID: "e3"),
        ]

        let projection = SessionReducer.reduce(history: history, ledgerRevision: 3)

        XCTAssertEqual(projection.execution, .terminalCompleted)
        XCTAssertEqual(projection.observation, .fresh)
        XCTAssertEqual(projection.ledgerRevision, 3)
    }

    func testFailedAndStoppedAreDistinctTerminalStates() {
        let failedHistory = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, eventID: "e1"),
            fact(ordinal: 2, family: .sessionActivity, activityKind: .failed, eventID: "e2"),
        ]
        XCTAssertEqual(SessionReducer.reduce(history: failedHistory, ledgerRevision: 2).execution, .terminalFailed)

        let stoppedHistory = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, eventID: "e1"),
            fact(ordinal: 2, family: .sessionActivity, activityKind: .stopped, eventID: "e2"),
        ]
        XCTAssertEqual(SessionReducer.reduce(history: stoppedHistory, ledgerRevision: 2).execution, .terminalStopped)
    }

    func testObservationBoundaryFromWorkingBecomesUnresolvedNeverTerminal() {
        let history = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, eventID: "e1"),
            fact(ordinal: 2, family: .observationBoundary, boundaryReason: .transportLost, eventID: "e2"),
        ]

        let projection = SessionReducer.reduce(history: history, ledgerRevision: 2)

        XCTAssertEqual(projection.execution, .unresolved)
        XCTAssertEqual(projection.observation, .unavailable)
        XCTAssertFalse(projection.execution.isTerminal)
    }

    func testObservationBoundaryAfterTerminalDoesNotRewriteTerminalOutcome() {
        let history = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, eventID: "e1"),
            fact(ordinal: 2, family: .sessionActivity, activityKind: .completed, eventID: "e2"),
            fact(ordinal: 3, family: .observationBoundary, boundaryReason: .transportLost, eventID: "e3"),
        ]

        let projection = SessionReducer.reduce(history: history, ledgerRevision: 3)

        XCTAssertEqual(projection.execution, .terminalCompleted, "a proven terminal outcome is historical fact, not erased by later transport loss")
        XCTAssertEqual(projection.observation, .unavailable)
    }

    func testUnknownActivityBeforeStartLeavesExecutionUnresolved() {
        let history = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .waiting, eventID: "e1"),
        ]

        let projection = SessionReducer.reduce(history: history, ledgerRevision: 1)

        XCTAssertEqual(projection.execution, .unresolved, "waiting is only reachable from working")
    }

    func testSessionDeclaredAloneEstablishesRecordWithoutLifecycleClaim() {
        let history = [
            fact(ordinal: 1, family: .sessionDeclared, eventID: "e1"),
        ]

        let projection = SessionReducer.reduce(history: history, ledgerRevision: 1)

        XCTAssertEqual(projection.execution, .unresolved)
        XCTAssertEqual(projection.identity, identity)
    }
}
