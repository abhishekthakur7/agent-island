import ClaudeCodeAdapter
import CodexCLIAdapter
import CursorHooksAdapter
import Darwin
import Foundation
import LocalProductDiscovery
import PresentationPort
import SessionDomain

/// Person-initiated, end-to-end proof that a real Agent Product CLI session
/// registers through the installed hook. Unlike the launch-time probe (ADR
/// 0009), which only exercises Agent Island's own helper with a synthetic
/// payload and must never start a live session, this runs ONLY on explicit
/// request: it spawns the real `claude`/`codex` CLI with a throwaway prompt
/// and waits for a genuine session to appear in the canonical projection.
public protocol IntegrationSessionVerifying: Sendable {
    func verify(product: ProductCLI, executablePath: String) async -> IntegrationVerificationOutcome
}

public enum IntegrationVerificationOutcome: Sendable, Equatable {
    /// A session Agent Island did not already know about registered while the
    /// probe CLI was running. Carries the Product-owned native session id.
    case registered(nativeSessionID: String)
    /// The CLI launched but no new session registered before the deadline.
    case noSessionObserved(waited: TimeInterval)
    /// The CLI could not be launched at all (missing/again-not-executable).
    case launchFailed(reason: String)
    /// The product has no observable-via-exec hook path (Cursor).
    case unsupported
}

/// UI-facing verification state, published per integration.
public struct IntegrationVerificationResult: Equatable, Sendable {
    public enum State: Equatable, Sendable { case running, passed, failed, unsupported }
    public var state: State
    public var message: String
    public var observedAt: Date

    public init(state: State, message: String, observedAt: Date) {
        self.state = state
        self.message = message
        self.observedAt = observedAt
    }

    public init(outcome: IntegrationVerificationOutcome, observedAt: Date) {
        self.observedAt = observedAt
        switch outcome {
        case .registered(let id):
            state = .passed
            message = "Session \(id) registered — end-to-end hook delivery confirmed."
        case .noSessionObserved(let waited):
            state = .failed
            message = "No session registered within \(Int(waited))s. Confirm the integration is installed and enabled, then retry."
        case .launchFailed(let reason):
            state = .failed
            message = "Couldn't launch the CLI: \(reason)"
        case .unsupported:
            state = .unsupported
            message = "This product registers sessions from its editor, not a headless run. Use its controlled-session control instead."
        }
    }
}

/// Concrete verifier bound to the live projection port.
public struct IntegrationSessionVerifier: IntegrationSessionVerifying {
    private let port: any PresentationPort
    private let timeout: TimeInterval

    public init(port: any PresentationPort, timeout: TimeInterval = 45) {
        self.port = port
        self.timeout = timeout
    }

    public func verify(product: ProductCLI, executablePath: String) async -> IntegrationVerificationOutcome {
        guard let namespace = Self.namespace(for: product) else { return .unsupported }
        let timeout = self.timeout
        let port = self.port

        return await withTaskGroup(of: IntegrationVerificationOutcome.self) { group in
            group.addTask {
                // Subscribe first so the baseline snapshot is captured BEFORE
                // the CLI can publish its SessionStart; otherwise the new
                // session would already be in the immediate snapshot and read
                // as pre-existing. The iterator stays inside this one task.
                var iterator = port.presentationStream().makeAsyncIterator()
                let firstRevision = await iterator.next()
                let baseline = Set((firstRevision?.sessions.keys.filter { $0.productNamespace == namespace }) ?? [])

                let process: Process
                do {
                    process = try Self.launch(executablePath: executablePath, product: product)
                } catch {
                    return .launchFailed(reason: String(describing: error))
                }
                // Kill the throwaway CLI the moment we have an answer (or on
                // cancellation from the timeout task) so a real session never
                // outlives the check and no extra model tokens are spent.
                defer { Self.terminate(process) }

                while !Task.isCancelled, let revision = await iterator.next() {
                    if let match = revision.sessions.keys.first(where: {
                        $0.productNamespace == namespace && !baseline.contains($0)
                    }) {
                        return .registered(nativeSessionID: match.nativeSessionID.rawValue)
                    }
                }
                return .noSessionObserved(waited: timeout)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .noSessionObserved(waited: timeout)
            }
            let result = await group.next() ?? .noSessionObserved(waited: timeout)
            group.cancelAll()
            return result
        }
    }

    private static func namespace(for product: ProductCLI) -> ProductNamespace? {
        switch product {
        case .claudeCode: ClaudeCodeIntegration.productNamespace
        case .codexCLI: CodexCLIIntegration.productNamespace
        // Cursor fires session hooks from its editor, not a headless exec, so
        // an exec-based verify cannot register one. Its direct path is the
        // controlled ACP session control.
        case .cursor: nil
        }
    }

    /// A throwaway prompt. SessionStart fires at session creation, before the
    /// model reply matters, so the exact text is irrelevant to the result.
    private static let prompt = "Agent Island connection check. Reply with: ok"

    private static func launch(executablePath: String, product: ProductCLI) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        switch product {
        case .claudeCode: process.arguments = ["-p", prompt]
        case .codexCLI: process.arguments = ["exec", prompt]
        case .cursor: process.arguments = ["--version"]
        }
        // Inherit the person's environment so the CLI uses its real
        // authentication and config, then guarantee its own directory is on
        // PATH for any helper it shells out to.
        var environment = ProcessInfo.processInfo.environment
        let executableDirectory = URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
        if let existing = environment["PATH"], !existing.isEmpty {
            environment["PATH"] = executableDirectory + ":" + existing
        } else {
            environment["PATH"] = executableDirectory
        }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Own process group so terminate() reaches any descendants the CLI
        // spawned; the concrete pid is the fallback if setpgid raced exec.
        _ = setpgid(process.processIdentifier, process.processIdentifier)
        return process
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        guard pid > 0 else { process.terminate(); return }
        _ = Darwin.kill(-pid, SIGTERM)
        _ = Darwin.kill(pid, SIGTERM)
    }
}
