import Foundation

/// The maturity of a negotiated capability.  Maturity is deliberately kept
/// separate from availability: an experimental capability may be available,
/// while a stable capability may be unavailable because its permission was
/// revoked.
public enum CapabilityMaturity: String, Sendable, Codable, Hashable {
    case unknown
    case experimental
    case beta
    case stable
    case deprecated
}

public enum CapabilityScope: String, Sendable, Codable, Hashable {
    case installation
    case mode
    case session
    case request
}

public enum CapabilityFreshness: String, Sendable, Codable, Hashable {
    case unknown
    case current
    case stale
    case expired
}

public enum CapabilityFallback: String, Sendable, Codable, Hashable {
    case none
    case observeOnly
    case nativeHost
    case retryProbe
    case manualSetup
    case unavailable
}

/// Provenance attached to every capability claim.  It is intentionally
/// redundant with the snapshot so a capability can be validated in isolation
/// before an Adapter event or action is accepted.
public struct CapabilityProvenance: Hashable, Sendable, Codable {
    public let snapshotID: NegotiationSnapshotID?
    public let integrationInstanceID: IntegrationInstanceID
    public let productNamespace: ProductNamespace
    public let integrationMode: String

    public init(
        snapshotID: NegotiationSnapshotID? = nil,
        integrationInstanceID: IntegrationInstanceID,
        productNamespace: ProductNamespace,
        integrationMode: String
    ) {
        self.snapshotID = snapshotID
        self.integrationInstanceID = integrationInstanceID
        self.productNamespace = productNamespace
        self.integrationMode = integrationMode
    }
}

/// A closed set of constraints.  Values are operational metadata only; the
/// model has no place for commands, prompts, credentials, or raw Product
/// payloads.
public struct CapabilityConstraints: Hashable, Sendable, Codable {
    public let values: [String: String]
    public let requiredPermission: String?
    public let requiresLiveEvidence: Bool

    public init(
        values: [String: String] = [:],
        requiredPermission: String? = nil,
        requiresLiveEvidence: Bool = false
    ) {
        self.values = values
        self.requiredPermission = requiredPermission
        self.requiresLiveEvidence = requiresLiveEvidence
    }

    public subscript(key: String) -> String? { values[key] }
}

/// A structured capability claim, never a boolean.  The original three-field
/// initializer remains source-compatible for the observation fixture.
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
        case interfaceChanged
        case stale
        case disabled
    }

    public let id: String
    public let revision: Int
    public let scope: CapabilityScope
    public let direction: Direction
    public let availability: Availability
    public let maturity: CapabilityMaturity
    public let constraints: CapabilityConstraints
    public let provenance: CapabilityProvenance?
    public let freshness: CapabilityFreshness
    public let fallback: CapabilityFallback
    public let semanticVariant: String?

    public init(
        id: String,
        direction: Direction,
        availability: Availability,
        revision: Int = 1,
        scope: CapabilityScope = .mode,
        maturity: CapabilityMaturity = .stable,
        constraints: CapabilityConstraints = CapabilityConstraints(),
        provenance: CapabilityProvenance? = nil,
        freshness: CapabilityFreshness = .current,
        fallback: CapabilityFallback = .none,
        semanticVariant: String? = nil
    ) {
        self.id = id
        self.revision = revision
        self.scope = scope
        self.direction = direction
        self.availability = availability
        self.maturity = maturity
        self.constraints = constraints
        self.provenance = provenance
        self.freshness = freshness
        self.fallback = fallback
        self.semanticVariant = semanticVariant
    }
}

