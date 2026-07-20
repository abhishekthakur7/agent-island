import Foundation
import ClaudeActionRouting
import ClaudeCodeAdapter
import SessionDomain

/// App-lifetime owner for the local Claude synchronous-action endpoint.  The
/// integration setup flow supplies the current negotiated configuration; an
/// absent or failed configuration stays fail-closed and is intentionally not
/// surfaced through diagnostics (it can contain endpoint and credential
/// metadata).  This object is retained by `AgentIslandApp`, not a test.
@MainActor
final class ClaudeActionApplicationComposition {
    private var production: ClaudeActionProductionComposition?

    @discardableResult
    func install(configuration: ClaudeActionRequestListener.Configuration) -> Bool {
        retire()
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Agent Island/IPC", isDirectory: true)
        let endpoint = ClaudeLocalEndpoint(path: root.appendingPathComponent("claude-actions.sock"), appOwnedRoot: root)
        let production = ClaudeActionProductionComposition(endpoint: endpoint, configuration: configuration)
        guard production.start() else { return false }
        self.production = production
        return true
    }

    func retire() {
        guard let production else { return }
        self.production = nil
        Task { await production.stop() }
    }
}
