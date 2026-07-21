import Foundation
import SessionDomain

/// The Agent Product a transcript file belongs to. Deliberately narrower than
/// `ProductNamespace`: only Products with a documented on-disk transcript
/// layout are represented here.
public enum TranscriptProduct: Sendable, Equatable {
    case claudeCode
    case codexCLI

    /// Maps a negotiated `ProductNamespace` rawValue to a transcript layout,
    /// when one is documented. Returns `nil` for any other namespace (e.g.
    /// Cursor, which has no local transcript file this reader knows how to
    /// tail) so callers fail closed rather than guess a layout.
    public init?(productNamespaceRawValue: String) {
        switch productNamespaceRawValue {
        case "claude-code": self = .claudeCode
        case "codex-cli": self = .codexCLI
        default: return nil
        }
    }
}

/// Resolves an Agent Session identity to the local transcript file path that
/// (probably) holds it, without reading any file content. Resolution is
/// evidence-gathering only: it is not a guarantee the file remains readable,
/// current, or exists by the time a caller opens it.
public protocol TranscriptPathResolving: Sendable {
    func transcriptPath(product: TranscriptProduct, nativeSessionID: String, workingDirectory: String?) -> String?
}

/// Resolution strategy for the two approved, documented transcript layouts.
///
/// **Claude Code**: `~/.claude/projects/<encoded-cwd>/<sessionID>.jsonl`. The
/// directory encodes the session's working directory by replacing every `/`
/// with `-` (confirmed against real transcripts on this machine: a session
/// whose own `cwd` field read
/// `/Users/…/Developer/agent-island/src` sits in a directory literally named
/// `-Users-…-Developer-agent-island-src`). That encoding is **one-way**: a
/// working directory whose own path segments already contain `-` (e.g.
/// `agent-island`) cannot be told apart from a `/` at the same position by
/// looking at the directory name alone, so this resolver never tries to
/// *decode* a directory name back into a path. It only *encodes* a known
/// `workingDirectory` forward as a fast-path guess, and always falls back to
/// a bounded, non-recursive directory scan keyed by the exact session UUID
/// filename — which is correct regardless of the encoding's reversibility
/// and regardless of Product-version changes to it.
///
/// **Codex CLI**: `~/.codex/sessions/<yyyy>/<mm>/<dd>/rollout-<timestamp>-<uuid>.jsonl`.
/// The session UUID is embedded in the filename, not the whole basename, and
/// files are nested under a date path this resolver does not otherwise know.
/// Resolution is therefore always a bounded recursive filename scan under
/// `~/.codex/sessions` for a `*.jsonl` file whose name contains the exact
/// session UUID.
///
/// Every scan only enumerates directory entries (metadata), never reads file
/// content — consistent with the "never read whole files" requirement, which
/// is about transcript *content*, not directory listings.
public struct DocumentedTranscriptPathResolver: TranscriptPathResolving {
    // `FileManager` is not `Sendable`, so this deliberately does not store an
    // injected instance (unlike `homeDirectory`); every use below goes
    // through the documented-thread-safe `FileManager.default` directly,
    // matching `LocalProductDiscovery`'s convention.
    private let homeDirectory: String

    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    private var fileManager: FileManager { .default }

    public func transcriptPath(product: TranscriptProduct, nativeSessionID: String, workingDirectory: String?) -> String? {
        let trimmedSession = nativeSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSession.isEmpty, isSafeIdentifierComponent(trimmedSession) else { return nil }
        switch product {
        case .claudeCode:
            return resolveClaude(nativeSessionID: trimmedSession, workingDirectory: workingDirectory)
        case .codexCLI:
            return resolveCodex(nativeSessionID: trimmedSession)
        }
    }

    // MARK: Claude Code

    private func resolveClaude(nativeSessionID: String, workingDirectory: String?) -> String? {
        let root = homeDirectory + "/.claude/projects"
        if let workingDirectory, let encoded = Self.encodeClaudeProjectDirectory(workingDirectory) {
            let guess = root + "/" + encoded + "/" + nativeSessionID + ".jsonl"
            if fileManager.fileExists(atPath: guess) { return guess }
        }
        // Fall back to a bounded, non-recursive scan: enumerate only the
        // immediate project directories (their names, not their contents)
        // and test for the exact session filename inside each.
        guard let projectDirectories = try? fileManager.contentsOfDirectory(atPath: root) else { return nil }
        var matches: [String] = []
        for directory in projectDirectories {
            let candidate = root + "/" + directory + "/" + nativeSessionID + ".jsonl"
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            matches.append(candidate)
        }
        // A session UUID should be globally unique; more than one hit means
        // something is wrong with the assumption, so fail closed rather than
        // guess which one is real.
        return matches.count == 1 ? matches[0] : nil
    }

    /// Forward-only encoding used purely as a fast-path optimization. Never
    /// treated as authoritative — callers always fall back to a scan.
    static func encodeClaudeProjectDirectory(_ workingDirectory: String) -> String? {
        guard !workingDirectory.isEmpty, !workingDirectory.contains("\n") else { return nil }
        return workingDirectory.replacingOccurrences(of: "/", with: "-")
    }

    // MARK: Codex CLI

    private func resolveCodex(nativeSessionID: String) -> String? {
        let root = homeDirectory + "/.codex/sessions"
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var matches: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl", url.lastPathComponent.contains(nativeSessionID) else { continue }
            matches.append(url.path)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Session identifiers are Product-native, but this resolver builds a
    /// filesystem path from one. Reject anything that could escape the
    /// documented root or is not a plausible identifier, rather than trying
    /// to sanitize it.
    private func isSafeIdentifierComponent(_ value: String) -> Bool {
        !value.contains("/") && !value.contains("\\") && value != "." && value != ".."
            && !value.unicodeScalars.contains(where: { $0.value <= 0x1F || $0.value == 0x7F })
    }
}
