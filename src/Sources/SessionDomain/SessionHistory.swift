import Foundation

/// The local tier for an Agent Session. This is a presentation/storage
/// placement only; it never changes the Product-owned lifecycle projection.
public enum SessionHistoryTier: String, Sendable, Codable, Equatable {
    case workingSet
    case history
}

/// Why a Session History entry is ordered at a particular position. Product
/// time is authoritative when the Product supplied it; the local timestamp is
/// explicitly labelled as a fallback and never becomes lifecycle evidence.
public enum SessionHistoryOrderingSource: String, Sendable, Codable, Equatable {
    case productCreationTime
    case localFirstObservedTime
}

/// A bounded, source-attributed recap. Recaps are optional because the
/// observation-only boundary may not have received one. The source event ID
/// prevents a locally invented summary from being treated as Product truth.
public struct SourcedSessionRecap: Hashable, Sendable, Codable {
    public let sourceEventIdentity: EventIdentity
    public let text: String

    public init(sourceEventIdentity: EventIdentity, text: String) {
        self.sourceEventIdentity = sourceEventIdentity
        self.text = text
    }
}

/// Content explicitly received through an authorized Adapter surface. It is
/// retained as protected local content and remains owned by the session (and,
/// when supplied, a native Turn or Attention Request).
public struct SessionHistoryContent: Hashable, Sendable, Codable {
    public let contentID: String
    public let classification: PayloadClassification
    public let bytes: Data
    public let nativeTurnID: String?
    public let nativeAttentionRequestID: String?

    public init(
        contentID: String,
        classification: PayloadClassification = .interactionContent,
        bytes: Data,
        nativeTurnID: String? = nil,
        nativeAttentionRequestID: String? = nil
    ) {
        self.contentID = contentID
        self.classification = classification
        self.bytes = bytes
        self.nativeTurnID = nativeTurnID
        self.nativeAttentionRequestID = nativeAttentionRequestID
    }
}

/// The durable logical record kept for an Agent Session after it moves to
/// Session History. Facts are never rewritten or reduced to a transcript.
public struct SessionHistoryRecord: Sendable, Codable {
    public let identity: AgentSessionIdentity
    public let facts: [NormalizedEventFact]
    public let projection: SessionProjection
    public let productCreationTime: Date?
    public let firstObservedTime: Date
    public let recap: SourcedSessionRecap?
    public let receivedContent: [SessionHistoryContent]

    public init(
        identity: AgentSessionIdentity,
        facts: [NormalizedEventFact],
        projection: SessionProjection,
        productCreationTime: Date? = nil,
        firstObservedTime: Date,
        recap: SourcedSessionRecap? = nil,
        receivedContent: [SessionHistoryContent] = []
    ) {
        self.identity = identity
        self.facts = facts.sorted { $0.receiptOrdinal < $1.receiptOrdinal }
        self.projection = projection
        self.productCreationTime = productCreationTime
        self.firstObservedTime = firstObservedTime
        self.recap = recap
        self.receivedContent = receivedContent
    }

    public var orderingSource: SessionHistoryOrderingSource {
        productCreationTime == nil ? .localFirstObservedTime : .productCreationTime
    }

    public var orderingDate: Date { productCreationTime ?? firstObservedTime }

    /// Bounded inspection protects the UI from unbounded historical payloads.
    public func inspect(maxFacts: Int = 200, maxContentItems: Int = 50, maxContentBytes: Int = 256 * 1024) -> SessionHistoryInspection {
        let factLimit = max(0, maxFacts)
        let contentLimit = max(0, maxContentItems)
        let boundedFacts = Array(facts.prefix(factLimit))
        var boundedContent: [SessionHistoryContent] = []
        var bytes = 0
        for content in receivedContent.prefix(contentLimit) {
            guard bytes + content.bytes.count <= max(0, maxContentBytes) else { break }
            boundedContent.append(content)
            bytes += content.bytes.count
        }
        return SessionHistoryInspection(
            record: self,
            facts: boundedFacts,
            receivedContent: boundedContent,
            factsTruncated: boundedFacts.count < facts.count,
            contentTruncated: boundedContent.count < receivedContent.count
        )
    }
}

/// Result of bounded local inspection. The full protected record remains
/// untouched; truncation is explicit rather than silently dropping evidence.
public struct SessionHistoryInspection: Sendable, Codable {
    public let record: SessionHistoryRecord
    public let facts: [NormalizedEventFact]
    public let receivedContent: [SessionHistoryContent]
    public let factsTruncated: Bool
    public let contentTruncated: Bool

    public init(record: SessionHistoryRecord, facts: [NormalizedEventFact], receivedContent: [SessionHistoryContent], factsTruncated: Bool, contentTruncated: Bool) {
        self.record = record
        self.facts = facts
        self.receivedContent = receivedContent
        self.factsTruncated = factsTruncated
        self.contentTruncated = contentTruncated
    }
}

