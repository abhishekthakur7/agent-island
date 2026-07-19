import AppKit

_ = LaunchEvidence.processStartedAt
EvidenceLogger.shared.record("launch_process_started")

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Automatic presentation is an accessory-app surface. Settings is the only
// explicit activation path in this disposable feasibility fixture.
application.setActivationPolicy(.accessory)
application.run()
