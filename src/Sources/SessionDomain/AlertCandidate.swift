import Foundation

/// The local semantic classes used by Notification Policy.  Their ordering is
/// deliberately explicit and is independent of source/product priority.
public enum AlertCandidateClass: String, Codable, Hashable, Sendable, CaseIterable {
    case attention
    case errorContextLimit
    case completion
    case sessionStart
    case reminder
    case acknowledgement
    case spam
    case childCompletion

    public static var error: Self { .errorContextLimit }
    public static var contextLimit: Self { .errorContextLimit }
    public static var start: Self { .sessionStart }
    public static var childRunCompletion: Self { .childCompletion }

    public var priority: Int {
        switch self {
        case .attention: 700
        case .errorContextLimit: 600
        case .completion: 500
        case .sessionStart: 400
        case .reminder: 300
        case .acknowledgement, .spam: 200
        case .childCompletion: 500
        }
    }

    public var defaultDwell: TimeInterval? {
        switch self {
        case .attention: nil
        case .completion, .errorContextLimit: 3.5
        case .sessionStart: 2.5
        case .childCompletion: 2.5
        case .reminder, .acknowledgement, .spam: 2
        }
    }

    public var isBackgroundNotificationEligible: Bool {
        switch self {
        case .attention, .errorContextLimit, .completion, .sessionStart, .reminder: true
        case .acknowledgement, .spam: false
        case .childCompletion: false
        }
    }
}

/// Source classification is retained as evidence so filters never infer a
/// launch, probe, directory, or child run from a title or Host label.
public enum AlertCandidateOrigin: String, Codable, Hashable, Sendable, CaseIterable {
    case normal
    case launcher
    case probe
    case builtInInternalWork
    case directory
    case firstPrompt
    case sourcedChildRun
}

public enum AlertCandidateRejectionReason: String, Codable, Hashable, Sendable, Error, CaseIterable {
    case notReducerAccepted
    case missingOwner
    case missingStableEventIdentity
    case weakKeyAmbiguous
    case crossOwnerProvenance
    case interactionContentUnsupported
    case staleRevision
    case unknownOwner
    case unsupportedSource
    case continuityGap
    case terminalLineageRequired
    case pendingAttention
    case activeOrUnknownChild
    case malformedMetadata
    case duplicate
}

/// Exact Product ownership and provenance.  It intentionally contains no
/// display text, prompt, path, model, Host title, or receipt timestamp.
public struct AlertCandidateOwner: Codable, Hashable, Sendable, Equatable {
    public let productNamespace: ProductNamespace
    public let nativeSessionID: NativeSessionID
    public let nativeTurnID: String?
    public let nativeAttentionRequestID: String?
    public let nativeSubagentRunID: String?
    public let integrationInstanceID: IntegrationInstanceID
    public let negotiationSnapshotID: NegotiationSnapshotID

    public init(
        productNamespace: ProductNamespace,
        nativeSessionID: NativeSessionID,
        nativeTurnID: String? = nil,
        nativeAttentionRequestID: String? = nil,
        nativeSubagentRunID: String? = nil,
        integrationInstanceID: IntegrationInstanceID,
        negotiationSnapshotID: NegotiationSnapshotID
    ) {
        self.productNamespace = productNamespace
        self.nativeSessionID = nativeSessionID
        self.nativeTurnID = nativeTurnID
        self.nativeAttentionRequestID = nativeAttentionRequestID
        self.nativeSubagentRunID = nativeSubagentRunID
        self.integrationInstanceID = integrationInstanceID
        self.negotiationSnapshotID = negotiationSnapshotID
    }

    public var sessionIdentity: AgentSessionIdentity {
        AgentSessionIdentity(productNamespace: productNamespace, nativeSessionID: nativeSessionID)
    }

