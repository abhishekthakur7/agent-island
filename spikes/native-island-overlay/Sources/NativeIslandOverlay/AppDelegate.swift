import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = OverlayController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        controller.start()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - LaunchEvidence.processStartedAt) / 1_000_000
        EvidenceLogger.shared.record("launch_usable", metadata: ["fixtureSessionCount": 30, "elapsedMs": elapsedMs])

        if CommandLine.arguments.contains("--evidence-automatic-reveal-after-ready") {
            DispatchQueue.main.async { [weak self] in self?.controller.autoReveal() }
        } else if CommandLine.arguments.contains("--evidence-quit-after-ready") {
            DispatchQueue.main.async { [weak self] in self?.terminateAfterEvidenceReady() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.terminate()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.terminate()
        return .terminateNow
    }

    @objc private func showSettings(_ sender: Any?) { controller.showSettings() }
    @objc private func engageKeyboard(_ sender: Any?) { controller.engageKeyboard() }
    @objc private func toggleOverlay(_ sender: Any?) { controller.toggleOverlay() }
    @objc private func autoReveal(_ sender: Any?) { controller.autoReveal() }
    @objc private func terminateAfterEvidenceReady() { NSApp.terminate(nil) }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        appItem.submenu = makeApplicationMenu()
        NSApp.mainMenu = menu

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Native Island Overlay")
        item.menu = makeApplicationMenu()
        statusItem = item
    }

    private func makeApplicationMenu() -> NSMenu {
        let appMenu = NSMenu()
        let toggle = appMenu.addItem(withTitle: "Show / Collapse Overlay", action: #selector(toggleOverlay(_:)), keyEquivalent: "")
        toggle.target = self
        let automaticReveal = appMenu.addItem(withTitle: "Automatic Reveal", action: #selector(autoReveal(_:)), keyEquivalent: "")
        automaticReveal.target = self
        let keyboard = appMenu.addItem(withTitle: "Engage Overlay Keyboard", action: #selector(engageKeyboard(_:)), keyEquivalent: "")
        keyboard.target = self
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Native Island Overlay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return appMenu
    }
}

enum LaunchEvidence {
    /// Forced from main before NSApplication is created so both launch markers
    /// share a process-local monotonic boundary rather than only measuring the
    /// delegate callback.
    static let processStartedAt = DispatchTime.now().uptimeNanoseconds
}

@MainActor
final class EvidenceLogger {
    static let shared = EvidenceLogger()
    static let schemaVersion = 1

    private let handle: FileHandle?
    private let scenario: String?

    private init() {
        let environment = ProcessInfo.processInfo.environment
        scenario = Self.commandArgument(named: "--evidence-scenario")
        guard let path = environment["AI_OVERLAY_EVIDENCE_LOG"], !path.isEmpty else {
            handle = nil
            return
        }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: path)
        _ = try? handle?.seekToEnd()
    }

    func record(_ event: String, metadata: [String: Any] = [:]) {
        guard let handle else { return }
        var record: [String: Any] = [
            "event": event,
            "timestampNs": String(DispatchTime.now().uptimeNanoseconds),
            "schemaVersion": Self.schemaVersion
        ]
        if let scenario { record["scenario"] = scenario }
        if !metadata.isEmpty { record["metadata"] = metadata }
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) else { return }
        try? handle.write(contentsOf: line)
    }

    private static func commandArgument(named name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
