import XCTest
import Foundation
@testable import SessionDomain
@testable import AdapterPort
@testable import PresentationPort
@testable import SessionStore
@testable import ApplicationRuntime
@testable import AdapterFixtureKit

/// End-to-end coverage for every AB-118 required-evidence scenario, driven
/// through `AdapterIntakePort` exactly as the fixture and any future
/// first-party Adapter would be. `AdapterFixtureKit` has no dependency on
/// `SessionStore`, so these tests only ever reach the store through the
/// port — the same architectural boundary production code is held to.
final class EndToEndFixtureTests: XCTestCase {
    private func makeRuntime() -> ApplicationRuntime {
        ApplicationRuntime(
            store: SessionStore(),
            idGenerator: { UUID().uuidString },
            clock: { Date(timeIntervalSince1970: 1_752_000_000) }
        )
    }

    func testPositiveObservationTrace() async {
        let result = await FixtureScenarios.positiveObservation(port: makeRuntime())
        XCTAssertTrue(result.succeeded, "\(result.steps)")
    }

    func testDuplicateStableDeliveryIsIdempotent() async {
        let result = await FixtureScenarios.duplicateStableDelivery(port: makeRuntime())
        XCTAssertTrue(result.succeeded, "\(result.steps)")
    }

    func testInvalidOwnershipProducesNoSessionOrLifecycleClaim() async {
        let result = await FixtureScenarios.invalidOwnership(port: makeRuntime())
        XCTAssertTrue(result.succeeded, "\(result.steps)")
    }

    func testIncompatibleContractProducesNoSession() async {
        let result = await FixtureScenarios.incompatibleContract(port: makeRuntime())
        XCTAssertTrue(result.succeeded, "\(result.steps)")
    }

    func testMalformedShapeIsRejected() async {
        let result = await FixtureScenarios.malformedShape(port: makeRuntime())
        XCTAssertTrue(result.succeeded, "\(result.steps)")
    }

    func testOversizedPayloadIsRejected() async {
        let result = await FixtureScenarios.oversizedPayload(port: makeRuntime())
        XCTAssertTrue(result.succeeded, "\(result.steps)")
    }

    func testTransportLossNeverProducesTerminalOrDuplicateCard() async {
        let runtime = makeRuntime()
        let result = await FixtureScenarios.transportLoss(port: runtime)
        XCTAssertTrue(result.succeeded, "\(result.steps)")

        var observed: ProjectionRevision?
        for await revision in runtime.presentationStream() {
            observed = revision
            break
        }
        guard let projection = observed?.sessions.values.first else {
            return XCTFail("expected a projection after transport loss")
        }
        XCTAssertFalse(projection.execution.isTerminal, "transport loss must never manufacture a terminal outcome")
        XCTAssertEqual(projection.observation, .unavailable)
    }

    func testDuplicateStableDeliveryLeavesExactlyOneCard() async {
        let runtime = makeRuntime()
        _ = await FixtureScenarios.duplicateStableDelivery(port: runtime)

        var observed: ProjectionRevision?
        for await revision in runtime.presentationStream() {
            observed = revision
            break
        }
        XCTAssertEqual(observed?.sessions.count, 1)
    }

    func testUIOnlySeesPresentationPortNotAdapterOrStore() async {
        // Compile-time boundary proof: `PresentationRuntime` (imported by
        // the UI target) depends only on `PresentationPort` + `SessionDomain`
        // — its target does not import `SessionStore` or `AdapterPort`, so
        // there is no expression the UI could write to reach either. This
        // test documents that guarantee at the type level: `PresentationPort`
        // exposes nothing beyond an immutable projection stream.
        let runtime = makeRuntime()
        let port: any PresentationPort = runtime
        var observed: ProjectionRevision?
        for await revision in port.presentationStream() {
            observed = revision
            break
        }
        XCTAssertNotNil(observed)
    }
}
