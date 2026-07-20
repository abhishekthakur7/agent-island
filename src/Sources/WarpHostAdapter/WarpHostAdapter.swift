@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation
import SessionDomain

/// Warp has no documented local selector for a pane, tab, block, or window.
/// This boundary therefore exposes only application activation and a
/// deliberately elected, process-local Accessibility window reference.
public enum WarpApplicationAvailability: String, Hashable, Sendable {
    case running
    case launchable
    case absent
}

public enum WarpApplicationActivationFailure: String, Error, Hashable, Sendable {
    case unavailable
    case rejectedBySystem
}

/// Outer seam for the one supported baseline: foregrounding or launching the
/// Warp application. It deliberately has no URL, title, path, tab, pane, or
/// block argument.
public protocol WarpApplicationClient: Sendable {
    func availability() -> WarpApplicationAvailability
    func activateOrLaunch() -> Result<Void, WarpApplicationActivationFailure>
}

/// The real NSWorkspace boundary. `open(_:)` receives only Warp's registered
/// application bundle URL; it is not a custom-destination or URL-scheme route.
public final class NSWorkspaceWarpApplicationClient: @unchecked Sendable, WarpApplicationClient {
    public static let bundleIdentifier = "dev.warp.Warp-Stable"

    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func availability() -> WarpApplicationAvailability {
        if runningApplication() != nil { return .running }
        return workspace.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) == nil ? .absent : .launchable
    }

    public func activateOrLaunch() -> Result<Void, WarpApplicationActivationFailure> {
        if let running = runningApplication() {
            return running.activate(options: []) ? .success(()) : .failure(.rejectedBySystem)
        }
        guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            return .failure(.unavailable)
        }
        return workspace.open(applicationURL) ? .success(()) : .failure(.rejectedBySystem)
    }

    private func runningApplication() -> NSRunningApplication? {
        workspace.runningApplications.first { $0.bundleIdentifier == Self.bundleIdentifier && !$0.isTerminated }
    }
}

public enum WarpAccessibilityPermissionState: String, Hashable, Sendable {
    case granted
    case notDetermined
    case denied

    fileprivate var hostPermission: HostPermissionState {
        switch self {
        case .granted: .granted
        case .notDetermined: .unknown
        case .denied: .denied
        }
    }
}

public enum WarpAccessibilityFailure: String, Error, Hashable, Sendable {
    case applicationUnavailable
    case permissionNotGranted
    case queryFailed
    case raiseFailed
}

/// An opaque reference to one current AX window. It has no public initializer
/// accepting title, label, URL, path, text, geometry, or any other metadata.
/// The fixture factory exists solely for the controllable client seam and
/// cannot manufacture a real Accessibility target.
public final class WarpAccessibilityWindow: @unchecked Sendable {
    fileprivate let element: AXUIElement?
    fileprivate let fixtureIdentity = UUID()

    fileprivate init(element: AXUIElement?) {
        self.element = element
    }

    public static func fixtureOpaqueWindow() -> WarpAccessibilityWindow {
        WarpAccessibilityWindow(element: nil)
    }
}

/// Read-only/window-raise Accessibility seam. No operation models keyboard
/// events, pointer clicks, text entry, focus traversal, or any Product input.
public protocol WarpAccessibilityClient: Sendable {
    /// Reads current trust without opening a system prompt.
    func permissionState() -> WarpAccessibilityPermissionState
    /// May display macOS's Accessibility prompt. This must be called only by
    /// the explicit person-election API below.
    func requestPermissionForExplicitElection() -> WarpAccessibilityPermissionState
    /// Returns the current focused Warp window after a person has elected it
    /// in Warp itself; it is never chosen using presentation metadata.
    func focusedWarpWindow() -> Result<WarpAccessibilityWindow?, WarpAccessibilityFailure>
    /// Enumerates only the currently live Warp AX windows for identity
    /// revalidation. Callers must not retain this as a durable locator.
    func currentWarpWindows() -> Result<[WarpAccessibilityWindow], WarpAccessibilityFailure>
    /// Exact object identity comparison inside one live Accessibility probe.
    func isSameCurrentWindow(_ lhs: WarpAccessibilityWindow, _ rhs: WarpAccessibilityWindow) -> Bool
    /// Raises the exact current window. This is not click/key/text automation.
    func raise(_ window: WarpAccessibilityWindow) -> Result<Void, WarpAccessibilityFailure>
}

/// Real macOS Accessibility boundary for the known Warp application. macOS
/// does not expose a reliable read-only distinction between a denial and a
/// not-yet-answered trust request, so an untrusted process is represented as
/// `.notDetermined`; the fixture seam covers an explicit denial/revocation.
public final class MacOSWarpAccessibilityClient: @unchecked Sendable, WarpAccessibilityClient {
    private let applicationClient: WarpApplicationClient
    private let processIdentifier: () -> pid_t?

