import AppKit
import Combine
import SwiftUI
import SessionDomain
import PresentationRuntime

@MainActor
final class IslandOverlayController: NSObject, ObservableObject {
    @Published private(set) var displays: [IslandDisplay] = []
    /// One explicit, stable display identity.  This remains nil until the
    /// person selects a display; AppKit's main screen is never an implicit
    /// fallback.
    @Published private(set) var selectedDisplayID: String?
    @Published var hideInFullscreen = true
    @Published var hideWhenNoActiveSession = true
    @Published var suppressWhenExactHostForeground = true
    @Published var quietSceneActive = false
    @Published var hoverExpansionEnabled = true
    @Published var collapseOnPointerExit = true
    @Published var revealOnCompletion = true
    @Published var revealOnAttention = true
    @Published var clickBehavior: AtlasClickBehavior = .inspectExpand
    @Published var displayPreferences: AtlasDisplayPreferences = .default
    @Published private(set) var displayStatus = "Looking for a selected display…"
    @Published private(set) var selectionAvailability: IslandDisplayAvailability = .selectionUnavailable
    @Published private(set) var lastClickOutcome: PresentationClickOutcome?
    @Published private(set) var focusedSessionIndex: Int? = nil
    @Published private(set) var shortcutRegistrationStatus: ShortcutRegistrationStatus = .unavailable("Native global registration is not configured.")
    /// Invocation feedback is separate from registration status: a native
    /// shortcut can remain registered while a live Guided request becomes
    /// unavailable. Settings receives this as an accessible, human-readable
    /// announcement rather than a misleading registration failure.
    @Published private(set) var shortcutInvocationFeedback: String?

    private let presentation: PresentationRuntime
    private let shortcutRegistrar: ShortcutRegistrationCoordinator
    private var stateMachine = IslandOverlayStateMachine()
    private var panel: IslandOverlayPanel?
    private var container: IslandOverlayContainerView?
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var precedingKeyWindow: NSWindow?
    private var shortcutGate = ShortcutInvocationGate()
    private var shortcutRegistry = ShortcutRegistry()
    private var keyboardFocus = KeyboardEngagementState()
    private var localEditActive = false
    private var presentationCancellable: AnyCancellable?
    private var hoverWork: DispatchWorkItem?
    private var dismissalWork: DispatchWorkItem?
    private var exactForegroundEvidence: (observation: ExactHostForegroundObservation, association: HostContextAssociation)?

    /// Optional bounded seam for a future/live Guided coordinator. The
    /// controller resolves one exact source-proven request before asking the
    /// coordinator to focus it. The focus handler must not auto-advance,
    /// reserve, consume, or dispatch an Action Attempt.
    private var guidedShortcutRequestsProvider: (() -> [GuidedAttentionRequest])?
    private var guidedShortcutFocusHandler: ((ShortcutGuidedRoute) -> ShortcutGuidedRouteOutcome)?

    /// The composition root may supply a Host-specific Jump Back coordinator.
    /// Without one, enabled Jump Back remains visibly unavailable and cannot
    /// accidentally activate a plausible app/window.
    var jumpBackAction: (() -> JumpBackOutcome?)?

    init(presentation: PresentationRuntime, shortcutRegistrar: ShortcutRegistrationCoordinator? = nil) {
        self.presentation = presentation
        self.shortcutRegistrar = shortcutRegistrar ?? ShortcutRegistrationCoordinator(backend: CarbonShortcutRegistrationBackend())
        self.shortcutRegistrationStatus = self.shortcutRegistrar.status
        self.shortcutInvocationFeedback = nil
    }

    /// Installs the narrow live Guided seam when composition has a coordinator
    /// and a current request snapshot. Without it, safe shortcuts fail closed
    /// to the native Host and never invent Product authority.
    func setGuidedShortcutRouting(
        requests: @escaping () -> [GuidedAttentionRequest],
        focus: @escaping (ShortcutGuidedRoute) -> ShortcutGuidedRouteOutcome
    ) {
        guidedShortcutRequestsProvider = requests
        guidedShortcutFocusHandler = focus
    }

