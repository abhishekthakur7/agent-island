import SessionDomain

/// The typed inward-facing port an Agent Adapter — first-party or fixture —
/// uses to reach `ApplicationRuntime`. It is the *only* boundary: this
/// package's dependency graph gives an Adapter no way to hold the canonical
/// store or a database/key handle, mutate a card directly, or bypass
/// validation and classification. `ApplicationRuntime` is the sole conformer.
public protocol AdapterIntakePort: Sendable {
    /// Read-only discovery is part of the inward boundary.  The default
    /// implementation is pure and does not alter enabled intent or external
    /// configuration, preserving compatibility for existing runtimes.
    func discover(_ request: DiscoveryRequest) async -> DiscoveryResult
    func negotiate(_ request: NegotiationRequest) async -> NegotiationOutcome
    func deliver(_ envelope: RawEventEnvelope) async -> IntakeOutcome
    func reportObservationBoundary(_ report: ObservationBoundaryReport) async -> IntakeOutcome
}

public extension AdapterIntakePort {
    func discover(_ request: DiscoveryRequest) async -> DiscoveryResult {
        ReadOnlyAdapterDiscovery.discover(request)
    }
}
