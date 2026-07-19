import Foundation

/// Event identity per the immutable-fact ADR: a stable Product-native
/// source-event ID is authoritative; a `weak` Adapter-declared key is
/// explicitly documented as weaker evidence that only suppresses duplicate
/// delivery of the same observation.
public enum EventIdentity: Hashable, Sendable, Codable {
    case stable(String)
    case weak(String)

    var isBlank: Bool {
        switch self {
        case .stable(let value), .weak(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public enum PayloadClassification: String, Sendable, Codable {
    case operationalMetadata
    case interactionContent
}

/// Deliberately narrower than Product event names. Only the families needed
/// for an observation-only vertical slice exist here.
public enum EventFamily: String, Sendable, Codable {
    case observationBoundary
    case sessionDeclared
    case sessionActivity
    case turnDeclared
    case turnLineage
    case subagentRunDeclared
    case attentionRequest
    case reconciliation
}

public enum SessionActivityKind: String, Sendable, Codable {
    case started
    case working
    case waiting
    case completed
    case failed
    case stopped
}

public enum ObservationBoundaryReason: String, Sendable, Codable {
    case transportLost
    case integrationStopped
}

/// Product ordering evidence. Receipt ordinal is deliberately not represented
/// here: it is an audit coordinate and cannot create lifecycle truth.
public struct SourceCursor: Hashable, Sendable, Codable {
    public let scope: String
    public let value: Int64

    public init(scope: String, value: Int64) {
        self.scope = scope
        self.value = value
    }
}

public enum TurnLineageKind: String, Sendable, Codable {
    case current
    case historical
    case ambiguous
}

public enum AttentionRequestKind: String, Sendable, Codable {
    case opened
    case resolved
}

/// A documented reconciliation has authority only within this explicit
/// scope. Omission from a non-exhaustive list is not Product lifecycle truth.
public enum ReconciliationScope: String, Sendable, Codable {
    case authoritativeExhaustive
    case nonExhaustive
    case continuityUnavailable
}

/// Native ownership identifiers supplied by the Agent Product. They are
/// optional because a session-level fact need not name a Turn or child, but
/// none may be invented from presentation data.
public struct LifecycleOwnership: Hashable, Sendable, Codable {
    public let nativeTurnID: String?
    public let replacedNativeTurnID: String?
    public let nativeSubagentRunID: String?
    public let nativeAttentionRequestID: String?

    public init(
        nativeTurnID: String? = nil,
        replacedNativeTurnID: String? = nil,
        nativeSubagentRunID: String? = nil,
        nativeAttentionRequestID: String? = nil
    ) {
        self.nativeTurnID = nativeTurnID
        self.replacedNativeTurnID = replacedNativeTurnID
        self.nativeSubagentRunID = nativeSubagentRunID
        self.nativeAttentionRequestID = nativeAttentionRequestID
    }
}

/// The untrusted envelope an Adapter (or fixture) submits through the typed
/// intake port. Every field is data the boundary must validate before a fact
/// is ever appended; `SessionDomain` treats none of it as trusted until
/// `SessionDomainValidator.validate` accepts it.
public struct RawEventEnvelope: Sendable {
    public let negotiationSnapshotID: NegotiationSnapshotID
    public let integrationInstanceID: IntegrationInstanceID
    public let contractVersion: ContractVersion
    public let productNamespace: String?
    public let nativeSessionID: String?
    public let eventIdentity: EventIdentity?
    public let family: EventFamily
    public let sourceVariant: String
    public let activityKind: SessionActivityKind?
    public let boundaryReason: ObservationBoundaryReason?
    public let classification: PayloadClassification
    public let payloadByteSize: Int
    public let occurrenceTime: Date?
    public let displayTitle: String?
    public let hostLabel: String?
    public let sourceCursor: SourceCursor?
    public let ownership: LifecycleOwnership?
    public let turnLineage: TurnLineageKind?
    public let attentionKind: AttentionRequestKind?
    public let reconciliationScope: ReconciliationScope?

    public init(
        negotiationSnapshotID: NegotiationSnapshotID,
        integrationInstanceID: IntegrationInstanceID,
        contractVersion: ContractVersion,
        productNamespace: String?,
        nativeSessionID: String?,
        eventIdentity: EventIdentity?,
        family: EventFamily,
        sourceVariant: String,
        activityKind: SessionActivityKind? = nil,
        boundaryReason: ObservationBoundaryReason? = nil,
        classification: PayloadClassification,
        payloadByteSize: Int,
        occurrenceTime: Date? = nil,
        displayTitle: String? = nil,
        hostLabel: String? = nil,
        sourceCursor: SourceCursor? = nil,
        ownership: LifecycleOwnership? = nil,
        turnLineage: TurnLineageKind? = nil,
        attentionKind: AttentionRequestKind? = nil,
        reconciliationScope: ReconciliationScope? = nil
    ) {
        self.negotiationSnapshotID = negotiationSnapshotID
        self.integrationInstanceID = integrationInstanceID
        self.contractVersion = contractVersion
        self.productNamespace = productNamespace
        self.nativeSessionID = nativeSessionID
        self.eventIdentity = eventIdentity
        self.family = family
        self.sourceVariant = sourceVariant
        self.activityKind = activityKind
        self.boundaryReason = boundaryReason
        self.classification = classification
        self.payloadByteSize = payloadByteSize
        self.occurrenceTime = occurrenceTime
        self.displayTitle = displayTitle
        self.hostLabel = hostLabel
        self.sourceCursor = sourceCursor
        self.ownership = ownership
        self.turnLineage = turnLineage
        self.attentionKind = attentionKind
        self.reconciliationScope = reconciliationScope
    }
}

/// One accepted, validated, immutable Normalized Event Fact. `receiptOrdinal`
/// is assigned by `SessionStore` at commit time and is the only field this
/// type receives after acceptance; everything else is fixed at validation.
public struct NormalizedEventFact: Hashable, Sendable, Codable {
    public let receiptOrdinal: Int64
    public let identity: AgentSessionIdentity
    public let integrationInstanceID: IntegrationInstanceID
    public let negotiationSnapshotID: NegotiationSnapshotID
    public let eventIdentity: EventIdentity
    public let family: EventFamily
    public let sourceVariant: String
    public let activityKind: SessionActivityKind?
    public let boundaryReason: ObservationBoundaryReason?
    public let classification: PayloadClassification
    public let occurrenceTime: Date?
    public let receiptTime: Date
    public let displayTitle: String?
    public let hostLabel: String?
    public let sourceCursor: SourceCursor?
    public let ownership: LifecycleOwnership?
    public let turnLineage: TurnLineageKind?
    public let attentionKind: AttentionRequestKind?
    public let reconciliationScope: ReconciliationScope?

    public init(
        receiptOrdinal: Int64,
        identity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        negotiationSnapshotID: NegotiationSnapshotID,
        eventIdentity: EventIdentity,
        family: EventFamily,
        sourceVariant: String,
        activityKind: SessionActivityKind?,
        boundaryReason: ObservationBoundaryReason?,
        classification: PayloadClassification,
        occurrenceTime: Date?,
        receiptTime: Date,
        displayTitle: String?,
        hostLabel: String?,
        sourceCursor: SourceCursor? = nil,
        ownership: LifecycleOwnership? = nil,
        turnLineage: TurnLineageKind? = nil,
        attentionKind: AttentionRequestKind? = nil,
        reconciliationScope: ReconciliationScope? = nil
    ) {
        self.receiptOrdinal = receiptOrdinal
        self.identity = identity
        self.integrationInstanceID = integrationInstanceID
        self.negotiationSnapshotID = negotiationSnapshotID
        self.eventIdentity = eventIdentity
        self.family = family
        self.sourceVariant = sourceVariant
        self.activityKind = activityKind
        self.boundaryReason = boundaryReason
        self.classification = classification
        self.occurrenceTime = occurrenceTime
        self.receiptTime = receiptTime
        self.displayTitle = displayTitle
        self.hostLabel = hostLabel
        self.sourceCursor = sourceCursor
        self.ownership = ownership
        self.turnLineage = turnLineage
        self.attentionKind = attentionKind
        self.reconciliationScope = reconciliationScope
    }

    public func withReceiptOrdinal(_ ordinal: Int64) -> NormalizedEventFact {
        NormalizedEventFact(
            receiptOrdinal: ordinal,
            identity: identity,
            integrationInstanceID: integrationInstanceID,
            negotiationSnapshotID: negotiationSnapshotID,
            eventIdentity: eventIdentity,
            family: family,
            sourceVariant: sourceVariant,
            activityKind: activityKind,
            boundaryReason: boundaryReason,
            classification: classification,
            occurrenceTime: occurrenceTime,
            receiptTime: receiptTime,
            displayTitle: displayTitle,
            hostLabel: hostLabel,
            sourceCursor: sourceCursor,
            ownership: ownership,
            turnLineage: turnLineage,
            attentionKind: attentionKind,
            reconciliationScope: reconciliationScope
        )
    }

    /// Priority-ordered fact identity used for idempotent commit: a stable
    /// source-event ID is scoped by Product namespace; a weak key is scoped
    /// by integration instance because it carries no Product-wide guarantee.
    public enum DeduplicationKey: Hashable, Sendable {
        case stable(productNamespace: ProductNamespace, sourceEventID: String)
        case weak(integrationInstanceID: IntegrationInstanceID, key: String)
    }

    public var deduplicationKey: DeduplicationKey {
        switch eventIdentity {
        case .stable(let value):
            return .stable(productNamespace: identity.productNamespace, sourceEventID: value)
        case .weak(let value):
            return .weak(integrationInstanceID: integrationInstanceID, key: value)
        }
    }
}
