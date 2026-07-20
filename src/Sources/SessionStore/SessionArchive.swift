import Foundation
import SessionDomain

/// Rebuildable placement and protected-record index for the compact working
/// set. It never owns Product action authority and never deletes canonical
/// evidence when a session is archived.
public struct SessionArchive: Sendable {
    public let workingSetLimit: Int
    private(set) public var records: [AgentSessionIdentity: SessionHistoryRecord] = [:]
    private(set) public var archivedIdentities: Set<AgentSessionIdentity> = []
    private var recentlyRestored: Set<AgentSessionIdentity> = []

    public init(workingSetLimit: Int = SessionHistoryPolicy.workingSetLimit) {
        self.workingSetLimit = max(1, workingSetLimit)
    }

    /// Rebuilds every record from verified immutable facts. Existing History
    /// placement is retained unless its native identity receives fresh
    /// authoritative evidence, in which case the caller removes that ID
    /// before rebuilding to model identity-safe restoration.
    public mutating func rebuild(
        facts: [NormalizedEventFact],
        projections: [AgentSessionIdentity: SessionProjection],
        content: [AgentSessionIdentity: [SessionHistoryContent]] = [:],
        recaps: [AgentSessionIdentity: SourcedSessionRecap?] = [:]
    ) {
        let identities = Set(facts.map(\.identity)).intersection(Set(projections.keys))
        archivedIdentities.formIntersection(identities)

        var rebuilt: [AgentSessionIdentity: SessionHistoryRecord] = [:]
        for identity in identities {
            let sessionFacts = facts.filter { $0.identity == identity }
            guard let projection = projections[identity], let first = sessionFacts.map(\.receiptTime).min() else { continue }
            let creation = sessionFacts
                .filter { $0.family == .sessionDeclared }
                .compactMap(\.occurrenceTime)
                .min()
            rebuilt[identity] = SessionHistoryRecord(
                identity: identity,
                facts: sessionFacts,
                projection: projection,
                productCreationTime: creation,
                firstObservedTime: first,
                recap: recaps[identity] ?? nil,
                receivedContent: content[identity] ?? []
            )
        }
        records = rebuilt

        // A previously archived record stays in History until fresh evidence
        // explicitly restores that exact native owner. New overflow can only
        // move safely inactive work; active/unresolved/attention work remains
        // visible even when the count exceeds the compact limit.
        let working = records.keys.filter { !archivedIdentities.contains($0) }
        let overflow = working.count - workingSetLimit
        guard overflow > 0 else {
            recentlyRestored.removeAll()
            return
        }
        let candidates = SessionHistoryPolicy.ordered(working.compactMap { identity in
            guard !recentlyRestored.contains(identity) else { return nil }
            guard let record = records[identity], SessionHistoryPolicy.isSafelyInactive(record.projection) else { return nil }
            return record
        })
        for record in candidates.prefix(overflow) {
            archivedIdentities.insert(record.identity)
        }
        recentlyRestored.removeAll()
    }

    public func tier(for identity: AgentSessionIdentity) -> SessionHistoryTier? {
        guard records[identity] != nil else { return nil }
        return archivedIdentities.contains(identity) ? .history : .workingSet
    }

    public var workingSet: [SessionProjection] {
        records.values
            .filter { !archivedIdentities.contains($0.identity) }
            .sorted { SessionArchive.sortKey($0.projection.identity) < SessionArchive.sortKey($1.projection.identity) }
            .map(\.projection)
    }

    public var history: [SessionHistorySummary] {
        SessionHistoryPolicy.ordered(records.values.filter { archivedIdentities.contains($0.identity) }).map {
            SessionHistorySummary(
                identity: $0.identity,
                displayTitle: $0.projection.displayTitle,
                visibleLifecycle: $0.projection.visibleLifecycle,
                creationDate: $0.orderingDate,
                orderingSource: $0.orderingSource,
                factCount: $0.facts.count,
                hasRecap: $0.recap != nil
            )
        }
    }

    public func record(for identity: AgentSessionIdentity) -> SessionHistoryRecord? {
        records[identity]
    }

    public mutating func restore(_ identity: AgentSessionIdentity) {
        archivedIdentities.remove(identity)
        recentlyRestored.insert(identity)
    }

    public mutating func remove(_ identity: AgentSessionIdentity) {
        records.removeValue(forKey: identity)
        archivedIdentities.remove(identity)
        recentlyRestored.remove(identity)
    }

    private static func sortKey(_ identity: AgentSessionIdentity) -> String {
        "\(identity.productNamespace.rawValue)\u{001F}\(identity.nativeSessionID.rawValue)"
    }
}