    public var isValid: Bool {
        !productNamespace.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !nativeSessionID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !integrationInstanceID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !negotiationSnapshotID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Candidate identity is stable across source revisions.  A later revision
/// updates the candidate record in-place instead of creating a second alert.
public struct AlertCandidateID: Codable, Hashable, Sendable, Equatable, Identifiable, CustomStringConvertible {
    public let owner: AlertCandidateOwner
    public let semanticClass: AlertCandidateClass
    public let sourceEventIdentity: EventIdentity

    public init(owner: AlertCandidateOwner, semanticClass: AlertCandidateClass, sourceEventIdentity: EventIdentity) {
        self.owner = owner
        self.semanticClass = semanticClass
        self.sourceEventIdentity = sourceEventIdentity
    }

    public var id: String { description }

    public var description: String {
        let event: String
        switch sourceEventIdentity {
        case .stable(let value): event = value
        case .weak(let value): event = value
        }
        return [
            owner.productNamespace.rawValue,
            owner.nativeSessionID.rawValue,
            owner.nativeTurnID ?? "-",
            owner.nativeAttentionRequestID ?? "-",
            owner.nativeSubagentRunID ?? "-",
            semanticClass.rawValue,
            event
        ].joined(separator: "::")
    }
}

public struct AlertCandidateDwell: Codable, Hashable, Sendable, Equatable {
    public let minimum: TimeInterval
    public let maximum: TimeInterval

    public init(minimum: TimeInterval, maximum: TimeInterval) {
        self.minimum = max(0, minimum)
        self.maximum = max(self.minimum, maximum)
    }

    public static let completion = Self(minimum: 3, maximum: 4)
    public static let sessionStart = Self(minimum: 2, maximum: 3)
}

public struct AlertCandidatePayload: Codable, Hashable, Sendable, Equatable {
    /// This is a bounded configured label, never a Product prompt or title.
    public let label: String?
    public let state: VisibleLifecycleState
    public let hasPendingAttention: Bool
    public let hasActiveChild: Bool

    public init(label: String? = nil, state: VisibleLifecycleState, hasPendingAttention: Bool = false, hasActiveChild: Bool = false) {
        self.label = Self.sanitize(label)
        self.state = state
        self.hasPendingAttention = hasPendingAttention
        self.hasActiveChild = hasActiveChild
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        let flattened = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty, flattened.utf8.count <= 128 else { return nil }
        // Secret-looking values are never copied to notification payloads.
        let lowered = flattened.lowercased()
        if lowered.contains("token=") || lowered.contains("password=") || lowered.contains("secret=") || lowered.contains("api_key=") {
            return nil
        }
        return String(flattened.prefix(128))
    }
}

/// Evidence supplied by the canonical reducer boundary.  The factory below
/// checks every field before it creates a user-facing candidate.
public struct AlertCandidateEvidence: Sendable {
    public let fact: NormalizedEventFact
    public let projection: SessionProjection
    public let semanticClass: AlertCandidateClass
    public let origin: AlertCandidateOrigin
    public let configuredLabel: String?
    public let reducerAccepted: Bool
    public let sourceRevision: Int64

    public init(
        fact: NormalizedEventFact,
        projection: SessionProjection,
        semanticClass: AlertCandidateClass,
        origin: AlertCandidateOrigin = .normal,
        configuredLabel: String? = nil,
        reducerAccepted: Bool = true,
        sourceRevision: Int64? = nil
    ) {
        self.fact = fact
        self.projection = projection
        self.semanticClass = semanticClass
        self.origin = origin
        self.configuredLabel = configuredLabel
        self.reducerAccepted = reducerAccepted
        self.sourceRevision = sourceRevision ?? fact.receiptOrdinal
    }
}

public struct AlertCandidate: Codable, Hashable, Sendable, Equatable, Identifiable {
    public let id: AlertCandidateID
    public let owner: AlertCandidateOwner
    public let semanticClass: AlertCandidateClass
    public let origin: AlertCandidateOrigin
    public let sourceEventIdentity: EventIdentity
    public let sourceVariant: String
    public let sourceRevision: Int64
    public let sourceObservedAt: Date
    public let payload: AlertCandidatePayload
    public let dwell: AlertCandidateDwell?

    public var candidateID: AlertCandidateID { id }

    public init(
        id: AlertCandidateID,
        owner: AlertCandidateOwner,
        semanticClass: AlertCandidateClass,
        origin: AlertCandidateOrigin,
        sourceEventIdentity: EventIdentity,
        sourceVariant: String,
        sourceRevision: Int64,
        sourceObservedAt: Date,
        payload: AlertCandidatePayload,
        dwell: AlertCandidateDwell?
    ) {
        self.id = id
        self.owner = owner
        self.semanticClass = semanticClass
        self.origin = origin
        self.sourceEventIdentity = sourceEventIdentity
        self.sourceVariant = String(sourceVariant.prefix(SessionDomainValidator.maxMetadataStringBytes))
        self.sourceRevision = sourceRevision
        self.sourceObservedAt = sourceObservedAt
        self.payload = payload
        self.dwell = dwell
    }

    public static func make(from evidence: AlertCandidateEvidence) -> Result<AlertCandidate, AlertCandidateRejectionReason> {
        let fact = evidence.fact
        guard evidence.reducerAccepted, fact.receiptOrdinal > 0 else { return .failure(.notReducerAccepted) }
        guard fact.identity == evidence.projection.identity else { return .failure(.unknownOwner) }
        guard case .stable = fact.eventIdentity else { return .failure(.weakKeyAmbiguous) }
        guard fact.classification == .operationalMetadata else { return .failure(.interactionContentUnsupported) }
        guard evidence.projection.observation != .gap, evidence.projection.observation != .unavailable else { return .failure(.continuityGap) }
        guard evidence.sourceRevision > 0, evidence.sourceRevision == fact.receiptOrdinal, evidence.sourceRevision <= evidence.projection.ledgerRevision else { return .failure(.staleRevision) }
        let owner = AlertCandidateOwner(
            productNamespace: fact.identity.productNamespace,
            nativeSessionID: fact.identity.nativeSessionID,
            nativeTurnID: fact.ownership?.nativeTurnID,
            nativeAttentionRequestID: fact.ownership?.nativeAttentionRequestID,
            nativeSubagentRunID: fact.ownership?.nativeSubagentRunID,
            integrationInstanceID: fact.integrationInstanceID,
            negotiationSnapshotID: fact.negotiationSnapshotID
        )
        guard owner.isValid else { return .failure(.missingOwner) }
        guard !fact.sourceVariant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.malformedMetadata) }
        guard sourceIsValid(evidence) else { return .failure(.unsupportedSource) }

        let state = evidence.projection.visibleLifecycle
        let payload = AlertCandidatePayload(
            label: evidence.configuredLabel,
            state: state,
            hasPendingAttention: evidence.projection.attention == .pending,
            hasActiveChild: evidence.projection.subagentRuns.contains { $0.execution == .working || $0.execution == .waiting }
        )
        let dwell: AlertCandidateDwell?
        switch evidence.semanticClass {
        case .completion, .errorContextLimit: dwell = .completion
        case .sessionStart, .childCompletion: dwell = .sessionStart
        default: dwell = nil
        }
        let id = AlertCandidateID(owner: owner, semanticClass: evidence.semanticClass, sourceEventIdentity: fact.eventIdentity)
        return .success(AlertCandidate(
            id: id,
            owner: owner,
            semanticClass: evidence.semanticClass,
            origin: evidence.origin,
            sourceEventIdentity: fact.eventIdentity,
            sourceVariant: fact.sourceVariant,
            sourceRevision: evidence.sourceRevision,
            sourceObservedAt: fact.occurrenceTime ?? fact.receiptTime,
            payload: payload,
            dwell: dwell
        ))
    }

