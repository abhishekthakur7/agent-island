import Foundation
import SessionDomain

/// Single-purpose local diagnostic evidence store. Adapters submit only the
/// closed `DiagnosticEvidence` projection; no raw envelope/event or store
/// handle crosses this boundary.
public actor DiagnosticEvidenceStore {
    private var records: [DiagnosticEvidence]
    private var revision: Int64

    public init(records: [DiagnosticEvidence] = []) {
        self.records = records
        self.revision = Int64(records.count)
    }

    @discardableResult
    public func append(_ evidence: DiagnosticEvidence) -> Int64 {
        records.append(evidence)
        revision &+= 1
        return revision
    }

    @discardableResult
    public func appendIntakeOutcome(
        _ outcome: IntakeOutcome,
        at date: Date = Date(),
        health: DiagnosticHealthDimensions = .unknown,
        capability: DiagnosticCapability? = .observation
    ) -> Int64 {
        let evidence: DiagnosticEvidence
        switch outcome {
        case .committed:
            evidence = .intake(outcome: .accepted, reason: .deliveryVerified, at: date, health: health, capability: capability, next: .inspect)
        case .duplicateIgnored:
            evidence = .intake(outcome: .deduplicated, reason: .duplicateDelivery, at: date, health: health, capability: capability, next: .inspect)
        case .rejected(let reason):
            evidence = .intake(outcome: .rejected, reason: Self.reason(for: reason), at: date, health: health, capability: capability, next: .inspect)
        case .storageUnavailable(let reason):
            let mapped: DiagnosticReason = switch reason {
            case .integrityCheckFailed: .integrityFailure
            case .unsupportedSchema: .schemaFailure
            case .migrationFailed: .migrationFailure
            case .keychainKeyMissing, .interruptedWrite, .unavailable: .storageUnavailable
            }
            evidence = DiagnosticEvidence(operation: .unavailable, outcome: .unavailable, scope: DiagnosticScope(component: .storage, owner: .store, capability: .storage), reason: mapped, occurredAt: date, correlationID: .generated(), health: health, safeNextStep: .preserveBytes)
        }
        return append(evidence)
    }

    public func all() -> [DiagnosticEvidence] { records }
    public func count() -> Int { records.count }

    public func previewBundle(at date: Date = Date()) throws -> DiagnosticBundle {
        try DiagnosticBundle(records: records, generatedAt: date)
    }

    /// This is intentionally the only writing operation exposed by the
    /// evidence store. It creates visible local artifacts and does not open,
    /// upload, network-send, or retain a second copy.
    public func createBundle(destination: DiagnosticBundleDestination, name: String = "agent-island-diagnostic-bundle", at date: Date = Date()) throws -> DiagnosticBundleArtifacts {
        let bundle = try DiagnosticBundle(records: records, generatedAt: date)
        return try DiagnosticBundleWriter.write(bundle, to: destination, name: name)
    }

    private static func reason(for reason: EnvelopeValidationError) -> DiagnosticReason {
        switch reason {
        case .unknownNegotiationSnapshot: .unknownNegotiation
        case .incompatibleContractMajor: .incompatibleContract
        case .capabilityNotGranted: .capabilityNotGranted
        case .missingOrAmbiguousOwnerIdentity, .crossOwnerProvenance: .ownerAmbiguous
        case .missingEventIdentity, .malformedShape: .malformedInput
        case .payloadTooLarge: .payloadTooLarge
        case .interactionContentUnsupported: .interactionContentUnsupported
        case .staleCapability: .staleEvidence
        case .killSwitchClosed: .killSwitchClosed
        }
    }
}

/// A small façade useful to a foreground Settings flow. It makes the
/// person-initiated boundary explicit without exposing the actor's storage.
public struct DiagnosticBundleRequest: Codable, Equatable, Hashable, Sendable {
    public let destination: DiagnosticBundleDestination
    public let fileName: String

    public init(destination: DiagnosticBundleDestination, fileName: String = "agent-island-diagnostic-bundle") {
        self.destination = destination
        self.fileName = fileName
    }
}
