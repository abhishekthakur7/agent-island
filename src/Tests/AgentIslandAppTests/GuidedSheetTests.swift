import XCTest
@testable import AgentIslandApp
@testable import SessionDomain

@MainActor
final class GuidedSheetTests: XCTestCase {
    private func request() -> GuidedAttentionRequest {
        let snapshot = NegotiationSnapshotID("snapshot")
        let instance = IntegrationInstanceID("instance")
        let product = ProductNamespace("fixture")
        let owner = GuidedAttentionOwner(productNamespace: product, nativeSessionID: NativeSessionID("session"), nativeAttentionRequestID: "request", integrationInstanceID: instance, negotiationSnapshotID: snapshot)
        let provenance = CapabilityProvenance(snapshotID: snapshot, integrationInstanceID: instance, productNamespace: product, integrationMode: "hooks")
        let capability = CapabilityRecord(id: "attention.respond", direction: .act, availability: .available, scope: .request, provenance: provenance)
        return GuidedAttentionRequest(evidence: GuidedAttentionEvidence(owner: owner, eventIdentity: .stable("event"), sourceVariant: "question", capability: capability, semanticShape: .structuredChoice([GuidedChoice(id: "one", label: "One", recommended: true)], minimumSelections: 1), constraints: GuidedAttentionConstraints(nativeFingerprint: "fp"), sourceObservedAt: Date(timeIntervalSince1970: 1)))
    }

    func testPriorityArrivalDoesNotStealSelectionOrFocusAndShortcutIsReversible() {
        let model = GuidedSheetModel(requests: [request()])
        model.setTextEntryFocused(false)
        model.select(model.requests[0].id)
        let selected = model.selectedRequestID
        model.handleNumberShortcut(1)
        XCTAssertEqual(model.selectedRequest?.draft.selectedChoiceIDs, ["one"])
        model.handleNumberShortcut(1)
        XCTAssertTrue(model.selectedRequest?.draft.selectedChoiceIDs.isEmpty == true)
        model.apply(requests: [request(), request()])
        XCTAssertEqual(model.selectedRequestID, selected)
    }
}