extension CapabilityRecord {
    private enum CodingKeys: String, CodingKey {
        case id, revision, scope, direction, availability, maturity, constraints, provenance, freshness, fallback, semanticVariant
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        scope = try c.decodeIfPresent(CapabilityScope.self, forKey: .scope) ?? .mode
        direction = try c.decode(CapabilityRecord.Direction.self, forKey: .direction)
        availability = try c.decode(CapabilityRecord.Availability.self, forKey: .availability)
        maturity = try c.decodeIfPresent(CapabilityMaturity.self, forKey: .maturity) ?? .stable
        constraints = try c.decodeIfPresent(CapabilityConstraints.self, forKey: .constraints) ?? CapabilityConstraints()
        provenance = try c.decodeIfPresent(CapabilityProvenance.self, forKey: .provenance)
        freshness = try c.decodeIfPresent(CapabilityFreshness.self, forKey: .freshness) ?? .current
        fallback = try c.decodeIfPresent(CapabilityFallback.self, forKey: .fallback) ?? .none
        semanticVariant = try c.decodeIfPresent(String.self, forKey: .semanticVariant)
    }
}

public typealias CapabilityDirection = CapabilityRecord.Direction
public typealias CapabilityAvailability = CapabilityRecord.Availability

/// The common capability catalog this slice negotiates. Only the observation
/// surface exists here; action/configure/navigate capabilities are later
/// tickets' concern.
public enum WellKnownCapability {
    public static let sessionObservation = "session.observation"
    public static let sessionAction = "session.action"
    public static let configuration = "integration.configuration"
    public static let hostNavigation = "host.navigation"
    public static let catalogRevision = "catalog.v1"
}

public enum NegotiationCompatibility: String, Sendable, Codable, Hashable {
    case compatible
    case interfaceChanged
    case unknown
    case incompatibleMajor
}

public enum ProbeSetupState: String, Sendable, Codable, Hashable {
    case unknown
    case required
    case loaded
    case permissionDenied
    case unavailable
}

/// Read-only evidence captured by a probe.  It is safe to persist and render:
/// only versions, enum states, permissions, and times are retained.
public struct NegotiationProbeEvidence: Hashable, Sendable, Codable {
    public let compatibility: NegotiationCompatibility
    public let productVersion: String
    public let interfaceVersion: String
    public let setup: ProbeSetupState
    public let requiredPermissions: [String]
    public let observedAt: Date

    public init(
        compatibility: NegotiationCompatibility = .compatible,
        productVersion: String = "unknown",
        interfaceVersion: String = "unknown",
        setup: ProbeSetupState = .unknown,
        requiredPermissions: [String] = [],
        observedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.compatibility = compatibility
        self.productVersion = productVersion
        self.interfaceVersion = interfaceVersion
        self.setup = setup
        self.requiredPermissions = requiredPermissions
        self.observedAt = observedAt
    }

    public static let unknown = Self()
}

public enum HealthDimensionStatus: String, Sendable, Codable, Hashable {
    case unknown
    case verified
    case setupRequired
    case denied
    case stale
    case degraded
    case unavailable
    case incompatible
    case disabled
}

public enum IntegrationHealthSummary: String, Sendable, Codable, Hashable {
    case disabled
    case setupRequired
    case healthy
    case degraded
    case unavailable
    case incompatible
}

public enum HealthSafeNextStep: String, Sendable, Codable, Hashable {
    case none
    case enableIntent
    case configure
    case repair
    case retry
    case update
    case inspect
    case useNativeHost
}

/// A truthful health vector.  A summary is derived from independent
/// dimensions; no single reachability bit can imply action or navigation.
public struct IntegrationHealthVector: Hashable, Sendable, Codable {
    public let intent: HealthDimensionStatus
    public let ownership: HealthDimensionStatus
    public let configured: HealthDimensionStatus
    public let loadPolicy: HealthDimensionStatus
    public let reachability: HealthDimensionStatus
    public let delivery: HealthDimensionStatus
    public let actionReadiness: HealthDimensionStatus
    public let navigationReadiness: HealthDimensionStatus
    public let summary: IntegrationHealthSummary
    public let evidenceAt: Date
    public let affectedCapabilities: [String]
    public let safeNextStep: HealthSafeNextStep

