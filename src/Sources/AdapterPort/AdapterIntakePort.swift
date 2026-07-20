import Foundation
import SessionDomain

/// The typed inward-facing port an Agent Adapter — first-party or fixture —
/// uses to reach `ApplicationRuntime`. It is the *only* boundary: this
/// package's dependency graph gives an Adapter no way to hold the canonical
/// store or a database/key handle, mutate a card directly, or bypass
/// validation and classification. `ApplicationRuntime` is the sole conformer.
public protocol AdapterIntakePort: Sendable {
    /// Read-only discovery is part of the inward boundary.  The default
    /// implementation is pure and does not alter enabled intent or external
    /// configuration, preserving compatibility for existing runtimes.
    func discover(_ request: DiscoveryRequest) async -> DiscoveryResult
    func negotiate(_ request: NegotiationRequest) async -> NegotiationOutcome
    func deliver(_ envelope: RawEventEnvelope) async -> IntakeOutcome
    func reportObservationBoundary(_ report: ObservationBoundaryReport) async -> IntakeOutcome
}

/// Cursor ACP's deliberately narrow control boundary.  The adapter owns
/// JSON-RPC and never receives canonical storage; the runtime owns the
/// controlled-session allowlist, Guided queue, Action Lease, and durable
/// Action Attempt.  These names are source/protocol specific so resemblance
/// to another Cursor surface cannot enter this path.
public typealias CursorACPControlledSession = CursorACPRecordedSession

public enum CursorACPControlledSessionResult: Sendable, Equatable {
    case recorded
    case alreadyRecorded
    case rejected
}

public enum CursorACPActionAvailability: Sendable, Equatable {
    case dispatch(ActionAttempt)
    case unavailable(ActionAttemptRejectionReason)
}

/// Typed addition for ACP only. It deliberately has no generic reply or
/// command method: an adapter can request one validated Guided action, then
/// report the single dispatch outcome back to the runtime.
public protocol CursorACPControlPort: AdapterIntakePort {
    func recordCursorACPControlledSession(_ session: CursorACPControlledSession) async -> CursorACPControlledSessionResult
    func mayLoadCursorACPControlledSession(_ session: CursorACPControlledSession) async -> Bool
    func ingestCursorACPAttention(_ evidence: GuidedAttentionEvidence) async -> GuidedAttentionIngestResult
    func resolveCursorACPAttention(_ id: GuidedAttentionRequestID, outcome: GuidedSourceOutcome, fingerprint: String?) async -> Bool
    func cursorACPAttentionRequests() async -> [GuidedAttentionRequest]
    func updateCursorACPAttentionDraft(_ id: GuidedAttentionRequestID, draft: GuidedAttentionDraft) async -> Bool
    func beginCursorACPAction(
        attemptID: String,
        requestID: GuidedAttentionRequestID,
        owner: GuidedAttentionOwner,
        action: GuidedAction,
        capability: CapabilityRecord,
        semanticFingerprint: String,
        nativeFingerprint: String,
        confirmed: Bool,
        deadline: Date
    ) async -> CursorACPActionAvailability
    func finishCursorACPAction(attemptID: String, outcome: ActionProductOutcome, evidence: String?) async -> ActionAttemptTransitionResult
    func invalidateCursorACPActionsForDisconnect() async
    func cursorACPActionAttempts() async -> [ActionAttempt]
}

public extension AdapterIntakePort {
    func discover(_ request: DiscoveryRequest) async -> DiscoveryResult {
        ReadOnlyAdapterDiscovery.discover(request)
    }
}
