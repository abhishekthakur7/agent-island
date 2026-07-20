import Foundation
import SessionDomain
import AdapterPort
import PresentationPort
import SessionStore

/// Intake orchestration and projection publication. This is the *only*
/// component in the package that holds a `SessionStore` reference — Adapter
/// fixtures/implementations reach it solely through `AdapterIntakePort`, and
/// presentation code reach it solely through `PresentationPort`. Generated
/// IDs and receipt time are assigned here, at the trusted boundary, never
/// inside `SessionDomain` and never trusted from the envelope itself.
public actor ApplicationRuntime: CursorACPControlPort, PresentationPort {
    private let store: SessionStore
    /// The runtime is the only store-holding component and therefore also
    /// owns the Guided ledger/lease authority.  ACP receives this actor only
    /// through the typed AdapterPort protocol, never the ledger or store.
    private var actionAttempts: ActionAttemptStore
    private var cursorACPStateHydrated = false
    private let idGenerator: @Sendable () -> String
    private let clock: @Sendable () -> Date

    public init(
        store: SessionStore,
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.actionAttempts = ActionAttemptStore()
        self.idGenerator = idGenerator
        self.clock = clock
    }

    public func recordCursorACPControlledSession(_ session: CursorACPControlledSession) async -> CursorACPControlledSessionResult {
        guard session.identity.productNamespace.rawValue == "cursor.acp",
              !session.identity.nativeSessionID.rawValue.isEmpty
        else { return .rejected }
        switch await store.recordCursorACPControlledSession(session) {
        case .recorded: return .recorded
        case .alreadyRecorded: return .alreadyRecorded
        case .storageUnavailable: return .rejected
        }
    }

    public func mayLoadCursorACPControlledSession(_ session: CursorACPControlledSession) async -> Bool {
        await store.hasCursorACPControlledSession(session)
    }

    public func ingestCursorACPAttention(_ evidence: GuidedAttentionEvidence) async -> GuidedAttentionIngestResult {
        guard evidence.owner.productNamespace.rawValue == "cursor.acp" else { return .rejected(.missingOwner) }
        await hydrateCursorACPStateIfNeeded()
        let result = await actionAttempts.ingest(evidence)
        guard await persistCursorACPState() == nil else { return .rejected(.malformedSourceMetadata) }
        return result
    }

    public func resolveCursorACPAttention(_ id: GuidedAttentionRequestID, outcome: GuidedSourceOutcome, fingerprint: String?) async -> Bool {
        await hydrateCursorACPStateIfNeeded()
        let updated = await actionAttempts.updateSource(id, outcome: outcome, fingerprint: fingerprint)
        guard updated else { return false }
        return await persistCursorACPState() == nil
    }

    public func cursorACPAttentionRequests() async -> [GuidedAttentionRequest] {
        await hydrateCursorACPStateIfNeeded()
        return await actionAttempts.requests()
    }

    public func updateCursorACPAttentionDraft(_ id: GuidedAttentionRequestID, draft: GuidedAttentionDraft) async -> Bool {
        await hydrateCursorACPStateIfNeeded()
        guard await actionAttempts.updateDraft(id, draft) else { return false }
        return await persistCursorACPState() == nil
    }

    public func beginCursorACPAction(
        attemptID: String,
        requestID: GuidedAttentionRequestID,
        owner: GuidedAttentionOwner,
        action: GuidedAction,
        capability: CapabilityRecord,
        semanticFingerprint: String,
        nativeFingerprint: String,
        confirmed: Bool,
        deadline: Date
    ) async -> CursorACPActionAvailability {
        await hydrateCursorACPStateIfNeeded()
        let leaseID = "cursor-acp:\(idGenerator())"
        let now = clock()
        guard case .issued = await actionAttempts.issueLease(
            id: leaseID, requestID: requestID, action: action,
            semanticFingerprint: semanticFingerprint, nativeFingerprint: nativeFingerprint,
            capability: capability, issuedAt: now, deadline: deadline, confirmation: confirmed
        ) else {
            let rejected = await actionAttempts.recordRejectedAttempt(id: attemptID, requestID: requestID, owner: owner, action: action, at: now, reason: .staleLease)
            return .unavailable(rejected.rejectionReason ?? .staleLease)
        }
        let binding = ActionLeaseBinding(requestID: requestID, owner: owner, capabilityID: capability.id, capabilityRevision: capability.revision, negotiationSnapshotID: owner.negotiationSnapshotID, semanticFingerprint: semanticFingerprint, nativeFingerprint: nativeFingerprint)
        let context = ActionLeaseValidationContext(binding: binding, capability: capability, currentNativeFingerprint: nativeFingerprint, now: now)
        switch await actionAttempts.reserveAttempt(id: attemptID, requestID: requestID, owner: owner, action: action, leaseID: leaseID, context: context, confirmation: confirmed, reservedAt: now) {
        case .reserved:
            // The reservation is the durable explicit Action Attempt. Do not
            // consume authority or write ACP until it has committed.
            guard await persistCursorACPState() == nil else { return .unavailable(.persistenceUnavailable) }
            switch await actionAttempts.prepareDispatch(attemptID: attemptID, context: context, now: clock(), confirmation: confirmed) {
            case .dispatch:
                // Persist dispatch handoff before the adapter gets authority
                // to write bytes. A restart will restore it indeterminate.
                guard await persistCursorACPState() == nil else {
                    _ = await actionAttempts.recordProductOutcome(attemptID: attemptID, outcome: .indeterminate, at: clock(), evidence: "local-persistence-unavailable")
                    _ = await persistCursorACPState()
                    return .unavailable(.persistenceUnavailable)
                }
                return .dispatch((await actionAttempts.attempt(for: attemptID))!)
            case .rejected(let attempt): return .unavailable(attempt.rejectionReason ?? .gateClosed)
            }
        case .rejected(let attempt), .duplicate(let attempt):
            return .unavailable(attempt.rejectionReason ?? .alreadyDispatched)
        }
    }

    public func finishCursorACPAction(attemptID: String, outcome: ActionProductOutcome, evidence: String?) async -> ActionAttemptTransitionResult {
        await hydrateCursorACPStateIfNeeded()
        let result = await actionAttempts.recordProductOutcome(attemptID: attemptID, outcome: outcome, at: clock(), evidence: evidence)
        _ = await persistCursorACPState()
        return result
    }

    public func invalidateCursorACPActionsForDisconnect() async { await hydrateCursorACPStateIfNeeded(); await actionAttempts.invalidateForReconnect(); _ = await persistCursorACPState() }
    public func cursorACPActionAttempts() async -> [ActionAttempt] { await hydrateCursorACPStateIfNeeded(); return await actionAttempts.attempts() }

    /// A process/wake/disconnect boundary never restores an Action Lease or
    /// callback route. Durable drafts and Attention Requests stay visible;
    /// in-flight handoffs become indeterminate and require fresh documented
    /// source reconciliation before any later action can be attempted.
    public func expireVolatileActionAuthority(for boundary: RecoveryBoundary) async {
        await hydrateCursorACPStateIfNeeded()
        switch boundary {
        case .coldResume, .explicitQuit:
            await actionAttempts.invalidateForRestart()
        case .systemWake:
            await actionAttempts.invalidateForWake()
        case .adapterDisconnected, .hostDisconnected:
            await actionAttempts.invalidateForReconnect()
        case .displayRecovered:
            return
        }
        _ = await persistCursorACPState()
    }

    public func verifyProtectedStateForRecovery() async -> StorageFailureReason? {
        await store.verifyProtectedStateForRecovery()
    }

    private func hydrateCursorACPStateIfNeeded() async {
        guard !cursorACPStateHydrated else { return }
        actionAttempts = ActionAttemptStore(snapshot: await store.loadedCursorACPActionState())
        cursorACPStateHydrated = true
    }

    private func persistCursorACPState() async -> StorageFailureReason? {
        await store.persistCursorACPActionState(await actionAttempts.durableSnapshot())
    }

    public func negotiate(_ request: NegotiationRequest) async -> NegotiationOutcome {
        let outcome = SessionDomainNegotiator.negotiate(
            request,
            id: NegotiationSnapshotID(idGenerator()),
            negotiatedAt: clock()
        )
        guard case .compatible(let snapshot) = outcome else { return outcome }
        if let failure = await store.registerNegotiation(snapshot) {
            return .storageUnavailable(failure)
        }
        return outcome
    }

    public func deliver(_ envelope: RawEventEnvelope) async -> IntakeOutcome {
        await store.intake(envelope, receiptTime: clock())
    }

    /// Transport loss/exit is degradation evidence, not Product truth. It is
    /// routed through the same validated intake path as any other envelope
    /// so it obeys the same negotiation/ownership checks and can only ever
    /// move a session toward `unresolved`/`unavailable` (AB-118 AC6).
    public func reportObservationBoundary(_ report: ObservationBoundaryReport) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: report.negotiationSnapshotID,
            integrationInstanceID: report.integrationInstanceID,
            contractVersion: ContractVersion(major: SessionDomainValidator.supportedContractMajor, minor: 0),
            productNamespace: report.identity.productNamespace.rawValue,
            nativeSessionID: report.identity.nativeSessionID.rawValue,
            eventIdentity: .weak(idGenerator()),
            family: .observationBoundary,
            sourceVariant: "boundary.\(report.reason.rawValue)",
            boundaryReason: report.reason,
            classification: .operationalMetadata,
            payloadByteSize: 0
        )
        return await deliver(envelope)
    }

    /// Synchronous per `PresentationPort`; reads only `store`, a nonisolated
    /// `let` reference to another actor, so no isolation hop is required to
    /// hand back the stream.
    nonisolated public func presentationStream() -> AsyncStream<ProjectionRevision> {
        AsyncStream { continuation in
            let task = Task {
                for await revision in await store.presentationStream() {
                    continuation.yield(revision)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
