import Foundation
import SessionDomain
import ProtectedStore

/// Single-writer canonical store. It holds the append-only fact ledger, the
/// commit ordinal, and the deterministic projection cache, optionally backed
/// by an encrypted `ProtectedStore` (AB-119). Without a `ProtectedStore` it
/// behaves exactly as the AB-118 vertical slice did: in-memory only, used by
/// fixtures and unit tests that don't need durability.
///
/// No Adapter, UI, or Host code receives a reference to this type. They only
/// ever see it through `AdapterIntakePort`/`PresentationPort`, both
/// implemented by `ApplicationRuntime`.
public actor SessionStore {
    private var negotiations: [NegotiationSnapshotID: NegotiationSnapshot] = [:]
    private var facts: [NormalizedEventFact] = []
    private var seenFactsByKey: [NormalizedEventFact.DeduplicationKey: NormalizedEventFact] = [:]
    private var nextOrdinal: Int64 = 1
    private var currentRevision: Int64 = 0
    private var projections: [AgentSessionIdentity: SessionProjection] = [:]
    private var continuations: [UUID: AsyncStream<ProjectionRevision>.Continuation] = [:]
    private let protectedStore: ProtectedStore?

    public private(set) var diagnostics: [DiagnosticRecord] = []

    public init() {
        self.protectedStore = nil
    }

    /// Opens (or bootstraps) the encrypted canonical store, verifies its
    /// integrity, and rebuilds every projection from its durable fact
    /// ledger — never from the cached projection snapshot alone (AB-119
    /// AC6). Throws `ProtectedStoreFailure` fail-closed when the store
    /// cannot be safely opened at all (missing key, corrupt ciphertext,
    /// interrupted migration): the caller must present a redacted
    /// unavailable/recovery state rather than launch with a silently reset
    /// store.
    public init(protectedStore: ProtectedStore) throws {
        self.protectedStore = protectedStore
        let loaded = try protectedStore.openOrBootstrap()

        for snapshot in loaded.negotiations {
            negotiations[snapshot.id] = snapshot
        }

        facts = loaded.facts.sorted { $0.receiptOrdinal < $1.receiptOrdinal }
        for fact in facts where seenFactsByKey[fact.deduplicationKey] == nil {
            seenFactsByKey[fact.deduplicationKey] = fact
        }
        nextOrdinal = (facts.map(\.receiptOrdinal).max() ?? 0) + 1
        currentRevision = facts.map(\.receiptOrdinal).max() ?? 0

        let now = Date()
        for identity in Set(facts.map(\.identity)) {
            let history = facts.filter { $0.identity == identity }
            let rebuilt = SessionReducer.reduce(history: history, ledgerRevision: currentRevision)
            projections[identity] = SessionReducer.applyRestartBoundary(rebuilt)
        }

        if loaded.projectionCacheFault != nil {
            diagnostics.append(.init(kind: .projectionCacheDiscarded, reason: nil, ledgerRevision: currentRevision, at: now))
        }
    }

    /// Mirrors `intake`'s durability gate: a negotiation only becomes usable
    /// for validating incoming envelopes once its durable write (when
    /// protected) has actually succeeded — never optimistically in memory
    /// first. Returns the storage reason on failure so the caller can
    /// surface it instead of silently treating an unpersisted negotiation as
    /// live.
    @discardableResult
    public func registerNegotiation(_ snapshot: NegotiationSnapshot) -> StorageFailureReason? {
        guard let protectedStore else {
            negotiations[snapshot.id] = snapshot
            return nil
        }
        do {
            try protectedStore.registerNegotiation(snapshot)
        } catch {
            let reason = (error as? ProtectedStoreFailure)?.redacted ?? .unavailable
            record(.init(kind: .storageFault, reason: nil, ledgerRevision: currentRevision, at: Date(), storageReason: reason))
            return reason
        }
        negotiations[snapshot.id] = snapshot
        return nil
    }

    /// Validate then, only if accepted and not a duplicate, atomically commit
    /// the fact (and, when protected, its durable write) before mutating any
    /// in-memory state or publishing — a durable-write failure leaves the
    /// ledger exactly as it was, never a partial/ghost commit (AB-119 AC1).
    public func intake(_ envelope: RawEventEnvelope, receiptTime: Date) -> IntakeOutcome {
        let negotiation = negotiations[envelope.negotiationSnapshotID]
        let result = SessionDomainValidator.validate(envelope, negotiation: negotiation, receiptTime: receiptTime)

        switch result {
        case .rejected(let reason):
            record(.init(kind: .envelopeRejected, reason: reason, ledgerRevision: nil, at: receiptTime))
            return .rejected(reason)

        case .accepted(let candidate):
            let key = candidate.deduplicationKey
            if let existing = seenFactsByKey[key] {
                // A stable Product source-event ID is idempotent. A weak key
                // may suppress only a documented replay of the same claim;
                // a collision is retained so the reducer can present the
                // resulting ambiguity instead of silently merging work.
                if case .stable = candidate.eventIdentity {
                    record(.init(kind: .duplicateDeliverySuppressed, reason: nil, ledgerRevision: currentRevision, at: receiptTime))
                    return .duplicateIgnored(ledgerRevision: currentRevision)
                }
                if sameWeakClaim(existing, candidate) {
                    record(.init(kind: .duplicateDeliverySuppressed, reason: nil, ledgerRevision: currentRevision, at: receiptTime))
                    return .duplicateIgnored(ledgerRevision: currentRevision)
                }
            }

            let ordinal = nextOrdinal
            let fact = candidate.withReceiptOrdinal(ordinal)
            let history = facts.filter { $0.identity == fact.identity } + [fact]
            let projection = SessionReducer.reduce(history: history, ledgerRevision: ordinal)

            if let protectedStore {
                do {
                    try protectedStore.commit(fact: fact, projection: projection)
                } catch {
                    let reason = (error as? ProtectedStoreFailure)?.redacted ?? .unavailable
                    record(.init(kind: .storageFault, reason: nil, ledgerRevision: currentRevision, at: receiptTime, storageReason: reason))
                    return .storageUnavailable(reason)
                }
            }

            nextOrdinal += 1
            facts.append(fact)
            if seenFactsByKey[key] == nil { seenFactsByKey[key] = fact }
            currentRevision = ordinal
            projections[fact.identity] = projection

            record(.init(kind: .factCommitted, reason: nil, ledgerRevision: ordinal, at: receiptTime))
            publish()

            return .committed(ledgerRevision: ordinal)
        }
    }

    public func presentationStream() -> AsyncStream<ProjectionRevision> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(ProjectionRevision(ledgerRevision: currentRevision, sessions: projections))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish() {
        let revision = ProjectionRevision(ledgerRevision: currentRevision, sessions: projections)
        for continuation in continuations.values {
            continuation.yield(revision)
        }
    }

    private func record(_ entry: DiagnosticRecord) {
        diagnostics.append(entry)
    }

    private func sameWeakClaim(_ lhs: NormalizedEventFact, _ rhs: NormalizedEventFact) -> Bool {
        lhs.identity == rhs.identity && lhs.family == rhs.family && lhs.activityKind == rhs.activityKind && lhs.boundaryReason == rhs.boundaryReason && lhs.sourceCursor == rhs.sourceCursor && lhs.ownership == rhs.ownership && lhs.turnLineage == rhs.turnLineage && lhs.attentionKind == rhs.attentionKind && lhs.reconciliationScope == rhs.reconciliationScope
    }
}