    private static func sourceIsValid(_ evidence: AlertCandidateEvidence) -> Bool {
        let fact = evidence.fact
        switch evidence.semanticClass {
        case .attention:
            return fact.family == .attentionRequest && fact.attentionKind == .opened && fact.ownership?.nativeAttentionRequestID?.isEmpty == false && evidence.projection.attention == .pending
        case .completion:
            return fact.family == .sessionActivity && fact.activityKind.map { $0 == .completed || $0 == .failed || $0 == .stopped } == true && evidence.projection.lineage == .current && evidence.projection.execution.isTerminal && evidence.projection.attention == .none && !evidence.projection.subagentRuns.contains { $0.execution == .working || $0.execution == .waiting || $0.execution == .unresolved }
        case .childCompletion:
            guard fact.family == .sessionActivity,
                  fact.activityKind.map({ $0 == .completed || $0 == .failed || $0 == .stopped }) == true,
                  let childID = fact.ownership?.nativeSubagentRunID,
                  let child = evidence.projection.subagentRuns.first(where: { $0.nativeSubagentRunID == childID })
            else { return false }
            return child.execution.isTerminal && evidence.projection.lineage == .current
        case .sessionStart:
            return fact.family == .sessionActivity && fact.activityKind == .started && evidence.projection.lineage == .current
        case .errorContextLimit, .reminder, .acknowledgement, .spam:
            // These classes require an explicit source classification.  No
            // presentation metadata is used to infer one.
            return !fact.sourceVariant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && evidence.projection.lineage == .current && evidence.projection.observation != .gap && evidence.projection.observation != .unavailable
        }
    }
}