    public init(applicationClient: WarpApplicationClient = NSWorkspaceWarpApplicationClient()) {
        self.applicationClient = applicationClient
        self.processIdentifier = {
            guard case .running = applicationClient.availability(),
                  applicationClient is NSWorkspaceWarpApplicationClient else { return nil }
            return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == NSWorkspaceWarpApplicationClient.bundleIdentifier })?.processIdentifier
        }
    }

    /// Injectable only for tests/platform seams that own their own process
    /// lookup. Production callers should use `init(applicationClient:)`.
    public init(applicationClient: WarpApplicationClient, processIdentifier: @escaping @Sendable () -> pid_t?) {
        self.applicationClient = applicationClient
        self.processIdentifier = processIdentifier
    }

    public func permissionState() -> WarpAccessibilityPermissionState {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    public func requestPermissionForExplicitElection() -> WarpAccessibilityPermissionState {
        guard !AXIsProcessTrusted() else { return .granted }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return permissionState()
    }

    public func focusedWarpWindow() -> Result<WarpAccessibilityWindow?, WarpAccessibilityFailure> {
        guard let application = warpApplicationElement() else { return .failure(.applicationUnavailable) }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
        guard status == .success else { return status == .noValue ? .success(nil) : .failure(.queryFailed) }
        guard let window = value as! AXUIElement? else { return .success(nil) }
        return .success(WarpAccessibilityWindow(element: window))
    }

    public func currentWarpWindows() -> Result<[WarpAccessibilityWindow], WarpAccessibilityFailure> {
        guard let application = warpApplicationElement() else { return .failure(.applicationUnavailable) }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard status == .success else { return status == .noValue ? .success([]) : .failure(.queryFailed) }
        guard let windows = value as? [AXUIElement] else { return .failure(.queryFailed) }
        return .success(windows.map { WarpAccessibilityWindow(element: $0) })
    }

    public func isSameCurrentWindow(_ lhs: WarpAccessibilityWindow, _ rhs: WarpAccessibilityWindow) -> Bool {
        switch (lhs.element, rhs.element) {
        case let (left?, right?): CFEqual(left, right)
        case (nil, nil): lhs.fixtureIdentity == rhs.fixtureIdentity
        default: false
        }
    }

    public func raise(_ window: WarpAccessibilityWindow) -> Result<Void, WarpAccessibilityFailure> {
        guard let element = window.element else { return .failure(.raiseFailed) }
        return AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success ? .success(()) : .failure(.raiseFailed)
    }

    private func warpApplicationElement() -> AXUIElement? {
        guard case .running = applicationClient.availability(), let processIdentifier = processIdentifier() else { return nil }
        return AXUIElementCreateApplication(processIdentifier)
    }
}

/// A successful explicit election. Its token is process-local and becomes
/// stale if this adapter is recreated; it is never a durable Warp identity.
public struct WarpWindowBestEffortElection: Hashable, Sendable {
    public let locator: HostLocator
    /// Per-adapter live incarnation to pair with the association. It is an
    /// Agent Island process boundary, not a Warp window/tab/pane identifier.
    public let hostIncarnation: HostIncarnation
    public let explanatoryLabel: String

    fileprivate init(token: String, hostIncarnation: HostIncarnation) {
        self.locator = .warpAXWindow(candidateToken: token)
        self.hostIncarnation = hostIncarnation
        self.explanatoryLabel = "Use Warp’s currently focused window as a best-effort Jump Back target. The original Warp pane and tab will not be verified."
    }
}

public enum WarpWindowBestEffortElectionResult: Hashable, Sendable {
    case elected(WarpWindowBestEffortElection)
    case applicationUnavailable
    case permissionNotGranted(WarpAccessibilityPermissionState)
    case noFocusedWindow
    case queryFailed

    public var accessibilityLabel: String {
        switch self {
        case .elected: "Warp best-effort window elected. Original pane and tab are unverified."
        case .applicationUnavailable: "Warp is unavailable; no best-effort window was elected."
        case .permissionNotGranted: "Accessibility permission was not granted; Warp application-only Jump Back remains available when Warp is installed."
        case .noFocusedWindow: "No current focused Warp window was elected."
        case .queryFailed: "Warp window query failed; no best-effort window was elected."
        }
    }
}

/// AppKit/Accessibility Host boundary for Warp. The only call that can prompt
/// for Accessibility is `electCurrentFocusedWindowBestEffort()`, which a UI
/// must invoke directly from a person's contextual election.
public final class WarpHostNavigationPort: @unchecked Sendable, HostNavigationPort {
    private struct ElectedWindow: @unchecked Sendable {
        let window: WarpAccessibilityWindow
    }

