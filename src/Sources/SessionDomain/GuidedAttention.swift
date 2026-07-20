import Foundation

/// The four visible steps in the Guided workflow.  A local stage is a
/// presentation concern and never changes the Product's source state.
public enum GuidedAttentionStage: String, Codable, Hashable, Sendable, CaseIterable {
    case arrived
    case review
    case respond
    case acknowledged

    public var title: String {
        switch self {
        case .arrived: "Arrived"
        case .review: "Review"
        case .respond: "Respond"
        case .acknowledged: "Acknowledged"
        }
    }
}

/// Product-provided priority.  Higher priority is shown first; the queue
/// uses source time and then the exact native identity as deterministic ties.
public enum AttentionPriority: Int, Codable, Hashable, Sendable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3
}

public enum GuidedSourceOutcome: String, Codable, Hashable, Sendable {
    case pending
    case resolvedElsewhere
    case unavailable
    case superseded
}

public enum GuidedLocalPresentation: String, Codable, Hashable, Sendable {
    case queued
    case presented
    case collapsed
    case acknowledged
}

public enum GuidedRoutingAvailability: String, Codable, Hashable, Sendable, Equatable {
    case available
    case observationOnly
    case stale
    case unavailable
}

/// Exact source ownership.  Product namespace and native request identity are
/// mandatory; optional turn identity is retained when the Product supplies it.
/// Integration and negotiation identities prevent a live route being borrowed
/// across installations or capability snapshots.
public struct GuidedAttentionOwner: Codable, Hashable, Sendable, Equatable {
    public let productNamespace: ProductNamespace
    public let nativeSessionID: NativeSessionID
    public let nativeAttentionRequestID: String
    public let nativeTurnID: String?
    public let integrationInstanceID: IntegrationInstanceID
    public let negotiationSnapshotID: NegotiationSnapshotID

    public init(
        productNamespace: ProductNamespace,
        nativeSessionID: NativeSessionID,
        nativeAttentionRequestID: String,
        nativeTurnID: String? = nil,
        integrationInstanceID: IntegrationInstanceID,
        negotiationSnapshotID: NegotiationSnapshotID
    ) {
        self.productNamespace = productNamespace
        self.nativeSessionID = nativeSessionID
        self.nativeAttentionRequestID = nativeAttentionRequestID
        self.nativeTurnID = nativeTurnID
        self.integrationInstanceID = integrationInstanceID
        self.negotiationSnapshotID = negotiationSnapshotID
    }

    public var sessionIdentity: AgentSessionIdentity {
        AgentSessionIdentity(productNamespace: productNamespace, nativeSessionID: nativeSessionID)
    }
}

/// Stable request identity.  It deliberately excludes title, Host, and text;
/// no similarity or presentation data can merge two native requests.
public struct GuidedAttentionRequestID: Codable, Hashable, Sendable, Equatable, Identifiable {
    public let productNamespace: ProductNamespace
    public let nativeSessionID: NativeSessionID
    public let nativeAttentionRequestID: String

    public init(productNamespace: ProductNamespace, nativeSessionID: NativeSessionID, nativeAttentionRequestID: String) {
        self.productNamespace = productNamespace
        self.nativeSessionID = nativeSessionID
        self.nativeAttentionRequestID = nativeAttentionRequestID
    }

    /// Compatibility convenience for callers that only have request identity.
    /// New source evidence always uses the exact session-scoped initializer.
    public init(productNamespace: ProductNamespace, nativeAttentionRequestID: String) {
        self.init(productNamespace: productNamespace, nativeSessionID: NativeSessionID(""), nativeAttentionRequestID: nativeAttentionRequestID)
    }

    public var id: String { "\(productNamespace.rawValue)::\(nativeSessionID.rawValue)::\(nativeAttentionRequestID)" }
}

public struct GuidedChoice: Codable, Hashable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    /// A recommendation is source evidence only.  It is never a selection.
    public let recommended: Bool

    public init(id: String, label: String, recommended: Bool = false) {
        self.id = id
        self.label = label
        self.recommended = recommended
    }
}

public enum GuidedSemanticKind: String, Codable, Hashable, Sendable, CaseIterable {
    case allowDeny
    case persistentSuggestion
    case structuredChoice
    case planReview
    case turnInput
    case interruption
    case productExtension
}

/// A closed, source-supported response shape.  The shape contains no generic
/// "execute" or terminal-input operation.  Choices start with an empty
/// selection even when one is marked recommended by the Product.
public struct GuidedSemanticShape: Codable, Hashable, Sendable, Equatable {
    public let kind: GuidedSemanticKind
    public let choices: [GuidedChoice]
    public let allowsMultipleSelection: Bool
    public let supportsFreeText: Bool
    public let minimumSelections: Int
    public let maximumSelections: Int?
    public let requiresConfirmation: Bool
    public let extensionNamespace: String?

