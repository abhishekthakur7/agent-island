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

/// The derived, replaceable current view of one Agent Session. Distinct from
/// `AgentSessionIdentity`, which never changes once established: everything
/// else here is sourced evidence that can be revised or go unresolved.
public struct SessionProjection: Sendable, Equatable {
    public let identity: AgentSessionIdentity
    public let execution: ExecutionState
    public let observation: ObservationState
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
        ledgerRevision: Int64
    ) {
        self.identity = identity
        self.execution = execution
        self.observation = observation
        self.displayTitle = displayTitle
        self.hostLabel = hostLabel
        self.sourceLastUpdated = sourceLastUpdated
        self.ledgerRevision = ledgerRevision
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