    private let applicationClient: WarpApplicationClient
    private let accessibilityClient: WarpAccessibilityClient
    private let lock = NSLock()
    private var electedWindows: [String: ElectedWindow] = [:]
    /// This deliberately changes when the outer adapter is recreated, making
    /// all old elected AX object tokens stale rather than rebindable.
    public let hostIncarnation: HostIncarnation

    public init(
        applicationClient: WarpApplicationClient = NSWorkspaceWarpApplicationClient(),
        accessibilityClient: WarpAccessibilityClient? = nil,
        hostIncarnation: HostIncarnation = .init("warp-adapter-\(UUID().uuidString.lowercased())")
    ) {
        self.applicationClient = applicationClient
        self.accessibilityClient = accessibilityClient ?? MacOSWarpAccessibilityClient(applicationClient: applicationClient)
        self.hostIncarnation = hostIncarnation
    }

    /// Explicit opt-in API. It is intentionally separate from revalidation
    /// and navigation, so those automatic paths can never cause a permission
    /// prompt. The person must first focus the desired Warp window themselves.
    public func electCurrentFocusedWindowBestEffort() -> WarpWindowBestEffortElectionResult {
        guard applicationClient.availability() == .running else { return .applicationUnavailable }
        let permission = accessibilityClient.permissionState()
        let granted = permission == .granted ? permission : accessibilityClient.requestPermissionForExplicitElection()
        guard granted == .granted else { return .permissionNotGranted(granted) }
        switch accessibilityClient.focusedWarpWindow() {
        case .success(let window?):
            let token = UUID().uuidString.lowercased()
            lock.lock()
            electedWindows[token] = ElectedWindow(window: window)
            lock.unlock()
            return .elected(WarpWindowBestEffortElection(token: token, hostIncarnation: hostIncarnation))
        case .success(nil): return .noFocusedWindow
        case .failure: return .queryFailed
        }
    }

    /// Elected AX objects are process-local and are never valid across a
    /// wake or restart. Clearing them cannot affect Product lifecycle.
    public func invalidateElectedWindows() {
        lock.lock()
        electedWindows.removeAll()
        lock.unlock()
    }

    public func revalidate(
        _ association: HostContextAssociation,
        for sessionIdentity: AgentSessionIdentity,
        negotiation: NegotiationSnapshot?,
        at date: Date
    ) -> HostNavigationRevalidation {
        let availability = applicationClient.availability()
        let applicationState: HostApplicationState = availability == .absent ? .absent : .available
        // AX trust gates only the optional AX locator. App activation uses
        // NSWorkspace and remains intentionally independent of that grant.
        let accessibilityPermission = accessibilityClient.permissionState()
        let navigationPermission: HostPermissionState = association.locator.requiresAccessibility
            ? accessibilityPermission.hostPermission
            : .notRequired
        var proven: Set<HostNavigationLevel> = applicationState == .available ? [.appOnly] : []
        var candidateCount = 0
        var currentToken: String?
        var optedIn = false

        if case .warpAXWindow(let token) = association.locator,
           availability == .running,
           accessibilityPermission == .granted,
           let elected = electedWindow(for: token) {
            optedIn = true
            switch accessibilityClient.currentWarpWindows() {
            case .success(let windows):
                candidateCount = windows.filter { accessibilityClient.isSameCurrentWindow(elected.window, $0) }.count
                if candidateCount == 1 {
                    proven.insert(.windowBestEffort)
                    currentToken = token
                }
            case .failure:
                // The app-only observation remains valid. A failed AX probe
                // never triggers a second query or an inferred replacement.
                break
            }
        }

        let observation = HostRuntimeObservation(
            host: .warp,
            integrationMode: association.integrationMode,
            incarnation: hostIncarnation,
            applicationState: applicationState,
            permission: navigationPermission,
            locatorState: .live,
            provenLevels: proven,
            candidateCount: candidateCount,
            currentAXCandidateToken: currentToken,
            accessibilityOptIn: optedIn
        )
        return HostNavigationPolicy.revalidate(
            association: association,
            sessionIdentity: sessionIdentity,
            negotiation: negotiation,
            observation: observation,
            at: date
        )
    }

