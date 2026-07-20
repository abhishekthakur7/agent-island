import XCTest
@testable import SessionDomain

final class GuidedAttentionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10_000)

    private func evidence(
        session: String = "session-1",
        request: String = "request-1",
        event: String = "event-1",
        priority: AttentionPriority = .normal,
        shape: GuidedSemanticShape = .allowDeny
    ) -> GuidedAttentionEvidence {
        let snapshot = NegotiationSnapshotID("snapshot-1")
        let instance = IntegrationInstanceID("instance-1")
        let product = ProductNamespace("fixture")
        let owner = GuidedAttentionOwner(productNamespace: product, nativeSessionID: NativeSessionID(session), nativeAttentionRequestID: request, integrationInstanceID: instance, negotiationSnapshotID: snapshot)
        let provenance = CapabilityProvenance(snapshotID: snapshot, integrationInstanceID: instance, productNamespace: product, integrationMode: "hooks")
        let capability = CapabilityRecord(id: "attention.respond", direction: .act, availability: .available, scope: .request, provenance: provenance)
        return GuidedAttentionEvidence(owner: owner, eventIdentity: .stable(event), sourceVariant: "fixture.question", capability: capability, semanticShape: shape, constraints: GuidedAttentionConstraints(nativeFingerprint: "native-v1"), sourceObservedAt: date, priority: priority, displayTitle: "Question", hostLabel: "Terminal")
    }

    func testStableOwnerIdentityRejectsMissingAndCrossOwnerEvidence() {
        var queue = GuidedAttentionQueue()
        let first = evidence()
        guard case .accepted = queue.ingest(first) else { return XCTFail("expected accepted evidence") }
        guard case .duplicate = queue.ingest(first) else { return XCTFail("expected exact duplicate") }

        let crossOwner = evidence(session: "session-2", request: "request-2", event: "event-1")
        guard case .rejected(.crossOwnerEventIdentity) = queue.ingest(crossOwner) else { return XCTFail("must reject cross-owner event identity") }

        let weak = GuidedAttentionEvidence(owner: first.owner, eventIdentity: .weak("weak"), sourceVariant: first.sourceVariant, capability: first.capability, semanticShape: first.semanticShape, constraints: first.constraints, sourceObservedAt: date)
        guard case .rejected(.missingStableEventIdentity) = queue.ingest(weak) else { return XCTFail("must reject weak native evidence") }
    }

    func testPriorityQueueIsStableAndRecommendedChoiceHasNoDefault() {
        var queue = GuidedAttentionQueue()
        let low = evidence(request: "low", event: "low-event", priority: .low)
        let urgent = evidence(request: "urgent", event: "urgent-event", priority: .urgent)
        _ = queue.ingest(low)
        _ = queue.ingest(urgent)
        XCTAssertEqual(queue.requests.map(\.priority), [.urgent, .low])

        let shape = GuidedSemanticShape.structuredChoice([GuidedChoice(id: "yes", label: "Yes", recommended: true)], minimumSelections: 1)
        let request = GuidedAttentionRequest(evidence: evidence(request: "choice", event: "choice-event", shape: shape))
        XCTAssertTrue(request.draft.selectedChoiceIDs.isEmpty)
        XCTAssertEqual(request.stage, .arrived)
    }

    func testDraftSelectionIsReversibleAndValidityGatesNextAction() {
        let shape = GuidedSemanticShape.structuredChoice([
            GuidedChoice(id: "one", label: "One"),
            GuidedChoice(id: "two", label: "Two")
        ], allowsMultipleSelection: false, minimumSelections: 1)
        let request = GuidedAttentionRequest(evidence: evidence(shape: shape))
        XCTAssertEqual(GuidedAttentionDraft.empty.validating(against: shape), .failure(.incompleteResponse))
        XCTAssertEqual(GuidedAttentionDraft(selectedChoiceIDs: ["one"]).validating(against: shape), .success(()))
        XCTAssertEqual(GuidedAttentionDraft(selectedChoiceIDs: ["missing"]).validating(against: shape), .failure(.invalidSelection))
        XCTAssertEqual(request.sourceOutcome, .pending)
    }
}

