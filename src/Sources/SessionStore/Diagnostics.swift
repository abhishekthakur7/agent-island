import Foundation
import SessionDomain

/// A redacted, in-memory operational diagnostic record. Never carries
/// Interaction Content, credentials, raw external identifiers, paths, or
/// payloads — only stable reason codes and counts, matching the AB-118
/// privacy acceptance criterion.
public struct DiagnosticRecord: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case envelopeRejected
        case envelopeFiltered
        case envelopeQuarantined
        case envelopeDowngraded
        case duplicateDeliverySuppressed
        case factCommitted
        case storageFault
        case projectionCacheDiscarded
        case historyDeleted
        case capabilityUnavailable
        case capabilityDegraded
        case operationFailed
    }

    public let kind: Kind
    public let reason: EnvelopeValidationError?
    public let ledgerRevision: Int64?
    public let at: Date
    public let storageReason: StorageFailureReason?
    /// The AB-130 allowlisted projection. Legacy fields above remain for
    /// source compatibility with the intake slice; bundle/export code uses
    /// this structural record instead of parsing those fields.
    public let evidence: DiagnosticEvidence

    public init(
        kind: Kind,
        reason: EnvelopeValidationError?,
        ledgerRevision: Int64?,
        at: Date,
        storageReason: StorageFailureReason? = nil
    ) {
        self.kind = kind
        self.reason = reason
        self.ledgerRevision = ledgerRevision
        self.at = at
        self.storageReason = storageReason
        self.evidence = Self.legacyEvidence(kind: kind, reason: reason, at: at, storageReason: storageReason)
    }

    public init(
        kind: Kind,
        evidence: DiagnosticEvidence,
        ledgerRevision: Int64? = nil,
        storageReason: StorageFailureReason? = nil
    ) {
        self.kind = kind
        self.reason = nil
        self.ledgerRevision = ledgerRevision
        self.at = evidence.occurredAt
        self.storageReason = storageReason
        self.evidence = evidence
    }

    public var outcome: DiagnosticOutcome { evidence.outcome }
    public var scope: DiagnosticScope { evidence.scope }
    public var correlationID: DiagnosticCorrelationID { evidence.correlationID }
    public var health: DiagnosticHealthDimensions { evidence.health }
    public var safeNextStep: DiagnosticSafeNextStep { evidence.safeNextStep }

    private static func legacyEvidence(kind: Kind, reason: EnvelopeValidationError?, at date: Date, storageReason: StorageFailureReason?) -> DiagnosticEvidence {
        let mappedReason: DiagnosticReason = switch reason {
        case .unknownNegotiationSnapshot: .unknownNegotiation
        case .incompatibleContractMajor: .incompatibleContract
        case .capabilityNotGranted: .capabilityNotGranted
        case .missingOrAmbiguousOwnerIdentity, .crossOwnerProvenance: .ownerAmbiguous
        case .missingEventIdentity: .malformedInput
        case .malformedShape: .malformedInput
        case .payloadTooLarge: .payloadTooLarge
        case .interactionContentUnsupported: .interactionContentUnsupported
        case .staleCapability: .staleEvidence
        case .killSwitchClosed: .killSwitchClosed
        case nil:
            switch storageReason {
            case .integrityCheckFailed: .integrityFailure
            case .unsupportedSchema: .schemaFailure
            case .migrationFailed: .migrationFailure
            case .keychainKeyMissing, .interruptedWrite, .unavailable: .storageUnavailable
            case nil: .unknown
            }
        }
        let outcome: DiagnosticOutcome = switch kind {
        case .factCommitted: .accepted
        case .duplicateDeliverySuppressed, .projectionCacheDiscarded: .deduplicated
        case .envelopeRejected: .rejected
        case .envelopeFiltered: .filtered
        case .envelopeQuarantined: .quarantined
        case .envelopeDowngraded: .downgraded
        case .capabilityUnavailable: .unavailable
        case .capabilityDegraded: .degraded
        case .storageFault: .unavailable
        case .historyDeleted: .accepted
        case .operationFailed: .failed
        }
        let operation: DiagnosticOperation = switch outcome {
        case .accepted: .accept
        case .filtered: .filter
        case .deduplicated: .deduplicate
        case .quarantined: .quarantine
        case .downgraded: .downgrade
        case .rejected: .reject
        case .unavailable: .unavailable
        case .degraded: .degrade
        case .failed: .fail
        }
        let next: DiagnosticSafeNextStep = switch mappedReason {
        case .incompatibleContract: .update
        case .permissionDenied, .capabilityNotGranted, .configurationUnavailable: .inspect
        case .storageUnavailable, .integrityFailure, .schemaFailure, .migrationFailure: .preserveBytes
        default: .inspect
        }
        return DiagnosticEvidence(operation: operation, outcome: outcome, scope: DiagnosticScope(component: kind == .storageFault ? .storage : .intake, owner: kind == .storageFault ? .store : .integration, capability: kind == .storageFault ? .storage : .observation), reason: mappedReason, occurredAt: date, correlationID: .generated(), health: .unknown, safeNextStep: next)
    }
}
