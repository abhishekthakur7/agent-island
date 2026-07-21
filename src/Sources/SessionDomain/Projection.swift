import Foundation

public enum ExecutionState: String, Sendable, Codable, Equatable {
    case working
    case waiting
    case terminalCompleted
    case terminalFailed
    case terminalStopped
    case unresolved

    public var isTerminal: Bool {
        switch self {
        case .terminalCompleted, .terminalFailed, .terminalStopped:
            return true
        case .working, .waiting, .unresolved:
            return false
        }
    }
}

public enum ObservationState: String, Sendable, Codable, Equatable {
    case fresh
    case degraded
    case gap
    case unavailable
}

public enum AttentionState: String, Sendable, Codable, Equatable {
    case none
    case pending
    case ambiguous
}

public enum LineageState: String, Sendable, Codable, Equatable {
    case current
    case historical
    case ambiguous
}

/// Presentation-facing labels remain separate from the evidence dimensions.
/// They are intentionally textual so presentation never needs color to make a
/// lifecycle distinction.
public enum VisibleLifecycleState: String, Sendable, Codable, Equatable {
    case working
    case needsAttention
    case completed
    case stopped
    case failed
    case unresolved
}

public struct TurnProjection: Sendable, Equatable, Codable {
    public let nativeTurnID: String
    public let lineage: LineageState
    public let execution: ExecutionState

    public init(nativeTurnID: String, lineage: LineageState, execution: ExecutionState) {
        self.nativeTurnID = nativeTurnID
        self.lineage = lineage
        self.execution = execution
    }
}

public struct SubagentRunProjection: Sendable, Equatable, Codable {
    public let nativeSubagentRunID: String
    public let ownerNativeTurnID: String?
    public let execution: ExecutionState

    public init(nativeSubagentRunID: String, ownerNativeTurnID: String?, execution: ExecutionState) {
        self.nativeSubagentRunID = nativeSubagentRunID
        self.ownerNativeTurnID = ownerNativeTurnID
        self.execution = execution
    }
}

/// The derived, replaceable current view of one Agent Session. Distinct from
/// `AgentSessionIdentity`, which never changes once established: everything
/// else here is sourced evidence that can be revised or go unresolved.
public struct SessionProjection: Sendable, Equatable, Codable {
    public let identity: AgentSessionIdentity
    public let execution: ExecutionState
    public let observation: ObservationState
    public let attention: AttentionState
    public let lineage: LineageState
    public let turns: [TurnProjection]
    public let subagentRuns: [SubagentRunProjection]
    public let displayTitle: String?
    public let hostLabel: String?
    public let sourceLastUpdated: Date?
    public let ledgerRevision: Int64
    /// Second, explicitly-separate evidence path (AB-156): best-effort
    /// evidence read directly from the Agent Product's own transcript file,
    /// never a `NormalizedEventFact`. `nil` means no transcript was read for
    /// this session. See `TranscriptEvidenceProjection`'s doc comment and
    /// `docs/adr/0001-transcript-reading-second-evidence-path.md`.
    public let transcriptEvidence: TranscriptEvidenceProjection?

    public init(
        identity: AgentSessionIdentity,
        execution: ExecutionState,
        observation: ObservationState,
        displayTitle: String?,
        hostLabel: String?,
        sourceLastUpdated: Date?,
        ledgerRevision: Int64,
        attention: AttentionState = .none,
        lineage: LineageState = .current,
        turns: [TurnProjection] = [],
        subagentRuns: [SubagentRunProjection] = [],
        transcriptEvidence: TranscriptEvidenceProjection? = nil
    ) {
        self.identity = identity
        self.execution = execution
        self.observation = observation
        self.attention = attention
        self.lineage = lineage
        self.turns = turns
        self.subagentRuns = subagentRuns
        self.displayTitle = displayTitle
        self.hostLabel = hostLabel
        self.sourceLastUpdated = sourceLastUpdated
        self.ledgerRevision = ledgerRevision
        self.transcriptEvidence = transcriptEvidence
    }

    /// Convenience accessor for the transcript-derived model string, when
    /// transcript evidence has been read for this session. This is the
    /// "carry `model` through to the projection" adjacent win called for by
    /// AB-156: it is deliberately sourced only from `transcriptEvidence`, not
    /// from `ClaudeAttributedContext.model` (the hook-parsed value), which
    /// today does not reach `NormalizedEventFact`/`SessionProjection` at all.
    /// Threading the hook-proven model through would require adding a field
    /// to `RawEventEnvelope`/`NormalizedEventFact` and a line in
    /// `SessionReducer` — a small, precedented change (mirrors
    /// `displayTitle`/`hostLabel`), but one that touches shared
    /// fact/validation/reducer files outside this ticket's granted
    /// ownership. Flagged for the consuming ticket (§1.6) rather than done
    /// here; see the AB-156 report.
    public var model: String? { transcriptEvidence?.modelFromTranscript }

    public var visibleLifecycle: VisibleLifecycleState {
        if attention == .pending { return .needsAttention }
        switch execution {
        case .working, .waiting: return .working
        case .terminalCompleted: return .completed
        case .terminalStopped: return .stopped
        case .terminalFailed: return .failed
        case .unresolved: return .unresolved
        }
    }
}

/// A projection snapshot tagged with the ledger revision that produced it,
/// published only after the underlying fact is durably committed.
public struct ProjectionRevision: Sendable, Equatable {
    public let ledgerRevision: Int64
    public let sessions: [AgentSessionIdentity: SessionProjection]

    public init(ledgerRevision: Int64, sessions: [AgentSessionIdentity: SessionProjection]) {
        self.ledgerRevision = ledgerRevision
        self.sessions = sessions
    }
}
