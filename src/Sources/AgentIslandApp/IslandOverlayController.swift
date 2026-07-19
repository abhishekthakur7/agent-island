import AppKit
import Combine
import SwiftUI
import PresentationRuntime

@MainActor
final class IslandOverlayController: NSObject, ObservableObject {
    @Published private(set) var displays: [IslandDisplay] = []
    @Published var selectedDisplayID: String?
    @Published var hideInFullscreen = true
    @Published var quietSceneActive = false
    @Published var hoverExpansionEnabled = true
    @Published private(set) var displayStatus = "Looking for a selected display…"

    private let presentation: PresentationRuntime
    private var stateMachine = IslandOverlayStateMachine()
    private var panel: IslandOverlayPanel?
    private var container: IslandOverlayContainerView?
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var presentationCancellable: AnyCancellable?
    private var hoverWork: DispatchWorkItem?
    private var dismissalWork: DispatchWorkItem?

    init(presentation: PresentationRuntime) { self.presentation = presentation }

    var selectedScreen: NSScreen? {
        guard let selectedDisplayID else { return nil }
        return NSScreen.screens.first { Self.displayIdentity(for: $0) == selectedDisplayID }
    }

    func start() {
        installObservers()
        presentationCancellable = presentation.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.renderIfVisible() }
        }
        refreshDisplays(coldResume: true)
    }

    func selectDisplay(id: String?) {
        releaseKeyboard()
        selectedDisplayID = id
        stateMachine.reduce(.displayLost)
        if selectedScreen != nil { stateMachine.reduce(.displayReconnected) }
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

    func engageKeyboard() {
        stateMachine.reduce(.engageKeyboard)
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
        panel?.keyboardEngaged = false
        panel?.resignKey()
        renderIfVisible()
    }

    func collapse() {
        dismissalWork?.cancel()
        hoverWork?.cancel()
        stateMachine.reduce(.collapse)
        panel?.keyboardEngaged = false
        panel?.resignKey()
        applyState()
    }

    func reconcilePresentation() {
        stateMachine.reduce(.setQuietSceneSuppressed((hideInFullscreen && isFullscreenActive) || quietSceneActive))
        applyState()
    }

    func terminate() {
        guard !stateMachine.state.terminated else { return }
        hoverWork?.cancel()
        dismissalWork?.cancel()
        presentationCancellable?.cancel()
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.stateMachine.state.keyboardEngaged else { return event }
            if event.keyCode == 53 { self.collapse(); return nil }
            return event
        }
    }

    private func handleSleep() {
        hoverWork?.cancel()
        dismissalWork?.cancel()
        stateMachine.reduce(.sleep)
        applyState()
    }

    private func refreshDisplays(coldResume: Bool) {
        displays = NSScreen.screens.compactMap(IslandDisplay.init(screen:))
        if selectedDisplayID == nil, let main = NSScreen.main { selectedDisplayID = Self.displayIdentity(for: main) }
        let available = selectedScreen != nil
        if coldResume {
            stateMachine.reduce(.wake(displayAvailable: available))
        } else if available, stateMachine.state.presentation == .withdrawn {
            stateMachine.reduce(.displayReconnected)
        } else if !available {
            stateMachine.reduce(.displayLost)
        }
        stateMachine.reduce(.setQuietSceneSuppressed((hideInFullscreen && isFullscreenActive) || quietSceneActive))
        updateStatus()
        applyState()
    }

    private func updateStatus() {
        if let display = displays.first(where: { $0.id == selectedDisplayID }) {
            displayStatus = "Overlay is assigned to \(display.name)."
        } else if selectedDisplayID != nil {
            displayStatus = "The selected display is unavailable. The overlay stays withdrawn until it reconnects or you select another display."
        } else {
            displayStatus = "Choose a display to show the overlay."
        }
    }

    private func applyState() {
        guard stateMachine.state.hasVisibleRegions else { removeOverlayRegionsAndWindow(); return }
        renderIfVisible()
    }

    private func renderIfVisible() {
        guard stateMachine.state.hasVisibleRegions, let screen = selectedScreen else { return }
        let geometry = IslandOverlayGeometry.make(for: screen, presentation: stateMachine.state.presentation)
        let root = IslandOverlayView(
            presentation: stateMachine.state.presentation,
            geometry: geometry,
            cards: presentation.cards,
            ledgerRevision: presentation.ledgerRevision,
            keyboardEngaged: stateMachine.state.keyboardEngaged,
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
        guard hoverExpansionEnabled, !stateMachine.state.interactionGuard, !stateMachine.state.keyboardEngaged else { return }
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static func displayIdentity(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return IslandDisplay.identity(for: CGDirectDisplayID(number.uint32Value))
    }
}
