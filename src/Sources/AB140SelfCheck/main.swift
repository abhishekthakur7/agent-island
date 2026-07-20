import Foundation
import ITerm2HostAdapter
import SessionDomain

private final class FixtureClient: @unchecked Sendable, ITerm2DocumentedAPIClient {
    var snapshot: ITerm2APISnapshot
    var activations: [(String?, String?, Bool)] = []

    init(snapshot: ITerm2APISnapshot) { self.snapshot = snapshot }
    func reprobe() -> Result<ITerm2APISnapshot, ITerm2APIClientFailure> { .success(snapshot) }
    func probe() -> Result<ITerm2APISnapshot, ITerm2APIClientFailure> { .success(snapshot) }
    func activate(sessionID: String?, tabID: String?, appOnly: Bool, expectedConnectionID: String?) -> Result<Void, ITerm2APIClientFailure> {
        activations.append((sessionID, tabID, appOnly))
        if expectedConnectionID != nil && expectedConnectionID != snapshot.connectionID { return .failure(.incarnationChanged) }
        if sessionID != nil && !snapshot.sessionIDs.contains(sessionID!) { return .failure(.targetUnavailable) }
        if tabID != nil && !snapshot.tabIDs.contains(tabID!) { return .failure(.targetUnavailable) }
        return .success(())
    }
}

@main
struct AB140SelfCheck {
    @MainActor static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("agent-session"))
        let integration = IntegrationInstanceID("iterm2-integration")
        let negotiation = NegotiationSnapshot(
            id: NegotiationSnapshotID("iterm2-snapshot"), contractVersion: .init(major: 1, minor: 0), adapterKind: "iterm2-host", adapterBuildVersion: "1", productNamespace: ProductNamespace("claude-code"), integrationInstanceID: integration, integrationMode: "iterm2-python-api", capabilities: [CapabilityRecord(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: .available)], negotiatedAt: now
        )
        let live = ITerm2APISnapshot(hostVersion: "3.5", connectionID: "connection-a", apiConnected: true, appAvailable: true, sessionIDs: ["pane-a"], tabIDs: ["tab-a"])
        let client = FixtureClient(snapshot: live)
        let capture = ITerm2HostContextCapture(client: client)
        guard case .success(let pane) = capture.captureSession(id: "pane-context", sessionIdentity: identity, integrationInstanceID: integration, integrationMode: "iterm2-python-api", sessionID: "pane-a", at: now) else { fail("source-proven-session-capture") }
        let port = ITerm2HostNavigationPort(client: client)
        let exact = JumpBackCoordinator(evidence: .init([pane]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: now))
        guard exact.qualifier == HostNavigationLevel.exactSurface, client.activations.count == 1, client.activations[0].0 == "pane-a", !exact.productActionGranted else { fail("exact-surface") }

        // Replacement is an explicit helper reprobe boundary. A locator
        // captured under connection-a cannot survive connection-b even when
        // the API reports the same opaque session ID.
        client.snapshot = ITerm2APISnapshot(hostVersion: "3.5", connectionID: "connection-b", apiConnected: true, appAvailable: true, sessionIDs: ["pane-a"], tabIDs: [])
        let replaced = JumpBackCoordinator(evidence: .init([pane]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: now))
        guard replaced.qualifier == HostNavigationLevel.appOnly,
              client.activations.last?.0 == nil else { fail("helper-incarnation-replacement") }
        client.snapshot = live

        guard case .success(let tab) = capture.captureTab(id: "tab-context", sessionIdentity: identity, integrationInstanceID: integration, integrationMode: "iterm2-python-api", tabID: "tab-a", at: now) else { fail("source-proven-tab-capture") }
        let tabResult = JumpBackCoordinator(evidence: .init([tab]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: now))
        guard tabResult.qualifier == HostNavigationLevel.exactTab, tabResult.presentationLabel.contains("select the pane") else { fail("exact-tab-feedback") }

        client.snapshot = ITerm2APISnapshot(hostVersion: "3.5", connectionID: "connection-b", apiConnected: true, appAvailable: true, sessionIDs: ["pane-a"], tabIDs: [])
        let relaunched = JumpBackCoordinator(evidence: .init([pane]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: now))
        guard relaunched.qualifier == HostNavigationLevel.appOnly else { fail("incarnation-change-downgrade") }

        let composition = ITerm2HostNavigationComposition(port: port)
        composition.record(association: pane)
        composition.register(navigationNegotiation: negotiation)
        let composedRelaunch = composition.jumpBack(for: identity, at: now)
        guard composedRelaunch.qualifier == HostNavigationLevel.appOnly,
              composition.associations(for: identity).first?.isInvalidated == true,
              composition.attempts.count == 1 else { fail("relaunch-history-preserved") }

        client.snapshot = ITerm2APISnapshot(hostVersion: "3.5", connectionID: "connection-a", apiConnected: true, appAvailable: true, sessionIDs: ["pane-a", "pane-a"], tabIDs: [])
        let duplicate = JumpBackCoordinator(evidence: .init([pane]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: now))
        guard duplicate.qualifier == HostNavigationLevel.appOnly else { fail("duplicate-pane-downgrade") }

        client.snapshot = ITerm2APISnapshot(hostVersion: "3.5", connectionID: "connection-a", apiConnected: true, appAvailable: true, sessionIDs: ["similar-pane"], tabIDs: [])
        let fuzzy = JumpBackCoordinator(evidence: .init([pane]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: now))
        guard fuzzy.qualifier == HostNavigationLevel.appOnly, !client.activations.contains(where: { $0.0 == "similar-pane" }) else { fail("fuzzy-never-rebound") }

        print("AB140SelfCheck PASS persistent-incarnation exactSurface exactTab relaunch duplicates fuzzy appOnly no-terminal-input")
    }

    private static func fail(_ stage: String) -> Never {
        FileHandle.standardError.write(Data("AB140SelfCheck failed: \(stage)\n".utf8))
        exit(EXIT_FAILURE)
    }
}
