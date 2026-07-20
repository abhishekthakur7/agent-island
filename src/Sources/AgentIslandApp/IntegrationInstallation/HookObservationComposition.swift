import Foundation
import ClaudeCodeAdapter
import CodexCLIAdapter
import CursorHooksAdapter

/// App composition for documented hook observation. It routes only validated
/// one-way frames to already-configured adapters; installation approval and
/// external configuration ownership stay with their respective coordinators.
final class HookObservationAdapterRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var claude: ClaudeCodeAdapter?
    private var codex: CodexCLIAdapter?
    private var cursor: CursorHooksReceiver?

    init(claude: ClaudeCodeAdapter? = nil, codex: CodexCLIAdapter? = nil, cursor: CursorHooksReceiver? = nil) {
        self.claude = claude
        self.codex = codex
        self.cursor = cursor
    }

    func register(claude: ClaudeCodeAdapter) { lock.withLock { self.claude = claude } }
    func register(codex: CodexCLIAdapter) { lock.withLock { self.codex = codex } }
    func register(cursor: CursorHooksReceiver) { lock.withLock { self.cursor = cursor } }

    func route(frame: Data, for product: HookObservationProduct) async {
        switch product {
        case .claude:
            guard let claude = lock.withLock({ claude }), let message = try? ClaudeHookIPCFrame.decode(frame) else { return }
            _ = await claude.ingest(message)
        case .codex:
            guard let codex = lock.withLock({ codex }), let message = try? ClaudeHookIPCFrame.decode(frame) else { return }
            _ = await codex.ingestOutcome(message)
        case .cursor:
            // Cursor's existing receiver is intentionally its authenticated
            // decoder boundary, so it receives the complete validated frame.
            guard let cursor = lock.withLock({ cursor }) else { return }
            _ = await cursor.receive(frame: frame)
        }
    }
}

/// Retains app-owned observation servers for the process lifetime. Starting a
/// server does not imply an Integration Installation exists or is enabled.
final class HookObservationProductionComposition: @unchecked Sendable {
    let appOwnedRoot: URL
    private let router: HookObservationAdapterRouter
    private let lock = NSLock()
    private var servers: [HookObservationProduct: HookObservationServer] = [:]

    init(appOwnedRoot: URL, router: HookObservationAdapterRouter) {
        self.appOwnedRoot = appOwnedRoot.standardizedFileURL
        self.router = router
    }

    convenience init(router: HookObservationAdapterRouter) {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Agent Island/IPC", isDirectory: true)
        self.init(appOwnedRoot: root, router: router)
    }

    func start(_ product: HookObservationProduct) throws {
        let server = lock.withLock { () -> HookObservationServer in
            if let existing = servers[product] { return existing }
            let server = HookObservationServer(product: product, appOwnedRoot: appOwnedRoot) { [router] frame in
                await router.route(frame: frame, for: product)
            }
            servers[product] = server
            return server
        }
        do {
            try server.start()
        } catch {
            lock.withLock {
                if servers[product] === server { servers.removeValue(forKey: product) }
            }
            throw error
        }
    }

    func stop(_ product: HookObservationProduct) {
        let server = lock.withLock { servers.removeValue(forKey: product) }
        server?.stop()
    }

    func stopAll() {
        let current = lock.withLock { () -> [HookObservationServer] in
            defer { servers.removeAll() }
            return Array(servers.values)
        }
        current.forEach { $0.stop() }
    }

    deinit { stopAll() }
}
