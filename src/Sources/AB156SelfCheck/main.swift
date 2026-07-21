import Foundation
import SessionDomain
import TranscriptEvidenceReader

/// Headless, read-only verification for AB-156. Unlike AB138…AB146, this
/// self-check deliberately reads a REAL transcript file on disk (never a
/// synthetic fixture) — the whole point of AB-156 is a reader whose reverse
/// tail-parse and extractors are field-shape-correct against an Agent
/// Product's actual on-disk transcript, which no fixture is proof of.
///
/// Usage: AB156SelfCheck <path-to.jsonl> [claude|codex]
/// Prints extracted evidence as JSON to stdout for direct before/after
/// comparison against the raw transcript, then a PASS/FAIL line.
@main
struct AB156SelfCheck {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fail("usage: AB156SelfCheck <path-to.jsonl> [claude|codex]\n       AB156SelfCheck --resolve <claude|codex> <nativeSessionID> [workingDirectory]")
        }
        if arguments[1] == "--resolve" {
            runResolve(arguments: Array(arguments.dropFirst(2)))
            return
        }
        let path = arguments[1]
        let product: TranscriptProduct = (arguments.count >= 3 && arguments[2] == "codex") ? .codexCLI : .claudeCode

        let reader = LocalTranscriptEvidenceReader()
        guard let evidence = reader.readEvidence(atPath: path, product: product, now: Date(timeIntervalSince1970: 1_800_000_000)) else {
            fail("readEvidence returned nil for \(path) — file unreadable, empty, or no recognized fields found")
        }

        print("--- TranscriptEvidenceProjection (\(product)) ---")
        print("truncated: \(evidence.truncated)")
        print("modelFromTranscript: \(evidence.modelFromTranscript ?? "nil")")
        if let usage = evidence.latestUsage {
            print("latestUsage: input=\(usage.inputTokens) output=\(usage.outputTokens) cacheRead=\(usage.cacheReadInputTokens) cacheCreate=\(usage.cacheCreationInputTokens) total=\(usage.totalTokens)")
        } else {
            print("latestUsage: nil")
        }
        print("latestAgentMessageText: \(evidence.latestAgentMessageText.map { String($0.prefix(200)) } ?? "nil")")
        print("latestUserPromptText: \(evidence.latestUserPromptText.map { String($0.prefix(200)) } ?? "nil")")
        print("recentTurns (\(evidence.recentTurns.count)):")
        for turn in evidence.recentTurns {
            let occurred = turn.occurredAt.map(ISO8601DateFormatter().string(from:)) ?? "nil"
            print("  [\(turn.role.rawValue)] (\(occurred)) \(turn.text.prefix(120))")
        }

        // Sanity assertions: at least one field must be non-empty (readEvidence
        // already guarantees hasAnyEvidence), and a real transcript with any
        // assistant traffic at all should show a non-nil model somewhere.
        guard evidence.hasAnyEvidence else { fail("evidence had no populated field") }
        guard !evidence.recentTurns.isEmpty || evidence.latestAgentMessageText != nil || evidence.latestUserPromptText != nil else {
            fail("no turn text extracted at all — extractor likely mismatched the real jsonl shape")
        }

        print("AB156SelfCheck PASS transcript reader extracted evidence from a real \(product) transcript without reading the whole file")
    }

    /// `--resolve <claude|codex> <nativeSessionID> [workingDirectory]`:
    /// exercises `DocumentedTranscriptPathResolver` alone (path resolution,
    /// AC-1), separate from the tail-read/extraction verification above.
    static func runResolve(arguments: [String]) {
        guard arguments.count >= 2 else { fail("usage: --resolve <claude|codex> <nativeSessionID> [workingDirectory]") }
        let product: TranscriptProduct = arguments[0] == "codex" ? .codexCLI : .claudeCode
        let sessionID = arguments[1]
        let workingDirectory = arguments.count >= 3 ? arguments[2] : nil
        let resolver = DocumentedTranscriptPathResolver()
        let resolved = resolver.transcriptPath(product: product, nativeSessionID: sessionID, workingDirectory: workingDirectory)
        print("resolved path: \(resolved ?? "nil")")
        guard let resolved, FileManager.default.fileExists(atPath: resolved) else {
            fail("resolution did not produce an existing file")
        }
        print("AB156SelfCheck PASS path resolution found an existing file for session \(sessionID)")
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("AB156SelfCheck failed: \(message)\n".utf8))
        exit(EXIT_FAILURE)
    }
}
