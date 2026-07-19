import Foundation

/// Pure, replay-safe reduction. Receipt ordinal provides a deterministic audit
/// traversal only; Product lifecycle precedence comes from source cursors,
/// native ownership, and explicit reconciliation scope. Ambiguity always wins
/// over a plausible terminal state.
public enum SessionReducer {
    public static func reduce(history: [NormalizedEventFact], ledgerRevision: Int64) -> SessionProjection {
        precondition(!history.isEmpty, "reduce requires at least one fact")
        let ordered = history.sorted { $0.receiptOrdinal < $1.receiptOrdinal }
        let identity = ordered[0].identity

        var execution: ExecutionState = .unresolved
        let sourceOrderAmbiguous = cursorAmbiguity(in: ordered)
        var observation: ObservationState = sourceOrderAmbiguous ? .gap : .fresh
        var attention: AttentionState = .none
        var lineage: LineageState = .current
        var turns: [String: TurnProjection] = [:]
        var children: [String: SubagentRunProjection] = [:]
        var currentTurnID: String?
        var displayTitle: String?
        var hostLabel: String?
        var lastUpdated: Date?
        var terminal: ExecutionState?
        var ambiguous = sourceOrderAmbiguous || weakKeyCollision(in: ordered)

        for fact in ordered {
            if let title = fact.displayTitle { displayTitle = title }
            if let host = fact.hostLabel { hostLabel = host }
            // Horizon may describe this field as source chronology. A local
            // receipt timestamp is audit evidence, not a Product-supplied
            // activity time, so it must never become a sourced UI timestamp.
            if let occurrenceTime = fact.occurrenceTime {
                lastUpdated = occurrenceTime
            }

            switch fact.family {
            case .sessionDeclared:
                continue
            case .turnDeclared:
                guard let turnID = fact.ownership?.nativeTurnID else { ambiguous = true; continue }
                if let currentTurnID, currentTurnID != turnID { ambiguous = true; lineage = .ambiguous }
                currentTurnID = turnID
                turns[turnID] = TurnProjection(nativeTurnID: turnID, lineage: .current, execution: .unresolved)
            case .turnLineage:
                guard let turnID = fact.ownership?.nativeTurnID, let stated = fact.turnLineage else { ambiguous = true; continue }
                let state = LineageState(rawValue: stated.rawValue) ?? .ambiguous
                if state == .current {
                    if let currentTurnID, currentTurnID != turnID { turns[currentTurnID] = reline(turns[currentTurnID], .historical) }
                    currentTurnID = turnID
                }
                if state == .ambiguous { ambiguous = true; lineage = .ambiguous }
                turns[turnID] = TurnProjection(nativeTurnID: turnID, lineage: state, execution: turns[turnID]?.execution ?? .unresolved)
            case .subagentRunDeclared:
                guard let childID = fact.ownership?.nativeSubagentRunID else { ambiguous = true; continue }
                let owner = fact.ownership?.nativeTurnID
                if let prior = children[childID], prior.ownerNativeTurnID != owner { ambiguous = true }
                children[childID] = SubagentRunProjection(nativeSubagentRunID: childID, ownerNativeTurnID: owner, execution: children[childID]?.execution ?? .unresolved)
            case .attentionRequest:
                guard let kind = fact.attentionKind else { ambiguous = true; continue }
                switch kind {
                case .opened: attention = .pending
                case .resolved:
                    if attention == .pending { attention = .none } else { ambiguous = true; attention = .ambiguous }
                }
            case .reconciliation:
                switch fact.reconciliationScope {
                case .authoritativeExhaustive:
                    break
                case .nonExhaustive:
                    observation = worst(observation, .gap)
                    ambiguous = true
                case .continuityUnavailable, .none:
                    observation = .unavailable
                    ambiguous = true
                }
            case .observationBoundary:
                observation = .unavailable
                if !execution.isTerminal { ambiguous = true }
            case .sessionActivity:
                guard let kind = fact.activityKind else { ambiguous = true; continue }
                let targetTurnID = fact.ownership?.nativeTurnID
                let appliesToCurrent = targetTurnID == nil || targetTurnID == currentTurnID
                if let childID = fact.ownership?.nativeSubagentRunID {
                    guard let child = children[childID] else { ambiguous = true; continue }
                    children[childID] = SubagentRunProjection(nativeSubagentRunID: childID, ownerNativeTurnID: child.ownerNativeTurnID, execution: advanced(child.execution, with: kind, ambiguous: &ambiguous))
                    continue
                }
                guard appliesToCurrent else { continue } // late historical Turn fact remains inspectable, never current truth
                execution = advanced(execution, with: kind, ambiguous: &ambiguous)
                if let turnID = targetTurnID, let turn = turns[turnID] {
                    turns[turnID] = TurnProjection(nativeTurnID: turnID, lineage: turn.lineage, execution: execution)
                }
                if execution.isTerminal {
                    if let terminal, terminal != execution { ambiguous = true } else { terminal = execution }
                }
            }
        }

        let activeChild = children.values.contains { $0.execution == .working || $0.execution == .waiting }
        let ambiguousChild = children.values.contains { $0.execution == .unresolved }
        if ambiguousChild || attention == .ambiguous { ambiguous = true }
        if execution.isTerminal && (activeChild || ambiguousChild || attention != .none) { ambiguous = true }
        if ambiguous { execution = .unresolved }

        return SessionProjection(
            identity: identity,
            execution: execution,
            observation: observation,
            displayTitle: displayTitle,
            hostLabel: hostLabel,
            sourceLastUpdated: lastUpdated,
            ledgerRevision: ledgerRevision,
            attention: attention,
            lineage: lineage,
            turns: turns.values.sorted { $0.nativeTurnID < $1.nativeTurnID },
            subagentRuns: children.values.sorted { $0.nativeSubagentRunID < $1.nativeSubagentRunID }
        )
    }

