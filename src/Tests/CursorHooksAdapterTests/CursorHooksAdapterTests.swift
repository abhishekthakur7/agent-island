import XCTest
@testable import CursorHooksAdapter
import SessionDomain

final class CursorHooksAdapterTests: XCTestCase {
    private let installation = IntegrationInstanceID("cursor-installation")
    private let scope = IntegrationInstallationScope(kind: .customPath, identifier: "selected", path: "/selected-only")

    func testPublicResearchResultIsExplicitlyUnavailableAndNeverInventsConfiguration() async {
        let adapter = CursorHooksAdapter(integrationInstanceID: installation)
        let request = await adapter.negotiationRequest()
        XCTAssertEqual(request.productNamespace, CursorHooksIntegration.productNamespace)
        XCTAssertEqual(request.compatibility, .unknown)
        XCTAssertEqual(request.requestedCapabilityRecords?.first?.availability, .unavailable)
        XCTAssertEqual(request.requestedCapabilityRecords?.first?.direction, .observe)
        XCTAssertFalse(CursorHooksIntegration.capabilityProvenance.isEmpty)

        let coordinator = CursorHooksInstallationCoordinator()
        let discovery = coordinator.discover(installationID: installation, scope: scope)
        XCTAssertEqual(discovery.state, .unsupported)
        XCTAssertFalse(discovery.safeToMutate)
        XCTAssertEqual(discovery.inspection.source.path, "")
        XCTAssertTrue(discovery.inspection.source.content == nil)
        XCTAssertNil(coordinator.apply().manifest)
        XCTAssertEqual(coordinator.apply().status, .unavailable)
        XCTAssertEqual(coordinator.disable().status, .unavailable)
        XCTAssertEqual(coordinator.repair().status, .unavailable)
        XCTAssertEqual(coordinator.remove().status, .unavailable)
        XCTAssertEqual(coordinator.verify().status, .unavailable)
    }

    func testMalformedOversizedFailureTimeoutAndTransportAreInspectableButFailOpen() async {
        let adapter = CursorHooksAdapter(integrationInstanceID: installation)
        guard case .degraded(let malformed) = await adapter.receive(Data("not-json".utf8)) else { return XCTFail("malformed input must not be accepted") }
        XCTAssertEqual(malformed.reason, .malformedEnvelope)
        guard case .degraded(let oversized) = await adapter.receive(Data(repeating: 0x20, count: CursorHookEnvelope.maximumBytes + 1)) else { return XCTFail("oversized input must not be accepted") }
        XCTAssertEqual(oversized.reason, .oversizedEnvelope)
        XCTAssertEqual(CursorHookDiagnostic(.timeout).redactedDescription, "cursor-hooks:timeout")
        XCTAssertEqual(CursorHookDiagnostic(.transportFailure).redactedDescription, "cursor-hooks:transportFailure")
    }

    func testAllJSONIncludingSameLookingConcurrentSessionsIsDiscardedUntilContractExists() async {
        let adapter = CursorHooksAdapter(integrationInstanceID: installation)
        let first = Data("{\"conversation_id\":\"private-a\",\"generation_id\":\"turn\",\"title\":\"same\",\"workspace\":\"/private\",\"model\":\"same\",\"user_email\":\"private@example.test\",\"transcript_path\":\"/private/transcript\"}".utf8)
        let second = Data("{\"conversation_id\":\"private-b\",\"generation_id\":\"turn\",\"title\":\"same\",\"workspace\":\"/private\",\"model\":\"same\"}".utf8)
        guard case .unavailable(let one) = await adapter.receive(first), case .unavailable(let two) = await adapter.receive(second) else { return XCTFail("uncontracted data must not project") }
        XCTAssertEqual(one.reason, .unsupportedContract)
        XCTAssertEqual(two.reason, .unsupportedContract)
        XCTAssertFalse(one.redactedDescription.contains("private"))
        XCTAssertFalse(two.redactedDescription.contains("private"))
    }

    func testProtectedIdentityCannotUseMetadataAndHasNoDiagnosticSurface() {
        let a = CursorProtectedIdentity(conversationID: "one", generationID: "generation")
        let b = CursorProtectedIdentity(conversationID: "two", generationID: "generation")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(Mirror(reflecting: a).displayStyle, .struct)
        XCTAssertFalse(String(reflecting: CursorHookDiagnostic(.deliveryGap)).contains("one"))
    }

    func testAttentionAndJumpBackAreHonestAndThereIsNoActionDispatch() {
        let presentation = CursorAttentionPresentation()
        XCTAssertEqual(presentation.dispatchCount, 0)
        XCTAssertTrue(presentation.availability.contains("Cursor"))
        XCTAssertTrue(presentation.jumpBackLevel.contains("App-only"))
        XCTAssertTrue(presentation.jumpBackLevel.contains("no documented live locator"))
    }

    func testAmbiguityCollisionGapAndUnprovenChildStopRemainNonMutatingDiagnostics() {
        for reason in [CursorHookRejection.ambiguousOwnership, .duplicateOrCollision, .deliveryGap, .unresolvedSubagentStop] {
            let diagnostic = CursorHookDiagnostic(reason)
            XCTAssertTrue(diagnostic.redactedDescription.hasPrefix("cursor-hooks:"))
            XCTAssertFalse(diagnostic.redactedDescription.contains("conversation"))
        }
    }
}
