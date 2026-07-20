import Foundation
import CursorHostAdapter
import SessionDomain

// This source is intentionally not package-registered during AB-141's
// private phase. The serialized registration owner will add the target with
// CursorHostAdapter + SessionDomain dependencies after review.
@main struct AB141SelfCheck {
    static func main() {
        let identity = AgentSessionIdentity(productNamespace: .init("cursor"), nativeSessionID: .init("self-check"))
        let integration = IntegrationInstanceID("cursor-host-self-check")
        let endpoint = FixtureEndpoint(identity: identity)
        let port = CursorHostNavigationPort(endpoint: endpoint, application: endpoint)
        let capture = CursorHostContextCapture(endpoint: endpoint)
        let registration = CursorExtensionLiveTerminalRegistration(endpointID: "fixture", incarnation: "extension-a", cursorVersion: "fixture", sessionIdentity: identity, terminalReference: "terminal-ref", authentication: .init(keyID: "fixture", proof: Data([1])))
        guard case .success(let captured) = capture.captureLiveTerminalContext(id: "cursor-context", sessionIdentity: identity, integrationInstanceID: integration, registration: registration, at: Date()) else { fail("capture") }
        let snapshot = NegotiationSnapshot(id: .init("cursor-host-self-check"), contractVersion: .init(major: 1, minor: 0), adapterKind: CursorHostContract.adapterKind, adapterBuildVersion: "1", productNamespace: identity.productNamespace, integrationInstanceID: integration, integrationMode: CursorHostContract.integrationMode, capabilities: [.init(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: .available)], negotiatedAt: Date())
        port.retain(captured)
        let exact = JumpBackCoordinator(evidence: .init([captured.association]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: snapshot, requestedAt: Date()))
        guard exact.qualifier == .exactSurface, endpoint.revealed else { fail("exact-live-reference") }
        endpoint.closed = true
        let closed = JumpBackCoordinator(evidence: .init([captured.association]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: snapshot, requestedAt: Date()))
        guard closed.qualifier == .appOnly else { fail("closure-fallback") }
        print("AB141SelfCheck PASS authenticated-incarnation retained-live-reference exactSurface closure-appOnly no-deep-link-or-input")
    }
    private static func fail(_ stage: String) -> Never { FileHandle.standardError.write(Data("AB141SelfCheck failed: \(stage)\n".utf8)); exit(EXIT_FAILURE) }
}

private final class FixtureEndpoint: @unchecked Sendable, CursorExtensionEndpointClient, CursorApplicationClient {
    let identity: AgentSessionIdentity; var binding: CursorExtensionEndpointBinding?; var closed = false; var revealed = false
    init(identity: AgentSessionIdentity) { self.identity = identity }
    func registerLiveTerminal(_ r: CursorExtensionLiveTerminalRegistration) -> Result<CursorExtensionEndpointBinding, CursorExtensionEndpointFailure> { let b = CursorExtensionEndpointBinding(endpointID: r.endpointID, incarnation: r.incarnation, protocolVersion: r.protocolVersion, cursorVersion: r.cursorVersion, sessionIdentity: r.sessionIdentity, terminalReference: r.terminalReference); binding = b; return .success(b) }
    func registerNativeThread(_ r: CursorExtensionNativeThreadRegistration) -> Result<CursorExtensionEndpointBinding, CursorExtensionEndpointFailure> { .failure(.registrationRejected) }
    func status(for b: CursorExtensionEndpointBinding) -> Result<CursorExtensionEndpointStatus, CursorExtensionEndpointFailure> { .success(.init(endpointID: b.endpointID, incarnation: b.incarnation, protocolVersion: 1, cursorVersion: b.cursorVersion, authenticated: true, connected: true, applicationAvailable: true, matchingLiveReferenceCount: closed ? 0 : 1)) }
    func workspaceFileProof(for b: CursorExtensionEndpointBinding, sessionIdentity: AgentSessionIdentity) -> Result<CursorWorkspaceFileProof?, CursorExtensionEndpointFailure> { .success(nil) }
    func revealLiveTerminal(_ b: CursorExtensionEndpointBinding) -> Result<Void, CursorExtensionEndpointFailure> { guard !closed else { return .failure(.terminalUnavailable) }; revealed = true; return .success(()) }
    func revealWorkspaceOrFile(_ p: CursorWorkspaceFileProof, through b: CursorExtensionEndpointBinding) -> Result<Void, CursorExtensionEndpointFailure> { .failure(.dispatchRejected) }
    func status() -> CursorApplicationState { .available }
    func activate() -> Result<Void, CursorExtensionEndpointFailure> { .success(()) }
}
