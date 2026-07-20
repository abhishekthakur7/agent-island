import Foundation

public struct GuidedStructuredResponse: Codable, Hashable, Sendable, Equatable {
    public let selectedChoiceIDs: [String]
    public let freeText: String?

    public init(selectedChoiceIDs: [String] = [], freeText: String? = nil) {
        self.selectedChoiceIDs = selectedChoiceIDs
        self.freeText = freeText
    }
}

public enum GuidedPlanDecision: String, Codable, Hashable, Sendable, CaseIterable {
    case accept
    case reject
}

public struct GuidedProductExtensionAction: Codable, Hashable, Sendable, Equatable {
    public let namespace: String
    public let name: String
    public let metadata: [String: String]

    public init(namespace: String, name: String, metadata: [String: String] = [:]) {
        self.namespace = namespace
        self.name = name
        self.metadata = metadata
    }
}

/// Typed actions only.  There is intentionally no generic command or
/// terminal-injection case; a Product must advertise a matching semantic
/// shape before one of these values can reach dispatch.
public enum GuidedAction: Codable, Hashable, Sendable, Equatable {
    case allow
    case deny
    case persistentSuggestion(allow: Bool)
    case structuredResponse(GuidedStructuredResponse)
    case planReview(GuidedPlanDecision, reason: String?)
    case turnInput(String)
    case interruption
    case productExtension(GuidedProductExtensionAction)

    public var semanticKind: GuidedSemanticKind {
        switch self {
        case .allow, .deny: .allowDeny
        case .persistentSuggestion: .persistentSuggestion
        case .structuredResponse: .structuredChoice
        case .planReview: .planReview
        case .turnInput: .turnInput
        case .interruption: .interruption
        case .productExtension: .productExtension
        }
    }
}

public enum GuidedActionValidationError: String, Codable, Hashable, Sendable, Equatable, Error {
    case unsupportedSemanticShape
    case invalidSelection
    case incompleteResponse
    case unsupportedFreeText
    case missingConfirmation
    case sourceResolved
    case capabilityUnavailable
    case ownerMismatch
    case fingerprintMismatch
    case gateClosed
}

public extension GuidedAction {
    func validating(against request: GuidedAttentionRequest, confirmation: Bool = true) -> Result<Void, GuidedActionValidationError> {
        guard request.semanticShape.isSourceSupported,
              request.semanticShape.kind == semanticKind
        else { return .failure(.unsupportedSemanticShape) }
        guard request.sourceOutcome == .pending else { return .failure(.sourceResolved) }
        guard confirmation || !(request.semanticShape.requiresConfirmation || request.constraints.requiresConfirmation) else { return .failure(.missingConfirmation) }

        switch self {
        case .allow, .deny, .persistentSuggestion, .interruption:
            return .success(())
        case .structuredResponse(let response):
            return GuidedAttentionDraft(selectedChoiceIDs: response.selectedChoiceIDs, freeText: response.freeText).validating(against: request.semanticShape)
        case .planReview(let decision, let reason):
            if decision == .reject, reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                return .failure(.incompleteResponse)
            }
            return .success(())
        case .turnInput(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.incompleteResponse) }
            return .success(())
        case .productExtension(let action):
            guard action.namespace == request.semanticShape.extensionNamespace else { return .failure(.unsupportedSemanticShape) }
            return .success(())
        }
    }
}

public enum ActionAttemptOutcome: String, Codable, Hashable, Sendable, Equatable, CaseIterable {
    case reserved
    case dispatching
    case rejected
    case acceptedByProduct
    case applied
    case superseded
    case indeterminate
}

public struct ActionAttempt: Codable, Hashable, Sendable, Equatable, Identifiable {
    public let id: String
    public let requestID: GuidedAttentionRequestID
    public let owner: GuidedAttentionOwner
    public let action: GuidedAction
    /// The lease ID is operational metadata and is never exposed by redacted
    /// diagnostics; it is retained here only to correlate one reservation.
    public let leaseID: String?
    public let reservedAt: Date
    public var outcome: ActionAttemptOutcome
    public var rejectionReason: ActionAttemptRejectionReason?
    public var dispatchCount: Int
    public var completedAt: Date?
    public var productEvidence: String?

    public init(
        id: String,
        requestID: GuidedAttentionRequestID,
        owner: GuidedAttentionOwner,
        action: GuidedAction,
        leaseID: String?,
        reservedAt: Date,
        outcome: ActionAttemptOutcome = .reserved,
        rejectionReason: ActionAttemptRejectionReason? = nil,
        dispatchCount: Int = 0,
        completedAt: Date? = nil,
        productEvidence: String? = nil
    ) {
        self.id = id
        self.requestID = requestID
        self.owner = owner
        self.action = action
        self.leaseID = leaseID
        self.reservedAt = reservedAt
        self.outcome = outcome
        self.rejectionReason = rejectionReason
        self.dispatchCount = dispatchCount
        self.completedAt = completedAt
        self.productEvidence = productEvidence
    }

    public var isTerminal: Bool {
        switch outcome {
        case .reserved, .dispatching: false
        case .rejected, .acceptedByProduct, .applied, .superseded, .indeterminate: true
        }
    }
}

public enum ActionAttemptRejectionReason: String, Codable, Hashable, Sendable, Equatable, Error, CaseIterable {
    case unknownRequest
    case duplicateAttempt
    case ownerMismatch
    case sourceResolved
    case sourceChanged
    case staleLease
    case expiredLease
    case capabilityMismatch
    case capabilityUnavailable
    case gateClosed
    case invalidSemanticResponse
    case missingConfirmation
    case alreadyDispatched
    case disconnected
    case restarted
    case wake
    case persistenceUnavailable
}

public enum ActionAttemptReservationResult: Sendable, Equatable {
    case reserved(ActionAttempt)
    case rejected(ActionAttempt)
    case duplicate(ActionAttempt)
}

public enum ActionDispatchPreparation: Sendable, Equatable {
    case dispatch(GuidedAction)
    case rejected(ActionAttempt)
}

public enum ActionAttemptTransitionResult: Sendable, Equatable {
    case updated(ActionAttempt)
    case rejected(ActionAttempt)
}

/// Product feedback after the one typed dispatch.  `indeterminate` is a
/// first-class result and is never retried by the local store.
public enum ActionProductOutcome: String, Codable, Hashable, Sendable, Equatable {
    case rejected
    case acceptedByProduct
    case applied
    case superseded
    case indeterminate
}

public struct RedactedActionAttemptDiagnostic: Codable, Hashable, Sendable, Equatable {
    public let attemptID: String
    public let requestID: String
    public let outcome: ActionAttemptOutcome
    public let dispatchCount: Int
    public let reason: ActionAttemptRejectionReason?

    public init(attempt: ActionAttempt) {
        self.attemptID = attempt.id
        self.requestID = attempt.requestID.id
        self.outcome = attempt.outcome
        self.dispatchCount = attempt.dispatchCount
        self.reason = attempt.rejectionReason
    }
}
