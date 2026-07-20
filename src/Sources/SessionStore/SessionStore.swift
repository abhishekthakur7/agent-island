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
    private var archive = SessionArchive()
    private var historyContent: [AgentSessionIdentity: [SessionHistoryContent]] = [:]
    private var historyRecaps: [AgentSessionIdentity: SourcedSessionRecap] = [:]
    private var deletionBoundaries: [AgentSessionIdentity: SessionHistoryDeletionBoundary] = [:]
    private var stoppedObservation: Set<AgentSessionIdentity> = []
    private var cursorACPControlledSessions: Set<CursorACPRecordedSession> = []
    private var cursorACPActionState: ActionAttemptStoreSnapshot?
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
        for item in loaded.historyContent {
            historyContent[item.identity, default: []].append(item.content)
        }
        for item in loaded.historyRecaps {
            historyRecaps[item.identity] = item.recap
        }
        for boundary in loaded.historyBoundaries {
            deletionBoundaries[boundary.identity] = boundary
        }
        cursorACPControlledSessions = Set(loaded.cursorACPControlledSessions)
        cursorACPActionState = loaded.cursorACPActionState
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

        archive.rebuild(facts: facts, projections: projections, content: historyContent, recaps: historyRecaps.mapValues { Optional($0) })

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

    /// Canonical ACP allowlist: an exact source-returned native ID is useful
    /// only after its protected write succeeds. An ID from Cursor IDE/CLI/SDK
    /// resemblance cannot enter because no discovery path writes this set.
    public func recordCursorACPControlledSession(_ session: CursorACPRecordedSession) -> CursorACPControlledSessionStoreOutcome {
        if cursorACPControlledSessions.contains(where: { $0.integrationInstanceID == session.integrationInstanceID && $0.identity == session.identity }) { return .alreadyRecorded }
        if let protectedStore {
            do { try protectedStore.recordCursorACPControlledSession(session) }
            catch {
                let reason = (error as? ProtectedStoreFailure)?.redacted ?? .unavailable
                record(.init(kind: .storageFault, reason: nil, ledgerRevision: currentRevision, at: Date(), storageReason: reason))
                return .storageUnavailable(reason)
            }
        }
        cursorACPControlledSessions.insert(session)
        return .recorded
    }

    public func hasCursorACPControlledSession(_ session: CursorACPRecordedSession) -> Bool {
        // A new negotiation snapshot is expected after process restart; the
        // allowlist remains scoped to adapter installation + exact native
        // identity, never to a lookalike Cursor surface.
        cursorACPControlledSessions.contains { $0.integrationInstanceID == session.integrationInstanceID && $0.identity == session.identity }
    }

    public func loadedCursorACPActionState() -> ActionAttemptStoreSnapshot? { cursorACPActionState }

    /// Re-check encrypted bytes at a lifecycle boundary without rebuilding
    /// from, repairing, or overwriting them. The caller must withdraw
    /// presentation on failure; only a later explicit recovery may proceed.
    public func verifyProtectedStateForRecovery() -> StorageFailureReason? {
        guard let protectedStore else { return nil }
        do {
            try protectedStore.verifyForRecovery()
            return nil
        } catch {
            let reason = (error as? ProtectedStoreFailure)?.redacted ?? .unavailable
            record(.init(kind: .storageFault, reason: nil, ledgerRevision: currentRevision, at: Date(), storageReason: reason))
            return reason
        }
    }

    /// The caller has already mutated its isolated ActionAttemptStore. This
    /// commits the complete no-lease snapshot before any native dispatch.
    @discardableResult
    public func persistCursorACPActionState(_ state: ActionAttemptStoreSnapshot) -> StorageFailureReason? {
        if let protectedStore {
            do { try protectedStore.commitCursorACPActionState(state) }
            catch {
                let reason = (error as? ProtectedStoreFailure)?.redacted ?? .unavailable
                record(.init(kind: .storageFault, reason: nil, ledgerRevision: currentRevision, at: Date(), storageReason: reason))
                return reason
            }
        }
        cursorACPActionState = state
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

            // A selected local deletion leaves a protected non-content replay
            // boundary. Old source evidence is ignored; a different native
            // owner is never merged based on presentation similarity.
            if isSuppressedByDeletionBoundary(candidate) {
                record(.init(kind: .duplicateDeliverySuppressed, reason: nil, ledgerRevision: currentRevision, at: receiptTime))
                return .duplicateIgnored(ledgerRevision: currentRevision)
            }
            // The separately confirmed active-local-history flow first stops
            // this local observation scope. The existing intake outcome has no
            // dedicated stopped case, so the event is conservatively ignored
            // and cannot create fresh local history before confirmation.
            if stoppedObservation.contains(candidate.identity) {
                record(.init(kind: .duplicateDeliverySuppressed, reason: nil, ledgerRevision: currentRevision, at: receiptTime))
                return .duplicateIgnored(ledgerRevision: currentRevision)
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

            // Fresh authoritative evidence for this exact native owner is the
            // only restoration path from History. Mutate placement only after
            // the fact's durable commit has succeeded.
            archive.restore(candidate.identity)
            nextOrdinal += 1
            facts.append(fact)
            if seenFactsByKey[key] == nil { seenFactsByKey[key] = fact }
            currentRevision = ordinal
            projections[fact.identity] = projection
            rebuildArchive()

            record(.init(kind: .factCommitted, reason: nil, ledgerRevision: ordinal, at: receiptTime))
            publish()

            return .committed(ledgerRevision: ordinal)
        }
    }

    public func presentationStream() -> AsyncStream<ProjectionRevision> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(ProjectionRevision(ledgerRevision: currentRevision, sessions: workingProjectionMap()))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish() {
        let revision = ProjectionRevision(ledgerRevision: currentRevision, sessions: workingProjectionMap())
        for continuation in continuations.values {
            continuation.yield(revision)
        }
    }

    private func record(_ entry: DiagnosticRecord) {
        diagnostics.append(entry)
    }

    private func sameWeakClaim(_ lhs: NormalizedEventFact, _ rhs: NormalizedEventFact) -> Bool {
        lhs.identity == rhs.identity && lhs.family == rhs.family && lhs.sourceVariant == rhs.sourceVariant && lhs.activityKind == rhs.activityKind && lhs.boundaryReason == rhs.boundaryReason && lhs.sourceCursor == rhs.sourceCursor && lhs.ownership == rhs.ownership && lhs.turnLineage == rhs.turnLineage && lhs.attentionKind == rhs.attentionKind && lhs.reconciliationScope == rhs.reconciliationScope
    }

    // MARK: - Session History

    /// The compact working-set limit is a presentation constraint. The
    /// returned map never includes archived sessions, while `historySummaries`
    /// remains available for bounded local inspection.
    public func workingSetProjections() -> [AgentSessionIdentity: SessionProjection] {
        workingProjectionMap()
    }

    public func historySummaries() -> [SessionHistorySummary] {
        archive.history
    }

    public func historyRecord(for identity: AgentSessionIdentity) -> SessionHistoryRecord? {
        archive.record(for: identity)
    }

    @discardableResult
    public func recordSourcedRecap(_ recap: SourcedSessionRecap, for identity: AgentSessionIdentity) -> HistoryMutationOutcome {
        guard archive.record(for: identity) != nil else { return .notFound }
        if let protectedStore {
            do { try protectedStore.commitHistoryRecap(recap, for: identity) }
            catch {
                let reason = (error as? ProtectedStoreFailure)?.redacted ?? .unavailable
                record(.init(kind: .storageFault, reason: nil, ledgerRevision: currentRevision, at: Date(), storageReason: reason))
                return .storageUnavailable(reason)
            }
        }
        historyRecaps[identity] = recap
        rebuildArchive()
        publish()
        return .recapRecorded
    }

    public func inspectHistory(for identity: AgentSessionIdentity, maxFacts: Int = 200, maxContentItems: Int = 50, maxContentBytes: Int = 256 * 1024) -> SessionHistoryInspection? {
        archive.record(for: identity)?.inspect(maxFacts: maxFacts, maxContentItems: maxContentItems, maxContentBytes: maxContentBytes)
    }

    public func tier(for identity: AgentSessionIdentity) -> SessionHistoryTier? {
        archive.tier(for: identity)
    }

    /// Returns an explicit scope preview. No mutation occurs until the caller
    /// supplies `preview.confirmation.confirming()` to deleteHistory.
    public func previewHistoryDeletion(for identity: AgentSessionIdentity) -> SessionHistoryDeletionPreview? {
        guard let record = archive.record(for: identity),
              archive.tier(for: identity) == .history,
              SessionHistoryPolicy.isSafelyInactive(record.projection)
        else { return nil }
        let cursors = record.facts.compactMap(\.sourceCursor)
        let digest = deletionDigest(identity: identity, facts: record.facts, content: record.receivedContent)
        return SessionHistoryDeletionPreview(identity: identity, factCount: record.facts.count, contentItemCount: record.receivedContent.count, sourceCursors: cursors, previewDigest: digest)
    }

    @discardableResult
    public func deleteHistory(for identity: AgentSessionIdentity, confirmation: SessionHistoryDeletionConfirmation) -> HistoryMutationOutcome {
        guard archive.record(for: identity) != nil else { return .notFound }
        guard let preview = previewHistoryDeletion(for: identity) else { return .notSafelyInactive }
        guard confirmation.identity == identity, confirmation.confirmed, confirmation.previewDigest == preview.previewDigest else { return .confirmationRequired }
        guard let historyRecord = archive.record(for: identity) else { return .notFound }
        let boundary = makeBoundary(for: historyRecord)
        if let protectedStore {
            do {
                try protectedStore.deleteHistory(facts: historyRecord.facts, boundary: boundary)
            } catch {
                let reason = (error as? ProtectedStoreFailure)?.redacted ?? .unavailable
                record(.init(kind: .storageFault, reason: nil, ledgerRevision: currentRevision, at: Date(), storageReason: reason))
                return .storageUnavailable(reason)
            }
        }
        deletionBoundaries[identity] = boundary
        historyContent.removeValue(forKey: identity)
        historyRecaps.removeValue(forKey: identity)
        facts.removeAll { $0.identity == identity }
        projections.removeValue(forKey: identity)
        seenFactsByKey = facts.reduce(into: [:]) { result, fact in
            if result[fact.deduplicationKey] == nil { result[fact.deduplicationKey] = fact }
        }
        archive.remove(identity)
        rebuildAllProjections()
        record(.init(kind: .historyDeleted, reason: nil, ledgerRevision: currentRevision, at: Date()))
        publish()
        return .deleted
    }

    /// Separately named active-local-history flow. Beginning it stops only
    /// this local observation scope; the Product is not stopped or mutated.
    public func beginActiveLocalHistoryDeletion(for identity: AgentSessionIdentity) -> ActiveLocalHistoryDeletionPreview? {
        guard let record = archive.record(for: identity), archive.tier(for: identity) == .workingSet,
              !record.projection.execution.isTerminal else { return nil }
        stoppedObservation.insert(identity)
        let digest = deletionDigest(identity: identity, facts: record.facts, content: record.receivedContent)
        return ActiveLocalHistoryDeletionPreview(identity: identity, observationStopped: true, factCount: record.facts.count, previewDigest: digest)
    }

    /// Cancels the local stop/confirmation flow without touching Product or
    /// retained evidence. A later documented observation may then be accepted.
    @discardableResult
    public func cancelActiveLocalHistoryDeletion(for identity: AgentSessionIdentity) -> Bool {
        stoppedObservation.remove(identity) != nil
    }

    @discardableResult
    public func deleteActiveLocalHistory(for identity: AgentSessionIdentity, confirmation: SessionHistoryDeletionConfirmation) -> HistoryMutationOutcome {
        guard stoppedObservation.contains(identity), let historyRecord = archive.record(for: identity) else { return .observationStopRequired }
        guard confirmation.identity == identity, confirmation.confirmed,
              confirmation.previewDigest == deletionDigest(identity: identity, facts: historyRecord.facts, content: historyRecord.receivedContent)
        else { return .confirmationRequired }
        let boundary = makeBoundary(for: historyRecord)
        if let protectedStore {
            do { try protectedStore.deleteHistory(facts: historyRecord.facts, boundary: boundary) }
            catch {
                let reason = (error as? ProtectedStoreFailure)?.redacted ?? .unavailable
                record(.init(kind: .storageFault, reason: nil, ledgerRevision: currentRevision, at: Date(), storageReason: reason))
                return .storageUnavailable(reason)
            }
        }
        deletionBoundaries[identity] = boundary
        historyContent.removeValue(forKey: identity)
        historyRecaps.removeValue(forKey: identity)
        facts.removeAll { $0.identity == identity }
        projections.removeValue(forKey: identity)
        stoppedObservation.remove(identity)
        seenFactsByKey = facts.reduce(into: [:]) { result, fact in
            if result[fact.deduplicationKey] == nil { result[fact.deduplicationKey] = fact }
        }
        archive.remove(identity)
        rebuildAllProjections()
        record(.init(kind: .historyDeleted, reason: nil, ledgerRevision: currentRevision, at: Date()))
        publish()
        return .deleted
    }

    @discardableResult
    public func recordAuthorizedContent(_ content: SessionHistoryContent, for identity: AgentSessionIdentity) -> HistoryMutationOutcome {
        guard archive.record(for: identity) != nil else { return .notFound }
        guard content.classification == .interactionContent || content.classification == .operationalMetadata else { return .invalidContent }
        if let protectedStore {
            do { try protectedStore.commitHistoryContent(content, for: identity) }
            catch {
                let reason = (error as? ProtectedStoreFailure)?.redacted ?? .unavailable
                record(.init(kind: .storageFault, reason: nil, ledgerRevision: currentRevision, at: Date(), storageReason: reason))
                return .storageUnavailable(reason)
            }
        }
        historyContent[identity, default: []].removeAll { $0.contentID == content.contentID }
        historyContent[identity, default: []].append(content)
        rebuildArchive()
        publish()
        return .contentRecorded
    }

    private func workingProjectionMap() -> [AgentSessionIdentity: SessionProjection] {
        Dictionary(uniqueKeysWithValues: archive.workingSet.map { ($0.identity, $0) })
    }

    private func rebuildArchive() {
        archive.rebuild(facts: facts, projections: projections, content: historyContent, recaps: historyRecaps.mapValues { Optional($0) })
    }

    private func rebuildAllProjections() {
        projections.removeAll()
        for identity in Set(facts.map(\.identity)) {
            let history = facts.filter { $0.identity == identity }
            projections[identity] = SessionReducer.reduce(history: history, ledgerRevision: currentRevision)
        }
        rebuildArchive()
    }

    private func isSuppressedByDeletionBoundary(_ fact: NormalizedEventFact) -> Bool {
        guard let boundary = deletionBoundaries[fact.identity] else { return false }
        if let cursor = fact.sourceCursor, boundary.sourceCursors.contains(cursor) {
            return true
        }
        switch fact.eventIdentity {
        case .stable(let eventID): return boundary.stableEventIdentities.contains(eventID)
        case .weak(let key): return boundary.weakEventKeys.contains(key)
        }
    }

    private func makeBoundary(for record: SessionHistoryRecord) -> SessionHistoryDeletionBoundary {
        var stable: [String] = []
        var weak: [String] = []
        for fact in record.facts {
            switch fact.eventIdentity {
            case .stable(let value): stable.append(value)
            case .weak(let value): weak.append(value)
            }
        }
        return SessionHistoryDeletionBoundary(identity: record.identity, stableEventIdentities: stable, weakEventKeys: weak, sourceCursors: record.facts.compactMap(\.sourceCursor))
    }

    private func deletionDigest(identity: AgentSessionIdentity, facts: [NormalizedEventFact], content: [SessionHistoryContent]) -> String {
        let factPart = facts.map { "\($0.receiptOrdinal):\($0.eventIdentity)" }.joined(separator: ",")
        let contentPart = content.map(\.contentID).sorted().joined(separator: ",")
        return "\(identity.productNamespace.rawValue)|\(identity.nativeSessionID.rawValue)|\(factPart)|\(contentPart)"
    }
}

public enum HistoryMutationOutcome: Sendable, Equatable {
    case deleted
    case contentRecorded
    case recapRecorded
    case notFound
    case notSafelyInactive
    case observationStopRequired
    case confirmationRequired
    case invalidContent
    case storageUnavailable(StorageFailureReason)
}