/// Named boundary for callers that want to make the reducer-acceptance step
/// explicit in composition code.
public enum AlertCandidateFactory {
    public static func make(from evidence: AlertCandidateEvidence) -> Result<AlertCandidate, AlertCandidateRejectionReason> {
        AlertCandidate.make(from: evidence)
    }

    public static func make(
        fact: NormalizedEventFact,
        projection: SessionProjection,
        semanticClass: AlertCandidateClass,
        origin: AlertCandidateOrigin = .normal,
        configuredLabel: String? = nil,
        reducerAccepted: Bool = true,
        sourceRevision: Int64? = nil
    ) -> Result<AlertCandidate, AlertCandidateRejectionReason> {
        make(from: AlertCandidateEvidence(fact: fact, projection: projection, semanticClass: semanticClass, origin: origin, configuredLabel: configuredLabel, reducerAccepted: reducerAccepted, sourceRevision: sourceRevision))
    }
}

public typealias AlertCandidateBuilder = AlertCandidateFactory

public enum AlertCandidateIngestResult: Sendable, Equatable {
    case accepted(AlertCandidate)
    case updated(AlertCandidate)
    case duplicate(AlertCandidate)
    case rejected(AlertCandidateRejectionReason)
}

public struct RedactedAlertCandidateDiagnostic: Codable, Hashable, Sendable, Equatable {
    public let candidateID: String?
    public let semanticClass: AlertCandidateClass?
    public let reason: AlertCandidateRejectionReason

    public init(candidateID: String? = nil, semanticClass: AlertCandidateClass? = nil, reason: AlertCandidateRejectionReason) {
        self.candidateID = candidateID.map { String($0.prefix(256)) }
        self.semanticClass = semanticClass
        self.reason = reason
    }
}

/// A replay-safe, bounded candidate ledger.  It is a local derived view and
/// never resolves requests or mutates Product lifecycle.
public struct AlertCandidateLedger: Codable, Hashable, Sendable, Equatable {
    private var values: [AlertCandidateID: AlertCandidate] = [:]
    private var diagnosticsValue: [RedactedAlertCandidateDiagnostic] = []

    public init(candidates: [AlertCandidate] = []) {
        for candidate in candidates { values[candidate.id] = candidate }
    }

    public var candidates: [AlertCandidate] {
        values.values.sorted {
            if $0.semanticClass.priority != $1.semanticClass.priority { return $0.semanticClass.priority > $1.semanticClass.priority }
            if $0.sourceObservedAt != $1.sourceObservedAt { return $0.sourceObservedAt < $1.sourceObservedAt }
            return $0.id.description < $1.id.description
        }
    }

    public var diagnostics: [RedactedAlertCandidateDiagnostic] { diagnosticsValue }

    public func candidate(for id: AlertCandidateID) -> AlertCandidate? { values[id] }

    public mutating func ingest(_ evidence: AlertCandidateEvidence) -> AlertCandidateIngestResult {
        switch AlertCandidate.make(from: evidence) {
        case .failure(let reason):
            diagnosticsValue.append(.init(semanticClass: evidence.semanticClass, reason: reason))
            diagnosticsValue = Array(diagnosticsValue.suffix(64))
            return .rejected(reason)
        case .success(let candidate):
            guard let existing = values[candidate.id] else {
                values[candidate.id] = candidate
                return .accepted(candidate)
            }
            guard candidate.sourceRevision >= existing.sourceRevision else {
                diagnosticsValue.append(.init(candidateID: candidate.id.description, semanticClass: candidate.semanticClass, reason: .staleRevision))
                diagnosticsValue = Array(diagnosticsValue.suffix(64))
                return .rejected(.staleRevision)
            }
            guard candidate.sourceRevision != existing.sourceRevision else { return .duplicate(existing) }
            values[candidate.id] = candidate
            return .updated(candidate)
        }
    }
}
