import Foundation

/// The only future purposes that may be represented by the Service Egress
/// seam.  The enum is intentionally closed: a caller cannot smuggle an
/// analytics purpose or an arbitrary destination through a free-form string.
public enum ServiceEgressPurpose: String, Codable, CaseIterable, Hashable, Sendable {
    case hostedPersistence
    case telemetry
    case supportDiagnostic
}

/// A destination identifies a future service class, not a URL, account, or
/// endpoint.  No production destination is configured by this contract.
public enum ServiceEgressDestination: String, Codable, CaseIterable, Hashable, Sendable {
    case hostedPersistence
    case telemetry
    case supportDiagnostic
}

public struct ServiceEgressSchemaVersion: Codable, Equatable, Hashable, Sendable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static let current = Self(major: 1, minor: 0)
}

/// Classification is closed and checked before a value reaches the port.
/// The forbidden cases are retained as explicit rejection vocabulary for
/// deterministic contract tests; none can be accepted by a change set.
public enum ServiceEgressClassification: String, Codable, CaseIterable, Hashable, Sendable {
    case redactedSessionState
    case aggregateTelemetry
    case separatelyRedactedDiagnostic

    case interactionContent
    case credentials
    case rawIdentifier
    case fullPath
    case commandLine
    case rawDiagnostic
    case callbackToken
    case unknownExtension

    public var isAllowed: Bool {
        switch self {
        case .redactedSessionState, .aggregateTelemetry, .separatelyRedactedDiagnostic:
            true
        case .interactionContent, .credentials, .rawIdentifier, .fullPath,
             .commandLine, .rawDiagnostic, .callbackToken, .unknownExtension:
            false
        }
    }
}

public enum ServiceEgressScopeKind: String, Codable, CaseIterable, Hashable, Sendable {
    case installationAggregate
    case selectedSessions
    case diagnosticArtifact
}

public enum ServiceEgressContractError: String, Codable, Equatable, Hashable, Sendable, Error, CaseIterable {
    case unsupportedSchema
    case invalidChangeSetID
    case invalidPseudonym
    case invalidScope
    case invalidConsent
    case forbiddenClassification
    case unknownExtension
    case purposeDestinationMismatch
    case purposePayloadMismatch
    case invalidPayload
    case supportDiagnosticConfirmationRequired
}

/// The selected scope contains no local or Product identity.  Session scope
/// is represented solely by destination-specific pseudonyms.
public struct ServiceEgressScope: Codable, Equatable, Hashable, Sendable {
    public let kind: ServiceEgressScopeKind
    public let pseudonyms: [ServiceEgressPseudonym]

    public init(kind: ServiceEgressScopeKind, pseudonyms: [ServiceEgressPseudonym] = []) throws {
        let sorted = pseudonyms.sorted { lhs, rhs in
            if lhs.destination != rhs.destination { return lhs.destination.rawValue < rhs.destination.rawValue }
            return lhs.value < rhs.value
        }
        guard Set(sorted).count == sorted.count else { throw ServiceEgressContractError.invalidScope }
        switch kind {
        case .selectedSessions:
            guard !sorted.isEmpty else { throw ServiceEgressContractError.invalidScope }
        case .installationAggregate, .diagnosticArtifact:
            guard sorted.isEmpty else { throw ServiceEgressContractError.invalidScope }
        }
        self.kind = kind
        self.pseudonyms = sorted
    }

    public static let installationAggregate = try! Self(kind: .installationAggregate)
    public static let diagnosticArtifact = try! Self(kind: .diagnosticArtifact)
}

/// A service-specific pseudonym has a constrained shape so a reusable local
/// or Product identifier cannot be placed in an outbound copy by accident.
public struct ServiceEgressPseudonym: Codable, Equatable, Hashable, Sendable {
    public let destination: ServiceEgressDestination
    public let value: String

    public init(destination: ServiceEgressDestination, value: String) throws {
        guard Self.isValid(value) else { throw ServiceEgressContractError.invalidPseudonym }
        self.destination = destination
        self.value = value
    }

    public var isStructurallyValid: Bool { Self.isValid(value) }