    func clearGuidedShortcutRouting() {
        guidedShortcutRequestsProvider = nil
        guidedShortcutFocusHandler = nil
    }

    var selectedScreen: NSScreen? {
        guard let selectedDisplayID else { return nil }
        return NSScreen.screens.first { Self.displayIdentity(for: $0) == selectedDisplayID }
    }

    /// A read-only presentation value for Settings.  It contains no Overlay
    /// or Host handle and is safe to forward to the local preview model.
    var previewDisplayAvailability: (available: Bool, label: String?) {
        switch selectionAvailability {
        case .available:
            return (true, nil)
        case .selectionUnavailable, .needsRevalidation:
            return (false, selectedDisplayID == nil ? "No display selected" : displayStatus)
        }
    }

    func start() {
        installObservers()
        presentationCancellable = presentation.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.reconcilePresentation() }
        }
        refreshDisplays(coldResume: true)
    }

    func selectDisplay(id: String?) {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitID = normalizedID?.isEmpty == true ? nil : normalizedID
        hoverWork?.cancel()
        dismissalWork?.cancel()
        releaseKeyboard()
        // Withdraw the old selected display before changing identity. This is
        // the single atomic transition point: no second live panel is ever
        // created and no stale engagement/timer/frame survives the switch.
        removeOverlayRegionsAndWindow()
        selectedDisplayID = explicitID
        displayPreferences.selectedDisplayID = explicitID
        stateMachine.reduce(.displayLost)
        if selectedScreen != nil { stateMachine.reduce(.displayRevalidated(available: true)) }
        updateStatus()
        applyState()
    }

    func toggleOverlay() {
        if stateMachine.state.presentation == .withdrawn || stateMachine.state.presentation == .collapsed {
            stateMachine.reduce(.hoverEntered)
        } else {
            collapse()
            return
        }
        applyState()
    }

    func primaryClick() {
        switch clickBehavior {
        case .inspectExpand:
            lastClickOutcome = .inspectedOrExpanded
            toggleOverlay()
        case .jumpBack:
            lastClickOutcome = PresentationClickPolicy.resolve(action: .jumpBack, jumpBackOutcome: jumpBackAction?())
        }
    }

    func autoReveal() {
        stateMachine.reduce(.automaticReveal)
        applyState()
        dismissalWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stateMachine.state.keyboardEngaged, !self.stateMachine.state.interactionGuard else { return }
            self.collapse()
        }
        dismissalWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Notification paths use these typed local presentation gates. The
    /// generic menu action above remains an explicit person-requested reveal.
    func revealCompletion() {
        guard revealOnCompletion else { return }
        autoReveal()
    }

    func revealAttention() {
        guard revealOnAttention else { return }
        autoReveal()
    }

    /// Pure policy used by the AppKit hover callback and deterministic tests.
    nonisolated static func shouldCollapseAfterPointerExit(
        collapseOnPointerExit: Bool,
        interactionGuard: Bool,
        keyboardEngaged: Bool
    ) -> Bool {
        collapseOnPointerExit && !interactionGuard && !keyboardEngaged
    }

    /// Selection validation is deliberately identity-only. No available
    /// display is substituted when the persisted selection is nil or missing.
    nonisolated static func validatedExplicitSelection(persistedID: String?, availableIDs: Set<String>) -> String? {
        guard let persistedID, availableIDs.contains(persistedID) else { return nil }
        return persistedID
    }

    func engageKeyboard() {
        precedingKeyWindow = NSApp.keyWindow === panel ? nil : NSApp.keyWindow
        stateMachine.reduce(.engageKeyboard)
        keyboardFocus.engage(visibleTargets: Self.visibleFocusTargets(
            hasSessions: !presentation.cards.isEmpty,
            canInspect: !presentation.cards.isEmpty,
            canShowAll: presentation.cards.count > 1
        ))
        focusedSessionIndex = presentation.cards.isEmpty ? nil : 0
        applyState()
        guard stateMachine.state.keyboardEngaged, let panel else { return }
        panel.keyboardEngaged = true
        // This is the sole deliberate keyboard path. Ambient reveal, hover,
        // redraw, and ordinary clicks never call makeKey or activate the app.
        panel.makeKeyAndOrderFront(nil)
    }

    func releaseKeyboard() {
        guard stateMachine.state.keyboardEngaged || panel?.keyboardEngaged == true else { return }
        stateMachine.reduce(.releaseKeyboard)
        keyboardFocus.end()
        focusedSessionIndex = nil
        shortcutGate.reset()
        panel?.keyboardEngaged = false
        panel?.resignKey()
        renderIfVisible()
    }

    func collapse() {
        dismissalWork?.cancel()
        hoverWork?.cancel()
        stateMachine.reduce(.collapse)
        keyboardFocus.end()
        focusedSessionIndex = nil
        shortcutGate.reset()
        panel?.keyboardEngaged = false
        panel?.resignKey()
        applyState()
        restorePrecedingKeyWindowIfEligible()
    }

    /// Bootstrap persisted mappings even if the OS rejects one. This preserves
    /// durable intent while exposing the exact unavailable/collision status.
    func bootstrapShortcutPreferences(_ preferences: AtlasShortcutPreferences) {
        shortcutRegistry = preferences.registry
        let result = shortcutRegistrar.apply(preferences.registry) { [weak self] command in
            self?.handleGlobalShortcut(command)
        }
        shortcutRegistrationStatus = result.status
    }

    /// Settings calls this before committing a rebind/master toggle. Native
    /// registration succeeds first; only then does the caller persist/swap its
    /// registry. Focused commands never reach Carbon.
    func tryApplyShortcutPreferences(_ preferences: AtlasShortcutPreferences) -> ShortcutRegistrationApplyResult {
        let result = shortcutRegistrar.apply(preferences.registry) { [weak self] command in
            self?.handleGlobalShortcut(command)
        }
        shortcutRegistrationStatus = result.status
        if case .accepted = result { shortcutRegistry = preferences.registry }
        return result
    }

    var keyboardFocusTarget: KeyboardFocusTarget? { keyboardFocus.focusedTarget }

    func setLocalEditActive(_ active: Bool) { localEditActive = active }

    nonisolated static func visibleFocusTargets(hasSessions: Bool, canInspect: Bool, canShowAll: Bool) -> [KeyboardFocusTarget] {
        var targets: [KeyboardFocusTarget] = [.summary]
        if hasSessions { targets.append(.session) }
        if canInspect { targets.append(.inspect) }
        if canShowAll { targets.append(.showAll) }
        targets += [.collapse, .settings]
        return targets
    }

    func reconcilePresentation() {
        let exactForeground = exactForegroundEvidence.map { evidence in
            presentation.cards.contains {
                let identity = AgentSessionIdentity(
                    productNamespace: ProductNamespace($0.productNamespace),
                    nativeSessionID: NativeSessionID($0.nativeSessionID)
                )
                return evidence.observation.isExact(for: identity, in: evidence.association)
            }
        } ?? false
        let suppressed = (hideInFullscreen && isFullscreenActive) || quietSceneActive || (hideWhenNoActiveSession && presentation.cards.isEmpty) || (suppressWhenExactHostForeground && exactForeground)
        stateMachine.reduce(.setQuietSceneSuppressed(suppressed))
        applyState()
    }

    /// Host integrations may provide this only after revalidating one exact
    /// owning Host Context. No title/path/app-only observation can enter this
    /// setter, and clearing it immediately removes suppression.
    func setExactHostForegroundEvidence(_ observation: ExactHostForegroundObservation?, association: HostContextAssociation? = nil) {
        if let observation, let association {
            exactForegroundEvidence = (observation, association)
        } else {
            exactForegroundEvidence = nil
        }
        reconcilePresentation()
    }

    func terminate() {
        guard !stateMachine.state.terminated else { return }
        hoverWork?.cancel()
        dismissalWork?.cancel()
        presentationCancellable?.cancel()
        shortcutRegistrar.unregisterAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        stateMachine.reduce(.terminate)
        removeOverlayRegionsAndWindow()
    }

    private var isFullscreenActive: Bool {
        // No Space identity is retained. This is only a current display policy
        // observation and cannot navigate, activate a Host, or collect pixels.
        NSApp.presentationOptions.contains(.fullScreen)
    }

    private func installObservers() {
        let notificationCenter = NotificationCenter.default
        observers.append(notificationCenter.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplays(coldResume: false) }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplays(coldResume: true) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcilePresentation() }
        })
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask([.keyDown, .keyUp])) { [weak self] event in
            guard let self, self.stateMachine.state.keyboardEngaged else { return event }
            let modifiers = ShortcutModifiers(rawValue: [
                event.modifierFlags.contains(.command) ? ShortcutModifiers.command.rawValue : 0,
                event.modifierFlags.contains(.option) ? ShortcutModifiers.option.rawValue : 0,
                event.modifierFlags.contains(.control) ? ShortcutModifiers.control.rawValue : 0,
                event.modifierFlags.contains(.shift) ? ShortcutModifiers.shift.rawValue : 0,
                event.modifierFlags.contains(.function) ? ShortcutModifiers.function.rawValue : 0
            ].reduce(0) { $0 | $1 })
            let keyEvent = ShortcutKeyEventMapper.make(
                keyCode: event.keyCode,
                modifiers: modifiers,
                phase: event.type == .keyUp ? .up : .down,
                isRepeat: event.isARepeat,
                hasMarkedText: CurrentMarkedTextState.hasMarkedText
            )
            let isNavigationKey = [PhysicalKey.escape.rawValue, PhysicalKey.tab.rawValue].contains(event.keyCode)
            if event.type == .keyUp {
                _ = self.shortcutGate.shouldInvoke(keyEvent)
                return event
            }
            if let command = self.shortcutRegistry.activeBindings.first(where: { $0.value == keyEvent.binding })?.key,
               command.isGloballyEligible {
                guard self.shortcutGate.shouldInvoke(keyEvent) else { return nil }
                self.dispatchLocalShortcut(command)
                return nil
            }
            if isNavigationKey, !self.shortcutGate.shouldInvoke(keyEvent) { return nil }
            if event.keyCode == PhysicalKey.escape.rawValue {
                if self.localEditActive {
                    self.localEditActive = false
                } else {
                    self.collapse()
                }
                return nil
            }
            if event.keyCode == PhysicalKey.tab.rawValue {
                if event.modifierFlags.contains(.shift) { self.keyboardFocus.moveBackward() } else { self.keyboardFocus.moveForward() }
                return nil
            }
            if event.keyCode == PhysicalKey.leftArrow.rawValue || event.keyCode == PhysicalKey.rightArrow.rawValue {
                self.navigateSession(offset: event.keyCode == PhysicalKey.leftArrow.rawValue ? -1 : 1)
                return nil
            }
            return event
        }
    }

    private func handleSleep() {
        hoverWork?.cancel()
        dismissalWork?.cancel()
        stateMachine.reduce(.sleep)
        applyState()
    }

    private func navigateSession(offset: Int) {
        guard !presentation.cards.isEmpty else { return }
        let current = focusedSessionIndex ?? 0
        let next = (current + offset + presentation.cards.count) % presentation.cards.count
        focusedSessionIndex = next
    }

    private func dispatchLocalShortcut(_ command: ShortcutCommand) {
        switch command {
        case .toggleOverlay: toggleOverlay()
        case .nextSession: navigateSession(offset: 1)
        case .previousSession: navigateSession(offset: -1)
        case .showAll:
            stateMachine.reduce(.hoverEntered)
            applyState()
        case .collapse: collapse()
        case .inspect: primaryClick()
        case .safeAction:
            routeSafeAction(command)
        }
    }

    /// Resolves one exact live Guided request and asks the injected
    /// coordinator only to focus/present it. A safe shortcut never constructs
    /// a lease or Action Attempt and never calls a Product client directly.
    private func routeSafeAction(_ command: ShortcutCommand) {
        guard case .safeAction = command else { return }
        guard guidedShortcutRequestsProvider != nil, guidedShortcutFocusHandler != nil else {
            publishShortcutInvocationFeedback(.guidedWorkflowUnavailable)
            return
        }

        switch ShortcutGuidedRouteResolver.resolve(command: command, requests: guidedShortcutRequestsProvider?() ?? []) {
        case let .unavailable(reason):
            publishShortcutInvocationFeedback(reason)
        case let .eligible(route):
            guard let outcome = guidedShortcutFocusHandler?(route) else {
                publishShortcutInvocationFeedback(.guidedWorkflowUnavailable)
                return
            }
            switch outcome {
            case .opened:
                shortcutInvocationFeedback = "Guided workflow focused the matching Attention Request. Review and confirm before sending; no Product action was sent."
            case let .unavailable(reason):
                publishShortcutInvocationFeedback(reason)
            }
        }
    }

    private func publishShortcutInvocationFeedback(_ reason: ShortcutGuidedRouteFailure) {
        shortcutInvocationFeedback = reason.humanReadableDescription
    }

    /// Global callbacks are deliberate engagement requests, not ambient
    /// reveals. A missing selected display leaves no panel/hit/AX region and
    /// reports the honest unavailable state to Settings.
    private func handleGlobalShortcut(_ command: ShortcutCommand) {
        guard command.isGloballyEligible else { return }
        guard selectedScreen != nil else {
            removeOverlayRegionsAndWindow()
            if command.configuredSafeAction != nil {
                shortcutInvocationFeedback = "No selected display is available; the Guided workflow remains withdrawn. Continue in the native Host."
            } else {
                shortcutRegistrationStatus = .unavailable("No selected display is available; the Overlay remains withdrawn.")
            }
            return
        }
        if command == .toggleOverlay {
            if stateMachine.state.keyboardEngaged {
                collapse()
            } else {
                if stateMachine.state.presentation == .withdrawn || stateMachine.state.presentation == .collapsed {
                    stateMachine.reduce(.hoverEntered)
                    applyState()
                }
                engageKeyboard()
            }
            return
        }
        if stateMachine.state.presentation == .withdrawn || stateMachine.state.presentation == .collapsed {
            stateMachine.reduce(.hoverEntered)
            applyState()
        }
        dispatchLocalShortcut(command)
        if !stateMachine.state.keyboardEngaged { engageKeyboard() }
    }

    private func refreshDisplays(coldResume: Bool) {
        displays = NSScreen.screens.compactMap(IslandDisplay.init(screen:))
        let availableIDs = Set(displays.map(\.id))
        let available = Self.validatedExplicitSelection(persistedID: selectedDisplayID, availableIDs: availableIDs) != nil
        if coldResume {
            stateMachine.reduce(.wake(displayAvailable: available))
            if available { stateMachine.reduce(.displayRevalidated(available: true)) }
            if !available {
                removeOverlayRegionsAndWindow()
            }
        } else if available, stateMachine.state.presentation == .withdrawn {
            stateMachine.reduce(.displayRevalidated(available: true))
        } else if !available {
            hoverWork?.cancel()
            dismissalWork?.cancel()
            stateMachine.reduce(.displayLost)
            releaseKeyboard()
            // Withdraw visible, hit-testing, and accessibility regions before
            // publishing selection-unavailable to the read-only preview.
            removeOverlayRegionsAndWindow()
        }
        stateMachine.reduce(.setQuietSceneSuppressed((hideInFullscreen && isFullscreenActive) || quietSceneActive || (hideWhenNoActiveSession && presentation.cards.isEmpty)))
        updateStatus()
        applyState()
    }

    private func updateStatus() {
        let status: String
        if let display = displays.first(where: { $0.id == selectedDisplayID }) {
            status = "Overlay is assigned to \(display.name)."
        } else if selectedDisplayID != nil {
            status = "The selected display is unavailable. The overlay stays withdrawn until it reconnects or you select another display."
        } else {
            status = "Choose a display to show the overlay."
        }
        // Publish the human-readable label first so the Settings bridge never
        // observes a new availability paired with a stale status string.
        displayStatus = status
        selectionAvailability = stateMachine.state.displayAvailability
    }

    private func applyState() {
        guard stateMachine.state.hasVisibleRegions else { removeOverlayRegionsAndWindow(); return }
        renderIfVisible()
    }

    private func renderIfVisible() {
        guard stateMachine.state.hasVisibleRegions, let screen = selectedScreen else { return }
        if stateMachine.state.keyboardEngaged {
            keyboardFocus.updateVisibleTargets(Self.visibleFocusTargets(
                hasSessions: !presentation.cards.isEmpty,
                canInspect: !presentation.cards.isEmpty,
                canShowAll: presentation.cards.count > 1
            ))
        }
        let geometry = IslandOverlayGeometry.make(for: screen, presentation: stateMachine.state.presentation, settings: displayPreferences)
        let root = IslandOverlayView(
            presentation: stateMachine.state.presentation,
            geometry: geometry,
            cards: presentation.cards,
            ledgerRevision: presentation.ledgerRevision,
            keyboardEngaged: stateMachine.state.keyboardEngaged,
            focusedSessionIndex: focusedSessionIndex,
            clickBehavior: clickBehavior,
            displayPreferences: displayPreferences,
            onPrimaryClick: { [weak self] in self?.primaryClick() },
            lastClickOutcome: lastClickOutcome,
            onExpand: { [weak self] in self?.toggleOverlay() },
            onCollapse: { [weak self] in self?.collapse() },
            onSettings: { [weak self] in self?.showSettings?() },
            onEngageKeyboard: { [weak self] in self?.engageKeyboard() }
        )
        if panel == nil {
            let panel = IslandOverlayPanel(contentRect: geometry.frame)
            let container = IslandOverlayContainerView(rootView: root)
            container.entered = { [weak self] in self?.hoverEntered() }
            container.exited = { [weak self] in self?.hoverExited() }
            panel.contentView = container
            self.panel = panel
            self.container = container
        } else {
            container?.replace(rootView: root)
        }
        panel?.setFrame(geometry.frame, display: true)
        container?.regions = geometry.hitRegions
        panel?.ignoresMouseEvents = false
        panel?.orderFrontRegardless()
    }

    /// Set by the AppKit shell so the overlay never needs to know how the
    /// independently activating Settings window is constructed.
    var showSettings: (() -> Void)?

    private func removeOverlayRegionsAndWindow() {
        // Order matters: make invisible regions non-interactive/non-AX before
        // ordering out the panel, including on display loss and termination.
        keyboardFocus.end()
        shortcutGate.reset()
        focusedSessionIndex = nil
        container?.regions = []
        container?.setAccessibilityHidden(true)
        panel?.ignoresMouseEvents = true
        panel?.keyboardEngaged = false
        panel?.orderOut(nil)
        container = nil
        panel = nil
    }

    private func hoverEntered() {
        guard hoverExpansionEnabled, stateMachine.state.presentation == .collapsed else { return }
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stateMachine.reduce(.hoverEntered)
            self.applyState()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func hoverExited() {
        guard Self.shouldCollapseAfterPointerExit(
            collapseOnPointerExit: collapseOnPointerExit,
            interactionGuard: stateMachine.state.interactionGuard,
            keyboardEngaged: stateMachine.state.keyboardEngaged
        ) else { return }
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static func displayIdentity(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return IslandDisplay.identity(for: CGDirectDisplayID(number.uint32Value))
    }

    private func restorePrecedingKeyWindowIfEligible() {
        guard let previous = precedingKeyWindow,
              previous !== panel,
              previous.isVisible,
              previous.canBecomeKey
        else { precedingKeyWindow = nil; return }
        previous.makeKey()
        precedingKeyWindow = nil
    }
}
