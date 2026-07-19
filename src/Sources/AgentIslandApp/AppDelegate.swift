import AppKit
import SwiftUI
import PresentationRuntime

/// The AppKit shell. It owns `NSApplication`/`NSWindow` mechanics; SwiftUI
/// only hosts presentation content inside it. This slice uses a standard
/// activating window — the non-activating Island Overlay panel is a later
/// ticket that reuses the already-accepted AB-116 spike.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let presentation: PresentationRuntime
    private let fixtureController: FixtureController
    private var window: NSWindow?

    init(presentation: PresentationRuntime, fixtureController: FixtureController) {
        self.presentation = presentation
        self.fixtureController = fixtureController
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView(presentation: presentation, fixtureController: fixtureController)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Island"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
