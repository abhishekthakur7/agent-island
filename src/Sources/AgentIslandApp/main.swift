import AppKit
import Foundation
import ApplicationRuntime
import SessionStore
import PresentationRuntime

@MainActor
private func launchGUI() {
    let store = SessionStore()
    let runtime = ApplicationRuntime(store: store)
    let presentation = PresentationRuntime(port: runtime)
    let fixtureController = FixtureController(port: runtime)

    let delegate = AppDelegate(presentation: presentation, fixtureController: fixtureController)
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}

if CommandLine.arguments.contains("--self-check") {
    let exitCode = await SelfCheck.run()
    exit(exitCode)
} else {
    await launchGUI()
}
