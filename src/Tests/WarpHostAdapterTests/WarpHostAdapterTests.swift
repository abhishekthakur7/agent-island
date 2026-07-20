import XCTest
@testable import WarpHostAdapter
@testable import SessionDomain

final class WarpHostAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("warp-session"))
    private let installation = IntegrationInstanceID("warp-installation")

    func testAppOnlyNeverPromptsOrClaimsPaneOrTab() {
        let app = FixtureApplication(availability: .running)
        let accessibility = FixtureAccessibility(permission: .notDetermined)
        let port = WarpHostNavigationPort(applicationClient: app, accessibilityClient: accessibility)
        let outcome = jumpBack(port: port, locator: .warpApplication)

        XCTAssertEqual(outcome.qualifier, .appOnly)
        XCTAssertEqual(accessibility.promptCount, 0)
        XCTAssertEqual(app.activationCount, 1)
        XCTAssertTrue(WarpHostNavigationPort.feedback(level: outcome.qualifier, reason: nil).contains("pane and tab were not verified"))
    }

    func testElectionIsOnlyPermissionPromptPathAndDeniedFallsBackToAppOnly() {
        let app = FixtureApplication(availability: .running)
        let accessibility = FixtureAccessibility(permission: .denied)
        let port = WarpHostNavigationPort(applicationClient: app, accessibilityClient: accessibility)

        XCTAssertEqual(port.electCurrentFocusedWindowBestEffort(), .permissionNotGranted(.denied))
        XCTAssertEqual(accessibility.promptCount, 1)
        XCTAssertEqual(jumpBack(port: port, locator: .warpApplication).qualifier, .appOnly)
        XCTAssertEqual(accessibility.raiseCount, 0)
    }

    func testOnePersonElectedCurrentObjectCanOnlyReachWindowBestEffort() {
        let elected = WarpAccessibilityWindow.fixtureOpaqueWindow()
        let app = FixtureApplication(availability: .running)
        let accessibility = FixtureAccessibility(permission: .granted, focused: elected, windows: [elected])
        let port = WarpHostNavigationPort(applicationClient: app, accessibilityClient: accessibility)
        guard case .elected(let election) = port.electCurrentFocusedWindowBestEffort() else { return XCTFail("expected elected window") }

        let outcome = jumpBack(port: port, locator: election.locator)
        XCTAssertEqual(outcome.qualifier, .windowBestEffort)
        XCTAssertEqual(accessibility.raiseCount, 1)
        XCTAssertEqual(accessibility.promptCount, 0)
        XCTAssertFalse(outcome.qualifier.isExact)
        XCTAssertTrue(WarpHostNavigationPort.feedback(level: outcome.qualifier, reason: .ready).contains("pane and tab were not verified"))
    }

    func testZeroMultipleAndStaleCurrentObjectsFallBackWithoutFuzzyRebinding() {
        let elected = WarpAccessibilityWindow.fixtureOpaqueWindow()
        let sameTitleLookalike = WarpAccessibilityWindow.fixtureOpaqueWindow()
        let app = FixtureApplication(availability: .running)
        let accessibility = FixtureAccessibility(permission: .granted, focused: elected, windows: [elected])
        let port = WarpHostNavigationPort(applicationClient: app, accessibilityClient: accessibility)
        guard case .elected(let election) = port.electCurrentFocusedWindowBestEffort() else { return XCTFail("expected election") }

        accessibility.windows = []
        XCTAssertEqual(jumpBack(port: port, locator: election.locator).qualifier, .appOnly)
        accessibility.windows = [elected, elected]
        XCTAssertEqual(jumpBack(port: port, locator: election.locator).qualifier, .appOnly)
        accessibility.windows = [sameTitleLookalike]
        XCTAssertEqual(jumpBack(port: port, locator: election.locator).qualifier, .appOnly)
        XCTAssertEqual(accessibility.raiseCount, 0)
    }

    func testAbsentWarpIsUnavailableAndNoCustomURLOrInputSurfaceExists() {
        let app = FixtureApplication(availability: .absent)
        let accessibility = FixtureAccessibility(permission: .notDetermined)
        let port = WarpHostNavigationPort(applicationClient: app, accessibilityClient: accessibility)
        XCTAssertEqual(jumpBack(port: port, locator: .warpApplication).qualifier, .unavailable)
        XCTAssertEqual(accessibility.promptCount, 0)
        XCTAssertEqual(accessibility.raiseCount, 0)
    }

    private func jumpBack(port: WarpHostNavigationPort, locator: HostLocator) -> JumpBackOutcome {
        let association = HostContextAssociation(
            id: HostContextID("warp-context"), sessionIdentity: identity, host: .warp, hostVersion: "unknown",
            integrationInstanceID: installation, integrationMode: "warp-appkit-accessibility", incarnation: port.hostIncarnation,
            locator: locator,
            provenance: HostLocatorProvenance(host: .warp, evidence: locator.requiresAccessibility ? .accessibilityProbe : .applicationPresence, observedAt: now),
            firstObservedAt: now
        )
        let negotiation = NegotiationSnapshot(
            id: NegotiationSnapshotID("warp-negotiation"), contractVersion: .init(major: 1, minor: 0), adapterKind: "warp-host", adapterBuildVersion: "1",
            productNamespace: identity.productNamespace, integrationInstanceID: installation, integrationMode: "warp-appkit-accessibility",
            capabilities: [.init(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: .available)], negotiatedAt: now
        )
        return JumpBackCoordinator(evidence: .init([association]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: now))
    }
}

private final class FixtureApplication: @unchecked Sendable, WarpApplicationClient {
    let currentAvailability: WarpApplicationAvailability
    var activationCount = 0
    init(availability: WarpApplicationAvailability) { currentAvailability = availability }
    func availability() -> WarpApplicationAvailability { currentAvailability }
    func activateOrLaunch() -> Result<Void, WarpApplicationActivationFailure> { activationCount += 1; return currentAvailability == .absent ? .failure(.unavailable) : .success(()) }
}

private final class FixtureAccessibility: @unchecked Sendable, WarpAccessibilityClient {
    var permission: WarpAccessibilityPermissionState
    var focused: WarpAccessibilityWindow?
    var windows: [WarpAccessibilityWindow]
    var promptCount = 0
    var raiseCount = 0
    init(permission: WarpAccessibilityPermissionState, focused: WarpAccessibilityWindow? = nil, windows: [WarpAccessibilityWindow] = []) {
        self.permission = permission; self.focused = focused; self.windows = windows
    }
    func permissionState() -> WarpAccessibilityPermissionState { permission }
    func requestPermissionForExplicitElection() -> WarpAccessibilityPermissionState { promptCount += 1; return permission }
    func focusedWarpWindow() -> Result<WarpAccessibilityWindow?, WarpAccessibilityFailure> { .success(focused) }
    func currentWarpWindows() -> Result<[WarpAccessibilityWindow], WarpAccessibilityFailure> { .success(windows) }
    func isSameCurrentWindow(_ lhs: WarpAccessibilityWindow, _ rhs: WarpAccessibilityWindow) -> Bool { lhs === rhs }
    func raise(_ window: WarpAccessibilityWindow) -> Result<Void, WarpAccessibilityFailure> { raiseCount += 1; return .success(()) }
}
