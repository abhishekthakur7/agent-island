import AppKit
import Combine
import SwiftUI
import ServiceManagement
import PresentationRuntime
import ClaudeCodeAdapter
import CursorACPAdapter
import ITerm2HostAdapter
import CursorHostAdapter
import WarpHostAdapter
import OrcaHostAdapter
import SessionDomain
import ApplicationRuntime
import LocalProductDiscovery

/// AppKit owns the two deliberately distinct presentation hosts: a normally
/// non-activating Island Overlay and an independently activating Settings
/// window. SwiftUI supplies content only; it never owns panel lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let presentation: PresentationRuntime
    private let fixtureController: FixtureController
    private let claudeActionComposition: ClaudeActionApplicationComposition
    private let claudeActionLifecycle: ClaudeActionIntegrationLifecycle
    private let cursorACPComposition: CursorACPApplicationComposition
    private let recoveryCoordinator: RecoveryCoordinator
    /// Host navigation is composed independently from every Product action
    /// route. Its only outward capability is `HostNavigationPort`.
    private let iterm2HostComposition: ITerm2HostNavigationComposition
    private let iterm2HostCapture: ITerm2HostContextCapture
    private let cursorHostComposition: CursorHostNavigationComposition
    private let cursorHostCapture: CursorHostContextCapture
    private let cursorHostSetup: CursorExtensionLocalEndpoint
    private let warpHostComposition: WarpHostNavigationComposition
    private let orcaHostComposition: OrcaHostNavigationComposition
    private let orcaHostCapture: OrcaHostContextCapture
    private let iterm2CaptureSetup = ITerm2CaptureSetupModel()
    private let warpCaptureSetup = WarpCaptureSetupModel()
    private let orcaCaptureSetup = OrcaCaptureSetupModel()
    private let atlasSettings: AtlasSettingsModel
    private let launchIntegrationAutoInstaller: LaunchIntegrationAutoInstaller
    private let notificationSettings = NotificationPolicySettingsModel()
    private let usageSettings = UsageSettingsModel()
    private lazy var settingsCoordinator = AtlasSettingsWindowCoordinator { [unowned self] in
        AnyView(AgentIslandSettingsView(
            model: self.atlasSettings,
            notificationSettings: self.notificationSettings,
            usageSettings: self.usageSettings,
            liveDisplayControls: AnyView(AtlasOverlayDisplayControls(model: self.atlasSettings, overlay: self.overlay)),
            cursorACPComposition: self.cursorACPComposition,
            iterm2HostControls: AnyView(ITerm2PersonAssertedCaptureControls(
                presentation: self.presentation,
                model: self.iterm2CaptureSetup,
                capture: { [weak self] identity, sessionID, tabID in self?.capturePersonAssertedITerm2Context(identity: identity, sessionID: sessionID, tabID: tabID) ?? "iTerm2 Host setup is unavailable." }
            )),
            warpHostControls: AnyView(WarpPersonAssertedCaptureControls(
                presentation: self.presentation,
                model: self.warpCaptureSetup,
                associateApplication: { [weak self] identity in self?.capturePersonAssertedWarpApplication(identity: identity) ?? "Warp Host setup is unavailable." },
                electFocusedWindow: { [weak self] identity in self?.electPersonAssertedWarpWindow(identity: identity) ?? "Warp best-effort election is unavailable." }
            )),
            orcaHostControls: AnyView(OrcaPersonAssertedCaptureControls(
                presentation: self.presentation,
                model: self.orcaCaptureSetup,
                capture: { [weak self] identity, terminalHandle, workspaceID, fileID in
                    self?.capturePersonAssertedOrcaContext(identity: identity, terminalHandle: terminalHandle, workspaceID: workspaceID, fileID: fileID) ?? "Orca Host setup is unavailable."
                }
            ))
        ))
    }
    private let horizon = HorizonController()
    private lazy var overlay = IslandOverlayController(presentation: presentation)
    private var statusItem: NSStatusItem?
    private var settingsCancellable: AnyCancellable?
    private var displaySettingsCancellable: AnyCancellable?
    private var displayAvailabilityCancellable: AnyCancellable?
    private var shortcutStatusCancellable: AnyCancellable?
    private var shortcutFeedbackCancellable: AnyCancellable?
    private var terminationInFlight = false
    private var recoveryObservers: [NSObjectProtocol] = []

    init(
        presentation: PresentationRuntime,
        fixtureController: FixtureController,
        claudeActionComposition: ClaudeActionApplicationComposition,
        cursorACPComposition: CursorACPApplicationComposition,
        recoveryCoordinator: RecoveryCoordinator,
        iterm2HostComposition: ITerm2HostNavigationComposition,
        iterm2HostCapture: ITerm2HostContextCapture,
        cursorHostComposition: CursorHostNavigationComposition,
        cursorHostCapture: CursorHostContextCapture,
        cursorHostSetup: CursorExtensionLocalEndpoint,
        warpHostComposition: WarpHostNavigationComposition,
        orcaHostComposition: OrcaHostNavigationComposition,
        orcaHostCapture: OrcaHostContextCapture,
        applicationRuntime: ApplicationRuntime,
        productInstallationIdentityVerifier: any ProductInstallationIdentityVerifying
    ) {
        self.presentation = presentation
        self.fixtureController = fixtureController
        self.claudeActionComposition = claudeActionComposition
        let claudeActionLifecycle = ClaudeActionIntegrationLifecycle(composition: claudeActionComposition)
        self.claudeActionLifecycle = claudeActionLifecycle
        self.cursorACPComposition = cursorACPComposition
        self.recoveryCoordinator = recoveryCoordinator
        self.iterm2HostComposition = iterm2HostComposition
        self.iterm2HostCapture = iterm2HostCapture
        self.cursorHostComposition = cursorHostComposition
        self.cursorHostCapture = cursorHostCapture
        self.cursorHostSetup = cursorHostSetup
        self.warpHostComposition = warpHostComposition
        self.orcaHostComposition = orcaHostComposition
        self.orcaHostCapture = orcaHostCapture
        let atlasSettings = AtlasSettingsModel(
            shortcutInputSourceResolver: {
                NativeShortcutInputSourceResolver.current()
            },
            sessionVerifier: IntegrationSessionVerifier(port: applicationRuntime)
        )
        self.atlasSettings = atlasSettings
        self.launchIntegrationAutoInstaller = LaunchIntegrationAutoInstaller(
            port: applicationRuntime,
            claudeActionLifecycle: claudeActionLifecycle,
            detector: productInstallationIdentityVerifier
        ) { [weak atlasSettings] kind, report in
            atlasSettings?.applyLaunchInstallationReport(kind, report: report)
        }
    }

    /// Explicit person-initiated production entry point. No startup scan or
    /// existing Cursor process can call into ACP control by resemblance.
    func startCursorACPAgentSession(cursorExecutable: URL, arguments: [String] = ["agent", "--acp"]) async -> Result<AgentSessionIdentity, CursorACPFailure> {
        await cursorACPComposition.start(cursorExecutable: cursorExecutable, arguments: arguments)
    }

    /// Typed production composition seam for an Agent Adapter that has a
    /// current negotiated `usage.observation` capability and a source-owned
    /// Usage Snapshot. This does not accept raw output, scrape Product state,
    /// or feed monitoring, filters, notifications, queues, actions, Jump
    /// Back, identity, or ordering. Cursor Hooks and ACP do not call it
    /// because they expose no such capability.
    func receiveUsageSnapshot(_ snapshot: UsageSnapshot, negotiation: NegotiationSnapshot, sessionIdentity: AgentSessionIdentity?) {
        usageSettings.presentation.receive(.init(snapshot: snapshot, negotiation: negotiation, sessionIdentity: sessionIdentity, receivedAt: Date()))
    }

    func withdrawUsageSnapshot(sourceID: String) {
        usageSettings.presentation.withdraw(sourceID: sourceID)
    }

    /// Guided-sheet action entry. The selected request and exact typed action
    /// are revalidated by the runtime's fresh Action Lease immediately before
    /// the adapter may write one JSON-RPC response.
    func submitCursorACPGuidedAction(requestID: GuidedAttentionRequestID, action: GuidedAction, attemptID: String, confirmed: Bool) async -> CursorACPActionResult {
        await cursorACPComposition.submit(requestID: requestID, action: action, attemptID: attemptID, confirmed: confirmed)
    }

    /// Narrow production ingestion point for a Host-aware integration that
    /// already has the exact Product owner and a documented iTerm2 session
    /// ID. Capture re-probes the API before recording; it cannot infer either
    /// value from the Overlay, card text, or terminal presentation.
    func captureITerm2SessionContext(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        sessionID: String,
        at date: Date = Date()
    ) -> Result<HostContextAssociation, ITerm2APIClientFailure> {
        let captured = iterm2HostCapture.captureSession(
            id: id,
            sessionIdentity: sessionIdentity,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            sessionID: sessionID,
            at: date
        )
        if case .success(let association) = captured { iterm2HostComposition.record(association: association) }
        return captured
    }

    /// A tab is captured separately from a pane and can therefore be used only
    /// as the honest `exactTab` fallback when it has its own live proof.
    func captureITerm2TabContext(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        tabID: String,
        at date: Date = Date()
    ) -> Result<HostContextAssociation, ITerm2APIClientFailure> {
        let captured = iterm2HostCapture.captureTab(
            id: id,
            sessionIdentity: sessionIdentity,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            tabID: tabID,
            at: date
        )
        if case .success(let association) = captured { iterm2HostComposition.record(association: association) }
        return captured
    }

    /// Host navigation is separately capability-negotiated from Product
    /// observation/actions. No Product action authority is accepted here.
    func registerITerm2NavigationNegotiation(_ snapshot: NegotiationSnapshot) {
        iterm2HostComposition.register(navigationNegotiation: snapshot)
    }

    /// Orca setup begins only with a person-selected current Agent Session
    /// and a runtime-issued opaque terminal handle. Capture calls the live
    /// documented runtime inspection before recording anything; titles,
    /// worktree/path resemblance, panes, and terminal contents are never
    /// candidates. A separately supplied workspace/file is captured only
    /// through its own current documented worktree proof.
    func captureOrcaTerminalContext(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        terminalHandle: String,
        at date: Date = Date()
    ) -> Result<HostContextAssociation, OrcaRuntimeClientFailure> {
        let captured = orcaHostCapture.captureTerminal(
            id: id,
            sessionIdentity: sessionIdentity,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            terminalHandle: terminalHandle,
            at: date
        )
        if case .success(let association) = captured { orcaHostComposition.record(association: association) }
        return captured
    }

    func captureOrcaWorkspaceFileContext(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        workspaceID: String,
        fileID: String,
        at date: Date = Date()
    ) -> Result<HostContextAssociation, OrcaRuntimeClientFailure> {
        let captured = orcaHostCapture.captureWorkspaceFile(
            id: id,
            sessionIdentity: sessionIdentity,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            workspaceID: workspaceID,
            fileID: fileID,
            at: date
        )
        if case .success(let association) = captured { orcaHostComposition.record(association: association) }
        return captured
    }

    func registerOrcaNavigationNegotiation(_ snapshot: NegotiationSnapshot) {
        orcaHostComposition.register(navigationNegotiation: snapshot)
    }

    /// Called only by the authenticated Cursor extension integration after it
    /// has observed the exact Product owner and retained a live terminal.
    func captureCursorLiveTerminalContext(id: HostContextID, sessionIdentity: AgentSessionIdentity, integrationInstanceID: IntegrationInstanceID, registration: CursorExtensionLiveTerminalRegistration, at date: Date = Date()) -> Result<HostContextAssociation, CursorExtensionEndpointFailure> {
        let result = cursorHostCapture.captureLiveTerminalContext(id: id, sessionIdentity: sessionIdentity, integrationInstanceID: integrationInstanceID, registration: registration, at: date)
        if case .success(let captured) = result { cursorHostComposition.record(captured) }
        return result.map(\.association)
    }

    func captureCursorNativeThreadContext(id: HostContextID, sessionIdentity: AgentSessionIdentity, integrationInstanceID: IntegrationInstanceID, registration: CursorExtensionNativeThreadRegistration, at date: Date = Date()) -> Result<HostContextAssociation, CursorExtensionEndpointFailure> {
        let result = cursorHostCapture.captureNativeThreadContext(id: id, sessionIdentity: sessionIdentity, integrationInstanceID: integrationInstanceID, registration: registration, at: date)
        // Native registrations have no live terminal reference; they remain
        // historical and cannot become exact through this app path.
        if case .success(let captured) = result { cursorHostComposition.record(captured) }
        return result.map(\.association)
    }

    func registerCursorNavigationNegotiation(_ snapshot: NegotiationSnapshot) { cursorHostComposition.register(navigationNegotiation: snapshot) }

    /// Person-asserted Warp setup deliberately binds only the selected,
    /// Product-owned Agent Session to Warp application activation. It does
    /// not inspect a title, CWD, PID, path, URL, AX label, terminal content,
    /// tab, pane, or block, and it does not activate Warp during setup.
    private func capturePersonAssertedWarpApplication(identity: AgentSessionIdentity) -> String {
        let integration = warpIntegrationID(for: identity)
        let now = Date()
        let association = HostContextAssociation(
            id: HostContextID("warp-application-\(UUID().uuidString)"),
            sessionIdentity: identity,
            host: .warp,
            integrationInstanceID: integration,
            integrationMode: "warp-appkit-accessibility",
            incarnation: warpHostComposition.hostIncarnation,
            locator: .warpApplication,
            provenance: HostLocatorProvenance(host: .warp, evidence: .applicationPresence, observedAt: now, sourceID: "person-asserted-warp"),
            validity: .live,
            firstObservedAt: now,
            lastValidatedAt: now
        )
        warpHostComposition.record(association: association)
        warpHostComposition.register(navigationNegotiation: warpNavigationSnapshot(identity: identity, integration: integration, at: now))
        return "Warp app-only Jump Back is associated with this Agent Session. Original Warp pane and tab are not verified."
    }

    /// This method is reachable only from the labelled contextual Settings
    /// button below. It is the only App route that may cause the system
    /// Accessibility prompt; the elected AX object/token stays in the
    /// process-local Warp composition and is never persisted or exported.
    private func electPersonAssertedWarpWindow(identity: AgentSessionIdentity) -> String {
        let now = Date()
        let integration = warpIntegrationID(for: identity)
        let electionResult = warpHostComposition.electCurrentFocusedWindowBestEffort()
        switch electionResult {
        case .elected(let election):
            let association = HostContextAssociation(
                id: HostContextID("warp-window-\(UUID().uuidString)"),
                sessionIdentity: identity,
                host: .warp,
                integrationInstanceID: integration,
                integrationMode: "warp-appkit-accessibility",
                incarnation: election.hostIncarnation,
                locator: election.locator,
                provenance: HostLocatorProvenance(host: .warp, evidence: .accessibilityProbe, observedAt: now, sourceID: "person-elected-current-warp-window"),
                validity: .live,
                firstObservedAt: now,
                lastValidatedAt: now
            )
            warpHostComposition.record(association: association)
            warpHostComposition.register(navigationNegotiation: warpNavigationSnapshot(identity: identity, integration: integration, at: now))
            return "Warp best-effort window elected for this app run. Original Warp pane and tab are not verified."
        case .applicationUnavailable, .permissionNotGranted, .noFocusedWindow, .queryFailed:
            return electionResult.accessibilityLabel
        }
    }

    private func warpIntegrationID(for identity: AgentSessionIdentity) -> IntegrationInstanceID {
        IntegrationInstanceID("person-asserted-warp-\(identity.productNamespace.rawValue)")
    }

    private func warpNavigationSnapshot(identity: AgentSessionIdentity, integration: IntegrationInstanceID, at date: Date) -> NegotiationSnapshot {
        NegotiationSnapshot(
            id: NegotiationSnapshotID("warp-navigation-\(UUID().uuidString)"),
            contractVersion: ContractVersion(major: 1, minor: 0),
            adapterKind: "warp.appkit-accessibility-host",
            adapterBuildVersion: "1",
            productNamespace: identity.productNamespace,
            integrationInstanceID: integration,
            integrationMode: "warp-appkit-accessibility",
            capabilities: [CapabilityRecord(
                id: WellKnownCapability.hostNavigation,
                direction: .navigate,
                availability: .available,
                scope: .session,
                constraints: CapabilityConstraints(values: ["host": "Warp", "windowBestEffort": "person-election-only"], requiresLiveEvidence: true),
                provenance: CapabilityProvenance(integrationInstanceID: integration, productNamespace: identity.productNamespace, integrationMode: "warp-appkit-accessibility"),
                freshness: .current,
                fallback: .nativeHost,
                semanticVariant: "app-only-with-explicit-ax-window-best-effort"
            )],
            negotiatedAt: date
        )
    }

    /// Explicit Settings path for a person who knows the exact documented
    /// iTerm2 API IDs. This is a person assertion, not Adapter discovery: the
    /// live persistent API probe must resolve every pasted opaque ID before it
    /// becomes a Host Context association or navigation capability.
    private func capturePersonAssertedITerm2Context(identity: AgentSessionIdentity, sessionID: String, tabID: String?) -> String {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else { return "Enter an exact iTerm2 session ID from its documented API." }
        let integration = IntegrationInstanceID("person-asserted-iterm2-\(identity.productNamespace.rawValue)")
        let mode = "person-asserted-iterm2-python-api"
        let sessionResult = captureITerm2SessionContext(
            id: HostContextID("iterm2-session-\(UUID().uuidString)"),
            sessionIdentity: identity,
            integrationInstanceID: integration,
            integrationMode: mode,
            sessionID: normalizedSessionID
        )
        guard case .success(let association) = sessionResult else {
            return "iTerm2 session was not captured: \(failureText(sessionResult))."
        }
        let snapshot = NegotiationSnapshot(
            id: NegotiationSnapshotID("iterm2-navigation-\(UUID().uuidString)"),
            contractVersion: ContractVersion(major: 1, minor: 0),
            adapterKind: "iterm2.person-asserted-host",
            adapterBuildVersion: association.hostVersion,
            productNamespace: identity.productNamespace,
            integrationInstanceID: integration,
            integrationMode: mode,
            capabilities: [CapabilityRecord(
                id: WellKnownCapability.hostNavigation,
                direction: .navigate,
                availability: .available,
                scope: .session,
                constraints: CapabilityConstraints(values: ["endpoint": association.provenance.endpointID ?? "unknown", "host": "iTerm2"], requiresLiveEvidence: true),
                provenance: CapabilityProvenance(integrationInstanceID: integration, productNamespace: identity.productNamespace, integrationMode: mode),
                freshness: .current,
                fallback: .manualSetup,
                semanticVariant: "person-asserted-exact-id"
            )],
            negotiatedAt: Date()
        )
        registerITerm2NavigationNegotiation(snapshot)
        if let tabID {
            let normalizedTabID = tabID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedTabID.isEmpty {
                let tabResult = captureITerm2TabContext(id: HostContextID("iterm2-tab-\(UUID().uuidString)"), sessionIdentity: identity, integrationInstanceID: integration, integrationMode: mode, tabID: normalizedTabID)
                if case .failure = tabResult { return "Exact iTerm2 pane captured; tab fallback was not captured: \(failureText(tabResult))." }
            }
        }
        return "iTerm2 navigation ready: exact session was live-probed on the current API connection."
    }

    private func failureText<T>(_ result: Result<T, ITerm2APIClientFailure>) -> String {
        if case .failure(let failure) = result { return failure.rawValue }
        return "unknown"
    }

    /// The only person-asserted Orca route. A terminal handle originates from
    /// the documented runtime; optional workspace/file data must be a pair so
    /// it can be independently revalidated. Supplying a title, path-like
    /// guess, or a non-live handle cannot create an association.
    private func capturePersonAssertedOrcaContext(identity: AgentSessionIdentity, terminalHandle: String, workspaceID: String?, fileID: String?) -> String {
        let handle = terminalHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let file = fileID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !handle.isEmpty || (!workspace.isEmpty && !file.isEmpty) else {
            return "Enter a documented Orca runtime-issued terminal handle, or an exact workspace and file pair."
        }
        guard (workspace.isEmpty && file.isEmpty) || (!workspace.isEmpty && !file.isEmpty) else {
            return "Workspace fallback needs both exact Orca workspace ID and file identifier; it is not inferred from a path or title."
        }
        let integration = IntegrationInstanceID("person-asserted-orca-\(identity.productNamespace.rawValue)")
        let mode = "person-asserted-orca-cli-runtime"
        var captured: [HostContextAssociation] = []
        var workspaceFallbackFailure: OrcaRuntimeClientFailure?
        if !handle.isEmpty {
            let terminalResult = captureOrcaTerminalContext(
                id: HostContextID("orca-terminal-\(UUID().uuidString)"),
                sessionIdentity: identity,
                integrationInstanceID: integration,
                integrationMode: mode,
                terminalHandle: handle
            )
            switch terminalResult {
            case .success(let association): captured.append(association)
            case .failure(let failure): return "Orca terminal handle was not captured: \(failure.rawValue)."
            }
        }
        if !workspace.isEmpty, !file.isEmpty {
            let workspaceResult = captureOrcaWorkspaceFileContext(
                id: HostContextID("orca-workspace-\(UUID().uuidString)"),
                sessionIdentity: identity,
                integrationInstanceID: integration,
                integrationMode: mode,
                workspaceID: workspace,
                fileID: file
            )
            switch workspaceResult {
            case .success(let association): captured.append(association)
            case .failure(let failure):
                // Workspace/file is optional when an exact runtime-issued
                // terminal handle was independently captured. Do not discard
                // that stronger current evidence merely because a lower
                // fallback was unavailable.
                workspaceFallbackFailure = failure
            }
        }
        guard let primary = captured.first else {
            if let workspaceFallbackFailure { return "Orca workspace/file fallback was not captured: \(workspaceFallbackFailure.rawValue)." }
            return "No current Orca runtime evidence was captured."
        }
        let snapshot = NegotiationSnapshot(
            id: NegotiationSnapshotID("orca-navigation-\(UUID().uuidString)"),
            contractVersion: ContractVersion(major: 1, minor: 0),
            adapterKind: "orca.person-asserted-runtime-host",
            adapterBuildVersion: primary.hostVersion,
            productNamespace: identity.productNamespace,
            integrationInstanceID: integration,
            integrationMode: mode,
            capabilities: [CapabilityRecord(
                id: WellKnownCapability.hostNavigation,
                direction: .navigate,
                availability: .available,
                scope: .session,
                constraints: CapabilityConstraints(values: ["endpoint": primary.provenance.endpointID ?? "orca-cli-runtime", "host": "Orca", "terminalSelection": "documented-terminal-switch"], requiresLiveEvidence: true),
                provenance: CapabilityProvenance(integrationInstanceID: integration, productNamespace: identity.productNamespace, integrationMode: mode),
                freshness: .current,
                fallback: .manualSetup,
                semanticVariant: "runtime-issued-handle-exact-tab-only-unless-runtime-proves-child"
            )],
            negotiatedAt: Date()
        )
        registerOrcaNavigationNegotiation(snapshot)
        if !handle.isEmpty {
            if let workspaceFallbackFailure {
                return "Orca navigation ready: the live runtime proved the opaque terminal handle and exact tab. Workspace/file fallback was not captured: \(workspaceFallbackFailure.rawValue). Child surface is unverified."
            }
            return workspace.isEmpty
                ? "Orca navigation ready: the live runtime proved the opaque terminal handle. Jump Back can select its exact tab; child surface is unverified."
                : "Orca navigation ready: the exact tab is live-proven and the workspace/file fallback was independently reproven. Child surface is unverified."
        }
        return "Orca workspace/file Jump Back is ready from independently reproven current runtime evidence; original terminal context is unverified."
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // AppKit may ask to restore windows before did-finish-launching.
        // Register the coordinator before that restoration phase begins.
        _ = settingsCoordinator
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Product discovery belongs to application launch, not to the first
        // presentation of Settings. The model coalesces repeated requests, so
        // restoration and a later Integrations view cannot start a second scan.
        atlasSettings.loadProductInstallationsIfNeeded()
        Task { await launchIntegrationAutoInstaller.start() }
        installMenu()
        overlay.showSettings = { [weak self] in self?.showSettings(nil) }
        // This is the production Overlay click path. It permits navigation
        // only when one visible Agent Session is explicitly unambiguous; the
        // Host composition then revalidates its source-proven association.
        overlay.jumpBackAction = { [weak self] in self?.jumpBackForVisibleSession() }
        applyLaunchAtLogin(atlasSettings.general.launchBehavior)
        applyAtlasPresentationPreferences(atlasSettings.general)
        applyAtlasDisplayPreferences(atlasSettings.display)
        overlay.bootstrapShortcutPreferences(atlasSettings.shortcuts)
        overlay.setUsagePresentation(usageSettings.presentation)
        atlasSettings.setShortcutRegistrationHandler { [weak self] preferences in
            guard let self else {
                return .rejected(.registrationUnavailable, .unavailable("Overlay registration coordinator is unavailable."), nil)
            }
            return self.overlay.tryApplyShortcutPreferences(preferences)
        }
        settingsCancellable = atlasSettings.$general.sink { [weak self] general in
            self?.applyLaunchAtLogin(general.launchBehavior)
            self?.applyAtlasPresentationPreferences(general)
        }
        displaySettingsCancellable = atlasSettings.$display.sink { [weak self] display in
            self?.applyAtlasDisplayPreferences(display)
        }
        shortcutStatusCancellable = overlay.$shortcutRegistrationStatus.sink { [weak self] status in
            self?.atlasSettings.updateShortcutRegistrationStatus(status)
        }
        shortcutFeedbackCancellable = overlay.$shortcutInvocationFeedback.sink { [weak self] feedback in
            guard let self, let feedback else { return }
            self.atlasSettings.updateShortcutFeedback(feedback)
        }
        overlay.start()
        // This is a one-way, read-only bridge into the Settings preview. The
        // preview receives no Overlay, Host, action, or configuration port.
        displayAvailabilityCancellable = overlay.$selectionAvailability.sink { [weak self] _ in
            guard let self else { return }
            let value = self.overlay.previewDisplayAvailability
            self.atlasSettings.updatePreviewDisplayAvailability(available: value.available, label: value.label)
        }
        let initialAvailability = overlay.previewDisplayAvailability
        atlasSettings.updatePreviewDisplayAvailability(available: initialAvailability.available, label: initialAvailability.label)
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        recoveryObservers.append(workspaceNotifications.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.recoverFromWake() }
        })
        // SessionStore already rebuilt facts synchronously before composition;
        // this expires any lazily hydrated volatile Guided state as well.
        Task { [weak self] in
            let outcome = await self?.recoveryCoordinator.cross(.coldResume)
            guard outcome?.state == .protectedStoreUnavailable, let self else { return }
            self.enterFailClosedRecovery(reason: outcome?.storageReason)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await launchIntegrationAutoInstaller.stop() }
        overlay.terminate()
        removeRecoveryObservers()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationInFlight else { return .terminateLater }
        terminationInFlight = true
        removeRecoveryObservers()
        overlay.terminate()
        invalidateAllHostLocators(reason: .hostUnavailable)
        Task { [weak self] in
            guard let self else { return }
            await self.launchIntegrationAutoInstaller.stop()
            await self.recoveryCoordinator.cross(.explicitQuit)
            // These components own only Agent Island helpers/routes. This
            // boundary never stops a Host or Agent Product process.
            await self.cursorACPComposition.stop()
            await self.claudeActionLifecycle.retireCurrentInstallation()
            await self.iterm2HostComposition.stopOwnedHelper()
            await MainActor.run {
                if let statusItem = self.statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    /// Called by the AppKit wake observer below. A wake never probes or
    /// launches a Host: it only invalidates opaque live evidence and lets a
    /// later explicit Jump Back perform its documented read-only probe.
    private func recoverFromWake() {
        invalidateAllHostLocators(reason: .systemWake)
        overlay.prepareForWakeRecovery()
        Task { [weak self] in
            guard let self else { return }
            let outcome = await recoveryCoordinator.cross(.systemWake)
            if outcome.state == .protectedStoreUnavailable {
                enterFailClosedRecovery(reason: outcome.storageReason)
            } else {
                overlay.recoverAfterWake()
            }
        }
    }

    private func removeRecoveryObservers() {
        recoveryObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        recoveryObservers.removeAll()
    }

    private func invalidateAllHostLocators(reason: HostContextInvalidationReason) {
        let now = Date()
        iterm2HostComposition.invalidateAllLocators(reason: reason, at: now)
        cursorHostComposition.invalidateAllLocators(reason: reason, at: now)
        warpHostComposition.invalidateAllLocators(reason: reason, at: now)
        orcaHostComposition.invalidateAllLocators(reason: reason, at: now)
    }

    /// If encrypted bytes cannot be re-verified after a wake, leave the
    /// existing bytes untouched and withdraw all interaction/presentation.
    /// This is intentionally a visible stop state, never a silent reset.
    private func enterFailClosedRecovery(reason: StorageFailureReason?) {
        overlay.terminate()
        invalidateAllHostLocators(reason: .hostUnavailable)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Agent Island's protected store requires recovery"
        alert.informativeText = "Reason: \(reason?.rawValue ?? "unavailable")\n\nLocal evidence was not changed. Quit and resolve the protected-store problem before reopening Agent Island."
        alert.addButton(withTitle: "Quit")
        _ = alert.runModal()
        NSApp.terminate(nil)
    }

    /// Reachable composition API for the Integration Installation flow. The
    /// current Settings surface does not yet provide installation controls;
    /// its future flow must call this only with newly verified installation,
    /// manifest, helper, snapshot, and Keychain credential evidence.
    @discardableResult
    func activateClaudeActionInstallation(
        installation: IntegrationInstallation,
        manifest: OwnershipManifest,
        helperID: String,
        snapshot: NegotiationSnapshot,
        credentialStore: any ClaudeHookCredentialStore = KeychainClaudeHookCredentialStore()
    ) async -> Bool {
        await claudeActionLifecycle.activate(
            installation: installation,
            manifest: manifest,
            helperID: helperID,
            snapshot: snapshot,
            credentialStore: credentialStore
        )
    }

    /// Matching lifecycle endpoint for disablement, helper loss, removal, or
    /// a capability/negotiation change. The reason invalidates Action Leases
    /// through the same source-change category before the endpoint stops.
    func retireClaudeActionInstallation(reason: ClaudeLiveActionRejection = .helperUnavailable) async {
        await claudeActionLifecycle.retireCurrentInstallation(reason: reason)
    }

    /// The user explicitly requested the normal window; this intentionally
    /// activates Agent Island, unlike all ambient overlay paths.
    @objc private func showSettings(_ sender: Any?) {
        settingsCoordinator.showSettings()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func applyAtlasPresentationPreferences(_ general: AtlasGeneralPreferences) {
        overlay.hideInFullscreen = general.hideInFullScreen
        overlay.hideWhenNoActiveSession = general.hideWhenNoActiveSession
        overlay.suppressWhenExactHostForeground = general.suppressWhenExactHostForeground
        overlay.hoverExpansionEnabled = general.expandOnHover
        overlay.collapseOnPointerExit = general.collapseOnPointerExit
        overlay.revealOnCompletion = general.revealOnCompletion
        overlay.revealOnAttention = general.revealOnAttention
        overlay.clickBehavior = general.clickBehavior
        overlay.reconcilePresentation()
    }

    private func jumpBackForVisibleSession() -> JumpBackOutcome {
        let cards = presentation.cards
        guard cards.count == 1, let card = cards.first else {
            let identity = AgentSessionIdentity(
                productNamespace: ProductNamespace(cards.first?.productNamespace ?? "unknown"),
                nativeSessionID: NativeSessionID(cards.first?.nativeSessionID ?? "unselected")
            )
            return JumpBackOutcome(
                sessionIdentity: identity,
                host: nil,
                qualifier: .unavailable,
                occurredAt: Date(),
                reason: .ambiguous(level: .exactSurface)
            )
        }
        let identity = AgentSessionIdentity(
            productNamespace: ProductNamespace(card.productNamespace),
            nativeSessionID: NativeSessionID(card.nativeSessionID)
        )
        let associatedHosts: [HostKind] = [
            cursorHostComposition.associations(for: identity).isEmpty ? nil : .cursor,
            iterm2HostComposition.associations(for: identity).isEmpty ? nil : .iterm2,
            warpHostComposition.associations(for: identity).isEmpty ? nil : .warp,
            orcaHostComposition.associations(for: identity).isEmpty ? nil : .orca
        ].compactMap { $0 }
        guard associatedHosts.count == 1, let host = associatedHosts.first else {
            return JumpBackOutcome(
                sessionIdentity: identity,
                host: nil,
                qualifier: .unavailable,
                occurredAt: Date(),
                reason: associatedHosts.isEmpty ? .noAssociation : .ambiguous(level: .exactSurface)
            )
        }
        switch host {
        case .cursor: return cursorHostComposition.jumpBack(for: identity)
        case .iterm2: return iterm2HostComposition.jumpBack(for: identity)
        case .warp: return warpHostComposition.jumpBack(for: identity)
        case .orca: return orcaHostComposition.jumpBack(for: identity)
        case .unknown:
            return JumpBackOutcome(sessionIdentity: identity, host: host, qualifier: .unavailable, occurredAt: Date(), reason: .revalidationFailed(.unsupportedHost))
        }
    }

    private func applyLaunchAtLogin(_ behavior: AtlasLaunchBehavior) {
        do {
            switch behavior {
            case .manual:
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                atlasSettings.recordLaunchAtLoginState(.disabled)
            case .atLogin:
                try SMAppService.mainApp.register()
                atlasSettings.recordLaunchAtLoginState(.enabled)
            }
        } catch {
            // A command-line build, missing app bundle, or OS policy may not
            // expose launch-at-login registration. Persisted intent remains
            // intact, while the capability is reported honestly.
            atlasSettings.recordLaunchAtLoginState(.unavailable)
        }
    }

    private func applyAtlasDisplayPreferences(_ display: AtlasDisplayPreferences) {
        overlay.displayPreferences = display
        if display.selectedDisplayID != overlay.selectedDisplayID {
            overlay.selectDisplay(id: display.selectedDisplayID)
        }
        overlay.reconcilePresentation()
    }

    @objc private func toggleOverlay(_ sender: Any?) { overlay.toggleOverlay() }
    @objc private func autoReveal(_ sender: Any?) { overlay.autoReveal() }
    @objc private func engageKeyboard(_ sender: Any?) { overlay.engageKeyboard() }

    private func installMenu() {
        let appMenu = NSMenu()
        let toggle = appMenu.addItem(withTitle: "Show / Collapse Overlay", action: #selector(toggleOverlay(_:)), keyEquivalent: "")
        toggle.target = self
        let reveal = appMenu.addItem(withTitle: "Automatic Reveal", action: #selector(autoReveal(_:)), keyEquivalent: "")
        reveal.target = self
        let keyboard = appMenu.addItem(withTitle: "Engage Overlay Keyboard", action: #selector(engageKeyboard(_:)), keyEquivalent: "")
        keyboard.target = self
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        let cursorSetup = appMenu.addItem(withTitle: "Cursor Host Setup…", action: #selector(showCursorHostSetup(_:)), keyEquivalent: "")
        cursorSetup.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Agent Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let menu = NSMenu()
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Agent Island")
        statusItem.menu = appMenu
        self.statusItem = statusItem
    }

    @objc private func showCursorHostSetup(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Configure the Cursor Host extension"
        alert.informativeText = "Install the bundled Agent Island Cursor Host contributor, then configure its local endpoint for this app run. The credential is sensitive; do not share it. Until its authenticated extension connection captures a live terminal for an Agent Session, Jump Back remains unavailable or app-only.\n\nSocket: \(cursorHostSetup.socketPath)\nCredential (base64): \(cursorHostSetup.credential.base64EncodedString())"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// Explicit live assignment controls are kept separate from the read-only
/// Display preview. This small AppKit-side bridge preserves the existing
/// selected-display behavior without giving preview views an Overlay handle.
private struct AtlasOverlayDisplayControls: View {
    @ObservedObject var model: AtlasSettingsModel
    @ObservedObject var overlay: IslandOverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Overlay assignment").font(.headline)
            Picker("Selected display", selection: Binding(
                get: { model.display.selectedDisplayID ?? overlay.selectedDisplayID },
                set: { selected in model.updateDisplay { $0.selectedDisplayID = selected } }
            )) {
                Text("No display selected").tag(Optional<String>.none)
                ForEach(overlay.displays) { display in
                    Text(display.name).tag(Optional(display.id))
                }
            }
            Text(overlay.displayStatus)
                .font(.caption)
                .foregroundStyle(overlay.selectedScreen == nil ? .orange : .secondary)
            if overlay.selectionAvailability != .available {
                Label("Selection unavailable; the Overlay is withdrawn until revalidated.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityIdentifier("atlas.display.liveAssignment")
    }
}

/// A deliberately manual recovery/setup surface. It exposes no browser,
/// terminal, title, project, CWD, PID, or automatic Host discovery; the
/// person chooses an already-observed Agent Session and supplies documented
/// opaque iTerm2 API IDs for a live probe.
private struct ITerm2PersonAssertedCaptureControls: View {
    @ObservedObject var presentation: PresentationRuntime
    @ObservedObject var model: ITerm2CaptureSetupModel
    let capture: (AgentSessionIdentity, String, String?) -> String

    private var selectedIdentity: AgentSessionIdentity? {
        guard let cardID = model.selectedCardID,
              let card = presentation.cards.first(where: { $0.id == cardID }) else { return nil }
        return AgentSessionIdentity(productNamespace: ProductNamespace(card.productNamespace), nativeSessionID: NativeSessionID(card.nativeSessionID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iTerm2 exact Host Context").font(.headline)
            Text("Person assertion: choose one current Agent Session and paste only exact documented iTerm2 API session ID (and optionally tab ID). Agent Island live-probes the IDs; it never searches by title, CWD, PID, tab order, window geometry, Space, or visible text.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Agent Session", selection: $model.selectedCardID) {
                Text("Select an Agent Session").tag(Optional<String>.none)
                ForEach(presentation.cards) { card in
                    Text("\(card.productNamespace) · \(card.nativeSessionID)").tag(Optional(card.id))
                }
            }
            TextField("Exact iTerm2 session ID", text: $model.sessionID)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("atlas.iterm2.sessionID")
            TextField("Exact iTerm2 tab ID (optional fallback)", text: $model.tabID)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("atlas.iterm2.tabID")
            Button("Probe and capture exact iTerm2 context") {
                guard let identity = selectedIdentity else {
                    model.result = "Select exactly one current Agent Session before capture."
                    return
                }
                model.result = capture(identity, model.sessionID, model.tabID.isEmpty ? nil : model.tabID)
            }
            .disabled(selectedIdentity == nil || model.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("atlas.iterm2.capture")
            Text(model.result)
                .font(.caption)
                .foregroundStyle(model.result.contains("ready") ? Color.secondary : Color.orange)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("iTerm2 Host Context capture result: \(model.result)")
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)) }
        .accessibilityIdentifier("atlas.iterm2.personAssertedCapture")
    }
}

/// Warp has no documented local pane/tab/block selector. This person-asserted
/// setup intentionally selects only an already visible Agent Session; it
/// never derives a Host Context from a card label or presentation metadata.
private struct WarpPersonAssertedCaptureControls: View {
    @ObservedObject var presentation: PresentationRuntime
    @ObservedObject var model: WarpCaptureSetupModel
    let associateApplication: (AgentSessionIdentity) -> String
    let electFocusedWindow: (AgentSessionIdentity) -> String

    private var selectedIdentity: AgentSessionIdentity? {
        guard let cardID = model.selectedCardID,
              let card = presentation.cards.first(where: { $0.id == cardID }) else { return nil }
        return AgentSessionIdentity(productNamespace: ProductNamespace(card.productNamespace), nativeSessionID: NativeSessionID(card.nativeSessionID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Warp Jump Back").font(.headline)
            Text("Person assertion: choose one current Agent Session that you are using in Warp. App-only Jump Back activates Warp only. It never identifies a pane or tab from title, URL, block text, terminal content, path, PID, geometry, Space, or Accessibility labels.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Agent Session", selection: $model.selectedCardID) {
                Text("Select an Agent Session").tag(Optional<String>.none)
                ForEach(presentation.cards) { card in
                    Text("\(card.productNamespace) · \(card.nativeSessionID)").tag(Optional(card.id))
                }
            }
            Button("Associate selected session with Warp app-only Jump Back") {
                guard let identity = selectedIdentity else {
                    model.result = "Select exactly one current Agent Session before Warp setup."
                    return
                }
                model.result = associateApplication(identity)
            }
            .disabled(selectedIdentity == nil)
            .accessibilityIdentifier("atlas.warp.associateApplication")
            Text("Optional best effort: first focus the desired Warp window yourself, then choose the button below. Selecting it may request macOS Accessibility permission now. If granted, Agent Island raises only that current window when exactly one live AX object still matches. It never verifies the original Warp pane or tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Use currently focused Warp window best effort") {
                guard let identity = selectedIdentity else {
                    model.result = "Select exactly one current Agent Session before the Warp window election."
                    return
                }
                model.result = electFocusedWindow(identity)
            }
            .disabled(selectedIdentity == nil)
            .accessibilityIdentifier("atlas.warp.electFocusedWindow")
            Text(model.result)
                .font(.caption)
                .foregroundStyle(model.result.contains("elected") || model.result.contains("associated") ? Color.secondary : Color.orange)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Warp Jump Back setup result: \(model.result). Original Warp pane and tab are unverified.")
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)) }
        .accessibilityIdentifier("atlas.warp.personAssertedCapture")
    }
}

/// Orca's documented terminal switch selects a terminal tab. The setup does
/// not enumerate or search terminals: a person selects the Agent Session and
/// supplies a runtime-issued opaque handle already observed from Orca. An
/// optional workspace/file pair is independently live-probed and is never a
/// title/path similarity fallback.
private struct OrcaPersonAssertedCaptureControls: View {
    @ObservedObject var presentation: PresentationRuntime
    @ObservedObject var model: OrcaCaptureSetupModel
    let capture: (AgentSessionIdentity, String, String?, String?) -> String

    private var selectedIdentity: AgentSessionIdentity? {
        guard let cardID = model.selectedCardID,
              let card = presentation.cards.first(where: { $0.id == cardID }) else { return nil }
        return AgentSessionIdentity(productNamespace: ProductNamespace(card.productNamespace), nativeSessionID: NativeSessionID(card.nativeSessionID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Orca exact tab Jump Back").font(.headline)
            Text("Person assertion: choose one current Agent Session and paste only an exact runtime-issued Orca terminal handle. Agent Island calls Orca’s documented live runtime to validate it before capture; it never searches terminal titles, Worktrees, paths, panes, stable-pane IDs, terminal text, geometry, or accessibility metadata. Documented terminal switch selects an exact tab; a child surface remains unverified unless a current runtime response explicitly proves it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Agent Session", selection: $model.selectedCardID) {
                Text("Select an Agent Session").tag(Optional<String>.none)
                ForEach(presentation.cards) { card in
                    Text("\(card.productNamespace) · \(card.nativeSessionID)").tag(Optional(card.id))
                }
            }
            TextField("Runtime-issued Orca terminal handle", text: $model.terminalHandle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("atlas.orca.terminalHandle")
            Text("Optional independently proven fallback: supply both values only when you have exact current Orca worktree/file evidence. Neither field is discovered from filesystem resemblance.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Exact Orca workspace ID (optional)", text: $model.workspaceID)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("atlas.orca.workspaceID")
            TextField("Exact Orca file identifier (optional)", text: $model.fileID)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("atlas.orca.fileID")
            Button("Probe and capture Orca navigation context") {
                guard let identity = selectedIdentity else {
                    model.result = "Select exactly one current Agent Session before Orca setup."
                    return
                }
                model.result = capture(identity, model.terminalHandle, model.workspaceID.isEmpty ? nil : model.workspaceID, model.fileID.isEmpty ? nil : model.fileID)
            }
            .disabled(selectedIdentity == nil || (model.terminalHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (model.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.fileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
            .accessibilityIdentifier("atlas.orca.capture")
            Text(model.result)
                .font(.caption)
                .foregroundStyle(model.result.contains("ready") ? Color.secondary : Color.orange)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Orca Host Context capture result: \(model.result)")
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)) }
        .accessibilityIdentifier("atlas.orca.personAssertedCapture")
    }
}

@MainActor
private final class ITerm2CaptureSetupModel: ObservableObject {
    @Published var selectedCardID: String?
    @Published var sessionID = ""
    @Published var tabID = ""
    @Published var result = "No person-asserted iTerm2 Host Context captured."
}

@MainActor
private final class WarpCaptureSetupModel: ObservableObject {
    @Published var selectedCardID: String?
    @Published var result = "No Warp Host Context is associated. Original Warp pane and tab are unverified."
}

@MainActor
private final class OrcaCaptureSetupModel: ObservableObject {
    @Published var selectedCardID: String?
    @Published var terminalHandle = ""
    @Published var workspaceID = ""
    @Published var fileID = ""
    @Published var result = "No person-asserted Orca Host Context captured."
}
