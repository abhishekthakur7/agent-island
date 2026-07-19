import AppKit
import Combine
import SwiftUI
import PresentationRuntime

/// AppKit owns the two deliberately distinct presentation hosts: a normally
/// non-activating Island Overlay and an independently activating Settings
/// window. SwiftUI supplies content only; it never owns panel lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let presentation: PresentationRuntime
    private let fixtureController: FixtureController
    private let atlasSettings: AtlasSettingsModel
    private lazy var settingsCoordinator = AtlasSettingsWindowCoordinator { [unowned self] in
        AnyView(AgentIslandSettingsView(
            model: self.atlasSettings,
            liveDisplayControls: AnyView(AtlasOverlayDisplayControls(overlay: self.overlay))
        ))
    }
    private let horizon = HorizonController()
    private lazy var overlay = IslandOverlayController(presentation: presentation)
    private var statusItem: NSStatusItem?
    private var settingsCancellable: AnyCancellable?

    init(presentation: PresentationRuntime, fixtureController: FixtureController) {
        self.presentation = presentation
        self.fixtureController = fixtureController
        let atlasSettings = AtlasSettingsModel()
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
        applyAtlasPresentationPreferences(atlasSettings.general)
        settingsCancellable = atlasSettings.$general.sink { [weak self] general in
            self?.applyAtlasPresentationPreferences(general)
        }
        overlay.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.terminate()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        overlay.terminate()
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
        overlay.hoverExpansionEnabled = general.expandOnHover
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
    @ObservedObject var overlay: IslandOverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Overlay assignment").font(.headline)
            Picker("Selected display", selection: Binding(
                get: { overlay.selectedDisplayID },
                set: { overlay.selectDisplay(id: $0) }
            )) {
                ForEach(overlay.displays) { display in
                    Text(display.name).tag(Optional(display.id))
                }
            }
            Text(overlay.displayStatus)
                .font(.caption)
                .foregroundStyle(overlay.selectedScreen == nil ? .orange : .secondary)
        }
        .accessibilityIdentifier("atlas.display.liveAssignment")
    }
}