    public init(
        kind: GuidedSemanticKind,
        choices: [GuidedChoice] = [],
        allowsMultipleSelection: Bool = false,
        supportsFreeText: Bool = false,
        minimumSelections: Int = 0,
        maximumSelections: Int? = nil,
        requiresConfirmation: Bool = true,
        extensionNamespace: String? = nil
    ) {
        self.kind = kind
        self.choices = choices
        self.allowsMultipleSelection = allowsMultipleSelection
        self.supportsFreeText = supportsFreeText
        self.minimumSelections = max(0, minimumSelections)
        self.maximumSelections = maximumSelections
        self.requiresConfirmation = requiresConfirmation
        self.extensionNamespace = extensionNamespace
    }

    public var isSourceSupported: Bool {
        guard minimumSelections >= 0,
              maximumSelections.map({ $0 >= minimumSelections }) ?? true,
              choices.map(\.id).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(choices.map(\.id)).count == choices.count
        else { return false }

        switch kind {
        case .allowDeny, .persistentSuggestion:
            return choices.isEmpty && !supportsFreeText
        case .structuredChoice:
            return !choices.isEmpty && minimumSelections > 0 && (maximumSelections ?? Int.max) >= minimumSelections
        case .planReview:
            return choices.isEmpty && !supportsFreeText
        case .turnInput, .interruption:
            return supportsFreeText && choices.isEmpty
        case .productExtension:
            return extensionNamespace?.isEmpty == false
        }
    }

    public static let allowDeny = Self(kind: .allowDeny)
    public static let persistentSuggestion = Self(kind: .persistentSuggestion)
    public static func structuredChoice(
        _ choices: [GuidedChoice],
        allowsMultipleSelection: Bool = false,
        minimumSelections: Int = 1,
        maximumSelections: Int? = nil
    ) -> Self {
        Self(kind: .structuredChoice, choices: choices, allowsMultipleSelection: allowsMultipleSelection, minimumSelections: minimumSelections, maximumSelections: maximumSelections)
    }
}

public struct GuidedAttentionConstraints: Codable, Hashable, Sendable, Equatable {
    public let requiresConfirmation: Bool
    public let maxDraftBytes: Int
    public let nativeFingerprint: String

    public init(requiresConfirmation: Bool = true, maxDraftBytes: Int = 64 * 1024, nativeFingerprint: String) {
        self.requiresConfirmation = requiresConfirmation
        self.maxDraftBytes = max(0, maxDraftBytes)
        self.nativeFingerprint = nativeFingerprint
    }
}

/// Local draft state is independent from source resolution and local
/// acknowledgement.  Empty selections are intentional and preserve the
/// absence of a default response.
public struct GuidedAttentionDraft: Codable, Hashable, Sendable, Equatable {
    public let selectedChoiceIDs: [String]
    public let freeText: String?
    public let questionIndex: Int

    public init(selectedChoiceIDs: [String] = [], freeText: String? = nil, questionIndex: Int = 0) {
        self.selectedChoiceIDs = selectedChoiceIDs
        self.freeText = freeText
        self.questionIndex = max(0, questionIndex)
    }

    public static let empty = Self()
}

/// Source-proven evidence accepted by the attention ledger.  Interaction
/// Content is intentionally refused: an adapter must provide a classified,
/// metadata-only request summary and semantic shape.
public struct GuidedAttentionEvidence: Codable, Hashable, Sendable, Equatable {
    public let owner: GuidedAttentionOwner
    public let eventIdentity: EventIdentity
    public let sourceVariant: String
    public let capability: CapabilityRecord
    public let semanticShape: GuidedSemanticShape
    public let constraints: GuidedAttentionConstraints
    public let classification: PayloadClassification
    public let sourceObservedAt: Date
    public let priority: AttentionPriority
    public let displayTitle: String?
    public let hostLabel: String?
    public let sourceContext: String?

    public init(
        owner: GuidedAttentionOwner,
        eventIdentity: EventIdentity,
        sourceVariant: String,
        capability: CapabilityRecord,
        semanticShape: GuidedSemanticShape,
        constraints: GuidedAttentionConstraints,
        classification: PayloadClassification = .operationalMetadata,
        sourceObservedAt: Date,
        priority: AttentionPriority = .normal,
        displayTitle: String? = nil,
        hostLabel: String? = nil,
        sourceContext: String? = nil
    ) {
        self.owner = owner
        self.eventIdentity = eventIdentity
        self.sourceVariant = sourceVariant
        self.capability = capability
        self.semanticShape = semanticShape
        self.constraints = constraints
        self.classification = classification
        self.sourceObservedAt = sourceObservedAt
        self.priority = priority
        self.displayTitle = displayTitle
        self.hostLabel = hostLabel
        self.sourceContext = sourceContext
    }