/// Rebuildable compact row data for a Session History view. It contains no
/// Product action authority and deliberately identifies History as local.
public struct SessionHistorySummary: Identifiable, Hashable, Sendable, Codable {
    public let identity: AgentSessionIdentity
    public let displayTitle: String?
    public let visibleLifecycle: VisibleLifecycleState
    public let creationDate: Date
    public let orderingSource: SessionHistoryOrderingSource
    public let factCount: Int
    public let hasRecap: Bool

    public var id: AgentSessionIdentity { identity }

    public init(identity: AgentSessionIdentity, displayTitle: String?, visibleLifecycle: VisibleLifecycleState, creationDate: Date, orderingSource: SessionHistoryOrderingSource, factCount: Int, hasRecap: Bool) {
        self.identity = identity
        self.displayTitle = displayTitle
        self.visibleLifecycle = visibleLifecycle
        self.creationDate = creationDate
        self.orderingSource = orderingSource
        self.factCount = factCount
        self.hasRecap = hasRecap
    }
}

/// A deterministic preview/confirmation pair for local historical deletion.
/// The confirmation carries only a redacted digest of the selected scope; it
/// cannot be used to route a Product action.
public struct SessionHistoryDeletionConfirmation: Hashable, Sendable, Codable {
    public let identity: AgentSessionIdentity
    public let previewDigest: String
    public let confirmed: Bool

    public init(identity: AgentSessionIdentity, previewDigest: String, confirmed: Bool = false) {
        self.identity = identity
        self.previewDigest = previewDigest
        self.confirmed = confirmed
    }

    public func confirming() -> SessionHistoryDeletionConfirmation {
        SessionHistoryDeletionConfirmation(identity: identity, previewDigest: previewDigest, confirmed: true)
    }
}

public struct SessionHistoryDeletionPreview: Hashable, Sendable, Codable {
    public let identity: AgentSessionIdentity
    public let factCount: Int
    public let contentItemCount: Int
    public let sourceCursors: [SourceCursor]
    public let previewDigest: String
    public let confirmation: SessionHistoryDeletionConfirmation

    public init(identity: AgentSessionIdentity, factCount: Int, contentItemCount: Int, sourceCursors: [SourceCursor], previewDigest: String) {
        self.identity = identity
        self.factCount = factCount
        self.contentItemCount = contentItemCount
        self.sourceCursors = sourceCursors
        self.previewDigest = previewDigest
        self.confirmation = SessionHistoryDeletionConfirmation(identity: identity, previewDigest: previewDigest)
    }
}

public struct ActiveLocalHistoryDeletionPreview: Hashable, Sendable, Codable {
    public let identity: AgentSessionIdentity
    public let observationStopped: Bool
    public let factCount: Int
    public let previewDigest: String

    public init(identity: AgentSessionIdentity, observationStopped: Bool, factCount: Int, previewDigest: String) {
        self.identity = identity
        self.observationStopped = observationStopped
        self.factCount = factCount
        self.previewDigest = previewDigest
    }

    public var confirmation: SessionHistoryDeletionConfirmation {
        SessionHistoryDeletionConfirmation(identity: identity, previewDigest: previewDigest)
    }
}

/// Minimum non-content boundary retained after selected local deletion. A
/// stable source-event identity is preferred; source cursor evidence is kept
/// when available so a documented old range cannot silently replay. This is
/// not a Product deletion marker and cannot alter Product state.
public struct SessionHistoryDeletionBoundary: Hashable, Sendable, Codable {
    public let identity: AgentSessionIdentity
    public let stableEventIdentities: [String]
    public let weakEventKeys: [String]
    public let sourceCursors: [SourceCursor]

    public init(identity: AgentSessionIdentity, stableEventIdentities: [String] = [], weakEventKeys: [String] = [], sourceCursors: [SourceCursor] = []) {
        self.identity = identity
        self.stableEventIdentities = Array(Set(stableEventIdentities)).sorted()
        self.weakEventKeys = Array(Set(weakEventKeys)).sorted()
        self.sourceCursors = Array(Set(sourceCursors)).sorted { lhs, rhs in
            lhs.scope == rhs.scope ? lhs.value < rhs.value : lhs.scope < rhs.scope
        }
    }
}

/// A pure retention policy shared by the store and deterministic tests.
public enum SessionHistoryPolicy {
    public static let workingSetLimit = 30

    public static func isSafelyInactive(_ projection: SessionProjection) -> Bool {
        guard projection.execution.isTerminal, projection.attention == .none else { return false }
        return !projection.subagentRuns.contains { run in
            run.execution == .working || run.execution == .waiting
        }
    }

    public static func ordered(_ records: [SessionHistoryRecord]) -> [SessionHistoryRecord] {
        records.sorted {
            if $0.orderingDate != $1.orderingDate { return $0.orderingDate < $1.orderingDate }
            if $0.orderingSource != $1.orderingSource {
                return $0.orderingSource == .productCreationTime
            }
            return identitySortKey($0.identity) < identitySortKey($1.identity)
        }
    }

    private static func identitySortKey(_ identity: AgentSessionIdentity) -> String {
        "\(identity.productNamespace.rawValue)\u{001F}\(identity.nativeSessionID.rawValue)"
    }
}
