import AppKit
import Combine
import SwiftUI
import ServiceManagement
import PresentationRuntime

/// AppKit owns the two deliberately distinct presentation hosts: a normally
/// non-activating Island Overlay and an independently activating Settings
/// window. SwiftUI supplies content only; it never owns panel lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let presentation: PresentationRuntime
    private let fixtureController: FixtureController
    private let claudeActionComposition: ClaudeActionApplicationComposition
    private let atlasSettings: AtlasSettingsModel
    private let notificationSettings = NotificationPolicySettingsModel()
    private lazy var settingsCoordinator = AtlasSettingsWindowCoordinator { [unowned self] in
        AnyView(AgentIslandSettingsView(
            model: self.atlasSettings,
            notificationSettings: self.notificationSettings,
            liveDisplayControls: AnyView(AtlasOverlayDisplayControls(model: self.atlasSettings, overlay: self.overlay))
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

    init(presentation: PresentationRuntime, fixtureController: FixtureController, claudeActionComposition: ClaudeActionApplicationComposition) {
        self.presentation = presentation
        self.fixtureController = fixtureController
        self.claudeActionComposition = claudeActionComposition
        let atlasSettings = AtlasSettingsModel(shortcutInputSourceResolver: {
            NativeShortcutInputSourceResolver.current()
        })
        self.atlasSettings = atlasSettings
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // AppKit may ask to restore windows before did-finish-launching.
        // Register the coordinator before that restoration phase begins.
        _ = settingsCoordinator
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        overlay.showSettings = { [weak self] in self?.showSettings(nil) }
        applyLaunchAtLogin(atlasSettings.general.launchBehavior)
        applyAtlasPresentationPreferences(atlasSettings.general)
        applyAtlasDisplayPreferences(atlasSettings.display)
        overlay.bootstrapShortcutPreferences(atlasSettings.shortcuts)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.terminate()
        claudeActionComposition.retire()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        overlay.terminate()
        claudeActionComposition.retire()
        return .terminateNow
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
