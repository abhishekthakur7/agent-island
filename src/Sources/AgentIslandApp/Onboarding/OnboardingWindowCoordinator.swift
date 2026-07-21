import AppKit
import SwiftUI

/// AB-164 — presents the onboarding flow (`OnboardingRootView`) in its own
/// `NSWindow`. Mirrors `AtlasSettingsWindowCoordinator`'s shape
/// (`Settings/AtlasSettingsWindowController.swift`): a composition-root
/// -supplied content factory, a lazily-built controller, and window-close
/// cleanup. Window state restoration is intentionally not ported over —
/// onboarding is a one-shot flow, not a window a person expects AppKit to
/// reopen after a relaunch.
///
/// Deliberately **not** wired into `AppDelegate`'s launch sequence — this
/// ticket's scope is the visual scaffold, not first-run auto-launch (see the
/// ticket's "Do NOT wire auto-launch" note). A later ticket (or a manual
/// debug call to `show()`) decides when this actually presents.
@MainActor
final class OnboardingWindowCoordinator: NSObject, NSWindowDelegate {
    private let content: () -> AnyView
    private var controller: NSWindowController?

    init(content: @escaping () -> AnyView) {
        self.content = content
        super.init()
    }

    /// Presents the onboarding window, creating it on first call and
    /// reusing it while it stays open.
    func show() {
        let controller = controller ?? makeController()
        self.controller = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Closes the window if one is open. Exposed so a future `onComplete`
    /// hook (see `OnboardingFlowModel`) can dismiss the flow once the last
    /// screen finishes, without reaching into AppKit itself.
    func close() {
        controller?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              closing === controller?.window else { return }
        controller = nil
    }

    private func makeController() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Island"
        // AC-2.1-b wants the real macOS traffic lights top-left with the
        // radial background running full-bleed behind them — no separate
        // gray titlebar strip and no hand-drawn fake dots. `.titled` +
        // `.fullSizeContentView` keeps the *real* traffic-light buttons
        // while letting `OnboardingRootView`'s content extend underneath;
        // hiding the title text and making the titlebar transparent removes
        // the strip itself.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: content())
        window.center()
        return NSWindowController(window: window)
    }
}
