import AppKit
import SwiftUI

@MainActor
final class OverlayController: NSObject, ObservableObject {
    @Published private(set) var displays: [DisplayOption] = []
    @Published var selectedDisplayID: String?
    @Published var hideInFullscreen = true
    @Published var simulateFullscreen = false
    @Published var hoverExpansionEnabled = true
    @Published private(set) var displayStatus = "Looking for selected display…"

    let sessions = FixtureSession.samples
    private var stateMachine = OverlayStateMachine()
    private var panel: OverlayPanel?
    private var container: OverlayContainerView?
    private var settings: SettingsWindowController?
    private var observers: [NSObjectProtocol] = []
    private var localKeyMonitor: Any?
    private var hoverWork: DispatchWorkItem?
    private var dismissalWork: DispatchWorkItem?

    var selectedScreen: NSScreen? {
        guard let selectedDisplayID else { return nil }
        return NSScreen.screens.first { Self.displayIdentity(for: $0) == selectedDisplayID }
    }

    func start() {
        installObservers()
        refreshDisplays(coldResume: true)
    }

    func showSettings() {
        if settings == nil { settings = SettingsWindowController(controller: self) }
        settings?.show()
    }

    func toggleOverlay() {
        if stateMachine.state.presentation == .withdrawn || stateMachine.state.presentation == .collapsed {
            stateMachine.reduce(.hoverEntered)
        } else {
            stateMachine.reduce(.collapse)
        }
        applyState(event: "toggle")
    }

    func autoReveal() {
        recordInteractionRequested(kind: "automaticReveal")
        stateMachine.reduce(.automaticReveal)
        applyState(event: "overlay_focused")
        recordInteractionRendered(kind: "automaticReveal")
        dismissalWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stateMachine.state.keyboardEngaged, !self.stateMachine.state.interactionGuard else { return }
            self.stateMachine.reduce(.collapse)
            self.applyState(event: "overlay_collapsed")
        }
        dismissalWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    func withdraw() {
        stateMachine.reduce(.displayLost)
        applyState(event: "panel_withdrawn")
    }

    func reconcilePresentation() {
        stateMachine.reduce(.setFullscreenSuppressed(hideInFullscreen && simulateFullscreen))
        applyState(event: stateMachine.state.presentation == .withdrawn ? "panel_withdrawn" : "overlay_collapsed")
    }

    func selectDisplay(id: String?) {
        releaseKeyboard()
        selectedDisplayID = id
        stateMachine.reduce(.displayLost)
        if selectedScreen != nil { stateMachine.reduce(.displayReconnected) }
        updateStatus()
        applyState(event: stateMachine.state.presentation == .withdrawn ? "panel_withdrawn" : "overlay_collapsed")
    }

    func engageKeyboard() {
        recordInteractionRequested(kind: "keyboard")
        stateMachine.reduce(.engageKeyboard)
        applyState(event: "keyboard_engaged")
        guard stateMachine.state.keyboardEngaged, let panel else { return }
        panel.keyboardEngaged = true
        panel.makeKeyAndOrderFront(nil) // Nonactivating panel: intentional key engagement, not app activation.
        recordInteractionRendered(kind: "keyboard")
    }

    func releaseKeyboard() {
        guard stateMachine.state.keyboardEngaged || panel?.keyboardEngaged == true else { return }
        stateMachine.reduce(.releaseKeyboard)
        panel?.keyboardEngaged = false
        panel?.resignKey()
        renderIfVisible()
        EvidenceLogger.shared.record("keyboard_released")
    }

    func collapse() {
        dismissalWork?.cancel()
        hoverWork?.cancel()
        stateMachine.reduce(.collapse)
        panel?.keyboardEngaged = false
        panel?.resignKey()
        applyState(event: "overlay_collapsed")
    }

    func handleWake() {
        refreshDisplays(coldResume: true)
        EvidenceLogger.shared.record("wake_rebuilt")
    }

