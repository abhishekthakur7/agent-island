import AppKit
import Foundation
import ApplicationRuntime
import SessionStore
import ProtectedStore
import PresentationRuntime
import ITerm2HostAdapter
import CursorHostAdapter
import WarpHostAdapter
import OrcaHostAdapter
import LocalProductDiscovery

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

private func makeCursorHostSetup() -> CursorExtensionLocalEndpoint {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AgentIsland/cursor-host", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: NSNumber(value: 0o700)])
    // This per-app-run credential is passed only through the explicit
    // person-initiated setup sheet. It is never stored in diagnostics.
    return CursorExtensionLocalEndpoint(socketPath: root.appendingPathComponent("extension.sock").path, credential: Data(UUID().uuidString.utf8))
}

/// A one-shot box used only to hand a background task's result back to a
/// launch-time thread that is waiting on a semaphore. `@unchecked` because the
/// producer signals the semaphore before the consumer reads, so the access is
/// already ordered.
private final class LaunchResultBox<Value>: @unchecked Sendable {
    var value: Value?
}

/// The Sendable result of the off-main store bootstrap. A non-store error is
/// reported as `.failed(nil)`, matching the previous generic-diagnostic path.
private enum StoreBootstrapOutcome: Sendable {
    case opened(SessionStore)
    case failed(ProtectedStoreFailure?)
}

/// Runs an async operation to completion while the calling thread waits.
///
/// This is used ONLY at cold launch, before `NSApplication.run()` starts the
/// AppKit run loop. It must never be called once the app is running: the app
/// must reach `app.run()` from a synchronous top-level context so the main
/// thread's run loop — not an occupied main-actor async task — is what drives
/// the concurrency executor. Otherwise every later `Task { @MainActor … }`
/// (product discovery, launch hook installation) is enqueued behind an
/// `app.run()` that never returns and can never run.
private func runToCompletion<Value: Sendable>(_ operation: @escaping @Sendable () async -> Value) -> Value {
    let semaphore = DispatchSemaphore(value: 0)
    let box = LaunchResultBox<Value>()
    Task.detached(priority: .userInitiated) {
        box.value = await operation()
        semaphore.signal()
    }
    semaphore.wait()
    return box.value!
}

