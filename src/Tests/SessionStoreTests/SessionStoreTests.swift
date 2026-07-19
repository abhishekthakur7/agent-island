import XCTest
import Foundation
@testable import SessionDomain
@testable import SessionStore

final class SessionStoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)

    private func snapshot(major: Int = 1) -> NegotiationSnapshot {
        NegotiationSnapshot(
            id: NegotiationSnapshotID("snapshot-1"),
            contractVersion: ContractVersion(major: major, minor: 0),
            adapterKind: "fixture.first-party",
            adapterBuildVersion: "0.1.0",
            productNamespace: ProductNamespace("claude-code"),
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            integrationMode: "fixtureObservation",
            capabilities: [CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available)],
            negotiatedAt: fixedDate
        )
    }

    private func envelope(snapshot: NegotiationSnapshot, nativeSessionID: String = "sess_1", eventID: String = "evt_1", family: EventFamily = .sessionDeclared, activityKind: SessionActivityKind? = nil) -> RawEventEnvelope {
        RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: snapshot.integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: "claude-code",
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(eventID),
            family: family,
            sourceVariant: "claudeCode.sessionDeclared",
            activityKind: activityKind,
            classification: .operationalMetadata,
            payloadByteSize: 64
        )
    }

    func testCommitPublishesBeforeReturningAndTagsLedgerRevision() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)

        let outcome = await store.intake(envelope(snapshot: snap), receiptTime: fixedDate)

        guard case .committed(let revision) = outcome else {
            return XCTFail("expected commit, got \(outcome)")
        }
        XCTAssertEqual(revision, 1)

        var received: ProjectionRevision?
        for await value in await store.presentationStream() {
            received = value
            break
        }
        XCTAssertEqual(received?.ledgerRevision, 1)
        XCTAssertEqual(received?.sessions.count, 1)
    }

    func testDuplicateStableDeliveryIsIgnoredNotCommittedTwice() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)

        let first = await store.intake(envelope(snapshot: snap, eventID: "evt_dup"), receiptTime: fixedDate)
        let second = await store.intake(envelope(snapshot: snap, eventID: "evt_dup"), receiptTime: fixedDate)

        guard case .committed(let firstRevision) = first else { return XCTFail("expected first commit") }
        guard case .duplicateIgnored(let secondRevision) = second else { return XCTFail("expected duplicate ignored, got \(second)") }
        XCTAssertEqual(firstRevision, secondRevision)

        var received: ProjectionRevision?
        for await value in await store.presentationStream() {
            received = value
            break
        }
        XCTAssertEqual(received?.sessions.count, 1)
    }

    func testRejectedEnvelopeProducesNoCardAndNoRevisionBump() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)

        let badEnvelope = RawEventEnvelope(
            negotiationSnapshotID: snap.id,
            integrationInstanceID: snap.integrationInstanceID,
            contractVersion: snap.contractVersion,
            productNamespace: "claude-code",
            nativeSessionID: nil,
            eventIdentity: .stable("evt_bad"),
            family: .sessionDeclared,
            sourceVariant: "claudeCode.sessionDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 64
        )

        let outcome = await store.intake(badEnvelope, receiptTime: fixedDate)
        XCTAssertEqual(outcome, .rejected(.missingOrAmbiguousOwnerIdentity))

        var received: ProjectionRevision?
        for await value in await store.presentationStream() {
            received = value
            break
        }
        XCTAssertEqual(received?.ledgerRevision, 0)
        XCTAssertEqual(received?.sessions.count, 0)
    }

    func testRejectionIsRecordedAsRedactedDiagnosticOnly() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)

        let badEnvelope = RawEventEnvelope(
            negotiationSnapshotID: snap.id,
            integrationInstanceID: snap.integrationInstanceID,
            contractVersion: snap.contractVersion,
            productNamespace: "claude-code",
            nativeSessionID: nil,
            eventIdentity: .stable("evt_bad"),
            family: .sessionDeclared,
            sourceVariant: "claudeCode.sessionDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 64
        )
        _ = await store.intake(badEnvelope, receiptTime: fixedDate)

        let diagnostics = await store.diagnostics
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].kind, .envelopeRejected)
        XCTAssertEqual(diagnostics[0].reason, .missingOrAmbiguousOwnerIdentity)
    }
}