    func terminate() {
        guard !stateMachine.state.terminated else { return }
        hoverWork?.cancel()
        dismissalWork?.cancel()
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        localKeyMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        stateMachine.reduce(.terminate)
        removeOverlayRegionsAndWindow()
        settings?.close()
        EvidenceLogger.shared.record("panel_withdrawn", metadata: ["reason": "termination"])
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplays(coldResume: false) }
        })
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        })
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcilePresentation() } // A Space is never stored or used as identity.
        })
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.stateMachine.state.keyboardEngaged else { return event }
            if event.keyCode == 53 { // Escape
                self.collapse()
                return nil
            }
            return event
        }
    }

    private func handleSleep() {
        hoverWork?.cancel()
        dismissalWork?.cancel()
        stateMachine.reduce(.sleep)
        applyState(event: "panel_withdrawn")
    }

    private func refreshDisplays(coldResume: Bool) {
        displays = NSScreen.screens.compactMap(DisplayOption.init(screen:))
        if selectedDisplayID == nil, let mainScreen = NSScreen.main {
            selectedDisplayID = Self.displayIdentity(for: mainScreen)
        }
        let available = selectedScreen != nil
        if coldResume {
            stateMachine.reduce(.wake(displayAvailable: available))
        } else if available, stateMachine.state.presentation == .withdrawn {
            stateMachine.reduce(.displayReconnected)
        } else if !available {
            stateMachine.reduce(.displayLost)
        }
        stateMachine.reduce(.setFullscreenSuppressed(hideInFullscreen && simulateFullscreen))
        updateStatus()
        applyState(event: stateMachine.state.presentation == .withdrawn ? "panel_withdrawn" : "overlay_collapsed")
    }

    private func updateStatus() {
        if let display = displays.first(where: { $0.id == selectedDisplayID }) {
            displayStatus = "Overlay is assigned to \(display.name)."
        } else if selectedDisplayID != nil {
            displayStatus = "Selected display is unavailable. The overlay remains withdrawn until it reconnects or you choose another display."
        } else {
            displayStatus = "Choose a display to show the overlay."
        }
    }

    private func applyState(event: String) {
        if stateMachine.state.presentation == .withdrawn {
            removeOverlayRegionsAndWindow()
            EvidenceLogger.shared.record(event)
            return
        }
        renderIfVisible()
        EvidenceLogger.shared.record(event)
    }

    /// The timing markers are causal around a synchronous AppKit render. They
    /// establish only the fixture's presentation boundary; the evidence report
    /// still requires human proof of VoiceOver operation and Host focus.
    private func recordInteractionRequested(kind: String) {
        EvidenceLogger.shared.record("interaction_requested", metadata: [
            "kind": kind,
            "applicationIsActive": NSApp.isActive
        ])
    }

    private func recordInteractionRendered(kind: String) {
        panel?.contentView?.layoutSubtreeIfNeeded()
        EvidenceLogger.shared.record("interaction_rendered", metadata: [
            "kind": kind,
            "presentation": stateMachine.state.presentation.rawValue,
            "keyboardEngaged": stateMachine.state.keyboardEngaged,
            "applicationIsActive": NSApp.isActive
        ])
    }

    private func renderIfVisible() {
        guard let screen = selectedScreen, stateMachine.state.presentation != .withdrawn else { return }
        let geometry = OverlayGeometry.make(for: screen, presentation: stateMachine.state.presentation)
        let root = makeRootView(geometry: geometry)
        if panel == nil {
            let created = OverlayPanel(contentRect: geometry.frame)
            let rootContainer = OverlayContainerView(rootView: root)
            rootContainer.entered = { [weak self] in self?.hoverEntered() }
            rootContainer.exited = { [weak self] in self?.hoverExited() }
            created.contentView = rootContainer
            panel = created
            container = rootContainer
        } else {
            container?.replace(rootView: root)
        }
        panel?.setFrame(geometry.frame, display: true)
        container?.regions = geometry.hitRegions
        container?.setAccessibilityLabel(stateMachine.state.presentation == .collapsed
            ? "Working; 30 Agent Sessions; \(sessions.filter { $0.state == .attention }.count) need attention"
            : "Agent Sessions, non-modal region")
        panel?.ignoresMouseEvents = false
        panel?.orderFrontRegardless()
    }

    private func removeOverlayRegionsAndWindow() {
        // Remove mouse and accessibility targets before the panel is ordered out.
        container?.regions = []
        container?.setAccessibilityHidden(true)
        panel?.ignoresMouseEvents = true
        panel?.keyboardEngaged = false
        panel?.orderOut(nil)
        container = nil
        panel = nil
    }

    private func makeRootView(geometry: OverlayGeometry) -> OverlayContentView {
        OverlayContentView(
            presentation: stateMachine.state.presentation,
            geometry: geometry,
            sessions: sessions,
            keyboardEngaged: stateMachine.state.keyboardEngaged,
            onExpand: { [weak self] in self?.toggleOverlay() },
            onCollapse: { [weak self] in self?.collapse() },
            onSettings: { [weak self] in self?.showSettings() },
            onEngageKeyboard: { [weak self] in self?.engageKeyboard() }
        )
    }

    private func hoverEntered() {
        guard hoverExpansionEnabled, stateMachine.state.presentation == .collapsed else { return }
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stateMachine.reduce(.hoverEntered)
            self.applyState(event: "overlay_expanded")
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func hoverExited() {
        guard hoverExpansionEnabled, !stateMachine.state.interactionGuard, !stateMachine.state.keyboardEngaged else { return }
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static func displayIdentity(for screen: NSScreen) -> String? {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let number else { return nil }
        return DisplayOption.identity(for: CGDirectDisplayID(number))
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(controller: OverlayController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Native Island Overlay Settings"
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true) // Settings is the explicit, normal activating surface.
    }
}
