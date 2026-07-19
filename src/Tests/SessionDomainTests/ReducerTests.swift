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
        sourceCursor: SourceCursor? = nil,
        ownership: LifecycleOwnership? = nil,
        turnLineage: TurnLineageKind? = nil,
        attentionKind: AttentionRequestKind? = nil,
        reconciliationScope: ReconciliationScope? = nil,
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
            hostLabel: nil,
            sourceCursor: sourceCursor,
            ownership: ownership,
            turnLineage: turnLineage,
            attentionKind: attentionKind,
            reconciliationScope: reconciliationScope
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

    func testReplayAndRebuildProduceIdenticalRevisionedProjection() {
        let history = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, sourceCursor: .init(scope: "session", value: 1), eventID: "e1"),
            fact(ordinal: 2, family: .sessionActivity, activityKind: .waiting, sourceCursor: .init(scope: "session", value: 2), eventID: "e2"),
        ]
        XCTAssertEqual(SessionReducer.reduce(history: history, ledgerRevision: 2), SessionReducer.reduce(history: history, ledgerRevision: 2))
    }

    func testCursorGapOrResetMakesLifecycleUnresolvedInsteadOfGuessingOrder() {
        let gap = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, sourceCursor: .init(scope: "session", value: 1), eventID: "e1"),
            fact(ordinal: 2, family: .sessionActivity, activityKind: .completed, sourceCursor: .init(scope: "session", value: 3), eventID: "e3"),
        ]
        let reset = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, sourceCursor: .init(scope: "session", value: 4), eventID: "e4"),
            fact(ordinal: 2, family: .sessionActivity, activityKind: .completed, sourceCursor: .init(scope: "session", value: 1), eventID: "e1"),
        ]
        XCTAssertEqual(SessionReducer.reduce(history: gap, ledgerRevision: 2).execution, .unresolved)
        XCTAssertEqual(SessionReducer.reduce(history: gap, ledgerRevision: 2).observation, .gap)
        XCTAssertEqual(SessionReducer.reduce(history: reset, ledgerRevision: 2).execution, .unresolved)
    }

    func testConflictingComparableTerminalFactsAreUnresolvedEvenAtEqualTimes() {
        let history = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, sourceCursor: .init(scope: "session", value: 1), eventID: "e1"),
            fact(ordinal: 2, family: .sessionActivity, activityKind: .completed, sourceCursor: .init(scope: "session", value: 2), eventID: "e2"),
            fact(ordinal: 3, family: .sessionActivity, activityKind: .failed, sourceCursor: .init(scope: "session", value: 3), eventID: "e3"),
        ]
        XCTAssertEqual(SessionReducer.reduce(history: history, ledgerRevision: 3).execution, .unresolved)
    }

    func testRewindPreservesHistoricalTurnAndLateHistoricalActivityCannotOverwriteCurrentTurn() {
        let first = LifecycleOwnership(nativeTurnID: "turn-1")
        let second = LifecycleOwnership(nativeTurnID: "turn-2", replacedNativeTurnID: "turn-1")
        let history = [
            fact(ordinal: 1, family: .turnDeclared, sourceCursor: .init(scope: "session", value: 1), ownership: first, eventID: "t1"),
            fact(ordinal: 2, family: .sessionActivity, activityKind: .started, sourceCursor: .init(scope: "session", value: 2), ownership: first, eventID: "a1"),
            fact(ordinal: 3, family: .turnLineage, sourceCursor: .init(scope: "session", value: 3), ownership: first, turnLineage: .historical, eventID: "h1"),
            fact(ordinal: 4, family: .turnLineage, sourceCursor: .init(scope: "session", value: 4), ownership: second, turnLineage: .current, eventID: "c2"),
            fact(ordinal: 5, family: .sessionActivity, activityKind: .working, sourceCursor: .init(scope: "session", value: 5), ownership: second, eventID: "a2"),
            fact(ordinal: 6, family: .sessionActivity, activityKind: .completed, sourceCursor: .init(scope: "session", value: 6), ownership: first, eventID: "late"),
        ]
        let projection = SessionReducer.reduce(history: history, ledgerRevision: 6)
        XCTAssertEqual(projection.execution, .working)
        XCTAssertEqual(projection.turns.first { $0.nativeTurnID == "turn-1" }?.lineage, .historical)
        XCTAssertEqual(projection.turns.first { $0.nativeTurnID == "turn-2" }?.lineage, .current)
    }

    func testActiveChildOrPendingAttentionPreventsConfidentParentTerminalPresentation() {
        let child = LifecycleOwnership(nativeSubagentRunID: "child-1")
        let attention = LifecycleOwnership(nativeAttentionRequestID: "attention-1")
        let history = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .started, sourceCursor: .init(scope: "session", value: 1), eventID: "s"),
            fact(ordinal: 2, family: .subagentRunDeclared, sourceCursor: .init(scope: "session", value: 2), ownership: child, eventID: "c"),
            fact(ordinal: 3, family: .sessionActivity, activityKind: .working, sourceCursor: .init(scope: "session", value: 3), ownership: child, eventID: "cw"),
            fact(ordinal: 4, family: .attentionRequest, sourceCursor: .init(scope: "session", value: 4), ownership: attention, attentionKind: .opened, eventID: "attention"),
            fact(ordinal: 5, family: .sessionActivity, activityKind: .completed, sourceCursor: .init(scope: "session", value: 5), eventID: "done"),
        ]
        let projection = SessionReducer.reduce(history: history, ledgerRevision: 5)
        XCTAssertEqual(projection.execution, .unresolved)
        XCTAssertEqual(projection.attention, .pending)
        XCTAssertEqual(projection.visibleLifecycle, .needsAttention)
    }

    func testNonExhaustiveReconciliationNeverInfersCompletion() {
        let history = [
            fact(ordinal: 1, family: .sessionActivity, activityKind: .working, sourceCursor: .init(scope: "session", value: 1), eventID: "work"),
            fact(ordinal: 2, family: .reconciliation, sourceCursor: .init(scope: "session", value: 2), reconciliationScope: .nonExhaustive, eventID: "list"),
        ]
        let projection = SessionReducer.reduce(history: history, ledgerRevision: 2)
        XCTAssertEqual(projection.execution, .unresolved)
        XCTAssertEqual(projection.observation, .gap)
    }
}