    public var status: IntegrationHealthSummary { summary }
    public var affectedCapability: String? { affectedCapabilities.first }
    public var observedAt: Date { evidenceAt }

    public init(
        intent: HealthDimensionStatus = .unknown,
        ownership: HealthDimensionStatus = .unknown,
        configured: HealthDimensionStatus = .unknown,
        loadPolicy: HealthDimensionStatus = .unknown,
        reachability: HealthDimensionStatus = .unknown,
        delivery: HealthDimensionStatus = .unknown,
        actionReadiness: HealthDimensionStatus = .unknown,
        navigationReadiness: HealthDimensionStatus = .unknown,
        summary: IntegrationHealthSummary = .unavailable,
        evidenceAt: Date = Date(timeIntervalSince1970: 0),
        affectedCapabilities: [String] = [],
        safeNextStep: HealthSafeNextStep = .inspect
    ) {
        self.intent = intent
        self.ownership = ownership
        self.configured = configured
        self.loadPolicy = loadPolicy
        self.reachability = reachability
        self.delivery = delivery
        self.actionReadiness = actionReadiness
        self.navigationReadiness = navigationReadiness
        self.summary = summary
        self.evidenceAt = evidenceAt
        self.affectedCapabilities = affectedCapabilities
        self.safeNextStep = safeNextStep
    }

    public static func from(
        probe: NegotiationProbeEvidence,
        negotiatedAt: Date,
        capabilities: [CapabilityRecord],
        killSwitches: IntegrationKillSwitches = .enabled
    ) -> Self {
        let intent: HealthDimensionStatus = .verified
        let configured: HealthDimensionStatus = switch probe.setup {
        case .loaded: .verified
        case .required: .setupRequired
        case .permissionDenied: .denied
        case .unavailable: .unavailable
        case .unknown: .unknown
        }
        let compatibility = probe.compatibility
        let summary: IntegrationHealthSummary
        let next: HealthSafeNextStep
        switch compatibility {
        case .incompatibleMajor:
            summary = .incompatible; next = .update
        case .interfaceChanged, .unknown:
            summary = .degraded; next = .retry
        case .compatible where configured == .setupRequired, .compatible where configured == .unknown:
            summary = .setupRequired; next = .configure
        case .compatible where configured == .denied:
            summary = .unavailable; next = .inspect
        case .compatible where configured == .unavailable:
            summary = .unavailable; next = .retry
        case .compatible:
            summary = .healthy; next = .none
        }
        let affected = capabilities.filter { $0.availability != .available || !killSwitches.isEnabled($0.direction) }.map(\.id)
        let actionStatus: HealthDimensionStatus = killSwitches.isEnabled(.act) ? .unknown : .disabled
        let navigationStatus: HealthDimensionStatus = killSwitches.isEnabled(.navigate) ? .unknown : .disabled
        let effectiveSummary: IntegrationHealthSummary = affected.isEmpty ? summary : (summary == .healthy ? .degraded : summary)
        return Self(
            intent: intent,
            ownership: .verified,
            configured: configured,
            loadPolicy: .verified,
            reachability: compatibility == .compatible ? .verified : .degraded,
            delivery: compatibility == .compatible ? .verified : .stale,
            actionReadiness: actionStatus,
            navigationReadiness: navigationStatus,
            summary: effectiveSummary,
            evidenceAt: probe.observedAt == Date(timeIntervalSince1970: 0) ? negotiatedAt : probe.observedAt,
            affectedCapabilities: affected,
            safeNextStep: affected.isEmpty ? next : .inspect
        )
    }
}

public struct IntegrationKillSwitches: Hashable, Sendable, Codable {
    public let globalObservationEnabled: Bool
    public let globalActionEnabled: Bool
    public let globalConfigurationEnabled: Bool
    public let globalNavigationEnabled: Bool
    public let observationEnabled: Bool
    public let actionEnabled: Bool
    public let configurationEnabled: Bool
    public let navigationEnabled: Bool

