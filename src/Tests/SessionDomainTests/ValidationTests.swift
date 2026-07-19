import XCTest
import Foundation
@testable import SessionDomain

final class ValidationTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)

    private func makeSnapshot(major: Int = 1) -> NegotiationSnapshot {
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

    private func makeEnvelope(
        snapshot: NegotiationSnapshot,
        productNamespace: String? = "claude-code",
        nativeSessionID: String? = "sess_1",
        eventIdentity: EventIdentity? = .stable("evt_1"),
        family: EventFamily = .sessionDeclared,
        activityKind: SessionActivityKind? = nil,
        boundaryReason: ObservationBoundaryReason? = nil,
        classification: PayloadClassification = .operationalMetadata,
        payloadByteSize: Int = 128
    ) -> RawEventEnvelope {
        RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: snapshot.integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: productNamespace,
            nativeSessionID: nativeSessionID,
            eventIdentity: eventIdentity,
            family: family,
            sourceVariant: "claudeCode.sessionDeclared",
            activityKind: activityKind,
            boundaryReason: boundaryReason,
            classification: classification,
            payloadByteSize: payloadByteSize
        )
    }

    func testValidEnvelopeIsAccepted() {
        let snapshot = makeSnapshot()
        let envelope = makeEnvelope(snapshot: snapshot)

        let result = SessionDomainValidator.validate(envelope, negotiation: snapshot, receiptTime: fixedDate)

        guard case .accepted(let fact) = result else {
            return XCTFail("expected acceptance, got \(result)")
        }
        XCTAssertEqual(fact.identity.productNamespace.rawValue, "claude-code")
        XCTAssertEqual(fact.identity.nativeSessionID.rawValue, "sess_1")
    }

    func testUnknownNegotiationSnapshotIsRejected() {
        let snapshot = makeSnapshot()
        let envelope = makeEnvelope(snapshot: snapshot)

        let result = SessionDomainValidator.validate(envelope, negotiation: nil, receiptTime: fixedDate)

        XCTAssertEqual(result.rejectionReason, .unknownNegotiationSnapshot)
    }

    func testIncompatibleContractMajorIsRejected() {
        let snapshot = makeSnapshot(major: 1)
        var envelope = makeEnvelope(snapshot: snapshot)
        envelope = RawEventEnvelope(
            negotiationSnapshotID: envelope.negotiationSnapshotID,
            integrationInstanceID: envelope.integrationInstanceID,
            contractVersion: ContractVersion(major: 99, minor: 0),
            productNamespace: envelope.productNamespace,
            nativeSessionID: envelope.nativeSessionID,
            eventIdentity: envelope.eventIdentity,
            family: envelope.family,
            sourceVariant: envelope.sourceVariant,
            classification: envelope.classification,
            payloadByteSize: envelope.payloadByteSize
        )

        let result = SessionDomainValidator.validate(envelope, negotiation: snapshot, receiptTime: fixedDate)

        XCTAssertEqual(result.rejectionReason, .incompatibleContractMajor)
    }

    func testCapabilityNotGrantedIsRejected() {
        let ungranted = NegotiationSnapshot(
            id: NegotiationSnapshotID("snapshot-ungranted"),
            contractVersion: ContractVersion(major: 1, minor: 0),
            adapterKind: "fixture.first-party",
            adapterBuildVersion: "0.1.0",
            productNamespace: ProductNamespace("claude-code"),
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            integrationMode: "fixtureObservation",
            capabilities: [],
            negotiatedAt: fixedDate
        )
        let envelope = makeEnvelope(snapshot: ungranted)

        let result = SessionDomainValidator.validate(envelope, negotiation: ungranted, receiptTime: fixedDate)

        XCTAssertEqual(result.rejectionReason, .capabilityNotGranted)
    }

    func testMissingOwnerIdentityIsRejected() {
        let snapshot = makeSnapshot()

        for envelope in [
            makeEnvelope(snapshot: snapshot, productNamespace: nil),
            makeEnvelope(snapshot: snapshot, nativeSessionID: nil),
            makeEnvelope(snapshot: snapshot, nativeSessionID: "   "),
            makeEnvelope(snapshot: snapshot, productNamespace: "codex-cli"),
        ] {
            let result = SessionDomainValidator.validate(envelope, negotiation: snapshot, receiptTime: fixedDate)
            XCTAssertEqual(result.rejectionReason, .missingOrAmbiguousOwnerIdentity)
        }
    }

    func testMissingEventIdentityIsRejected() {
        let snapshot = makeSnapshot()
        let envelope = makeEnvelope(snapshot: snapshot, eventIdentity: nil)

        let result = SessionDomainValidator.validate(envelope, negotiation: snapshot, receiptTime: fixedDate)

        XCTAssertEqual(result.rejectionReason, .missingEventIdentity)
    }

    func testMalformedActivityShapeIsRejected() {
        let snapshot = makeSnapshot()
        let envelope = makeEnvelope(snapshot: snapshot, family: .sessionActivity, activityKind: nil)

        let result = SessionDomainValidator.validate(envelope, negotiation: snapshot, receiptTime: fixedDate)

        XCTAssertEqual(result.rejectionReason, .malformedShape)
    }

    func testMalformedObservationBoundaryShapeIsRejected() {
        let snapshot = makeSnapshot()
        let envelope = makeEnvelope(snapshot: snapshot, family: .observationBoundary, boundaryReason: nil)

        let result = SessionDomainValidator.validate(envelope, negotiation: snapshot, receiptTime: fixedDate)

        XCTAssertEqual(result.rejectionReason, .malformedShape)
    }

    func testOversizedPayloadIsRejected() {
        let snapshot = makeSnapshot()
        let envelope = makeEnvelope(snapshot: snapshot, payloadByteSize: SessionDomainValidator.maxPayloadBytes + 1)

        let result = SessionDomainValidator.validate(envelope, negotiation: snapshot, receiptTime: fixedDate)

        XCTAssertEqual(result.rejectionReason, .payloadTooLarge)
    }

    func testInteractionContentIsRejectedInThisSlice() {
        let snapshot = makeSnapshot()
        let envelope = makeEnvelope(snapshot: snapshot, classification: .interactionContent)

        let result = SessionDomainValidator.validate(envelope, negotiation: snapshot, receiptTime: fixedDate)

        XCTAssertEqual(result.rejectionReason, .interactionContentUnsupported)
    }

    func testDuplicateStableDeliveryProducesEqualDeduplicationKeys() {
        let snapshot = makeSnapshot()
        let first = makeEnvelope(snapshot: snapshot, eventIdentity: .stable("evt_dup"))
        let second = makeEnvelope(snapshot: snapshot, eventIdentity: .stable("evt_dup"))

        guard case .accepted(let firstFact) = SessionDomainValidator.validate(first, negotiation: snapshot, receiptTime: fixedDate),
              case .accepted(let secondFact) = SessionDomainValidator.validate(second, negotiation: snapshot, receiptTime: fixedDate) else {
            return XCTFail("expected both deliveries to validate")
        }

        XCTAssertEqual(firstFact.deduplicationKey, secondFact.deduplicationKey)
    }
}

private extension ValidationResult {
    var rejectionReason: EnvelopeValidationError? {
        if case .rejected(let reason) = self { return reason }
        return nil
    }
}
