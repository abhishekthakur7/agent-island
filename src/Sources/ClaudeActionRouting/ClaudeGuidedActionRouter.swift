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
    /// Volatile input state supplied by the presentation that owns the text
    /// editor. This is deliberately state, never inferred from text content.
    public let textCompositionActive: Bool

    public init(action: GuidedAction, deliberateConfirmation: Bool, persistentScopeConfirmation: String? = nil, textCompositionActive: Bool = false) {
        self.action = action; self.deliberateConfirmation = deliberateConfirmation; self.persistentScopeConfirmation = persistentScopeConfirmation; self.textCompositionActive = textCompositionActive
    }
}

public enum ClaudeActionRoutingResult: Sendable, Equatable {
    case dispatched(ClaudeTypedHookResponse, ActionAttempt)
    case rejected(ActionAttempt?, ClaudeLiveActionRejection)
}

/// The only composition boundary permitted to hand a response back to the
/// still-blocked Claude hook.  It deliberately reports delivery evidence,
/// rather than treating construction of `ClaudeTypedHookResponse` as delivery.
public struct ClaudeActionDispatchRequest: Sendable {
    public let callback: ClaudeLiveCallback
    public let response: ClaudeTypedHookResponse
    public let attemptID: String

    public init(callback: ClaudeLiveCallback, response: ClaudeTypedHookResponse, attemptID: String) {
        self.callback = callback; self.response = response; self.attemptID = attemptID
    }
}

public enum ClaudeActionDispatchOutcome: Sendable, Equatable {
    /// No byte was handed to the helper/Product.  This is a zero-dispatch
    /// rejection, not an ambiguous Product outcome.
    case rejectedBeforeDispatch
    /// The authenticated helper explicitly accepted the exact callback tuple.
    case acceptedByProduct
    /// A documented Product application acknowledgement was received.
    case applied
    /// The Product reported the request had already resolved elsewhere.
    case superseded
    /// The send may have occurred but its result cannot be proven. Never retry.
    case indeterminate
}

public protocol ClaudeActionDispatchPort: Sendable {
    func dispatch(_ request: ClaudeActionDispatchRequest, at: Date) async -> ClaudeActionDispatchOutcome
}

/// Dispatch-time evidence is intentionally separate from callback creation:
/// a wake, reconnect, capability update, or helper reincarnation can fail it.
public protocol ClaudeLiveActionValidationPort: Sendable {
    func validate(_ callback: ClaudeLiveCallback, at: Date) async -> Bool
}

public struct ClaudeStaticLiveActionValidationPort: ClaudeLiveActionValidationPort {
    public init() {}
    public func validate(_ callback: ClaudeLiveCallback, at now: Date) async -> Bool {
        callback.isWellFormed && now <= callback.deadline &&
        callback.capability.availability == .available && callback.capability.freshness == .current
    }
}

/// Safe default for composition that has not installed the helper callback
/// bridge. It makes that absence explicit instead of fabricating acceptance.
public struct ClaudeUnavailableActionDispatchPort: ClaudeActionDispatchPort {
    public init() {}
    public func dispatch(_ request: ClaudeActionDispatchRequest, at: Date) async -> ClaudeActionDispatchOutcome { .rejectedBeforeDispatch }
}