    public var requestID: GuidedAttentionRequestID {
        GuidedAttentionRequestID(productNamespace: owner.productNamespace, nativeSessionID: owner.nativeSessionID, nativeAttentionRequestID: owner.nativeAttentionRequestID)
    }
}

public struct GuidedAttentionRequest: Codable, Hashable, Sendable, Equatable, Identifiable {
    public let id: GuidedAttentionRequestID
    public let owner: GuidedAttentionOwner
    public let sourceEventIdentity: EventIdentity
    public let sourceVariant: String
    public let capability: CapabilityRecord
    public let semanticShape: GuidedSemanticShape
    public let constraints: GuidedAttentionConstraints
    public let classification: PayloadClassification
    public let sourceObservedAt: Date
    public let priority: AttentionPriority
    public let displayTitle: String?
    public let hostLabel: String?
    public let sourceContext: String?
    public var sourceOutcome: GuidedSourceOutcome
    public var localPresentation: GuidedLocalPresentation
    public var stage: GuidedAttentionStage
    public var draft: GuidedAttentionDraft
    public var lastSourceFingerprint: String

    public init(evidence: GuidedAttentionEvidence) {
        id = evidence.requestID
        owner = evidence.owner
        sourceEventIdentity = evidence.eventIdentity
        sourceVariant = evidence.sourceVariant
        capability = evidence.capability
        semanticShape = evidence.semanticShape
        constraints = evidence.constraints
        classification = evidence.classification
        sourceObservedAt = evidence.sourceObservedAt
        priority = evidence.priority
        displayTitle = evidence.displayTitle
        hostLabel = evidence.hostLabel
        sourceContext = evidence.sourceContext
        sourceOutcome = .pending
        localPresentation = .queued
        stage = .arrived
        draft = .empty
        lastSourceFingerprint = evidence.constraints.nativeFingerprint
    }

    public var sessionIdentity: AgentSessionIdentity { owner.sessionIdentity }

    public var routingAvailability: GuidedRoutingAvailability {
        guard capability.direction == .act else { return .observationOnly }
        guard capability.availability == .available, capability.freshness == .current else { return .stale }
        return .available
    }

    public var canRouteAction: Bool { routingAvailability == .available }
}

/// Canonical glossary-friendly aliases for adapter and presentation ports.
public typealias AttentionRequestRecord = GuidedAttentionRequest
public typealias AttentionRequestRecordID = GuidedAttentionRequestID

public enum GuidedAttentionIngestRejection: String, Codable, Hashable, Sendable, Error {
    case missingOwner
    case missingStableEventIdentity
    case crossOwnerEventIdentity
    case interactionContentUnsupported
    case unsupportedSemanticShape
    case capabilityNotGranted
    case malformedSourceMetadata
}

public enum GuidedAttentionIngestResult: Sendable, Equatable {
    case accepted(GuidedAttentionRequest)
    case duplicate(GuidedAttentionRequest)
    case rejected(GuidedAttentionIngestRejection)
}

/// Deterministic local queue.  It is deliberately independent of SwiftUI and
/// can be replayed from a protected snapshot without source similarity logic.
public struct GuidedAttentionQueue: Codable, Hashable, Sendable, Equatable {
    private var requestsByID: [GuidedAttentionRequestID: GuidedAttentionRequest] = [:]
    private var ownerByEvent: [EventIdentity: GuidedAttentionOwner] = [:]

    public init() {}

    public var requests: [GuidedAttentionRequest] {
        requestsByID.values.sorted(by: Self.isHigherPriority)
    }

    public func request(for id: GuidedAttentionRequestID) -> GuidedAttentionRequest? { requestsByID[id] }

