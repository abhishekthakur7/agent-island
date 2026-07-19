import Foundation
import SessionDomain

/// Single-writer canonical store for this vertical slice. It holds the
/// append-only fact ledger, the commit ordinal, and the deterministic
/// projection cache — the same shape the encrypted SQLCipher-backed store
/// (AB-119) will persist. This slice keeps it in memory only; ledger
/// durability across restart is explicitly out of scope here.
///
/// No Adapter, UI, or Host code receives a reference to this type. They only
/// ever see it through `AdapterIntakePort`/`PresentationPort`, both
/// implemented by `ApplicationRuntime`.
public actor SessionStore {
    private var negotiations: [NegotiationSnapshotID: NegotiationSnapshot] = [:]
    private var facts: [NormalizedEventFact] = []
    private var seenKeys: Set<NormalizedEventFact.DeduplicationKey> = []
    private var nextOrdinal: Int64 = 1
    private var currentRevision: Int64 = 0
    private var projections: [AgentSessionIdentity: SessionProjection] = [:]
    private var continuations: [UUID: AsyncStream<ProjectionRevision>.Continuation] = [:]

    public private(set) var diagnostics: [DiagnosticRecord] = []

    public init() {}

    public func registerNegotiation(_ snapshot: NegotiationSnapshot) {
        negotiations[snapshot.id] = snapshot
    }

    /// Validate then, only if accepted and not a duplicate, atomically append
    /// the fact and recompute+publish its session's projection. Publication
    /// happens strictly after the commit, never before (AB-118 AC3).
    public func intake(_ envelope: RawEventEnvelope, receiptTime: Date) -> IntakeOutcome {
        let negotiation = negotiations[envelope.negotiationSnapshotID]
        let result = SessionDomainValidator.validate(envelope, negotiation: negotiation, receiptTime: receiptTime)

        switch result {
        case .rejected(let reason):
            record(.init(kind: .envelopeRejected, reason: reason, ledgerRevision: nil, at: receiptTime))
            return .rejected(reason)

        case .accepted(let candidate):
            let key = candidate.deduplicationKey
            if seenKeys.contains(key) {
                record(.init(kind: .duplicateDeliverySuppressed, reason: nil, ledgerRevision: currentRevision, at: receiptTime))
                return .duplicateIgnored(ledgerRevision: currentRevision)
            }

            let ordinal = nextOrdinal
            nextOrdinal += 1
            let fact = candidate.withReceiptOrdinal(ordinal)

            facts.append(fact)
            seenKeys.insert(key)
            currentRevision = ordinal

            let history = facts.filter { $0.identity == fact.identity }
            projections[fact.identity] = SessionReducer.reduce(history: history, ledgerRevision: ordinal)

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
}
