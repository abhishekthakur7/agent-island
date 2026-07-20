import XCTest
@testable import SessionDomain
@testable import SessionStore

final class ActionAttemptStoreTests: XCTestCase {
    private func evidence() -> GuidedAttentionEvidence {
        let snapshot = NegotiationSnapshotID("snapshot")
        let instance = IntegrationInstanceID("instance")
        let product = ProductNamespace("fixture")
        let owner = GuidedAttentionOwner(productNamespace: product, nativeSessionID: NativeSessionID("session"), nativeAttentionRequestID: "request", integrationInstanceID: instance, negotiationSnapshotID: snapshot)
        let provenance = CapabilityProvenance(snapshotID: snapshot, integrationInstanceID: instance, productNamespace: product, integrationMode: "hooks")
        let capability = CapabilityRecord(id: "attention.respond", direction: .act, availability: .available, scope: .request, provenance: provenance)
        return GuidedAttentionEvidence(owner: owner, eventIdentity: .stable("event"), sourceVariant: "question", capability: capability, semanticShape: .allowDeny, constraints: GuidedAttentionConstraints(nativeFingerprint: "fp"), sourceObservedAt: Date(timeIntervalSince1970: 1))
    }

    func testReservationCountsAtMostOneDispatchAndPreservesSnapshotAcrossRestart() async {
        let store = ActionAttemptStore()
        let request: GuidedAttentionRequest
        guard case .accepted(let accepted) = await store.ingest(evidence()) else { return XCTFail("request should be accepted") }
        request = accepted
        let capability = request.capability
        let binding = ActionLeaseBinding(requestID: request.id, owner: request.owner, capabilityID: capability.id, capabilityRevision: capability.revision, negotiationSnapshotID: request.owner.negotiationSnapshotID, semanticFingerprint: "allow", nativeFingerprint: "fp")
        let context = ActionLeaseValidationContext(binding: binding, capability: capability, currentNativeFingerprint: "fp", now: Date(timeIntervalSince1970: 10))
        guard case .issued = await store.issueLease(id: "lease", requestID: request.id, action: .allow, semanticFingerprint: "allow", nativeFingerprint: "fp", capability: capability, issuedAt: Date(timeIntervalSince1970: 9), deadline: Date(timeIntervalSince1970: 30)) else { return XCTFail("lease should issue") }
        guard case .reserved(let reserved) = await store.reserveAttempt(id: "attempt", requestID: request.id, owner: request.owner, action: .allow, leaseID: "lease", context: context, reservedAt: Date(timeIntervalSince1970: 10)) else { return XCTFail("attempt should reserve") }
        XCTAssertEqual(reserved.dispatchCount, 0)
        guard case .dispatch = await store.prepareDispatch(attemptID: "attempt", context: context, now: Date(timeIntervalSince1970: 10)) else { return XCTFail("dispatch should prepare") }
        guard case .rejected(let repeated) = await store.prepareDispatch(attemptID: "attempt", context: context, now: Date(timeIntervalSince1970: 10)) else { return XCTFail("repeat must reject") }
        XCTAssertEqual(repeated.dispatchCount, 1)
        _ = await store.recordProductOutcome(attemptID: "attempt", outcome: .indeterminate, at: Date(timeIntervalSince1970: 11))
        _ = await store.updateDraft(request.id, GuidedAttentionDraft(freeText: nil))
        let snapshot = await store.durableSnapshot()
        let reopened = ActionAttemptStore(snapshot: snapshot)
        let requests = await reopened.requests()
        let restoredAttempt = await reopened.attempt(for: "attempt")
        XCTAssertEqual(requests.first?.id, request.id)
        XCTAssertEqual(restoredAttempt?.outcome, .indeterminate)
        XCTAssertEqual(restoredAttempt?.dispatchCount, 1)
    }
}
