import XCTest
@testable import SessionDomain

final class ActionLeaseTests: XCTestCase {
    private func fixture() -> (GuidedAttentionRequest, CapabilityRecord, ActionLeaseBinding) {
        let snapshot = NegotiationSnapshotID("snapshot")
        let instance = IntegrationInstanceID("instance")
        let product = ProductNamespace("fixture")
        let owner = GuidedAttentionOwner(productNamespace: product, nativeSessionID: NativeSessionID("session"), nativeAttentionRequestID: "request", integrationInstanceID: instance, negotiationSnapshotID: snapshot)
        let provenance = CapabilityProvenance(snapshotID: snapshot, integrationInstanceID: instance, productNamespace: product, integrationMode: "hooks")
        let capability = CapabilityRecord(id: "attention.respond", direction: .act, availability: .available, scope: .request, provenance: provenance)
        let evidence = GuidedAttentionEvidence(owner: owner, eventIdentity: .stable("event"), sourceVariant: "question", capability: capability, semanticShape: .allowDeny, constraints: GuidedAttentionConstraints(nativeFingerprint: "fp"), sourceObservedAt: Date(timeIntervalSince1970: 1))
        let request = GuidedAttentionRequest(evidence: evidence)
        let binding = ActionLeaseBinding(requestID: request.id, owner: owner, capabilityID: capability.id, capabilityRevision: capability.revision, negotiationSnapshotID: snapshot, semanticFingerprint: "allow", nativeFingerprint: "fp")
        return (request, capability, binding)
    }

    func testExpiryMismatchAndSingleUse() async {
        let (_, capability, binding) = fixture()
        let authority = ActionLeaseAuthority()
        let start = Date(timeIntervalSince1970: 100)
        guard case .issued = await authority.issue(id: "lease", binding: binding, capability: capability, issuedAt: start, deadline: start.addingTimeInterval(5)) else { return XCTFail("lease should issue") }
        let context = ActionLeaseValidationContext(binding: binding, capability: capability, currentNativeFingerprint: "fp", now: start.addingTimeInterval(1))
        let consumed = await authority.consume("lease", context: context)
        XCTAssertEqual(consumed, .valid)
        let repeated = await authority.consume("lease", context: context)
        XCTAssertEqual(repeated, .rejected(.consumed))

        guard case .issued = await authority.issue(id: "lease-2", binding: binding, capability: capability, issuedAt: start, deadline: start.addingTimeInterval(5)) else { return XCTFail("second lease should issue") }
        let expired = ActionLeaseValidationContext(binding: binding, capability: capability, currentNativeFingerprint: "fp", now: start.addingTimeInterval(6))
        let expiredResult = await authority.validate("lease-2", context: expired)
        XCTAssertEqual(expiredResult, .rejected(.expired))
        let mismatch = ActionLeaseValidationContext(binding: binding, capability: capability, currentNativeFingerprint: "new-fingerprint", now: start.addingTimeInterval(1))
        let mismatchResult = await authority.validate("lease-2", context: mismatch)
        XCTAssertEqual(mismatchResult, .rejected(.expired))
    }

    func testRestartReconnectAndWakeRevokeWithoutPersistence() async {
        let (_, capability, binding) = fixture()
        let authority = ActionLeaseAuthority()
        let start = Date(timeIntervalSince1970: 100)
        _ = await authority.issue(id: "lease", binding: binding, capability: capability, issuedAt: start, deadline: start.addingTimeInterval(30))
        await authority.invalidateForRestart()
        let context = ActionLeaseValidationContext(binding: binding, capability: capability, currentNativeFingerprint: "fp", now: start.addingTimeInterval(1))
        let restartResult = await authority.validate("lease", context: context)
        XCTAssertEqual(restartResult, .rejected(.restart))
        let live = await authority.liveLeaseCount()
        XCTAssertEqual(live, 0)
    }
}
