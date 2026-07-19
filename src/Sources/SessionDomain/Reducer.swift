import Foundation

/// Pure, replay-safe reduction from an ordered fact history to the current
/// projection for one Agent Session. Deterministic in the ledger revision
/// alone: the same history always reduces to the same projection, which is
/// what makes reopen (a later ticket) safe to rebuild from stored facts.
///
/// `unresolved` is the conservative default. Transport/observation loss can
/// only move a non-terminal session to `unresolved`; it can never manufacture
/// a terminal outcome (ADR 0003, and AB-118 AC6).
public enum SessionReducer {
    public static func reduce(history: [NormalizedEventFact], ledgerRevision: Int64) -> SessionProjection {
        precondition(!history.isEmpty, "reduce requires at least one fact")
        let ordered = history.sorted { $0.receiptOrdinal < $1.receiptOrdinal }
        let identity = ordered[0].identity

        var execution: ExecutionState = .unresolved
        var observation: ObservationState = .fresh
        var displayTitle: String?
        var hostLabel: String?
        var lastUpdated: Date?

        for fact in ordered {
            if let title = fact.displayTitle { displayTitle = title }
            if let host = fact.hostLabel { hostLabel = host }
            lastUpdated = fact.occurrenceTime ?? fact.receiptTime

            switch fact.family {
            case .sessionDeclared:
                continue

            case .sessionActivity:
                guard let kind = fact.activityKind else { continue }
                switch kind {
                case .started, .working:
                    execution = .working
                case .waiting:
                    if execution == .working {
                        execution = .waiting
                    }
                case .completed:
                    if execution == .working || execution == .waiting {
                        execution = .terminalCompleted
                    }
                case .failed:
                    if execution == .working || execution == .waiting {
                        execution = .terminalFailed
                    }
                case .stopped:
                    if execution == .working || execution == .waiting {
                        execution = .terminalStopped
                    }
                }

            case .observationBoundary:
                observation = .unavailable
                if !execution.isTerminal {
                    execution = .unresolved
                }
            }
        }

        return SessionProjection(
            identity: identity,
            execution: execution,
            observation: observation,
            displayTitle: displayTitle,
            hostLabel: hostLabel,
            sourceLastUpdated: lastUpdated,
            ledgerRevision: ledgerRevision
        )
    }
}
