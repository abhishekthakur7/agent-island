import Foundation

/// A structured capability claim, never a boolean. This slice only needs the
/// observation direction, but keeps the full shape so later tickets add
/// scope/maturity/evidence/freshness without breaking this contract.
public struct CapabilityRecord: Hashable, Sendable, Codable {
    public enum Direction: String, Sendable, Codable {
        case observe
        case act
        case configure
        case navigate
    }

    public enum Availability: String, Sendable, Codable {
        case available
        case unavailable
        case temporarilyUnavailable
        case unknown
        case incompatible
    }

    public let id: String
    public let direction: Direction
    public let availability: Availability

    public init(id: String, direction: Direction, availability: Availability) {
        self.id = id
        self.direction = direction
        self.availability = availability
    }
}

/// The common capability catalog this slice negotiates. Only the observation
/// surface exists here; action/configure/navigate capabilities are later
/// tickets' concern.
public enum WellKnownCapability {
    public static let sessionObservation = "session.observation"
}

/// What an Adapter (or fixture) proposes at activation. `SessionDomain`
/// receives the offered contract version and requested capabilities as data;
/// it makes no discovery or I/O call of its own.
public struct NegotiationRequest: Sendable {
    public let integrationInstanceID: IntegrationInstanceID
    public let adapterKind: String
    public let adapterBuildVersion: String
    public let productNamespace: ProductNamespace
    public let integrationMode: String
    public let offeredContractVersion: ContractVersion
    public let requestedCapabilities: [String]

    public init(
        integrationInstanceID: IntegrationInstanceID,
        adapterKind: String,
        adapterBuildVersion: String,
        productNamespace: ProductNamespace,
        integrationMode: String,
        offeredContractVersion: ContractVersion,
        requestedCapabilities: [String]
    ) {
        self.integrationInstanceID = integrationInstanceID
        self.adapterKind = adapterKind
        self.adapterBuildVersion = adapterBuildVersion
        self.productNamespace = productNamespace
        self.integrationMode = integrationMode
        self.offeredContractVersion = offeredContractVersion
        self.requestedCapabilities = requestedCapabilities
    }
}

/// The immutable local record of one Adapter contract/version/capability
/// negotiation, per ADR 0002. `id` and `negotiatedAt` are generated outside
/// `SessionDomain` and supplied as data.
public struct NegotiationSnapshot: Hashable, Sendable, Codable {
    public let id: NegotiationSnapshotID
    public let contractVersion: ContractVersion
    public let adapterKind: String
    public let adapterBuildVersion: String
    public let productNamespace: ProductNamespace
    public let integrationInstanceID: IntegrationInstanceID
    public let integrationMode: String
    public let capabilities: [CapabilityRecord]
    public let negotiatedAt: Date

    public init(
        id: NegotiationSnapshotID,
        contractVersion: ContractVersion,
        adapterKind: String,
        adapterBuildVersion: String,
        productNamespace: ProductNamespace,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        capabilities: [CapabilityRecord],
        negotiatedAt: Date
    ) {
        self.id = id
        self.contractVersion = contractVersion
        self.adapterKind = adapterKind
        self.adapterBuildVersion = adapterBuildVersion
        self.productNamespace = productNamespace
        self.integrationInstanceID = integrationInstanceID
        self.integrationMode = integrationMode
        self.capabilities = capabilities
        self.negotiatedAt = negotiatedAt
    }

    public func grants(_ capabilityID: String, direction: CapabilityRecord.Direction) -> Bool {
        capabilities.contains { $0.id == capabilityID && $0.direction == direction && $0.availability == .available }
    }
}

public enum NegotiationOutcome: Sendable {
    case compatible(NegotiationSnapshot)
    case incompatible(reason: EnvelopeValidationError)
    /// The negotiation was contract-compatible, but its durable write to the
    /// protected store failed (AB-119). It never becomes usable in memory
    /// without that durable write succeeding first.
    case storageUnavailable(StorageFailureReason)
}

/// Pure negotiation decision. An unsupported contract major makes the
/// instance `incompatible`: no snapshot is produced, so nothing downstream
/// can reference it. This is the first line of defense behind AC5
/// ("incompatible contract major ... produces no Agent Session").
public enum SessionDomainNegotiator {
    public static func negotiate(
        _ request: NegotiationRequest,
        id: NegotiationSnapshotID,
        negotiatedAt: Date
    ) -> NegotiationOutcome {
        guard request.offeredContractVersion.major == SessionDomainValidator.supportedContractMajor else {
            return .incompatible(reason: .incompatibleContractMajor)
        }
        let capabilities = request.requestedCapabilities.map {
            CapabilityRecord(id: $0, direction: .observe, availability: .available)
        }
        let snapshot = NegotiationSnapshot(
            id: id,
            contractVersion: request.offeredContractVersion,
            adapterKind: request.adapterKind,
            adapterBuildVersion: request.adapterBuildVersion,
            productNamespace: request.productNamespace,
            integrationInstanceID: request.integrationInstanceID,
            integrationMode: request.integrationMode,
            capabilities: capabilities,
            negotiatedAt: negotiatedAt
        )
        return .compatible(snapshot)
    }
}
