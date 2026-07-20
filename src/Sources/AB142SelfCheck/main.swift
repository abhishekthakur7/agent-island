import Foundation
import SessionDomain
import WarpHostAdapter

private final class FixtureApplication: @unchecked Sendable, WarpApplicationClient {
    var current: WarpApplicationAvailability
    var activations = 0
    init(_ current: WarpApplicationAvailability) { self.current = current }
    func availability() -> WarpApplicationAvailability { current }
    func activateOrLaunch() -> Result<Void, WarpApplicationActivationFailure> { activations += 1; return current == .absent ? .failure(.unavailable) : .success(()) }
}

private final class FixtureAccessibility: @unchecked Sendable, WarpAccessibilityClient {
    var permission: WarpAccessibilityPermissionState
    var focused: WarpAccessibilityWindow?
    var windows: [WarpAccessibilityWindow]
    var prompts = 0
    var raises = 0
    init(permission: WarpAccessibilityPermissionState, focused: WarpAccessibilityWindow? = nil, windows: [WarpAccessibilityWindow] = []) { self.permission = permission; self.focused = focused; self.windows = windows }
    func permissionState() -> WarpAccessibilityPermissionState { permission }
    func requestPermissionForExplicitElection() -> WarpAccessibilityPermissionState { prompts += 1; return permission }
    func focusedWarpWindow() -> Result<WarpAccessibilityWindow?, WarpAccessibilityFailure> { .success(focused) }
    func currentWarpWindows() -> Result<[WarpAccessibilityWindow], WarpAccessibilityFailure> { .success(windows) }
    func isSameCurrentWindow(_ lhs: WarpAccessibilityWindow, _ rhs: WarpAccessibilityWindow) -> Bool { lhs === rhs }
    func raise(_ window: WarpAccessibilityWindow) -> Result<Void, WarpAccessibilityFailure> { raises += 1; return .success(()) }
}

@main
struct AB142SelfCheck {
    @MainActor static func main() {
        let electedWindow = WarpAccessibilityWindow.fixtureOpaqueWindow()
        let app = FixtureApplication(.running)
        let accessibility = FixtureAccessibility(permission: .notDetermined, focused: electedWindow, windows: [electedWindow])
        let port = WarpHostNavigationPort(applicationClient: app, accessibilityClient: accessibility)
        guard jump(port, locator: .warpApplication).qualifier == .appOnly, accessibility.prompts == 0 else { fail("app-only-no-automatic-prompt") }
        accessibility.permission = .denied
        guard case .permissionNotGranted(.denied) = port.electCurrentFocusedWindowBestEffort(), accessibility.prompts == 1 else { fail("denied-election") }
        accessibility.permission = .granted
        guard case .elected(let election) = port.electCurrentFocusedWindowBestEffort() else { fail("explicit-current-window-election") }
        let exactOne = jump(port, locator: election.locator)
        guard exactOne.qualifier == .windowBestEffort, accessibility.raises == 1, !exactOne.qualifier.isExact,
              WarpHostNavigationPort.feedback(level: exactOne.qualifier, reason: .ready).contains("pane and tab were not verified") else { fail("one-window-best-effort-only") }
        accessibility.windows = []
        guard jump(port, locator: election.locator).qualifier == .appOnly else { fail("zero-window-app-only") }
        accessibility.windows = [electedWindow, electedWindow]
        guard jump(port, locator: election.locator).qualifier == .appOnly, accessibility.raises == 1 else { fail("multiple-window-app-only") }
        let restarted = WarpHostNavigationPort(applicationClient: app, accessibilityClient: accessibility)
        guard jump(restarted, locator: election.locator).qualifier == .appOnly else { fail("stale-election-app-only") }
        let absent = WarpHostNavigationPort(applicationClient: FixtureApplication(.absent), accessibilityClient: FixtureAccessibility(permission: .notDetermined))
        guard jump(absent, locator: .warpApplication).qualifier == .unavailable else { fail("absent-warp-unavailable") }
        print("AB142SelfCheck PASS appOnly explicit-AX-election one-window-best-effort denied zero multiple stale absent no-input-no-custom-url")
    }

    private static func jump(_ port: WarpHostNavigationPort, locator: HostLocator) -> JumpBackOutcome {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("warp-session"))
        let installation = IntegrationInstanceID("warp-installation")
        let association = HostContextAssociation(id: "warp-context", sessionIdentity: identity, host: .warp, integrationInstanceID: installation, integrationMode: "warp-appkit-accessibility", incarnation: port.hostIncarnation, locator: locator, provenance: .init(host: .warp, evidence: locator.requiresAccessibility ? .accessibilityProbe : .applicationPresence, observedAt: now), firstObservedAt: now)
        let negotiation = NegotiationSnapshot(id: NegotiationSnapshotID("warp-negotiation"), contractVersion: .init(major: 1, minor: 0), adapterKind: "warp-host", adapterBuildVersion: "1", productNamespace: identity.productNamespace, integrationInstanceID: installation, integrationMode: "warp-appkit-accessibility", capabilities: [.init(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: .available)], negotiatedAt: now)
        return JumpBackCoordinator(evidence: .init([association]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: now))
    }

    private static func fail(_ stage: String) -> Never {
        FileHandle.standardError.write(Data("AB142SelfCheck failed: \(stage)\n".utf8))
        exit(EXIT_FAILURE)
    }
}
