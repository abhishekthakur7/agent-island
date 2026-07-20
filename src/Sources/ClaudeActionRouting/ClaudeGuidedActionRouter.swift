import Foundation
import ClaudeCodeAdapter
import SessionDomain
import SessionStore

/// Explicit UI intent. `persistentScopeConfirmation` must repeat the exact
/// Product-offered scope; it is a second gesture, not a remembered setting.
public struct ClaudeActionSubmission: Sendable {
    public let action: GuidedAction
    public let deliberateConfirmation: Bool
    public let persistentScopeConfirmation: String?

    public init(action: GuidedAction, deliberateConfirmation: Bool, persistentScopeConfirmation: String? = nil) {
        self.action = action; self.deliberateConfirmation = deliberateConfirmation; self.persistentScopeConfirmation = persistentScopeConfirmation
    }
}

public enum ClaudeActionRoutingResult: Sendable, Equatable {
    case dispatched(ClaudeTypedHookResponse, ActionAttempt)
    case rejected(ActionAttempt?, ClaudeLiveActionRejection)
}

/// The composition-side bridge between the durable Guided ledger and one
/// synchronous Claude callback.  The Claude adapter remains store-free; only
/// this local action coordinator has both a protected callback and the local
/// durable Action Attempt store.
public actor ClaudeGuidedActionRouter {
    private enum CallbackState { case open, reserving, consumed }
    private struct LiveCallback { var callback: ClaudeLiveCallback; var state: CallbackState }

    private let store: ActionAttemptStore
    private var live: [UUID: LiveCallback] = [:]
    private var identityOwners: [CallbackOwnerKey: UUID] = [:]

    public init(store: ActionAttemptStore) { self.store = store }

    /// Creates exactly one durable Attention Request while the native callback
    /// remains live. Reusing an otherwise identical callback is rejected by
    /// nonce/identity, never by prompt or tool text.
    public func open(_ callback: ClaudeLiveCallback, at now: Date) async -> Result<GuidedAttentionRequest, ClaudeLiveActionRejection> {
        guard callback.isWellFormed else { return .failure(.malformedCallback) }
        guard now <= callback.deadline else { return .failure(.expired) }
        guard callback.capability.availability == .available, callback.capability.freshness == .current else { return .failure(.capabilityUnavailable) }
        let key = CallbackOwnerKey(callback.identity)
        guard live[callback.identity.nonce] == nil, identityOwners[key] == nil else { return .failure(.duplicateCallback) }
        let evidence = GuidedAttentionEvidence(
            owner: callback.owner,
            eventIdentity: .stable("claude-live:" + callback.identity.nonce.uuidString),
            sourceVariant: "claude.live." + callback.identity.hook.rawValue,
            capability: callback.capability,
            semanticShape: callback.semanticShape,
            constraints: GuidedAttentionConstraints(requiresConfirmation: true, nativeFingerprint: callback.identity.callbackInputFingerprint),
            sourceObservedAt: now,
            displayTitle: title(for: callback.semantic),
            hostLabel: "Claude Code"
        )
        switch await store.ingest(evidence) {
        case .accepted(let request), .duplicate(let request):
            live[callback.identity.nonce] = LiveCallback(callback: callback, state: .open)
            identityOwners[key] = callback.identity.nonce
            return .success(request)
        case .rejected:
            return .failure(.malformedCallback)
        }
    }

    /// Atomically reserves an Action Attempt, consumes the exact live lease,
    /// and produces one typed native response. A second click/shortcut sees a
    /// consumed callback before it can enter the store again.
    public func submit(
        callbackIdentity: ClaudeLiveCallbackIdentity,
        submission: ClaudeActionSubmission,
        attemptID: String,
        at now: Date
    ) async -> ClaudeActionRoutingResult {
        guard var liveCallback = live[callbackIdentity.nonce], liveCallback.callback.identity == callbackIdentity else {
            return .rejected(nil, .staleCallback)
        }
        guard liveCallback.state == .open else { return .rejected(nil, .duplicateCallback) }
        guard now <= liveCallback.callback.deadline else {
            live.removeValue(forKey: callbackIdentity.nonce); identityOwners.removeValue(forKey: CallbackOwnerKey(callbackIdentity))
            await store.invalidateForSourceChange()
            return .rejected(nil, .expired)
        }
        guard submission.deliberateConfirmation else {
            let attempt = await store.recordRejectedAttempt(id: attemptID, requestID: liveCallback.callback.requestID, owner: liveCallback.callback.owner, action: submission.action, at: now, reason: .missingConfirmation)
            return .rejected(attempt, .missingConfirmation)
        }
        guard validate(submission, for: liveCallback.callback) else {
            let attempt = await store.recordRejectedAttempt(id: attemptID, requestID: liveCallback.callback.requestID, owner: liveCallback.callback.owner, action: submission.action, at: now, reason: .invalidSemanticResponse)
            return .rejected(attempt, .invalidAnswer)
        }

        // Set the volatile gate before awaiting another actor; this is the
        // critical double-click/shortcut-repeat boundary.
        liveCallback.state = .reserving
        live[callbackIdentity.nonce] = liveCallback
        let callback = liveCallback.callback
        let binding = ActionLeaseBinding(
            requestID: callback.requestID,
            owner: callback.owner,
            capabilityID: callback.capability.id,
            capabilityRevision: callback.capability.revision,
            negotiationSnapshotID: callback.owner.negotiationSnapshotID,
            semanticFingerprint: semanticFingerprint(submission.action),
            nativeFingerprint: callback.identity.callbackInputFingerprint
        )
        let context = ActionLeaseValidationContext(binding: binding, capability: callback.capability, currentNativeFingerprint: callback.identity.callbackInputFingerprint, now: now)
        let leaseID = "claude-live-" + callbackIdentity.nonce.uuidString + "-" + attemptID
        guard case .issued = await store.issueLease(id: leaseID, requestID: callback.requestID, action: submission.action, semanticFingerprint: binding.semanticFingerprint, nativeFingerprint: binding.nativeFingerprint, capability: callback.capability, issuedAt: now, deadline: callback.deadline, confirmation: true) else {
            live[callbackIdentity.nonce]?.state = .open
            return .rejected(nil, .capabilityUnavailable)
        }
        let reservation = await store.reserveAttempt(id: attemptID, requestID: callback.requestID, owner: callback.owner, action: submission.action, leaseID: leaseID, context: context, confirmation: true, reservedAt: now)
        guard case .reserved = reservation else {
            live[callbackIdentity.nonce]?.state = .open
            let attempt = reservation.attempt
            return .rejected(attempt, .invalidAnswer)
        }
        guard case .dispatch = await store.prepareDispatch(attemptID: attemptID, context: context, now: now, confirmation: true) else {
            live[callbackIdentity.nonce]?.state = .consumed
            let attempt = await store.attempt(for: attemptID)
            return .rejected(attempt, .staleCallback)
        }
        guard let response = encode(submission.action, callback: callback) else {
            _ = await store.recordProductOutcome(attemptID: attemptID, outcome: .rejected, at: now)
            live[callbackIdentity.nonce]?.state = .consumed
            return .rejected(await store.attempt(for: attemptID), .invalidAnswer)
        }
        // Handoff to the helper is the only Product acknowledgement we can
        // prove synchronously. It is not a claim that Claude applied it.
        let updated: ActionAttempt
        switch await store.recordProductOutcome(attemptID: attemptID, outcome: .acceptedByProduct, at: now) {
        case .updated(let attempt): updated = attempt
        case .rejected(let attempt): return .rejected(attempt, .staleCallback)
        }
        live[callbackIdentity.nonce]?.state = .consumed
        live.removeValue(forKey: callbackIdentity.nonce)
        identityOwners.removeValue(forKey: CallbackOwnerKey(callbackIdentity))
        return .dispatched(response, updated)
    }

    /// Called for native resolution, helper loss, timeout, restart, wake,
    /// reconnect, and capability changes. No stale callback is recreated.
    public func retireAll(reason: ClaudeLiveActionRejection) async {
        live.removeAll(); identityOwners.removeAll()
        switch reason {
        case .helperUnavailable: await store.invalidateForReconnect()
        case .capabilityUnavailable: await store.invalidateForCapabilityChange()
        case .expired, .staleCallback, .sourceResolved: await store.invalidateForSourceChange()
        default: await store.invalidateForGateChange()
        }
    }

    public func resolvedElsewhere(_ callbackIdentity: ClaudeLiveCallbackIdentity) async {
        guard let liveCallback = live.removeValue(forKey: callbackIdentity.nonce), liveCallback.callback.identity == callbackIdentity else { return }
        identityOwners.removeValue(forKey: CallbackOwnerKey(callbackIdentity))
        _ = await store.updateSource(liveCallback.callback.requestID, outcome: .resolvedElsewhere)
    }

    public func recordApplied(attemptID: String, at now: Date) async { _ = await store.recordProductOutcome(attemptID: attemptID, outcome: .applied, at: now) }
    public func recordSuperseded(attemptID: String, at now: Date) async { _ = await store.recordProductOutcome(attemptID: attemptID, outcome: .superseded, at: now) }
    public func recordIndeterminate(attemptID: String, at now: Date) async { _ = await store.recordProductOutcome(attemptID: attemptID, outcome: .indeterminate, at: now) }

    private func validate(_ submission: ClaudeActionSubmission, for callback: ClaudeLiveCallback) -> Bool {
        switch callback.semantic {
        case .permission:
            return submission.action == .allow || submission.action == .deny
        case .permissionSuggestion:
            return submission.action == .persistentSuggestion(allow: true) && submission.persistentScopeConfirmation == callback.offeredSuggestion?.persistenceScope
        case .questionAnswers:
            guard case .structuredResponse(let answer) = submission.action,
                  case .success = GuidedAttentionDraft(selectedChoiceIDs: answer.selectedChoiceIDs, freeText: answer.freeText).validating(against: callback.semanticShape) else { return false }
            let selected = Set(answer.selectedChoiceIDs)
            return callback.questionGroups.allSatisfy { group in
                let count = group.choiceIDs.filter(selected.contains).count
                return group.allowsMultiple ? count >= 1 : count == 1
            }
        case .planApproval:
            return submission.action == .planReview(.accept, reason: nil)
        }
    }

    private func encode(_ action: GuidedAction, callback: ClaudeLiveCallback) -> ClaudeTypedHookResponse? {
        switch (callback.semantic, action) {
        case (.permission, .allow): return .permission(.allow, exactSuggestionJSON: nil)
        case (.permission, .deny): return .permission(.deny, exactSuggestionJSON: nil)
        case (.permissionSuggestion, .persistentSuggestion): return callback.offeredSuggestion.map { .permission(.allow, exactSuggestionJSON: $0.exactNativeJSON) }
        case (.questionAnswers, .structuredResponse), (.planApproval, .planReview): return .preToolAllow(updatedInput: callback.nativeInput)
        default: return nil
        }
    }

    private func semanticFingerprint(_ action: GuidedAction) -> String {
        switch action {
        case .allow: "allow"; case .deny: "deny"; case .persistentSuggestion: "persistent"; case .structuredResponse: "answers"; case .planReview: "plan-approval"
        case .turnInput, .interruption, .productExtension: "unsupported"
        }
    }

    private func title(for semantic: ClaudeLiveActionSemantic) -> String {
        switch semantic { case .permission: "Claude permission"; case .permissionSuggestion: "Claude persistent permission"; case .questionAnswers: "Claude question"; case .planApproval: "Claude plan approval" }
    }
}

private struct CallbackOwnerKey: Hashable {
    let session: NativeSessionID; let prompt: String?; let hook: ClaudeHookName; let toolUse: String?; let fingerprint: String
    init(_ identity: ClaudeLiveCallbackIdentity) { session = identity.nativeSessionID; prompt = identity.promptID; hook = identity.hook; toolUse = identity.toolUseID; fingerprint = identity.callbackInputFingerprint }
}

private extension ActionAttemptReservationResult {
    var attempt: ActionAttempt? { switch self { case .reserved(let value), .rejected(let value), .duplicate(let value): value } }
}