    public init(
        globalObservationEnabled: Bool = true,
        globalActionEnabled: Bool = true,
        globalConfigurationEnabled: Bool = true,
        globalNavigationEnabled: Bool = true,
        observationEnabled: Bool = true,
        actionEnabled: Bool = true,
        configurationEnabled: Bool = true,
        navigationEnabled: Bool = true
    ) {
        self.globalObservationEnabled = globalObservationEnabled
        self.globalActionEnabled = globalActionEnabled
        self.globalConfigurationEnabled = globalConfigurationEnabled
        self.globalNavigationEnabled = globalNavigationEnabled
        self.observationEnabled = observationEnabled
        self.actionEnabled = actionEnabled
        self.configurationEnabled = configurationEnabled
        self.navigationEnabled = navigationEnabled
    }

    public static let enabled = Self()

    public func isEnabled(_ direction: CapabilityRecord.Direction) -> Bool {
        switch direction {
        case .observe: globalObservationEnabled && observationEnabled
        case .act: globalActionEnabled && actionEnabled
        case .configure: globalConfigurationEnabled && configurationEnabled
        case .navigate: globalNavigationEnabled && navigationEnabled
        }
    }

    public func closing(_ direction: CapabilityRecord.Direction) -> Self {
        switch direction {
        case .observe: return Self(globalObservationEnabled: globalObservationEnabled, globalActionEnabled: globalActionEnabled, globalConfigurationEnabled: globalConfigurationEnabled, globalNavigationEnabled: globalNavigationEnabled, observationEnabled: false, actionEnabled: actionEnabled, configurationEnabled: configurationEnabled, navigationEnabled: navigationEnabled)
        case .act: return Self(globalObservationEnabled: globalObservationEnabled, globalActionEnabled: globalActionEnabled, globalConfigurationEnabled: globalConfigurationEnabled, globalNavigationEnabled: globalNavigationEnabled, observationEnabled: observationEnabled, actionEnabled: false, configurationEnabled: configurationEnabled, navigationEnabled: navigationEnabled)
        case .configure: return Self(globalObservationEnabled: globalObservationEnabled, globalActionEnabled: globalActionEnabled, globalConfigurationEnabled: globalConfigurationEnabled, globalNavigationEnabled: globalNavigationEnabled, observationEnabled: observationEnabled, actionEnabled: actionEnabled, configurationEnabled: false, navigationEnabled: navigationEnabled)
        case .navigate: return Self(globalObservationEnabled: globalObservationEnabled, globalActionEnabled: globalActionEnabled, globalConfigurationEnabled: globalConfigurationEnabled, globalNavigationEnabled: globalNavigationEnabled, observationEnabled: observationEnabled, actionEnabled: actionEnabled, configurationEnabled: configurationEnabled, navigationEnabled: false)
        }
    }

    public func closingGlobally(_ direction: CapabilityRecord.Direction) -> Self {
        switch direction {
        case .observe: return Self(globalObservationEnabled: false, globalActionEnabled: globalActionEnabled, globalConfigurationEnabled: globalConfigurationEnabled, globalNavigationEnabled: globalNavigationEnabled, observationEnabled: observationEnabled, actionEnabled: actionEnabled, configurationEnabled: configurationEnabled, navigationEnabled: navigationEnabled)
        case .act: return Self(globalObservationEnabled: globalObservationEnabled, globalActionEnabled: false, globalConfigurationEnabled: globalConfigurationEnabled, globalNavigationEnabled: globalNavigationEnabled, observationEnabled: observationEnabled, actionEnabled: actionEnabled, configurationEnabled: configurationEnabled, navigationEnabled: navigationEnabled)
        case .configure: return Self(globalObservationEnabled: globalObservationEnabled, globalActionEnabled: globalActionEnabled, globalConfigurationEnabled: false, globalNavigationEnabled: globalNavigationEnabled, observationEnabled: observationEnabled, actionEnabled: actionEnabled, configurationEnabled: configurationEnabled, navigationEnabled: navigationEnabled)
        case .navigate: return Self(globalObservationEnabled: globalObservationEnabled, globalActionEnabled: globalActionEnabled, globalConfigurationEnabled: globalConfigurationEnabled, globalNavigationEnabled: false, observationEnabled: observationEnabled, actionEnabled: actionEnabled, configurationEnabled: configurationEnabled, navigationEnabled: navigationEnabled)
        }
    }
}