    /// Derives a destination-specific, non-reversible identifier from local
    /// identity.  The identity itself never crosses the boundary.
    public static func derived(for identity: AgentSessionIdentity, destination: ServiceEgressDestination) -> Self {
        let material = "agent-island-egress-v1|\(destination.rawValue)|\(identity.productNamespace.rawValue)|\(identity.nativeSessionID.rawValue)"
        let digest = ExactEntryDigest.value(Data(material.utf8))
        return try! Self(destination: destination, value: "pseudonym-\(digest)")
    }

    private static func isValid(_ value: String) -> Bool {
        value.range(of: "^pseudonym-[0-9a-f]{16}$", options: .regularExpression) != nil
    }
}

/// Opt-in, purpose-granular consent.  Revocation is evaluated by the
/// dispatcher at the instant it attempts delivery, rather than at enqueue.
public struct ServiceEgressConsent: Codable, Equatable, Hashable, Sendable {
    public let purpose: ServiceEgressPurpose
    public let version: Int
    public let grantedAt: Date
    public let revokedAt: Date?

    public init(purpose: ServiceEgressPurpose, version: Int, grantedAt: Date, revokedAt: Date? = nil) throws {
        guard version > 0, grantedAt <= (revokedAt ?? Date.distantFuture) else {
            throw ServiceEgressContractError.invalidConsent
        }
        self.purpose = purpose
        self.version = version
        self.grantedAt = grantedAt
        self.revokedAt = revokedAt
    }

    public var isRevoked: Bool { revokedAt != nil }

    public func allowsDispatch(at date: Date) -> Bool {
        guard grantedAt <= date else { return false }
        guard let revokedAt else { return true }
        return date < revokedAt
    }

    public func revoked(at date: Date) -> Self {
        try! Self(purpose: purpose, version: version, grantedAt: grantedAt, revokedAt: date)
    }
}

public enum ServiceEgressConsentStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case disabled
    case granted
    case revoked
}

public struct ServiceEgressConsentSnapshot: Codable, Equatable, Hashable, Sendable {
    public let purpose: ServiceEgressPurpose
    public let status: ServiceEgressConsentStatus
    public let version: Int?
    public let changedAt: Date?

    public init(purpose: ServiceEgressPurpose, status: ServiceEgressConsentStatus, version: Int? = nil, changedAt: Date? = nil) {
        self.purpose = purpose
        self.status = status
        self.version = version
        self.changedAt = changedAt
    }
}

public struct ServiceEgressSessionState: Codable, Equatable, Hashable, Sendable {
    public let pseudonym: ServiceEgressPseudonym
    public let execution: ExecutionState
    public let observation: ObservationState
    public let attention: AttentionState
    public let lineage: LineageState
    public let turnCount: Int
    public let subagentRunCount: Int

    public init(
        pseudonym: ServiceEgressPseudonym,
        execution: ExecutionState,
        observation: ObservationState,
        attention: AttentionState,
        lineage: LineageState,
        turnCount: Int = 0,
        subagentRunCount: Int = 0
    ) throws {
        guard turnCount >= 0, subagentRunCount >= 0 else { throw ServiceEgressContractError.invalidPayload }
        self.pseudonym = pseudonym
        self.execution = execution
        self.observation = observation
        self.attention = attention
        self.lineage = lineage
        self.turnCount = turnCount
        self.subagentRunCount = subagentRunCount
    }

    public init(projection: SessionProjection, destination: ServiceEgressDestination) {
        self.pseudonym = ServiceEgressPseudonym.derived(for: projection.identity, destination: destination)
        self.execution = projection.execution
        self.observation = projection.observation
        self.attention = projection.attention
        self.lineage = projection.lineage
        self.turnCount = projection.turns.count
        self.subagentRunCount = projection.subagentRuns.count
    }
}

public struct ServiceEgressHostedSnapshot: Codable, Equatable, Hashable, Sendable {
    public let schemaVersion: ServiceEgressSchemaVersion
    public let ledgerRevision: Int64
    public let sessions: [ServiceEgressSessionState]

