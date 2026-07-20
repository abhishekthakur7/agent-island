import AppKit
import Foundation
import ApplicationRuntime
import SessionStore
import ProtectedStore
import PresentationRuntime

/// One stable per-installation Keychain account for this personal, single-
/// user companion app (ADR 0008). Not a multi-account/multi-tenant marker.
private let protectedStoreKeychainAccount = "default-installation"

private func protectedStoreDatabaseURL() -> URL {
    let appSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AgentIsland", isDirectory: true)
    return appSupport.appendingPathComponent("protected-store.sqlite")
}

private func makeProtectedStore() -> ProtectedStore {
    ProtectedStore(configuration: ProtectedStoreConfiguration(
        databaseURL: protectedStoreDatabaseURL(),
        keychainAccount: protectedStoreKeychainAccount
    ))
}

@MainActor
private func launchGUI() async {
    let store: SessionStore
    do {
        // Opening/bootstrapping the encrypted store does real disk I/O and
        // SQLCipher pragma/integrity work — never block the main thread with
        // it, on first launch or on a post-discard relaunch.
        let protectedStore = makeProtectedStore()
        store = try await Task.detached(priority: .userInitiated) {
            try SessionStore(protectedStore: protectedStore)
        }.value
    } catch {
        await presentStorageUnavailable(error)
        return
    }

    let runtime = ApplicationRuntime(store: store)
    let presentation = PresentationRuntime(port: runtime)
    let fixtureController = FixtureController(port: runtime)
    // The app retains the real action-server composition for the lifetime of
    // its GUI. Integration setup installs a current negotiated configuration;
    // until then it remains deliberately fail-closed and Claude stays native.
    let claudeActionComposition = ClaudeActionApplicationComposition()

    let delegate = AppDelegate(presentation: presentation, fixtureController: fixtureController, claudeActionComposition: claudeActionComposition)
    let app = NSApplication.shared
    app.delegate = delegate
    // Ambient Island presentation is an accessory surface. Settings explicitly
    // activates only when the person opens it from the system menu.
    app.setActivationPolicy(.accessory)
    app.run()
}

/// AB-119 AC5: a missing key, corrupt ciphertext, integrity failure, or
/// interrupted migration must never launch with a silently reset store. This
/// presents the redacted reason and only ever acts on an explicit person
/// choice — it never resets or deletes local evidence on its own. A
/// transient Keychain access problem (`isSafeToOfferDestructivePurge ==
/// false`) never offers the destructive discard/purge choice, since the key
/// was never actually shown to be lost.
@MainActor
private func presentStorageUnavailable(_ error: Error) async {
    let failure = error as? ProtectedStoreFailure
    let diagnosticCode = failure?.diagnosticCode ?? "storage.unavailable"
    let canOfferDiscard = failure?.isSafeToOfferDestructivePurge ?? true

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Agent Island's protected store is unavailable"
    alert.informativeText = canOfferDiscard
        ? "Reason: \(diagnosticCode)\n\nYour local Agent Session evidence has not been deleted or reset. Choose how to proceed."
        : "Reason: \(diagnosticCode)\n\nThis looks like a temporary problem reaching the Keychain, not lost data. Try again before assuming anything is gone."
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Reveal in Finder")
    if canOfferDiscard {
        alert.addButton(withTitle: "Discard Local Data…")
    }

    switch alert.runModal() {
    case .alertSecondButtonReturn:
        NSWorkspace.shared.activateFileViewerSelecting([protectedStoreDatabaseURL()])
        exit(EXIT_FAILURE)

    case .alertThirdButtonReturn where canOfferDiscard:
        guard confirmDestructiveDiscard() else {
            exit(EXIT_FAILURE)
        }
        discardLocalProtectedStore()
        await launchGUI()

    default:
        exit(EXIT_FAILURE)
    }
}

@MainActor
private func confirmDestructiveDiscard() -> Bool {
    let confirmation = NSAlert()
    confirmation.alertStyle = .critical
    confirmation.messageText = "Discard local Agent Session data?"
    confirmation.informativeText = "This permanently deletes the protected local store and its per-installation key. This cannot be undone."
    confirmation.addButton(withTitle: "Cancel")
    confirmation.addButton(withTitle: "Discard")
    return confirmation.runModal() == .alertSecondButtonReturn
}

private func discardLocalProtectedStore() {
    makeProtectedStore().discardAllLocalDataAfterPersonConfirmedPurge()
}

if CommandLine.arguments.contains("--self-check") {
    let exitCode = await SelfCheck.run()
    exit(exitCode)
} else {
    await launchGUI()
}
