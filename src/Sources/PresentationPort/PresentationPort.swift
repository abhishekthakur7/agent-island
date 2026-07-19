import SessionDomain

/// The typed outward-facing port `PresentationRuntime` subscribes through.
/// It exposes only an immutable, revisioned projection stream — never the
/// canonical store, an Adapter client, or a command path. `ApplicationRuntime`
/// is the sole conformer, so this package's dependency graph gives the UI no
/// way to reach `SessionStore` or `AdapterIntakePort` directly.
public protocol PresentationPort: Sendable {
    func presentationStream() -> AsyncStream<ProjectionRevision>
}