    public func navigate(_ target: HostNavigationTarget, at date: Date) -> HostNavigationDispatch {
        guard target.host == .warp else { return .rejected(.unsupportedHost) }
        switch target.level {
        case .appOnly:
            return activateApplication()
        case .windowBestEffort:
            guard case .warpAXWindow(let token) = target.locator,
                  accessibilityClient.permissionState() == .granted,
                  let elected = electedWindow(for: token),
                  case .success(let windows) = accessibilityClient.currentWarpWindows(),
                  windows.filter({ accessibilityClient.isSameCurrentWindow(elected.window, $0) }).count == 1 else {
                return .rejected(.noSeparatelyProvenFallback)
            }
            guard case .success = applicationClient.activateOrLaunch() else { return .rejected(.dispatchFailed) }
            return accessibilityClient.raise(elected.window).isSuccess ? .reached : .rejected(.dispatchFailed)
        case .exactSurface, .exactTab, .workspaceOrFile, .unavailable:
            return .rejected(.noSeparatelyProvenFallback)
        }
    }

    /// Copy for UI/VoiceOver and redacted diagnostics. This boundary names the
    /// achieved level and never includes AX labels, title, URL, path, text, or
    /// any candidate token.
    public static func feedback(level: HostNavigationLevel, reason: HostNavigationRevalidationReason?) -> String {
        let result: String
        switch level {
        case .windowBestEffort: result = "Brought forward one elected Warp window best-effort; the original Warp pane and tab were not verified."
        case .appOnly: result = "Opened Warp; the original Warp pane and tab were not verified."
        case .unavailable: result = "Warp Jump Back is unavailable; no Warp pane or tab was verified."
        case .exactSurface, .exactTab, .workspaceOrFile: result = "Warp does not support this Jump Back level."
        }
        guard let reason else { return result }
        return "\(result) Reason: \(reason.redactedDescription)"
    }

    private func activateApplication() -> HostNavigationDispatch {
        switch applicationClient.activateOrLaunch() {
        case .success: .reached
        case .failure: .rejected(.hostUnavailable)
        }
    }

    private func electedWindow(for token: String) -> ElectedWindow? {
        lock.lock()
        defer { lock.unlock() }
        return electedWindows[token]
    }
}

private extension Result where Success == Void, Failure == WarpAccessibilityFailure {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// App-root registry for the deliberately transient Warp association. It
/// retains neither a durable AX object nor a candidate token outside the live
/// process. A later election replaces the route selected for that exact Agent
/// Session; it never scores or combines old Warp candidates.
@MainActor
public final class WarpHostNavigationComposition {
    private var evidence = HostContextEvidenceStore()
    private var negotiations: [IntegrationInstanceID: NegotiationSnapshot] = [:]
    private var selectedAssociationIDs: [AgentSessionIdentity: HostContextID] = [:]
    private let port: WarpHostNavigationPort
    public private(set) var attempts: [JumpBackAttemptRecord] = []

    public init(port: WarpHostNavigationPort = WarpHostNavigationPort()) {
        self.port = port
    }

    public var hostIncarnation: HostIncarnation { port.hostIncarnation }

    /// The sole forwarding point for the explicit person-election call. No
    /// composition revalidation or Jump Back request can invoke this method.
    public func electCurrentFocusedWindowBestEffort() -> WarpWindowBestEffortElectionResult {
        port.electCurrentFocusedWindowBestEffort()
    }

    public func record(association: HostContextAssociation) {
        guard association.host == .warp else { return }
        evidence.record(association)
        selectedAssociationIDs[association.sessionIdentity] = association.id
    }

    public func register(navigationNegotiation snapshot: NegotiationSnapshot) {
        negotiations[snapshot.integrationInstanceID] = snapshot
    }

    public func associations(for identity: AgentSessionIdentity) -> [HostContextAssociation] {
        evidence.associations(for: identity).filter { $0.host == .warp }
    }

    public func invalidateAllLocators(reason: HostContextInvalidationReason, at date: Date = Date()) {
        port.invalidateElectedWindows()
        selectedAssociationIDs.removeAll()
        evidence.invalidateAll(reason: reason, at: date)
    }

    public func jumpBack(for identity: AgentSessionIdentity, at date: Date = Date()) -> JumpBackOutcome {
        guard let selectedID = selectedAssociationIDs[identity],
              let association = evidence.association(selectedID),
              let negotiation = negotiations[association.integrationInstanceID] else {
            let outcome = JumpBackOutcome(sessionIdentity: identity, host: .warp, qualifier: .unavailable, occurredAt: date, reason: .noAssociation)
            attempts.append(.init(attemptID: "", sessionIdentity: identity, trigger: .explicitPersonAction, candidateAssociationID: nil, candidateLocator: nil, outcome: outcome))
            return outcome
        }
        let attempt = JumpBackCoordinator(evidence: .init([association]), port: port)
            .attempt(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: date))
        attempts.append(attempt)
        return attempt.outcome
    }
}