/// What an Adapter (or fixture) proposes at activation. `SessionDomain`
/// receives the offered contract version and requested capabilities as data;
/// it makes no discovery or I/O call of its own.
public struct NegotiationRequest: Hashable, Sendable, Codable {
    public let integrationInstanceID: IntegrationInstanceID
    public let adapterKind: String
    public let adapterBuildVersion: String
    public let productNamespace: ProductNamespace
    public let integrationMode: String
    public let offeredContractVersion: ContractVersion
    public let requestedCapabilities: [String]
    public let catalogRevision: String
    public let productVersion: String?
    public let interfaceVersion: String?
    public let probeEvidence: NegotiationProbeEvidence?
    public let requestedCapabilityRecords: [CapabilityRecord]?
    public let compatibility: NegotiationCompatibility

    public init(
        integrationInstanceID: IntegrationInstanceID,
        adapterKind: String,
        adapterBuildVersion: String,
        productNamespace: ProductNamespace,
        integrationMode: String,
        offeredContractVersion: ContractVersion,
        requestedCapabilities: [String],
        catalogRevision: String = WellKnownCapability.catalogRevision,
        productVersion: String? = nil,
        interfaceVersion: String? = nil,
        probeEvidence: NegotiationProbeEvidence? = nil,
        requestedCapabilityRecords: [CapabilityRecord]? = nil,
        compatibility: NegotiationCompatibility = .compatible
    ) {
        self.integrationInstanceID = integrationInstanceID
        self.adapterKind = adapterKind
        self.adapterBuildVersion = adapterBuildVersion
        self.productNamespace = productNamespace
        self.integrationMode = integrationMode
        self.offeredContractVersion = offeredContractVersion
        self.requestedCapabilities = requestedCapabilities
        self.catalogRevision = catalogRevision
        self.productVersion = productVersion
        self.interfaceVersion = interfaceVersion
        self.probeEvidence = probeEvidence
        self.requestedCapabilityRecords = requestedCapabilityRecords
        self.compatibility = compatibility
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
    public let catalogRevision: String
    public let productVersion: String
    public let interfaceVersion: String
    public let probeEvidence: NegotiationProbeEvidence
    public let compatibility: NegotiationCompatibility
    public let health: IntegrationHealthVector
    public let killSwitches: IntegrationKillSwitches

    public var catalog: String { catalogRevision }
    public var contract: ContractVersion { contractVersion }
    public var adapterVersion: String { adapterBuildVersion }
    public var mode: String { integrationMode }
    public var evidenceTime: Date { probeEvidence.observedAt }
    public var capabilityRecords: [CapabilityRecord] { capabilities }
    public var healthDimensions: IntegrationHealthVector { health }

    public init(
        id: NegotiationSnapshotID,
        contractVersion: ContractVersion,
        adapterKind: String,
        adapterBuildVersion: String,
        productNamespace: ProductNamespace,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        capabilities: [CapabilityRecord],
        negotiatedAt: Date,
        catalogRevision: String = WellKnownCapability.catalogRevision,
        productVersion: String = "unknown",
        interfaceVersion: String = "unknown",
        probeEvidence: NegotiationProbeEvidence? = nil,
        compatibility: NegotiationCompatibility = .compatible,
        health: IntegrationHealthVector? = nil,
        killSwitches: IntegrationKillSwitches = .enabled
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
        let evidence = probeEvidence ?? NegotiationProbeEvidence(
            compatibility: compatibility,
            productVersion: productVersion,
            interfaceVersion: interfaceVersion,
            observedAt: negotiatedAt
        )
        self.catalogRevision = catalogRevision
        self.productVersion = productVersion
        self.interfaceVersion = interfaceVersion
        self.probeEvidence = evidence
        self.compatibility = compatibility
        self.killSwitches = killSwitches
        self.health = health ?? IntegrationHealthVector.from(probe: evidence, negotiatedAt: negotiatedAt, capabilities: capabilities, killSwitches: killSwitches)
    }

    public func grants(_ capabilityID: String, direction: CapabilityRecord.Direction) -> Bool {
        capabilities.contains {
            $0.id == capabilityID &&
            $0.direction == direction &&
            $0.availability == .available &&
            $0.freshness == .current &&
            ($0.provenance == nil || ($0.provenance?.snapshotID == id && $0.provenance?.integrationInstanceID == integrationInstanceID && $0.provenance?.productNamespace == productNamespace && $0.provenance?.integrationMode == integrationMode)) &&
            killSwitches.isEnabled(direction)
        }
    }

    public func grants(_ capability: CapabilityRecord, at: Date = Date()) -> Bool {
        guard grants(capability.id, direction: capability.direction) else { return false }
        guard capability.revision == capabilities.first(where: { $0.id == capability.id && $0.direction == capability.direction })?.revision else { return false }
        return true
    }

    public func applying(killSwitches: IntegrationKillSwitches) -> Self {
        let narrowedCapabilities = capabilities.map { capability in
            guard !killSwitches.isEnabled(capability.direction), capability.availability == .available else { return capability }
            return CapabilityRecord(
                id: capability.id,
                direction: capability.direction,
                availability: .disabled,
                revision: capability.revision,
                scope: capability.scope,
                maturity: capability.maturity,
                constraints: capability.constraints,
                provenance: capability.provenance,
                freshness: .stale,
                fallback: capability.fallback == .none ? (capability.direction == .observe ? .retryProbe : .observeOnly) : capability.fallback,
                semanticVariant: capability.semanticVariant
            )
        }
        return Self(
            id: id,
            contractVersion: contractVersion,
            adapterKind: adapterKind,
            adapterBuildVersion: adapterBuildVersion,
            productNamespace: productNamespace,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            capabilities: narrowedCapabilities,
            negotiatedAt: negotiatedAt,
            catalogRevision: catalogRevision,
            productVersion: productVersion,
            interfaceVersion: interfaceVersion,
            probeEvidence: probeEvidence,
            compatibility: compatibility,
            health: IntegrationHealthVector.from(probe: probeEvidence, negotiatedAt: negotiatedAt, capabilities: capabilities, killSwitches: killSwitches),
            killSwitches: killSwitches
        )
    }
}

extension NegotiationSnapshot {
    private enum CodingKeys: String, CodingKey {
        case id, contractVersion, adapterKind, adapterBuildVersion, productNamespace
        case integrationInstanceID, integrationMode, capabilities, negotiatedAt
        case catalogRevision, productVersion, interfaceVersion, probeEvidence, compatibility, health, killSwitches
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(NegotiationSnapshotID.self, forKey: .id)
        contractVersion = try c.decode(ContractVersion.self, forKey: .contractVersion)
        adapterKind = try c.decode(String.self, forKey: .adapterKind)
        adapterBuildVersion = try c.decode(String.self, forKey: .adapterBuildVersion)
        productNamespace = try c.decode(ProductNamespace.self, forKey: .productNamespace)
        integrationInstanceID = try c.decode(IntegrationInstanceID.self, forKey: .integrationInstanceID)
        integrationMode = try c.decode(String.self, forKey: .integrationMode)
        capabilities = try c.decode([CapabilityRecord].self, forKey: .capabilities)
        negotiatedAt = try c.decode(Date.self, forKey: .negotiatedAt)
        catalogRevision = try c.decodeIfPresent(String.self, forKey: .catalogRevision) ?? WellKnownCapability.catalogRevision
        productVersion = try c.decodeIfPresent(String.self, forKey: .productVersion) ?? "unknown"
        interfaceVersion = try c.decodeIfPresent(String.self, forKey: .interfaceVersion) ?? "unknown"
        compatibility = try c.decodeIfPresent(NegotiationCompatibility.self, forKey: .compatibility) ?? .compatible
        probeEvidence = try c.decodeIfPresent(NegotiationProbeEvidence.self, forKey: .probeEvidence) ?? NegotiationProbeEvidence(compatibility: compatibility, productVersion: productVersion, interfaceVersion: interfaceVersion, observedAt: negotiatedAt)
        killSwitches = try c.decodeIfPresent(IntegrationKillSwitches.self, forKey: .killSwitches) ?? .enabled
        health = try c.decodeIfPresent(IntegrationHealthVector.self, forKey: .health) ?? IntegrationHealthVector.from(probe: probeEvidence, negotiatedAt: negotiatedAt, capabilities: capabilities, killSwitches: killSwitches)
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
        guard request.requestedCapabilities.count <= 128 else {
            return .incompatible(reason: .malformedShape)
        }
        guard !request.adapterKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.adapterBuildVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.integrationMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.catalogRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .incompatible(reason: .malformedShape)
        }
        let proposed = request.requestedCapabilityRecords ?? request.requestedCapabilities.map {
            CapabilityRecord(id: $0, direction: .observe, availability: .available)
        }
        guard proposed.allSatisfy({
            let id = $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
            return !id.isEmpty && id.utf8.count <= 256 && $0.revision > 0
        }) else {
            return .incompatible(reason: .malformedShape)
        }
        let capabilities = proposed.map { offered in
            let narrowed: CapabilityRecord.Availability
            switch request.compatibility {
            case .compatible:
                narrowed = offered.availability
            case .interfaceChanged:
                narrowed = offered.direction == .observe && offered.availability == .available ? .available : .interfaceChanged
            case .unknown:
                narrowed = offered.direction == .observe && offered.availability == .available ? .available : .unknown
            case .incompatibleMajor:
                narrowed = .incompatible
            }
            return CapabilityRecord(
                id: offered.id,
                direction: offered.direction,
                availability: narrowed,
                revision: offered.revision,
                scope: offered.scope,
                maturity: offered.maturity,
                constraints: offered.constraints,
                provenance: CapabilityProvenance(
                    snapshotID: id,
                    integrationInstanceID: request.integrationInstanceID,
                    productNamespace: request.productNamespace,
                    integrationMode: request.integrationMode
                ),
                freshness: narrowed == .available ? .current : .stale,
                fallback: offered.fallback == .none && narrowed != .available ? (offered.direction == .observe ? .retryProbe : .observeOnly) : offered.fallback,
                semanticVariant: offered.semanticVariant
            )
        }
        let evidence = request.probeEvidence ?? NegotiationProbeEvidence(
            compatibility: request.compatibility,
            productVersion: request.productVersion ?? "unknown",
            interfaceVersion: request.interfaceVersion ?? "unknown",
            observedAt: negotiatedAt
        )
        let snapshot = NegotiationSnapshot(
            id: id,
            contractVersion: request.offeredContractVersion,
            adapterKind: request.adapterKind,
            adapterBuildVersion: request.adapterBuildVersion,
            productNamespace: request.productNamespace,
            integrationInstanceID: request.integrationInstanceID,
            integrationMode: request.integrationMode,
            capabilities: capabilities,
            negotiatedAt: negotiatedAt,
            catalogRevision: request.catalogRevision,
            productVersion: request.productVersion ?? evidence.productVersion,
            interfaceVersion: request.interfaceVersion ?? evidence.interfaceVersion,
            probeEvidence: evidence,
            compatibility: request.compatibility
        )
        return .compatible(snapshot)
    }
}
