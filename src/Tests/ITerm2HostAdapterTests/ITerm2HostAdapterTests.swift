import XCTest
@testable import ITerm2HostAdapter
@testable import SessionDomain

final class ITerm2HostAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("agent-session"))
    private let installation = IntegrationInstanceID("iterm2-installation")

    private func negotiation() -> NegotiationSnapshot {
        .init(id: NegotiationSnapshotID("snapshot"), contractVersion: .init(major: 1, minor: 0), adapterKind: "iterm2-host", adapterBuildVersion: "1", productNamespace: ProductNamespace("claude-code"), integrationInstanceID: installation, integrationMode: "iterm2-python-api", capabilities: [.init(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: .available)], negotiatedAt: now)
    }

    func testExactSurfaceUsesOnlyLiveDocumentedSessionID() {
        let client = TestClient(snapshot: .init(hostVersion: "3.5", connectionID: "connection", apiConnected: true, appAvailable: true, sessionIDs: ["session-1"]))
        let capture = ITerm2HostContextCapture(client: client)
        let context = try! capture.captureSession(id: "context", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "iterm2-python-api", sessionID: "session-1", at: now).get()
        let outcome = JumpBackCoordinator(evidence: .init([context]), port: ITerm2HostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, .exactSurface)
        XCTAssertEqual(client.activatedSession, "session-1")
        XCTAssertFalse(outcome.productActionGranted)
    }

    func testClosureAndRestartInvalidateExactSessionAndNeverFuzzyRebind() {
        let client = TestClient(snapshot: .init(connectionID: "connection-a", apiConnected: true, appAvailable: true, sessionIDs: ["session-1"]))
        let context = try! ITerm2HostContextCapture(client: client).captureSession(id: "context", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "iterm2-python-api", sessionID: "session-1", at: now).get()
        client.snapshot = .init(connectionID: "connection-b", apiConnected: true, appAvailable: true, sessionIDs: ["similar-session"])
        let outcome = JumpBackCoordinator(evidence: .init([context]), port: ITerm2HostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, .appOnly)
        XCTAssertNil(client.activatedSession)
    }

    func testPersistentHelperIncarnationReplacementDowngradesBeforeActivation() {
        let client = TestClient(snapshot: .init(connectionID: "helper-a", apiConnected: true, appAvailable: true, sessionIDs: ["session-1"]))
        let context = try! ITerm2HostContextCapture(client: client).captureSession(id: "context", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "iterm2-python-api", sessionID: "session-1", at: now).get()
        // This models an explicit reprobe after helper/API loss. The session ID
        // deliberately remains equal to prove it cannot bridge incarnations.
        client.snapshot = .init(connectionID: "helper-b", apiConnected: true, appAvailable: true, sessionIDs: ["session-1"])
        let outcome = JumpBackCoordinator(evidence: .init([context]), port: ITerm2HostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, .appOnly)
        XCTAssertNil(client.activatedSession)
    }

    func testExactTabIsSeparateAndTellsPersonToSelectPane() {
        let client = TestClient(snapshot: .init(connectionID: "connection", apiConnected: true, appAvailable: true, tabIDs: ["tab-1"]))
        let context = try! ITerm2HostContextCapture(client: client).captureTab(id: "tab-context", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "iterm2-python-api", tabID: "tab-1", at: now).get()
        let outcome = JumpBackCoordinator(evidence: .init([context]), port: ITerm2HostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, .exactTab)
        XCTAssertTrue(outcome.voiceOverLabel.contains("select the pane"))
    }
}

private final class TestClient: @unchecked Sendable, ITerm2DocumentedAPIClient {
    var snapshot: ITerm2APISnapshot
    var activatedSession: String?
    init(snapshot: ITerm2APISnapshot) { self.snapshot = snapshot }
    func reprobe() -> Result<ITerm2APISnapshot, ITerm2APIClientFailure> { .success(snapshot) }
    func probe() -> Result<ITerm2APISnapshot, ITerm2APIClientFailure> { .success(snapshot) }
    func activate(sessionID: String?, tabID: String?, appOnly: Bool, expectedConnectionID: String?) -> Result<Void, ITerm2APIClientFailure> {
        activatedSession = sessionID
        if expectedConnectionID != nil && expectedConnectionID != snapshot.connectionID { return .failure(.incarnationChanged) }
        if sessionID != nil && !snapshot.sessionIDs.contains(sessionID!) { return .failure(.targetUnavailable) }
        if tabID != nil && !snapshot.tabIDs.contains(tabID!) { return .failure(.targetUnavailable) }
        return .success(())
    }
}
