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
}