/// The composition-side bridge between the durable Guided ledger and one
/// synchronous Claude callback.  The Claude adapter remains store-free; only
/// this local action coordinator has both a protected callback and the local
/// durable Action Attempt store.
public actor ClaudeGuidedActionRouter {
    private enum CallbackState { case open, reserving, consumed }
    private struct LiveCallback { var callback: ClaudeLiveCallback; var state: CallbackState }

    private let store: ActionAttemptStore
    private let dispatchPort: any ClaudeActionDispatchPort
    private let validationPort: any ClaudeLiveActionValidationPort
    private var live: [UUID: LiveCallback] = [:]
    private var identityOwners: [CallbackOwnerKey: UUID] = [:]

    public init(store: ActionAttemptStore, dispatchPort: any ClaudeActionDispatchPort = ClaudeUnavailableActionDispatchPort(), validationPort: any ClaudeLiveActionValidationPort = ClaudeStaticLiveActionValidationPort()) {
        self.store = store; self.dispatchPort = dispatchPort; self.validationPort = validationPort
    }

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
        guard var liveCallback = live[callbackIdentity.nonce] else {
            return .rejected(nil, .staleCallback)
        }
        guard liveCallback.callback.identity == callbackIdentity else {
            let attempt = await rejectKnown(liveCallback.callback, attemptID: attemptID, action: submission.action, at: now, reason: .ownerMismatch)
            return .rejected(attempt, .ownerMismatch)
        }
        guard liveCallback.state == .open else { return .rejected(nil, .duplicateCallback) }
        guard now <= liveCallback.callback.deadline else {
            let attempt = await rejectKnown(liveCallback.callback, attemptID: attemptID, action: submission.action, at: now, reason: .expiredLease)
            live.removeValue(forKey: callbackIdentity.nonce); identityOwners.removeValue(forKey: CallbackOwnerKey(callbackIdentity))
            await store.invalidateForSourceChange()
            return .rejected(attempt, .expired)
        }
        guard submission.deliberateConfirmation else {
            let attempt = await store.recordRejectedAttempt(id: attemptID, requestID: liveCallback.callback.requestID, owner: liveCallback.callback.owner, action: submission.action, at: now, reason: .missingConfirmation)
            return .rejected(attempt, .missingConfirmation)
        }
        // IME/text composition is live presentation state.  Answer and plan
        // mappings can change native input, so they must wait until the
        // caller reports composition ended. The rejected attempt retains no
        // text payload beyond the typed action's existing redacted shape.
        guard !(submission.textCompositionActive && requiresCompositionToBeIdle(liveCallback.callback.semantic)) else {
            let attempt = await store.recordRejectedAttempt(id: attemptID, requestID: liveCallback.callback.requestID, owner: liveCallback.callback.owner, action: submission.action, at: now, reason: .textCompositionActive)
            return .rejected(attempt, .invalidAnswer)
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
            let attempt = await rejectKnown(callback, attemptID: attemptID, action: submission.action, at: now, reason: .capabilityUnavailable)
            return .rejected(attempt, .capabilityUnavailable)
        }
        let reservation = await store.reserveAttempt(id: attemptID, requestID: callback.requestID, owner: callback.owner, action: submission.action, leaseID: leaseID, context: context, confirmation: true, reservedAt: now)
        guard case .reserved = reservation else {
            live[callbackIdentity.nonce]?.state = .open
            let attempt = reservation.attempt
            return .rejected(attempt, .invalidAnswer)
        }
        // Re-check current authority immediately before consuming the lease;
        // callback construction evidence is not authorization at dispatch time.
        guard await validationPort.validate(callback, at: now) else {
            let attempt = await store.rejectReservedAttempt(id: attemptID, at: now, reason: .capabilityUnavailable)
            live[callbackIdentity.nonce]?.state = .consumed
            return .rejected(attempt, .capabilityUnavailable)
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
        // The lease was consumed before this await. This is the one and only
        // handoff; ambiguous delivery is terminal and is never retried.
        let delivery = await dispatchPort.dispatch(ClaudeActionDispatchRequest(callback: callback, response: response, attemptID: attemptID), at: now)
        let productOutcome: ActionProductOutcome = switch delivery {
        case .rejectedBeforeDispatch: .rejected
        case .acceptedByProduct: .acceptedByProduct
        case .applied: .applied
        case .superseded: .superseded
        case .indeterminate: .indeterminate
        }
        let transition = await store.recordProductOutcome(attemptID: attemptID, outcome: productOutcome, at: now)
        let updated = transition.attempt
        live[callbackIdentity.nonce]?.state = .consumed
        live.removeValue(forKey: callbackIdentity.nonce)
        identityOwners.removeValue(forKey: CallbackOwnerKey(callbackIdentity))
        if delivery == .rejectedBeforeDispatch { return .rejected(updated, .helperUnavailable) }
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
        case (.permission, .allow): return .permission(.allow, suggestionJSON: nil)
        case (.permission, .deny): return .permission(.deny, suggestionJSON: nil)
        case (.permissionSuggestion, .persistentSuggestion): return callback.offeredSuggestion.map { .permission(.allow, suggestionJSON: $0.canonicalNativeJSON) }
        case (.questionAnswers, .structuredResponse(let answer)):
            return updatedQuestionInput(callback: callback, selectedIDs: answer.selectedChoiceIDs)
        case (.planApproval, .planReview):
            return updatedPlanInput(callback: callback)
        default: return nil
        }
    }

    private func updatedQuestionInput(callback: ClaudeLiveCallback, selectedIDs: [String]) -> ClaudeTypedHookResponse? {
        guard selectedIDs.count == Set(selectedIDs).count,
              let root = try? JSONSerialization.jsonObject(with: callback.nativeInput) as? [String: Any] else { return nil }
        var output = root
        let usesToolInput = root["tool_input"] != nil || root["toolInput"] != nil
        let key = root["tool_input"] != nil ? "tool_input" : "toolInput"
        let candidate = (usesToolInput ? root[key] : root) as? [String: Any]
        guard var input = candidate, var questions = input["questions"] as? [[String: Any]], questions.count == callback.questionGroups.count else { return nil }
        let selected = Set(selectedIDs)
        for group in callback.questionGroups {
            guard questions.indices.contains(group.questionIndex),
                  let options = questions[group.questionIndex]["options"] as? [[String: Any]] else { return nil }
            let values = group.choiceIDs.enumerated().compactMap { index, id -> Any? in
                guard selected.contains(id), options.indices.contains(index), let value = options[index]["label"] as? String, !value.isEmpty else { return nil }
                return value
            }
            let count = group.choiceIDs.filter(selected.contains).count
            guard count == values.count, group.allowsMultiple ? count >= 1 : count == 1 else { return nil }
            questions[group.questionIndex]["answers"] = values
        }
        input["questions"] = questions
        if usesToolInput { output[key] = input } else { output = input }
        guard JSONSerialization.isValidJSONObject(output), let encoded = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]) else { return nil }
        return .preToolAllow(updatedInput: encoded)
    }

    private func updatedPlanInput(callback: ClaudeLiveCallback) -> ClaudeTypedHookResponse? {
        guard var root = try? JSONSerialization.jsonObject(with: callback.nativeInput) as? [String: Any] else { return nil }
        let key = root["tool_input"] != nil ? "tool_input" : "toolInput"
        if var input = root[key] as? [String: Any] { input["approved"] = true; root[key] = input }
        else { root["approved"] = true }
        guard JSONSerialization.isValidJSONObject(root), let encoded = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return nil }
        return .preToolAllow(updatedInput: encoded)
    }

    private func rejectKnown(_ callback: ClaudeLiveCallback, attemptID: String, action: GuidedAction, at: Date, reason: ActionAttemptRejectionReason) async -> ActionAttempt {
        await store.recordRejectedAttempt(id: attemptID, requestID: callback.requestID, owner: callback.owner, action: action, at: at, reason: reason)
    }

    private func semanticFingerprint(_ action: GuidedAction) -> String {
        switch action {
        case .allow: "allow"; case .deny: "deny"; case .persistentSuggestion: "persistent"; case .structuredResponse: "answers"; case .planReview: "plan-approval"
        case .turnInput, .interruption, .productExtension: "unsupported"
        }
    }

    private func requiresCompositionToBeIdle(_ semantic: ClaudeLiveActionSemantic) -> Bool {
        switch semantic {
        case .questionAnswers, .planApproval: true
        case .permission, .permissionSuggestion: false
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

private extension ActionAttemptTransitionResult {
    var attempt: ActionAttempt { switch self { case .updated(let value), .rejected(let value): value } }
}
