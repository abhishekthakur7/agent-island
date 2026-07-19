import Foundation

/// Redacted rejection reasons only. No raw payload, path, or identifier is
/// ever attached — these values are safe to place directly in diagnostics.
public enum EnvelopeValidationError: String, Sendable, Equatable, Codable, CaseIterable {
    case unknownNegotiationSnapshot
    case incompatibleContractMajor
    case capabilityNotGranted
    case missingOrAmbiguousOwnerIdentity
    case missingEventIdentity
    case malformedShape
    case payloadTooLarge
    case interactionContentUnsupported
}

public enum ValidationResult: Sendable {
    case accepted(NormalizedEventFact)
    case rejected(EnvelopeValidationError)
}

/// Pure validation: contract/version compatibility, source and owner
/// identity, payload size/shape, capability provenance, and classification —
/// every gate the AB-118 acceptance criteria require before a fact is
/// accepted. Calls no clock, ID generator, or I/O; `receiptTime` is supplied
/// by the trusted boundary that invoked delivery, never by the envelope
/// itself.
public enum SessionDomainValidator {
    public static let supportedContractMajor = 1
    public static let maxPayloadBytes = 64 * 1024

    public static func validate(
        _ envelope: RawEventEnvelope,
        negotiation: NegotiationSnapshot?,
        receiptTime: Date
    ) -> ValidationResult {
        guard let negotiation, negotiation.id == envelope.negotiationSnapshotID else {
            return .rejected(.unknownNegotiationSnapshot)
        }
        guard
            envelope.contractVersion.major == supportedContractMajor,
            negotiation.contractVersion.major == supportedContractMajor
        else {
            return .rejected(.incompatibleContractMajor)
        }
        guard negotiation.grants(WellKnownCapability.sessionObservation, direction: .observe) else {
            return .rejected(.capabilityNotGranted)
        }
        guard envelope.payloadByteSize >= 0, envelope.payloadByteSize <= maxPayloadBytes else {
            return .rejected(.payloadTooLarge)
        }
        guard envelope.classification == .operationalMetadata else {
            return .rejected(.interactionContentUnsupported)
        }
        guard
            let rawNamespace = envelope.productNamespace,
            !rawNamespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let rawSessionID = envelope.nativeSessionID,
            !rawSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .rejected(.missingOrAmbiguousOwnerIdentity)
        }
        guard negotiation.productNamespace.rawValue == rawNamespace else {
            return .rejected(.missingOrAmbiguousOwnerIdentity)
        }
        guard let eventIdentity = envelope.eventIdentity, !eventIdentity.isBlank else {
            return .rejected(.missingEventIdentity)
        }
        switch envelope.family {
        case .sessionDeclared:
            break
        case .sessionActivity:
            guard envelope.activityKind != nil else { return .rejected(.malformedShape) }
        case .observationBoundary:
            guard envelope.boundaryReason != nil else { return .rejected(.malformedShape) }
        case .turnDeclared:
            guard envelope.ownership?.nativeTurnID != nil else { return .rejected(.malformedShape) }
        case .subagentRunDeclared:
            guard envelope.ownership?.nativeSubagentRunID != nil else { return .rejected(.malformedShape) }
        case .turnLineage:
            guard envelope.ownership?.nativeTurnID != nil, envelope.turnLineage != nil else { return .rejected(.malformedShape) }
        case .attentionRequest:
            guard envelope.ownership?.nativeAttentionRequestID != nil, envelope.attentionKind != nil else { return .rejected(.malformedShape) }
        case .reconciliation:
            guard envelope.reconciliationScope != nil else { return .rejected(.malformedShape) }
        }

        let identity = AgentSessionIdentity(
            productNamespace: ProductNamespace(rawNamespace),
            nativeSessionID: NativeSessionID(rawSessionID)
        )
        let fact = NormalizedEventFact(
            receiptOrdinal: 0,
            identity: identity,
            integrationInstanceID: envelope.integrationInstanceID,
            negotiationSnapshotID: envelope.negotiationSnapshotID,
            eventIdentity: eventIdentity,
            family: envelope.family,
            sourceVariant: envelope.sourceVariant,
            activityKind: envelope.activityKind,
            boundaryReason: envelope.boundaryReason,
            classification: envelope.classification,
            occurrenceTime: envelope.occurrenceTime,
            receiptTime: receiptTime,
            displayTitle: envelope.displayTitle,
            hostLabel: envelope.hostLabel,
            sourceCursor: envelope.sourceCursor,
            ownership: envelope.ownership,
            turnLineage: envelope.turnLineage,
            attentionKind: envelope.attentionKind,
            reconciliationScope: envelope.reconciliationScope
        )
        return .accepted(fact)
    }
}
