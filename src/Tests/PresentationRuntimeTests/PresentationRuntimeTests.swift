import XCTest
import Foundation
@testable import SessionDomain
@testable import PresentationPort
@testable import PresentationRuntime

private struct FakePresentationPort: PresentationPort {
    let revisions: [ProjectionRevision]

    func presentationStream() -> AsyncStream<ProjectionRevision> {
        AsyncStream { continuation in
            for revision in revisions {
                continuation.yield(revision)
            }
            continuation.finish()
        }
    }
}

@MainActor
final class PresentationRuntimeTests: XCTestCase {
    private let identity = AgentSessionIdentity(
        productNamespace: ProductNamespace("claude-code"),
        nativeSessionID: NativeSessionID("sess_1")
    )

    func testCardPreservesIdentityAndOmitsUnavailableSourcedFields() async {
        let projection = SessionProjection(
            identity: identity,
            execution: .working,
            observation: .fresh,
            displayTitle: nil,
            hostLabel: nil,
            sourceLastUpdated: nil,
            ledgerRevision: 1
        )
        let port = FakePresentationPort(revisions: [ProjectionRevision(ledgerRevision: 1, sessions: [identity: projection])])
        let runtime = PresentationRuntime(port: port)

        await waitUntil { runtime.cards.count == 1 }

        let card = try? XCTUnwrap(runtime.cards.first)
        XCTAssertEqual(card?.productNamespace, "claude-code")
        XCTAssertEqual(card?.nativeSessionID, "sess_1")
        XCTAssertNil(card?.displayTitle, "unavailable sourced metadata must be omitted, never invented")
        XCTAssertNil(card?.hostLabel)
        XCTAssertNil(card?.sourceLastUpdated)
        XCTAssertTrue(card?.turns.isEmpty ?? false)
        XCTAssertTrue(card?.subagentRuns.isEmpty ?? false)
        XCTAssertEqual(card?.visibleLifecycle, .working)
    }

    func testCardSurfacesSourcedFieldsWhenPresent() async {
        let projection = SessionProjection(
            identity: identity,
            execution: .waiting,
            observation: .fresh,
            displayTitle: "Refactor billing service",
            hostLabel: "iTerm2",
            sourceLastUpdated: nil,
            ledgerRevision: 2
        )
        let port = FakePresentationPort(revisions: [ProjectionRevision(ledgerRevision: 2, sessions: [identity: projection])])
        let runtime = PresentationRuntime(port: port)

        await waitUntil { runtime.cards.count == 1 }

        XCTAssertEqual(runtime.cards.first?.displayTitle, "Refactor billing service")
        XCTAssertEqual(runtime.cards.first?.hostLabel, "iTerm2")
        XCTAssertEqual(runtime.cards.first?.execution, .waiting)
    }

    func testCardsUseSourceChronologyWithoutInventingTimes() async {
        let earlierIdentity = AgentSessionIdentity(
            productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("sess_earlier")
        )
        let laterIdentity = AgentSessionIdentity(
            productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("sess_later")
        )
        let earlier = SessionProjection(
            identity: earlierIdentity, execution: .working, observation: .fresh,
            displayTitle: nil, hostLabel: nil,
            sourceLastUpdated: Date(timeIntervalSince1970: 10), ledgerRevision: 1
        )
        let later = SessionProjection(
            identity: laterIdentity, execution: .working, observation: .fresh,
            displayTitle: nil, hostLabel: nil,
            sourceLastUpdated: Date(timeIntervalSince1970: 20), ledgerRevision: 1
        )
        let runtime = PresentationRuntime(port: FakePresentationPort(revisions: [
            ProjectionRevision(ledgerRevision: 1, sessions: [earlierIdentity: earlier, laterIdentity: later]),
        ]))

        await waitUntil { runtime.cards.count == 2 }
        XCTAssertEqual(runtime.cards.map(\.nativeSessionID), ["sess_later", "sess_earlier"])
    }

    func testMissingSourceTimeRemainsUnavailableWhenOnlyReceiptTimeExists() {
        let fact = NormalizedEventFact(
            receiptOrdinal: 1,
            identity: identity,
            integrationInstanceID: IntegrationInstanceID("fixture.instance"),
            negotiationSnapshotID: NegotiationSnapshotID("snapshot"),
            eventIdentity: .stable("event"),
            family: .sessionActivity,
            sourceVariant: "fixture.started",
            activityKind: .started,
            boundaryReason: nil,
            classification: .operationalMetadata,
            occurrenceTime: nil,
            receiptTime: Date(timeIntervalSince1970: 20),
            displayTitle: nil,
            hostLabel: nil
        )

        XCTAssertNil(SessionReducer.reduce(history: [fact], ledgerRevision: 1).sourceLastUpdated)
    }

    func testCardExposesNonColorAttentionLifecycleLabel() async {
        let projection = SessionProjection(
            identity: identity, execution: .waiting, observation: .fresh,
            displayTitle: nil, hostLabel: nil, sourceLastUpdated: nil, ledgerRevision: 1,
            attention: .pending
        )
        let runtime = PresentationRuntime(port: FakePresentationPort(revisions: [
            ProjectionRevision(ledgerRevision: 1, sessions: [identity: projection]),
        ]))
        await waitUntil { runtime.cards.count == 1 }
        XCTAssertEqual(runtime.cards.first?.visibleLifecycle, .needsAttention)
        XCTAssertEqual(runtime.cards.first?.attention, .pending)
    }

    func testLedgerRevisionTracksLatestPublishedRevision() async {
        let firstProjection = SessionProjection(
            identity: identity, execution: .working, observation: .fresh,
            displayTitle: nil, hostLabel: nil, sourceLastUpdated: nil, ledgerRevision: 1
        )
        let secondProjection = SessionProjection(
            identity: identity, execution: .waiting, observation: .fresh,
            displayTitle: nil, hostLabel: nil, sourceLastUpdated: nil, ledgerRevision: 2
        )
        let port = FakePresentationPort(revisions: [
            ProjectionRevision(ledgerRevision: 1, sessions: [identity: firstProjection]),
            ProjectionRevision(ledgerRevision: 2, sessions: [identity: secondProjection]),
        ])
        let runtime = PresentationRuntime(port: port)

        await waitUntil { runtime.ledgerRevision == 2 }

        XCTAssertEqual(runtime.cards.first?.execution, .waiting)
    }

    /// `PresentationRuntime` yields to the run loop between checks because
    /// its subscription task consumes the fake stream asynchronously.
    private func waitUntil(timeout: TimeInterval = 1, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
    }
}
