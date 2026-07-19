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

public enum IntakeOutcome: Sendable, Equatable {
    case committed(ledgerRevision: Int64)
    case duplicateIgnored(ledgerRevision: Int64)
    case rejected(EnvelopeValidationError)
}