    public init(
        schemaVersion: ServiceEgressSchemaVersion = .current,
        ledgerRevision: Int64,
        sessions: [ServiceEgressSessionState]
    ) throws {
        guard ledgerRevision >= 0, !sessions.isEmpty else { throw ServiceEgressContractError.invalidPayload }
        self.schemaVersion = schemaVersion
        self.ledgerRevision = ledgerRevision
        self.sessions = sessions
    }
}

public enum ServiceEgressTelemetryMetric: String, Codable, CaseIterable, Hashable, Sendable {
    case sessionsObserved
    case sessionsWorking
    case sessionsWaiting
    case sessionsCompleted
    case sessionsFailed
    case attentionRequests
    case factCommits
    case recoveryBoundaries
}

public struct ServiceEgressTelemetrySnapshot: Codable, Equatable, Hashable, Sendable {
    public let schemaVersion: ServiceEgressSchemaVersion
    public let metrics: [ServiceEgressTelemetryMetric: Int64]

    public init(schemaVersion: ServiceEgressSchemaVersion = .current, metrics: [ServiceEgressTelemetryMetric: Int64]) throws {
        guard metrics.values.allSatisfy({ $0 >= 0 }) else { throw ServiceEgressContractError.invalidPayload }
        self.schemaVersion = schemaVersion
        self.metrics = metrics
    }
}

/// Support diagnostics are a separately confirmed, already-redacted artifact;
/// the normal dispatcher never manufactures one from local store contents.
public struct ServiceEgressSupportDiagnostic: Codable, Equatable, Hashable, Sendable {
    public let schemaVersion: ServiceEgressSchemaVersion
    public let records: [DiagnosticEvidence]
    public let explicitlyConfirmedAt: Date

    public init(
        schemaVersion: ServiceEgressSchemaVersion = .current,
        records: [DiagnosticEvidence],
        explicitlyConfirmedAt: Date?
    ) throws {
        guard let explicitlyConfirmedAt,
              records.allSatisfy({ $0.correlationID.value.hasPrefix("corr-") })
        else { throw ServiceEgressContractError.supportDiagnosticConfirmationRequired }
        self.schemaVersion = schemaVersion
        self.records = records
        self.explicitlyConfirmedAt = explicitlyConfirmedAt
    }
}

public enum ServiceEgressPayload: Codable, Equatable, Hashable, Sendable {
    case hostedPersistence(ServiceEgressHostedSnapshot)
    case telemetry(ServiceEgressTelemetrySnapshot)
    case supportDiagnostic(ServiceEgressSupportDiagnostic)
}

public struct ServiceEgressChangeSetID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) throws {
        guard value.range(of: "^egress-[0-9a-f]{16}$", options: .regularExpression) != nil else {
            throw ServiceEgressContractError.invalidChangeSetID
        }
        self.value = value
    }

    public static func derived(from data: Data) -> Self {
        try! Self("egress-\(ExactEntryDigest.value(data))")
    }

    public var description: String { value }
}

/// The sole value crossing the future service boundary.  It contains only a
/// classified projection, selected scope, consent metadata, and pseudonyms;
/// no database/key handle, raw Adapter record, endpoint, or inbound command
/// can be represented.
public struct ServiceEgressChangeSet: Codable, Equatable, Hashable, Sendable {
    public static let supportedSchema = ServiceEgressSchemaVersion.current

    public let id: ServiceEgressChangeSetID
    public let schemaVersion: ServiceEgressSchemaVersion
    public let purpose: ServiceEgressPurpose
    public let destination: ServiceEgressDestination
    public let scope: ServiceEgressScope
    public let consentVersion: Int
    public let consentGrantedAt: Date
    public let pseudonyms: [ServiceEgressPseudonym]
    public let classification: ServiceEgressClassification
    public let payload: ServiceEgressPayload
    /// Reserved only to make unknown extensions fail closed.  The current
    /// schema permits none; a future major can add a typed allowlisted case.
    public let extensions: [String]
    public let createdAt: Date

