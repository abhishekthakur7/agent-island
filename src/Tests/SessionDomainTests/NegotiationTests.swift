import XCTest
import Foundation
@testable import SessionDomain

final class NegotiationTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)

    private func request(major: Int) -> NegotiationRequest {
        NegotiationRequest(
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            adapterKind: "fixture.first-party",
            adapterBuildVersion: "0.1.0",
            productNamespace: ProductNamespace("claude-code"),
            integrationMode: "fixtureObservation",
            offeredContractVersion: ContractVersion(major: major, minor: 0),
            requestedCapabilities: [WellKnownCapability.sessionObservation]
        )
    }

    func testCompatibleMajorProducesGrantedSnapshot() {
        let outcome = SessionDomainNegotiator.negotiate(
            request(major: SessionDomainValidator.supportedContractMajor),
            id: NegotiationSnapshotID("snap-1"),
            negotiatedAt: fixedDate
        )

        guard case .compatible(let snapshot) = outcome else {
            return XCTFail("expected compatible outcome")
        }
        XCTAssertTrue(snapshot.grants(WellKnownCapability.sessionObservation, direction: .observe))
    }

    func testIncompatibleMajorProducesNoSnapshot() {
        let outcome = SessionDomainNegotiator.negotiate(
            request(major: 99),
            id: NegotiationSnapshotID("snap-2"),
            negotiatedAt: fixedDate
        )

        guard case .incompatible(let reason) = outcome else {
            return XCTFail("expected incompatible outcome")
        }
        XCTAssertEqual(reason, .incompatibleContractMajor)
    }

    func testSnapshotCarriesVersionsEvidenceAndIndependentDirections() {
        let request = NegotiationRequest(
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            adapterKind: "fixture.first-party",
            adapterBuildVersion: "0.2.0",
            productNamespace: ProductNamespace("claude-code"),
            integrationMode: "hooks",
            offeredContractVersion: ContractVersion(major: 1, minor: 7),
            requestedCapabilities: [],
            catalogRevision: "catalog.7",
            productVersion: "1.5.0",
            interfaceVersion: "hooks-v2",
            requestedCapabilityRecords: [
                CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available, revision: 3, scope: .mode),
                CapabilityRecord(id: WellKnownCapability.sessionAction, direction: .act, availability: .available, revision: 2, scope: .request, constraints: CapabilityConstraints(requiredPermission: "dispatch"), fallback: .nativeHost),
                CapabilityRecord(id: WellKnownCapability.configuration, direction: .configure, availability: .available, revision: 1, scope: .installation)
            ]
        )
        guard case .compatible(let snapshot) = SessionDomainNegotiator.negotiate(request, id: NegotiationSnapshotID("snap-rich"), negotiatedAt: fixedDate) else {
            return XCTFail("expected compatible outcome")
        }
        XCTAssertEqual(snapshot.catalogRevision, "catalog.7")
        XCTAssertEqual(snapshot.productVersion, "1.5.0")
        XCTAssertEqual(snapshot.interfaceVersion, "hooks-v2")
        XCTAssertEqual(Set(snapshot.capabilities.map(\.direction)), [.observe, .act, .configure])
        XCTAssertEqual(snapshot.capabilities.first { $0.direction == .act }?.constraints.requiredPermission, "dispatch")
        XCTAssertEqual(snapshot.capabilities.first { $0.direction == .act }?.fallback, .nativeHost)
        XCTAssertEqual(snapshot.capabilities.first { $0.direction == .act }?.provenance?.snapshotID, snapshot.id)
    }

    func testInterfaceChangeNarrowsOnlyUnprovenAction() {
        let request = NegotiationRequest(
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            adapterKind: "fixture.first-party",
            adapterBuildVersion: "0.2.0",
            productNamespace: ProductNamespace("claude-code"),
            integrationMode: "hooks",
            offeredContractVersion: ContractVersion(major: 1, minor: 1),
            requestedCapabilities: [],
            compatibility: .interfaceChanged,
            requestedCapabilityRecords: [
                CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available),
                CapabilityRecord(id: WellKnownCapability.sessionAction, direction: .act, availability: .available)
            ]
        )
        guard case .compatible(let snapshot) = SessionDomainNegotiator.negotiate(request, id: NegotiationSnapshotID("snap-change"), negotiatedAt: fixedDate) else {
            return XCTFail("expected narrowed compatible outcome")
        }
        XCTAssertEqual(snapshot.compatibility, .interfaceChanged)
        XCTAssertEqual(snapshot.capabilities.first { $0.id == WellKnownCapability.sessionObservation }?.availability, .available)
        XCTAssertEqual(snapshot.capabilities.first { $0.id == WellKnownCapability.sessionAction }?.availability, .interfaceChanged)
        XCTAssertTrue(snapshot.grants(WellKnownCapability.sessionObservation, direction: .observe))
        XCTAssertFalse(snapshot.grants(WellKnownCapability.sessionAction, direction: .act))
    }

    func testKillSwitchClosesOnlySelectedDirectionAndValidationFailsClosed() {
        guard case .compatible(let original) = SessionDomainNegotiator.negotiate(request(major: 1), id: NegotiationSnapshotID("snap-switch"), negotiatedAt: fixedDate) else {
            return XCTFail("expected compatible outcome")
        }
        let closed = original.applying(killSwitches: original.killSwitches.closing(.observe))
        XCTAssertFalse(closed.grants(WellKnownCapability.sessionObservation, direction: .observe))
        XCTAssertTrue(closed.capabilities.contains { $0.id == WellKnownCapability.sessionObservation && $0.availability == .disabled })
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: closed.id,
            integrationInstanceID: closed.integrationInstanceID,
            contractVersion: closed.contractVersion,
            productNamespace: closed.productNamespace.rawValue,
            nativeSessionID: "session",
            eventIdentity: .stable("event"),
            family: .sessionDeclared,
            sourceVariant: "fixture.sessionDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 10
        )
        guard case .rejected(.killSwitchClosed) = SessionDomainValidator.validate(envelope, negotiation: closed, receiptTime: fixedDate) else {
            return XCTFail("observation kill switch must fail closed")
        }
    }

    func testCrossOwnerAndStaleCapabilityAreRejected() {
        guard case .compatible(let snapshot) = SessionDomainNegotiator.negotiate(request(major: 1), id: NegotiationSnapshotID("snap-owner"), negotiatedAt: fixedDate) else {
            return XCTFail("expected compatible outcome")
        }
        let crossOwner = RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: IntegrationInstanceID("different"),
            contractVersion: snapshot.contractVersion,
            productNamespace: snapshot.productNamespace.rawValue,
            nativeSessionID: "session",
            eventIdentity: .stable("event-cross-owner"),
            family: .sessionDeclared,
            sourceVariant: "fixture.sessionDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 10
        )
        guard case .rejected(.crossOwnerProvenance) = SessionDomainValidator.validate(crossOwner, negotiation: snapshot, receiptTime: fixedDate) else {
            return XCTFail("cross-owner envelope must be rejected")
        }
        let stale = CapabilityRecord(id: WellKnownCapability.sessionAction, direction: .act, availability: .available, freshness: .stale, provenance: CapabilityProvenance(snapshotID: snapshot.id, integrationInstanceID: snapshot.integrationInstanceID, productNamespace: snapshot.productNamespace, integrationMode: snapshot.integrationMode))
        XCTAssertEqual(SessionDomainValidator.validateCapability(stale, in: snapshot), .failure(.staleCapability))
    }

    func testReadOnlyDiscoveryRejectsMutatingProbePlan() {
        let candidate = IntegrationDiscoveryCandidate(
            id: "candidate",
            product: ProductNamespace("claude-code"),
            availableModes: ["hooks"],
            probePlan: NonMutatingProbePlan(surfaces: ["bad"], mutatesExternal: true)
        )
        guard case .rejected(.mutatingProbePlan) = ReadOnlyAdapterDiscovery.discover(DiscoveryRequest(candidates: [candidate])) else {
            return XCTFail("mutating discovery probe must be rejected")
        }
    }
}
