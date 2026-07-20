import XCTest
import Foundation
@testable import SessionDomain
@testable import SessionStore

final class SessionHistoryStoreTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_752_000_000)

    private func snapshot() -> NegotiationSnapshot {
        NegotiationSnapshot(id: NegotiationSnapshotID("history-snapshot"), contractVersion: ContractVersion(major: 1, minor: 0), adapterKind: "fixture", adapterBuildVersion: "1", productNamespace: ProductNamespace("claude-code"), integrationInstanceID: IntegrationInstanceID("history-instance"), integrationMode: "fixtureObservation", capabilities: [CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available)], negotiatedAt: date)
    }

    private func envelope(_ snapshot: NegotiationSnapshot, session: String, event: String, family: EventFamily, activity: SessionActivityKind? = nil, occurrence: Date? = nil) -> RawEventEnvelope {
        RawEventEnvelope(negotiationSnapshotID: snapshot.id, integrationInstanceID: snapshot.integrationInstanceID, contractVersion: snapshot.contractVersion, productNamespace: "claude-code", nativeSessionID: session, eventIdentity: .stable(event), family: family, sourceVariant: "fixture", activityKind: activity, classification: .operationalMetadata, payloadByteSize: 1, occurrenceTime: occurrence)
    }

    @discardableResult
    private func addCompleted(_ store: SessionStore, snapshot: NegotiationSnapshot, session: String, index: Int) async -> IntakeOutcome {
        _ = await store.intake(envelope(snapshot, session: session, event: "start-\(index)", family: .sessionActivity, activity: .started), receiptTime: date.addingTimeInterval(Double(index)))
        return await store.intake(envelope(snapshot, session: session, event: "done-\(index)", family: .sessionActivity, activity: .completed), receiptTime: date.addingTimeInterval(Double(index)))
    }

    func testThirtyFirstSafelyInactiveSessionMovesOldestToHistory() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)
        for index in 0..<31 { _ = await addCompleted(store, snapshot: snap, session: "s\(index)", index: index) }
        let working = await store.workingSetProjections()
        let history = await store.historySummaries()
        XCTAssertEqual(working.count, 30)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.identity.nativeSessionID.rawValue, "s0")
        XCTAssertEqual(history.first?.orderingSource, .localFirstObservedTime)
    }

    func testTwentyNineAndThirtyStayInWorkingSet() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)
        for index in 0..<30 { _ = await addCompleted(store, snapshot: snap, session: "s\(index)", index: index) }
        let atThirty = await store.workingSetProjections()
        let historyAtThirty = await store.historySummaries()
        XCTAssertEqual(atThirty.count, 30)
        XCTAssertTrue(historyAtThirty.isEmpty)

        // A separate store captures the 29-session boundary without relying
        // on a timer or cleanup side effect.
        let twentyNineStore = SessionStore()
        await twentyNineStore.registerNegotiation(snap)
        for index in 0..<29 { _ = await addCompleted(twentyNineStore, snapshot: snap, session: "twentyNine-\(index)", index: index) }
        let twentyNineWorking = await twentyNineStore.workingSetProjections()
        let twentyNineHistory = await twentyNineStore.historySummaries()
        XCTAssertEqual(twentyNineWorking.count, 29)
        XCTAssertTrue(twentyNineHistory.isEmpty)
    }

    func testAllActiveOverflowStaysVisible() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)
        for index in 0..<31 {
            _ = await store.intake(envelope(snap, session: "active\(index)", event: "active-\(index)", family: .sessionActivity, activity: .started), receiptTime: date.addingTimeInterval(Double(index)))
        }
        let working = await store.workingSetProjections()
        let history = await store.historySummaries()
        XCTAssertEqual(working.count, 31)
        XCTAssertTrue(history.isEmpty)
    }

    func testAuthoritativeFactRestoresExactArchivedOwnerAndSimilarityDoesNot() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)
        for index in 0..<31 { _ = await addCompleted(store, snapshot: snap, session: "s\(index)", index: index) }
        let archived = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("s0"))
        let initialTier = await store.tier(for: archived)
        XCTAssertEqual(initialTier, .history)
        _ = await store.intake(envelope(snap, session: "s0", event: "late-declared", family: .sessionDeclared), receiptTime: date.addingTimeInterval(100))
        let restoredTier = await store.tier(for: archived)
        XCTAssertEqual(restoredTier, .workingSet)
        let restoredHistory = await store.historySummaries()
        XCTAssertFalse(restoredHistory.contains { $0.identity == archived })
    }

    func testDeletionRequiresConfirmationIsExactAndSuppressesOldReplay() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)
        for index in 0..<31 { _ = await addCompleted(store, snapshot: snap, session: "s\(index)", index: index) }
        let deleted = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("s0"))
        guard let preview = await store.previewHistoryDeletion(for: deleted) else { return XCTFail("expected history preview") }
        let unconfirmed = await store.deleteHistory(for: deleted, confirmation: preview.confirmation)
        XCTAssertEqual(unconfirmed, .confirmationRequired)
        let deletedOutcome = await store.deleteHistory(for: deleted, confirmation: preview.confirmation.confirming())
        XCTAssertEqual(deletedOutcome, .deleted)
        let deletedTier = await store.tier(for: deleted)
        XCTAssertNil(deletedTier)
        let replay = await store.intake(envelope(snap, session: "s0", event: "start-0", family: .sessionActivity, activity: .started), receiptTime: date.addingTimeInterval(200))
        XCTAssertEqual(replay, .duplicateIgnored(ledgerRevision: 62))
        let otherTier = await store.tier(for: AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("s1")))
        XCTAssertNotNil(otherTier)
    }

    func testActiveLocalHistoryFlowStopsOnlyLocalObservationUntilConfirmation() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)
        _ = await store.intake(envelope(snap, session: "active", event: "active-start", family: .sessionActivity, activity: .started), receiptTime: date)
        guard let preview = await store.beginActiveLocalHistoryDeletion(for: AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("active"))) else {
            return XCTFail("expected active local-history preview")
        }
        let stopped = await store.intake(envelope(snap, session: "active", event: "active-working", family: .sessionActivity, activity: .working), receiptTime: date.addingTimeInterval(1))
        XCTAssertEqual(stopped, .duplicateIgnored(ledgerRevision: 1))
        let cancelled = await store.cancelActiveLocalHistoryDeletion(for: preview.identity)
        XCTAssertTrue(cancelled)
        let fresh = await store.intake(envelope(snap, session: "active", event: "active-done", family: .sessionActivity, activity: .completed), receiptTime: date.addingTimeInterval(2))
        XCTAssertEqual(fresh, .committed(ledgerRevision: 2))
    }
}
