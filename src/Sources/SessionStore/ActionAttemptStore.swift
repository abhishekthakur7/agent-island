import Foundation
import SessionDomain

/// Durable local portion of the Guided workflow.  Requests, drafts, and
/// Action Attempts are snapshot-able; Action Leases are deliberately absent
/// from the snapshot and are recreated only after a fresh negotiation.
public struct ActionAttemptStoreSnapshot: Codable, Hashable, Sendable, Equatable {
    public let queue: GuidedAttentionQueue
    public let attempts: [ActionAttempt]

    public init(queue: GuidedAttentionQueue = GuidedAttentionQueue(), attempts: [ActionAttempt] = []) {
        self.queue = queue
        self.attempts = attempts
    }
}

public actor ActionAttemptStore {
    private var queue: GuidedAttentionQueue
    private var attemptsByID: [String: ActionAttempt]
    private let leaseAuthority: ActionLeaseAuthority

    public init(snapshot: ActionAttemptStoreSnapshot? = nil, leaseAuthority: ActionLeaseAuthority = ActionLeaseAuthority()) {
        self.leaseAuthority = leaseAuthority
        self.queue = snapshot?.queue ?? GuidedAttentionQueue()
        var restoredAttempts: [String: ActionAttempt] = [:]
        for attempt in snapshot?.attempts ?? [] {
            var restored = attempt
            // A process boundary cannot prove an in-flight Product dispatch.
            if restored.outcome == .dispatching {
                restored.outcome = .indeterminate
            }
            restoredAttempts[restored.id] = restored
        }
        self.attemptsByID = restoredAttempts
    }

    public func durableSnapshot() -> ActionAttemptStoreSnapshot {
        ActionAttemptStoreSnapshot(queue: queue, attempts: attemptsByID.values.sorted { $0.id < $1.id })
    }

    public func request(for id: GuidedAttentionRequestID) -> GuidedAttentionRequest? { queue.request(for: id) }
    public func requests() -> [GuidedAttentionRequest] { queue.requests }

    @discardableResult
    public func ingest(_ evidence: GuidedAttentionEvidence) -> GuidedAttentionIngestResult {
        queue.ingest(evidence)
    }

    @discardableResult
    public func updateDraft(_ id: GuidedAttentionRequestID, _ draft: GuidedAttentionDraft) -> Bool {
        queue.updateDraft(id, draft)
    }

    @discardableResult
    public func setStage(_ id: GuidedAttentionRequestID, _ stage: GuidedAttentionStage) -> Bool {
        queue.setStage(id, stage)
    }

    @discardableResult
    public func setLocalPresentation(_ id: GuidedAttentionRequestID, _ state: GuidedLocalPresentation) -> Bool {
        queue.setLocalPresentation(id, state)
    }

    /// Local acknowledgement only changes presentation state.  It does not
    /// mark the source request resolved and cannot manufacture Product truth.
    @discardableResult
    public func acknowledgeLocally(_ id: GuidedAttentionRequestID) -> Bool {
        queue.acknowledgeLocally(id)
    }

    @discardableResult
    public func updateSource(_ id: GuidedAttentionRequestID, outcome: GuidedSourceOutcome, fingerprint: String? = nil) async -> Bool {
        guard let current = queue.request(for: id) else { return false }
        if fingerprint.map({ $0 != current.lastSourceFingerprint }) ?? false {
            await leaseAuthority.invalidateForSourceChange()
        }
        return queue.updateSource(id, outcome: outcome, fingerprint: fingerprint)
    }

    public func issueLease(
        id: String,
        requestID: GuidedAttentionRequestID,
        action: GuidedAction,
        semanticFingerprint: String,
        nativeFingerprint: String,
        capability: CapabilityRecord,
        issuedAt: Date,
        deadline: Date,
        gateOpen: Bool = true,
        confirmation: Bool = true
    ) async -> ActionLeaseIssueResult {
        guard let request = queue.request(for: requestID) else { return .rejected(.unknownLease) }
        guard request.id == requestID else { return .rejected(.ownerMismatch) }
        guard case .success = action.validating(against: request, confirmation: confirmation) else { return .rejected(.sourceChanged) }
        let binding = ActionLeaseBinding(
            requestID: requestID,
            owner: request.owner,
            capabilityID: capability.id,
            capabilityRevision: capability.revision,
            negotiationSnapshotID: request.owner.negotiationSnapshotID,
            semanticFingerprint: semanticFingerprint,
            nativeFingerprint: nativeFingerprint
        )
        return await leaseAuthority.issue(id: id, binding: binding, capability: capability, sourceOutcome: request.sourceOutcome, gateOpen: gateOpen, issuedAt: issuedAt, deadline: deadline)
    }

    /// Reserves the durable Action Attempt before any Product call.  Every
    /// rejected validation still receives a durable record with zero typed
    /// dispatches, which makes duplicate activation auditable.
    public func reserveAttempt(
        id: String,
        requestID: GuidedAttentionRequestID,
        owner: GuidedAttentionOwner,
        action: GuidedAction,
        leaseID: String?,
        context: ActionLeaseValidationContext,
        confirmation: Bool = true,
        reservedAt: Date
    ) async -> ActionAttemptReservationResult {
        if let existing = attemptsByID[id] { return .duplicate(existing) }

        guard let request = queue.request(for: requestID) else {
            return .rejected(recordRejected(id: id, requestID: requestID, owner: owner, action: action, leaseID: leaseID, at: reservedAt, reason: .unknownRequest))
        }
        guard owner == request.owner else {
            return .rejected(recordRejected(id: id, requestID: requestID, owner: owner, action: action, leaseID: leaseID, at: reservedAt, reason: .ownerMismatch))
        }
        guard context.binding.requestID == requestID, context.binding.owner == owner else {
            return .rejected(recordRejected(id: id, requestID: requestID, owner: owner, action: action, leaseID: leaseID, at: reservedAt, reason: .ownerMismatch))
        }
        guard case .success = action.validating(against: request, confirmation: confirmation) else {
            let reason: ActionAttemptRejectionReason = confirmation ? .invalidSemanticResponse : .missingConfirmation
            return .rejected(recordRejected(id: id, requestID: requestID, owner: owner, action: action, leaseID: leaseID, at: reservedAt, reason: reason))
        }
        guard let leaseID else {
            return .rejected(recordRejected(id: id, requestID: requestID, owner: owner, action: action, leaseID: nil, at: reservedAt, reason: .staleLease))
        }
        switch await leaseAuthority.validate(leaseID, context: context) {
        case .valid:
            let attempt = ActionAttempt(id: id, requestID: requestID, owner: owner, action: action, leaseID: leaseID, reservedAt: reservedAt)
            attemptsByID[id] = attempt
            return .reserved(attempt)
        case .rejected(let failure):
            return .rejected(recordRejected(id: id, requestID: requestID, owner: owner, action: action, leaseID: leaseID, at: reservedAt, reason: Self.map(failure)))
        }
    }

    /// Performs the final pre-dispatch validation and consumes the lease.  A
    /// successful call is the only path that may produce one typed dispatch;
    /// repeat calls cannot increment `dispatchCount` again.
    public func prepareDispatch(
        attemptID: String,
        context: ActionLeaseValidationContext,
        now: Date,
        confirmation: Bool = true
    ) async -> ActionDispatchPreparation {
        guard var attempt = attemptsByID[attemptID] else { return .rejected(ActionAttempt(id: attemptID, requestID: context.binding.requestID, owner: context.binding.owner, action: .interruption, leaseID: nil, reservedAt: now, outcome: .rejected, rejectionReason: .unknownRequest)) }
        guard attempt.outcome == .reserved, attempt.dispatchCount == 0 else {
            attempt.outcome = .rejected
            attempt.rejectionReason = .alreadyDispatched
            attemptsByID[attemptID] = attempt
            return .rejected(attempt)
        }
        guard let request = queue.request(for: attempt.requestID) else {
            attempt.outcome = .rejected; attempt.rejectionReason = .unknownRequest; attemptsByID[attemptID] = attempt; return .rejected(attempt)
        }
        guard attempt.owner == request.owner, context.binding.owner == request.owner else {
            attempt.outcome = .rejected; attempt.rejectionReason = .ownerMismatch; attemptsByID[attemptID] = attempt; return .rejected(attempt)
        }
        guard case .success = attempt.action.validating(against: request, confirmation: confirmation) else {
            attempt.outcome = .rejected; attempt.rejectionReason = confirmation ? .invalidSemanticResponse : .missingConfirmation; attemptsByID[attemptID] = attempt; return .rejected(attempt)
        }
        guard let leaseID = attempt.leaseID else {
            attempt.outcome = .rejected; attempt.rejectionReason = .staleLease; attemptsByID[attemptID] = attempt; return .rejected(attempt)
        }
        switch await leaseAuthority.consume(leaseID, context: context) {
        case .valid:
            attempt.outcome = .dispatching
            attempt.dispatchCount = 1
            attemptsByID[attemptID] = attempt
            return .dispatch(attempt.action)
        case .rejected(let failure):
            attempt.outcome = .rejected
            attempt.rejectionReason = Self.map(failure)
            attemptsByID[attemptID] = attempt
            return .rejected(attempt)
        }
    }

    public func recordProductOutcome(
        attemptID: String,
        outcome: ActionProductOutcome,
        at date: Date,
        evidence: String? = nil
    ) -> ActionAttemptTransitionResult {
        guard var attempt = attemptsByID[attemptID] else { return .rejected(ActionAttempt(id: attemptID, requestID: GuidedAttentionRequestID(productNamespace: ProductNamespace("unknown"), nativeAttentionRequestID: "unknown"), owner: GuidedAttentionOwner(productNamespace: ProductNamespace("unknown"), nativeSessionID: NativeSessionID("unknown"), nativeAttentionRequestID: "unknown", integrationInstanceID: IntegrationInstanceID("unknown"), negotiationSnapshotID: NegotiationSnapshotID("unknown")), action: .interruption, leaseID: nil, reservedAt: date, outcome: .rejected, rejectionReason: .unknownRequest)) }
        guard attempt.outcome == .dispatching, attempt.dispatchCount == 1 else {
            attempt.outcome = .rejected; attempt.rejectionReason = .alreadyDispatched; attemptsByID[attemptID] = attempt; return .rejected(attempt)
        }
        attempt.outcome = switch outcome {
        case .rejected: .rejected
        case .acceptedByProduct: .acceptedByProduct
        case .applied: .applied
        case .superseded: .superseded
        case .indeterminate: .indeterminate
        }
        attempt.completedAt = date
        attempt.productEvidence = evidence.map { String($0.prefix(SessionDomainValidator.maxMetadataStringBytes)) }
        attemptsByID[attemptID] = attempt
        return .updated(attempt)
    }

    public func attempt(for id: String) -> ActionAttempt? { attemptsByID[id] }
    public func attempts() -> [ActionAttempt] { attemptsByID.values.sorted { $0.reservedAt < $1.reservedAt || ($0.reservedAt == $1.reservedAt && $0.id < $1.id) } }
    public func redactedDiagnostics() -> [RedactedActionAttemptDiagnostic] { attempts().map(RedactedActionAttemptDiagnostic.init) }

    public func invalidateForSourceChange() async { await invalidate(.sourceChanged, lease: { await self.leaseAuthority.invalidateForSourceChange() }) }
    public func invalidateForReconnect() async { await invalidate(.disconnected, lease: { await self.leaseAuthority.invalidateForReconnect() }) }
    public func invalidateForWake() async { await invalidate(.wake, lease: { await self.leaseAuthority.invalidateForWake() }) }
    public func invalidateForRestart() async { await invalidate(.restarted, lease: { await self.leaseAuthority.invalidateForRestart() }) }
    public func invalidateForCapabilityChange() async { await invalidate(.capabilityMismatch, lease: { await self.leaseAuthority.invalidateForCapabilityChange() }) }
    public func invalidateForGateChange() async { await invalidate(.gateClosed, lease: { await self.leaseAuthority.invalidateForGateChange() }) }

    public func restart() async { await invalidateForRestart() }
    public func reconnect() async { await invalidateForReconnect() }
    public func wake() async { await invalidateForWake() }

    private func invalidate(_ reason: ActionAttemptRejectionReason, lease: @escaping @Sendable () async -> Void) async {
        await lease()
        for id in attemptsByID.keys {
            guard var attempt = attemptsByID[id], attempt.outcome == .dispatching else { continue }
            attempt.outcome = .indeterminate
            attempt.rejectionReason = reason
            attemptsByID[id] = attempt
        }
    }

    private func recordRejected(id: String, requestID: GuidedAttentionRequestID, owner: GuidedAttentionOwner, action: GuidedAction, leaseID: String?, at date: Date, reason: ActionAttemptRejectionReason) -> ActionAttempt {
        let attempt = ActionAttempt(id: id, requestID: requestID, owner: owner, action: action, leaseID: leaseID, reservedAt: date, outcome: .rejected, rejectionReason: reason)
        attemptsByID[id] = attempt
        return attempt
    }

    private static func map(_ failure: ActionLeaseFailure) -> ActionAttemptRejectionReason {
        switch failure {
        case .unknownLease: .staleLease
        case .expired: .expiredLease
        case .consumed: .alreadyDispatched
        case .revoked, .sourceChanged: .sourceChanged
        case .requestMismatch, .ownerMismatch: .ownerMismatch
        case .capabilityMismatch: .capabilityMismatch
        case .capabilityUnavailable: .capabilityUnavailable
        case .sourceResolved: .sourceResolved
        case .gateClosed: .gateClosed
        case .restart: .restarted
        case .reconnect: .disconnected
        case .wake: .wake
        case .invalidDeadline: .expiredLease
        }
    }
}