    public mutating func ingest(_ evidence: GuidedAttentionEvidence) -> GuidedAttentionIngestResult {
        guard !evidence.owner.nativeAttentionRequestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !evidence.owner.nativeSessionID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !evidence.owner.productNamespace.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .rejected(.missingOwner) }
        guard case .stable(let sourceID) = evidence.eventIdentity,
              !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .rejected(.missingStableEventIdentity) }
        guard evidence.classification == .operationalMetadata else { return .rejected(.interactionContentUnsupported) }
        guard evidence.semanticShape.isSourceSupported else { return .rejected(.unsupportedSemanticShape) }
        guard evidence.capability.provenance?.integrationInstanceID == evidence.owner.integrationInstanceID,
              evidence.capability.provenance?.productNamespace == evidence.owner.productNamespace,
              evidence.capability.provenance?.snapshotID == evidence.owner.negotiationSnapshotID
        else { return .rejected(.capabilityNotGranted) }
        guard evidence.sourceVariant.utf8.count <= SessionDomainValidator.maxMetadataStringBytes,
              evidence.displayTitle?.utf8.count ?? 0 <= SessionDomainValidator.maxMetadataStringBytes,
              evidence.hostLabel?.utf8.count ?? 0 <= SessionDomainValidator.maxMetadataStringBytes,
              evidence.sourceContext?.utf8.count ?? 0 <= SessionDomainValidator.maxMetadataStringBytes,
              evidence.constraints.maxDraftBytes <= SessionDomainValidator.maxPayloadBytes
        else { return .rejected(.malformedSourceMetadata) }

        let id = evidence.requestID
        if let priorOwner = ownerByEvent[evidence.eventIdentity], priorOwner != evidence.owner {
            return .rejected(.crossOwnerEventIdentity)
        }
        if let existing = requestsByID.values.first(where: { $0.sourceEventIdentity == evidence.eventIdentity }) {
            return .duplicate(existing)
        }
        if let existing = requestsByID[id] {
            guard existing.owner == evidence.owner else { return .rejected(.crossOwnerEventIdentity) }
            return .duplicate(existing)
        }
        let request = GuidedAttentionRequest(evidence: evidence)
        requestsByID[id] = request
        ownerByEvent[evidence.eventIdentity] = evidence.owner
        return .accepted(request)
    }

    @discardableResult
    public mutating func updateSource(_ id: GuidedAttentionRequestID, outcome: GuidedSourceOutcome, fingerprint: String? = nil) -> Bool {
        guard var request = requestsByID[id] else { return false }
        request.sourceOutcome = outcome
        if let fingerprint { request.lastSourceFingerprint = fingerprint }
        requestsByID[id] = request
        return true
    }

    @discardableResult
    public mutating func setLocalPresentation(_ id: GuidedAttentionRequestID, _ presentation: GuidedLocalPresentation) -> Bool {
        guard var request = requestsByID[id] else { return false }
        request.localPresentation = presentation
        requestsByID[id] = request
        return true
    }

    @discardableResult
    public mutating func setStage(_ id: GuidedAttentionRequestID, _ stage: GuidedAttentionStage) -> Bool {
        guard var request = requestsByID[id] else { return false }
        request.stage = stage
        requestsByID[id] = request
        return true
    }

    @discardableResult
    public mutating func updateDraft(_ id: GuidedAttentionRequestID, _ draft: GuidedAttentionDraft) -> Bool {
        guard var request = requestsByID[id], draft.freeText?.utf8.count ?? 0 <= request.constraints.maxDraftBytes else { return false }
        request.draft = draft
        requestsByID[id] = request
        return true
    }

    public mutating func acknowledgeLocally(_ id: GuidedAttentionRequestID) -> Bool {
        guard var request = requestsByID[id] else { return false }
        request.localPresentation = .acknowledged
        request.stage = .acknowledged
        requestsByID[id] = request
        return true
    }

    private static func isHigherPriority(_ lhs: GuidedAttentionRequest, _ rhs: GuidedAttentionRequest) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        if lhs.sourceObservedAt != rhs.sourceObservedAt { return lhs.sourceObservedAt < rhs.sourceObservedAt }
        return lhs.id.id < rhs.id.id
    }
}

public extension GuidedAttentionDraft {
    func validating(against shape: GuidedSemanticShape) -> Result<Void, GuidedActionValidationError> {
        guard shape.isSourceSupported else { return .failure(.unsupportedSemanticShape) }
        let unique = Set(selectedChoiceIDs)
        guard unique.count == selectedChoiceIDs.count,
              selectedChoiceIDs.allSatisfy({ selectedID in shape.choices.contains { $0.id == selectedID } })
        else { return .failure(.invalidSelection) }
        if !shape.allowsMultipleSelection, selectedChoiceIDs.count > 1 { return .failure(.invalidSelection) }
        guard selectedChoiceIDs.count >= shape.minimumSelections,
              shape.maximumSelections.map({ selectedChoiceIDs.count <= $0 }) ?? true
        else { return .failure(.incompleteResponse) }
        if !shape.supportsFreeText, freeText?.isEmpty == false { return .failure(.unsupportedFreeText) }
        if shape.supportsFreeText, shape.kind == .turnInput || shape.kind == .interruption, freeText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return .failure(.incompleteResponse)
        }
        return .success(())
    }
}