@MainActor
private func launchGUI() {
    let store: SessionStore
    // Opening/bootstrapping the encrypted store does real disk I/O and
    // SQLCipher pragma/integrity work; it runs on a background task so the
    // SQLCipher work stays off the main thread. The main thread waits for it
    // here — this is cold launch, before the run loop exists — rather than
    // suspending an async main-actor task that would then own `app.run()`.
    let protectedStore = makeProtectedStore()
    switch runToCompletion({ () -> StoreBootstrapOutcome in
        do { return .opened(try SessionStore(protectedStore: protectedStore)) }
        catch { return .failed(error as? ProtectedStoreFailure) }
    }) {
    case .opened(let opened):
        store = opened
    case .failed(let failure):
        presentStorageUnavailable(failure)
        return
    }

    let runtime = ApplicationRuntime(store: store)
    let recoveryCoordinator = RecoveryCoordinator(runtime: runtime)
    let presentation = PresentationRuntime(port: runtime)
    let fixtureController = FixtureController(port: runtime)
    // The app retains the real action-server composition for the lifetime of
    // its GUI. Integration setup installs a current negotiated configuration;
    // until then it remains deliberately fail-closed and Claude stays native.
    let claudeActionComposition = ClaudeActionApplicationComposition()
    let cursorACPComposition = CursorACPApplicationComposition(runtime: runtime)
    let iterm2APIClient = ITerm2PythonAPIClient()
    let iterm2HostComposition = ITerm2HostNavigationComposition(port: ITerm2HostNavigationPort(client: iterm2APIClient))
    let iterm2HostCapture = ITerm2HostContextCapture(client: iterm2APIClient)
    let cursorHostSetup = makeCursorHostSetup()
    let cursorEndpoint = CursorExtensionMessageClient(transport: CursorExtensionUnixSocketTransport(endpoint: cursorHostSetup))
    let cursorHostPort = CursorHostNavigationPort(endpoint: cursorEndpoint)
    let cursorHostComposition = CursorHostNavigationComposition(port: cursorHostPort)
    let cursorHostCapture = CursorHostContextCapture(endpoint: cursorEndpoint)
    let warpHostComposition = WarpHostNavigationComposition(port: WarpHostNavigationPort())
    // Orca is kept as a separate Host-only composition. The CLI transport
    // revalidates its runtime-issued terminal handle on every attempt.
    let orcaRuntimeClient = OrcaCLIClient()
    let orcaHostComposition = OrcaHostNavigationComposition(port: OrcaHostNavigationPort(client: orcaRuntimeClient))
    let orcaHostCapture = OrcaHostContextCapture(client: orcaRuntimeClient)

    let delegate = AppDelegate(
        presentation: presentation,
        fixtureController: fixtureController,
        claudeActionComposition: claudeActionComposition,
        cursorACPComposition: cursorACPComposition,
        recoveryCoordinator: recoveryCoordinator,
        iterm2HostComposition: iterm2HostComposition,
        iterm2HostCapture: iterm2HostCapture,
        cursorHostComposition: cursorHostComposition,
        cursorHostCapture: cursorHostCapture,
        cursorHostSetup: cursorHostSetup,
        warpHostComposition: warpHostComposition,
        orcaHostComposition: orcaHostComposition,
        orcaHostCapture: orcaHostCapture,
        applicationRuntime: runtime,
        productInstallationIdentityVerifier: LocalProductInstallationDetector()
    )
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
private func presentStorageUnavailable(_ failure: ProtectedStoreFailure?) {
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
        launchGUI()

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

// The top level is deliberately synchronous: `launchGUI()` must reach
// `NSApplication.run()` from here, not from inside an `await`-ing main-actor
// task. A top-level `await` turns this entry point into an async main task
// that then *owns* `app.run()` for the process lifetime, starving every
// main-actor `Task { … }` scheduled afterwards (product discovery, launch hook
// installation). See `runToCompletion`.
/// Headless person-initiated hook install. Runs the same bounded, fail-closed
/// pipeline as launch — including the code-signature identity gate — and prints
/// the per-product outcome. `--home DIR` and `--app-support DIR` redirect the
/// config and durable-state roots for isolated verification without touching
/// the real user configuration.
@MainActor
private func runInstallHooks() async -> Int32 {
    func argValue(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }
    let home = argValue("--home").map { URL(fileURLWithPath: $0, isDirectory: true) }
    let appSupport = argValue("--app-support").map { URL(fileURLWithPath: $0, isDirectory: true) }

    let runtime = ApplicationRuntime(store: SessionStore())
    let installer = LaunchIntegrationAutoInstaller(
        port: runtime,
        claudeActionLifecycle: ClaudeActionIntegrationLifecycle(composition: ClaudeActionApplicationComposition()),
        detector: LocalProductInstallationDetector(),
        homeDirectory: home ?? FileManager.default.homeDirectoryForCurrentUser,
        publish: { _, _ in }
    )
    print("Installing Agent Island hooks (home=\(home?.path ?? "REAL user home"))…")
    let reports = await installer.installOnRequest(applicationSupport: appSupport)
    var anyInstalled = false
    for kind in AtlasIntegrationKind.allCases {
        let line: String
        switch reports[kind] {
        case .installed(_, let already):
            anyInstalled = anyInstalled || !already
            line = already ? "already installed (verified)" : "INSTALLED"
        case .refused(let message): line = "refused — \(message)"
        case .failed(let message): line = "failed — \(message)"
        case nil: line = "no report"
        }
        print("[\(kind)] \(line)")
    }
    return anyInstalled ? 0 : 1
}

if CommandLine.arguments.contains("--self-check") {
    exit(runToCompletion { await SelfCheck.run() })
} else if CommandLine.arguments.contains("--install-hooks") {
    exit(runToCompletion { await runInstallHooks() })
} else {
    launchGUI()
}
