import Foundation

/// The only application-composition entry point for this integration. A UI
/// must explicitly invoke one of these operations; discovery alone cannot
/// attach to an existing terminal, Codex process, Hooks installation, or
/// thread. The caller then waits for the normal initialize/initialized ready
/// state before submitting the separately typed resume/start request.
public actor CodexAppServerCoordinator {
    private let adapter: CodexAppServerAdapter

    public init(adapter: CodexAppServerAdapter) { self.adapter = adapter }

    @discardableResult
    public func startApplicationOwnedChild() async -> Result<Int64, CodexAppServerFailure> {
        await adapter.connect(ownership: .startedByAgentIsland)
    }

    @discardableResult
    public func resumeExplicitlySelectedThreadChild() async -> Result<Int64, CodexAppServerFailure> {
        await adapter.connect(ownership: .explicitlyResumedByAgentIsland)
    }

    /// Call only after the explicitly-resumed child reaches `ready`. The
    /// adapter admits this direct native Thread ID once the exact resume
    /// response returns the same ID; no terminal discovery is involved.
    public func resumeSelectedThread(_ threadID: String, attemptID: String, confirmed: Bool = true) async -> String? {
        await adapter.resumeThread(threadID: threadID, attemptID: attemptID, confirmed: confirmed)
    }

    public func health() async -> CodexAppServerHealth { await adapter.health() }
}
