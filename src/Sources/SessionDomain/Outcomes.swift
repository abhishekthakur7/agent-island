/// A degradation/transport signal, kept separate from `RawEventEnvelope`
/// because it never carries owner-asserted lifecycle content — only the
/// negotiated scope and a reason. It can only ever move a session toward
/// `unresolved`/`unavailable`, never toward a terminal outcome.
public struct ObservationBoundaryReport: Sendable {
    public let negotiationSnapshotID: NegotiationSnapshotID
    public let integrationInstanceID: IntegrationInstanceID
    public let identity: AgentSessionIdentity
    public let reason: ObservationBoundaryReason

    public init(
        negotiationSnapshotID: NegotiationSnapshotID,
        integrationInstanceID: IntegrationInstanceID,
        identity: AgentSessionIdentity,
        reason: ObservationBoundaryReason
    ) {
        self.negotiationSnapshotID = negotiationSnapshotID
        self.integrationInstanceID = integrationInstanceID
        self.identity = identity
        self.reason = reason
    }
}

/// Redacted storage-fault reason for the protected canonical store (AB-119).
/// No path, key, SQL, or payload ever attaches to a case here — only a
/// stable, presentable reason a person can act on.
public enum StorageFailureReason: String, Sendable, Equatable, Codable {
    case keychainKeyMissing
    case integrityCheckFailed
    case interruptedWrite
    case unsupportedSchema
    case migrationFailed
    case unavailable
}

public enum IntakeOutcome: Sendable, Equatable {
    case committed(ledgerRevision: Int64)
    case duplicateIgnored(ledgerRevision: Int64)
    case rejected(EnvelopeValidationError)
    /// The envelope validated, but the protected store fail-closed before the
    /// fact could be durably committed. No ghost card is created: an
    /// in-memory-only projection never advances without a matching durable
    /// write (AB-119 AC1).
    case storageUnavailable(StorageFailureReason)
}