    public init(
        id: ServiceEgressChangeSetID,
        schemaVersion: ServiceEgressSchemaVersion = ServiceEgressChangeSet.supportedSchema,
        purpose: ServiceEgressPurpose,
        destination: ServiceEgressDestination,
        scope: ServiceEgressScope,
        consent: ServiceEgressConsent,
        classification: ServiceEgressClassification,
        payload: ServiceEgressPayload,
        extensions: [String] = [],
        createdAt: Date
    ) throws {
        guard schemaVersion.major == Self.supportedSchema.major,
              schemaVersion.minor <= Self.supportedSchema.minor
        else { throw ServiceEgressContractError.unsupportedSchema }
        guard consent.purpose == purpose, consent.version > 0 else { throw ServiceEgressContractError.invalidConsent }
        guard extensions.isEmpty else { throw ServiceEgressContractError.unknownExtension }
        guard classification.isAllowed else { throw ServiceEgressContractError.forbiddenClassification }
        guard purpose == destination.asPurpose else { throw ServiceEgressContractError.purposeDestinationMismatch }
        guard classification == payload.classification else { throw ServiceEgressContractError.purposePayloadMismatch }
        guard Self.validScopeShape(scope),
              Self.pseudonyms(for: payload).allSatisfy(\.isStructurallyValid),
              scope.pseudonyms.allSatisfy({ $0.destination == destination }),
              Self.pseudonyms(for: payload).allSatisfy({ $0.destination == destination }),
              Self.validPayloadSchema(payload),
              Self.scopeMatches(purpose: purpose, scope: scope), Self.payloadMatchesScope(payload, scope: scope) else {
            throw ServiceEgressContractError.invalidScope
        }
        self.id = id
        self.schemaVersion = schemaVersion
        self.purpose = purpose
        self.destination = destination
        self.scope = scope
        self.consentVersion = consent.version
        self.consentGrantedAt = consent.grantedAt
        self.pseudonyms = Self.pseudonyms(for: payload)
        self.classification = classification
        self.payload = payload
        self.extensions = extensions
        self.createdAt = createdAt
    }

    public func validate() throws {
        guard schemaVersion.major == Self.supportedSchema.major,
              schemaVersion.minor <= Self.supportedSchema.minor else { throw ServiceEgressContractError.unsupportedSchema }
        guard classification.isAllowed else { throw ServiceEgressContractError.forbiddenClassification }
        guard extensions.isEmpty else { throw ServiceEgressContractError.unknownExtension }
        guard consentVersion > 0,
              Self.validScopeShape(scope),
              Self.pseudonyms(for: payload).allSatisfy(\.isStructurallyValid),
              scope.pseudonyms.allSatisfy({ $0.destination == destination }),
              Self.pseudonyms(for: payload).allSatisfy({ $0.destination == destination }),
              Self.validPayloadSchema(payload),
              purpose == destination.asPurpose, classification == payload.classification,
              Self.scopeMatches(purpose: purpose, scope: scope), Self.payloadMatchesScope(payload, scope: scope)
        else { throw ServiceEgressContractError.invalidPayload }
    }

    private static func pseudonyms(for payload: ServiceEgressPayload) -> [ServiceEgressPseudonym] {
        switch payload {
        case .hostedPersistence(let snapshot): snapshot.sessions.map(\.pseudonym)
        case .telemetry, .supportDiagnostic: []
        }
    }

    private static func scopeMatches(purpose: ServiceEgressPurpose, scope: ServiceEgressScope) -> Bool {
        switch purpose {
        case .hostedPersistence: scope.kind == .selectedSessions
        case .telemetry: scope.kind == .installationAggregate
        case .supportDiagnostic: scope.kind == .diagnosticArtifact
        }
    }

    private static func payloadMatchesScope(_ payload: ServiceEgressPayload, scope: ServiceEgressScope) -> Bool {
        switch payload {
        case .hostedPersistence(let snapshot):
            let payloadPseudonyms = snapshot.sessions.map(\.pseudonym)
            return Set(payloadPseudonyms) == Set(scope.pseudonyms)
        case .telemetry, .supportDiagnostic:
            return scope.pseudonyms.isEmpty
        }
    }