    public static func applyRestartBoundary(_ projection: SessionProjection) -> SessionProjection {
        guard !projection.execution.isTerminal else { return projection }
        return SessionProjection(identity: projection.identity, execution: .unresolved, observation: projection.observation == .unavailable ? .unavailable : .degraded, displayTitle: projection.displayTitle, hostLabel: projection.hostLabel, sourceLastUpdated: projection.sourceLastUpdated, ledgerRevision: projection.ledgerRevision, attention: projection.attention, lineage: projection.lineage, turns: projection.turns, subagentRuns: projection.subagentRuns)
    }

    private static func advanced(_ state: ExecutionState, with kind: SessionActivityKind, ambiguous: inout Bool) -> ExecutionState {
        switch kind {
        case .started, .working:
            if state.isTerminal { ambiguous = true; return .unresolved }
            return .working
        case .waiting:
            guard state == .working || state == .waiting else { ambiguous = true; return .unresolved }
            return .waiting
        case .completed, .failed, .stopped:
            let next: ExecutionState = kind == .completed ? .terminalCompleted : (kind == .failed ? .terminalFailed : .terminalStopped)
            if state.isTerminal && state != next { ambiguous = true; return .unresolved }
            return next
        }
    }

    private static func reline(_ turn: TurnProjection?, _ state: LineageState) -> TurnProjection? {
        guard let turn else { return nil }
        return TurnProjection(nativeTurnID: turn.nativeTurnID, lineage: state, execution: turn.execution)
    }

    private static func worst(_ lhs: ObservationState, _ rhs: ObservationState) -> ObservationState {
        let ranks: [ObservationState: Int] = [.fresh: 0, .degraded: 1, .gap: 2, .unavailable: 3]
        return (ranks[lhs] ?? 0) >= (ranks[rhs] ?? 0) ? lhs : rhs
    }

    private static func cursorAmbiguity(in facts: [NormalizedEventFact]) -> Bool {
        var latest: [String: Int64] = [:]
        for fact in facts {
            guard let cursor = fact.sourceCursor else { continue }
            if let previous = latest[cursor.scope], cursor.value != previous + 1 { return true }
            latest[cursor.scope] = cursor.value
        }
        return false
    }

    private static func weakKeyCollision(in facts: [NormalizedEventFact]) -> Bool {
        var claims: [String: NormalizedEventFact] = [:]
        for fact in facts {
            guard case .weak(let key) = fact.eventIdentity else { continue }
            let scoped = "\(fact.integrationInstanceID.rawValue)::\(key)"
            if let prior = claims[scoped], !sameWeakClaim(prior, fact) { return true }
            claims[scoped] = fact
        }
        return false
    }

    private static func sameWeakClaim(_ lhs: NormalizedEventFact, _ rhs: NormalizedEventFact) -> Bool {
        lhs.identity == rhs.identity && lhs.family == rhs.family && lhs.activityKind == rhs.activityKind && lhs.boundaryReason == rhs.boundaryReason && lhs.sourceCursor == rhs.sourceCursor && lhs.ownership == rhs.ownership && lhs.turnLineage == rhs.turnLineage && lhs.attentionKind == rhs.attentionKind && lhs.reconciliationScope == rhs.reconciliationScope
    }
}
