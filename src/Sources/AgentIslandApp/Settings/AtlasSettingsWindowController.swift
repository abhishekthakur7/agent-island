import AppKit
import SwiftUI

/// Owns the ordinary, activating Settings window independently from the
/// non-activating Island Overlay. The content factory is composition-root
/// supplied so restoration never needs an Overlay or Product dependency.
@MainActor
final class AtlasSettingsWindowCoordinator: NSObject, NSWindowDelegate {
    static let restorationIdentifier = NSUserInterfaceItemIdentifier("com.agentisland.settings.atlas")
    static let frameAutosaveName = "AgentIsland.AtlasSettings.Frame"

    private let content: () -> AnyView
    private var controller: NSWindowController?

    init(content: @escaping () -> AnyView) {
        self.content = content
        super.init()
        AtlasSettingsWindowRestorer.coordinator = self
    }

    func showSettings() {
        let controller = controller ?? makeController()
        self.controller = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func restoreSettingsWindow(completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        let controller = self.controller ?? makeController()
        self.controller = controller
        completionHandler(controller.window, nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              closing === controller?.window else { return }
        controller = nil
    }

    private func makeController() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Island Settings"
        window.identifier = Self.restorationIdentifier
        window.isRestorable = true
        window.restorationClass = AtlasSettingsWindowRestorer.self
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.minSize = NSSize(width: 680, height: 520)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: content())
        window.center()
        return NSWindowController(window: window)
    }
}

/// AppKit calls this type during state restoration. Reconstruction is routed
/// to the composition-root coordinator rather than relying on a retained old
/// window controller or encoding application services into restorable state.
final class AtlasSettingsWindowRestorer: NSObject, NSWindowRestoration {
    nonisolated(unsafe) static weak var coordinator: AtlasSettingsWindowCoordinator?

    static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, Error?) -> Void
    ) {
        Task { @MainActor in
            guard identifier == AtlasSettingsWindowCoordinator.restorationIdentifier,
                  let coordinator else {
                completionHandler(nil, nil)
                return
            }
            coordinator.restoreSettingsWindow(completionHandler: completionHandler)
        }
    }
}