    private static func validScopeShape(_ scope: ServiceEgressScope) -> Bool {
        guard Set(scope.pseudonyms).count == scope.pseudonyms.count else { return false }
        switch scope.kind {
        case .selectedSessions: return !scope.pseudonyms.isEmpty
        case .installationAggregate, .diagnosticArtifact: return scope.pseudonyms.isEmpty
        }
    }

    private static func validPayloadSchema(_ payload: ServiceEgressPayload) -> Bool {
        let version: ServiceEgressSchemaVersion
        switch payload {
        case .hostedPersistence(let value): version = value.schemaVersion
        case .telemetry(let value): version = value.schemaVersion
        case .supportDiagnostic(let value): version = value.schemaVersion
        }
        return version.major == Self.supportedSchema.major && version.minor <= Self.supportedSchema.minor
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, purpose, destination, scope, consentVersion,
             consentGrantedAt, pseudonyms, classification, payload, extensions,
             createdAt
    }

    /// Decode through the validating initializer so a persisted or manually
    /// crafted unsupported change set cannot become port input by decoding.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let purpose = try c.decode(ServiceEgressPurpose.self, forKey: .purpose)
        let consent = try ServiceEgressConsent(
            purpose: purpose,
            version: c.decode(Int.self, forKey: .consentVersion),
            grantedAt: c.decode(Date.self, forKey: .consentGrantedAt)
        )
        try self.init(
            id: c.decode(ServiceEgressChangeSetID.self, forKey: .id),
            schemaVersion: c.decode(ServiceEgressSchemaVersion.self, forKey: .schemaVersion),
            purpose: purpose,
            destination: c.decode(ServiceEgressDestination.self, forKey: .destination),
            scope: c.decode(ServiceEgressScope.self, forKey: .scope),
            consent: consent,
            classification: c.decode(ServiceEgressClassification.self, forKey: .classification),
            payload: c.decode(ServiceEgressPayload.self, forKey: .payload),
            extensions: c.decodeIfPresent([String].self, forKey: .extensions) ?? [],
            createdAt: c.decode(Date.self, forKey: .createdAt)
        )
    }
}

private extension ServiceEgressPayload {
    var classification: ServiceEgressClassification {
        switch self {
        case .hostedPersistence: .redactedSessionState
        case .telemetry: .aggregateTelemetry
        case .supportDiagnostic: .separatelyRedactedDiagnostic
        }
    }
}

private extension ServiceEgressDestination {
    var asPurpose: ServiceEgressPurpose {
        switch self {
        case .hostedPersistence: .hostedPersistence
        case .telemetry: .telemetry
        case .supportDiagnostic: .supportDiagnostic
        }
    }
}

public enum ServiceEgressDispatchStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case delivered
    case denied
    case unavailable
    case incompatible
    case failed
}

public enum ServiceEgressDispatchReason: String, Codable, CaseIterable, Hashable, Sendable {
    case delivered
    case noPort
    case consentNotGranted
    case consentRevoked
    case consentVersionChanged
    case purposeDisabled
    case unsupportedSchema
    case forbiddenClassification
    case portRejected
    case portUnavailable
    case portIncompatible
    case portFailed
}

/// Redacted local evidence for one attempted egress.  It records no payload,
/// endpoint, account, identifier, or error text, and therefore is safe to
/// show locally or include in a separately confirmed Diagnostic Bundle.
public struct ServiceEgressDiagnostic: Codable, Equatable, Hashable, Sendable {
    public let changeSetID: ServiceEgressChangeSetID
    public let purpose: ServiceEgressPurpose
    public let status: ServiceEgressDispatchStatus
    public let reason: ServiceEgressDispatchReason
    public let occurredAt: Date

    public init(changeSetID: ServiceEgressChangeSetID, purpose: ServiceEgressPurpose, status: ServiceEgressDispatchStatus, reason: ServiceEgressDispatchReason, occurredAt: Date) {
        self.changeSetID = changeSetID
        self.purpose = purpose
        self.status = status
        self.reason = reason
        self.occurredAt = occurredAt
    }
}
