import Foundation

/// Redacted rejection reasons only. No raw payload, path, or identifier is
/// ever attached — these values are safe to place directly in diagnostics.
public enum EnvelopeValidationError: String, Sendable, Equatable, Codable, CaseIterable, Error {
    case unknownNegotiationSnapshot
    case incompatibleContractMajor
    case capabilityNotGranted
    case missingOrAmbiguousOwnerIdentity
    case missingEventIdentity
    case malformedShape
    case payloadTooLarge
    case interactionContentUnsupported
    case crossOwnerProvenance
    case staleCapability
    case killSwitchClosed
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
    public static let maxMetadataStringBytes = 4 * 1024

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
        guard envelope.sourceVariant.utf8.count <= maxMetadataStringBytes,
              envelope.displayTitle?.utf8.count ?? 0 <= maxMetadataStringBytes,
              envelope.hostLabel?.utf8.count ?? 0 <= maxMetadataStringBytes else {
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
        guard negotiation.integrationInstanceID == envelope.integrationInstanceID else {
            return .rejected(.crossOwnerProvenance)
        }
        if let mode = envelope.integrationMode, mode != negotiation.integrationMode {
            return .rejected(.crossOwnerProvenance)
        }
        if let capabilityID = envelope.capabilityID {
            let direction = envelope.capabilityDirection ?? .observe
            guard let capability = negotiation.capabilities.first(where: { $0.id == capabilityID && $0.direction == direction }) else {
                return .rejected(.capabilityNotGranted)
            }
            guard capability.availability == .available else {
                return .rejected(capability.freshness == .stale ? .staleCapability : .capabilityNotGranted)
            }
            if let revision = envelope.capabilityRevision, revision != capability.revision {
                return .rejected(.crossOwnerProvenance)
            }
            guard negotiation.grants(capabilityID, direction: direction) else {
                return .rejected(negotiation.killSwitches.isEnabled(direction) ? .capabilityNotGranted : .killSwitchClosed)
            }
        } else {
            guard negotiation.grants(WellKnownCapability.sessionObservation, direction: .observe) else {
                return .rejected(negotiation.killSwitches.isEnabled(.observe) ? .capabilityNotGranted : .killSwitchClosed)
            }
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

    public static func validateCapability(
        _ capability: CapabilityRecord,
        in negotiation: NegotiationSnapshot?,
        at date: Date = Date()
    ) -> Result<Void, EnvelopeValidationError> {
        guard let negotiation, negotiation.id == capability.provenance?.snapshotID else {
            return .failure(.unknownNegotiationSnapshot)
        }
        guard capability.provenance?.integrationInstanceID == negotiation.integrationInstanceID,
              capability.provenance?.productNamespace == negotiation.productNamespace,
              capability.provenance?.integrationMode == negotiation.integrationMode else {
            return .failure(.crossOwnerProvenance)
        }
        guard capability.availability == .available else {
            return .failure(capability.freshness == .stale ? .staleCapability : .capabilityNotGranted)
        }
        guard capability.freshness == .current else {
            return .failure(.staleCapability)
        }
        guard negotiation.grants(capability, at: date) else {
            return .failure(negotiation.killSwitches.isEnabled(capability.direction) ? .capabilityNotGranted : .killSwitchClosed)
        }
        return .success(())
    }
}
