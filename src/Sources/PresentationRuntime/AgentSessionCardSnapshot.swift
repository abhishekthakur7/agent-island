import SessionDomain

/// The only shape SwiftUI/AppKit code ever sees. Identity
/// (`productNamespace`/`nativeSessionID`) is always present and never
/// invented; sourced display fields are optional and stay `nil` — never a
/// placeholder — when the Product hasn't supplied them.
public struct AgentSessionCardSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    public let productNamespace: String
    public let nativeSessionID: String
    public let execution: ExecutionState
    public let observation: ObservationState
    public let displayTitle: String?
    public let hostLabel: String?
    public let ledgerRevision: Int64

    public init(projection: SessionProjection) {
        self.id = "\(projection.identity.productNamespace.rawValue)::\(projection.identity.nativeSessionID.rawValue)"
        self.productNamespace = projection.identity.productNamespace.rawValue
        self.nativeSessionID = projection.identity.nativeSessionID.rawValue
        self.execution = projection.execution
        self.observation = projection.observation
        self.displayTitle = projection.displayTitle
        self.hostLabel = projection.hostLabel
        self.ledgerRevision = projection.ledgerRevision
    }
}
