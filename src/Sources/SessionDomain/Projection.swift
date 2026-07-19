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
        subagentRuns: [SubagentRunProjection] = []
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
    }

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
