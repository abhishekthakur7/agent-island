import AppKit
import SwiftUI
import PresentationRuntime

/// AppKit owns the two deliberately distinct presentation hosts: a normally
/// non-activating Island Overlay and an independently activating Settings
/// window. SwiftUI supplies content only; it never owns panel lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let presentation: PresentationRuntime
    private let fixtureController: FixtureController
    private let horizon = HorizonController()
    private lazy var overlay = IslandOverlayController(presentation: presentation)
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    init(presentation: PresentationRuntime, fixtureController: FixtureController) {
        self.presentation = presentation
        self.fixtureController = fixtureController
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        overlay.showSettings = { [weak self] in self?.showSettings(nil) }
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
        if settingsWindow == nil {
            let root = AgentIslandSettingsView(overlay: overlay, presentation: presentation, fixtureController: fixtureController, horizon: horizon)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 840),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Agent Island Settings"
            window.contentView = NSHostingView(rootView: root)
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
