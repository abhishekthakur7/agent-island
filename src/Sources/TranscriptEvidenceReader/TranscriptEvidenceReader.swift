import Foundation
import SessionDomain

/// Reads best-effort `TranscriptEvidenceProjection` evidence for one Agent
/// Session. See `TranscriptEvidenceProjection`'s doc comment for why this is
/// a second, explicitly separate evidence path from `NormalizedEventFact`.
public protocol TranscriptEvidenceReading: Sendable {
    func readEvidence(product: TranscriptProduct, nativeSessionID: String, workingDirectory: String?, now: Date) -> TranscriptEvidenceProjection?
}

extension TranscriptEvidenceReading {
    public func readEvidence(product: TranscriptProduct, nativeSessionID: String, workingDirectory: String? = nil) -> TranscriptEvidenceProjection? {
        readEvidence(product: product, nativeSessionID: nativeSessionID, workingDirectory: workingDirectory, now: Date())
    }
}

/// Tails a Claude Code or Codex CLI transcript using the same strategy as
/// `agent-notch`'s `tailInfo` (`main.swift:136–168`): open a `FileHandle`,
/// seek to the end, read only the last ~128 KB, and parse lines in reverse
/// so the most recent evidence is found first without ever reading the
/// whole file. Because `model` can appear only once, early in a long
/// transcript, a truncated read also peeks the first ~64 KB (head) once, if
/// the tail scan didn't find one — exactly agent-notch's fallback.
///
/// Every failure mode degrades to `nil`/partial evidence rather than
/// throwing: an unreadable file, a truncated multi-byte UTF-8 sequence at
/// the read boundary (`String(decoding:as:)` replaces invalid sequences
/// rather than failing), and a malformed/partial JSON line (the likely
/// shape of whatever sits right at the tail boundary, since it is probably a
/// fragment of a longer line) are all simply skipped.
public struct LocalTranscriptEvidenceReader: TranscriptEvidenceReading {
    /// 128 KB — matches agent-notch's `tailInfo` exactly (`main.swift:140`).
    public static let defaultTailByteLimit = 131_072
    /// 64 KB — matches agent-notch's head-peek-for-model fallback (`main.swift:160`).
    public static let defaultHeadByteLimit = 65_536
    /// How many recent qualifying Turns to keep for the scrollable transcript
    /// excerpt (§1.10). A generous but bounded number; the consuming UI is
    /// free to show fewer.
    public static let defaultRecentTurnLimit = 12

    private let pathResolver: any TranscriptPathResolving
    private let tailByteLimit: Int
    private let headByteLimit: Int
    private let recentTurnLimit: Int

    public init(
        pathResolver: any TranscriptPathResolving = DocumentedTranscriptPathResolver(),
        tailByteLimit: Int = LocalTranscriptEvidenceReader.defaultTailByteLimit,
        headByteLimit: Int = LocalTranscriptEvidenceReader.defaultHeadByteLimit,
        recentTurnLimit: Int = LocalTranscriptEvidenceReader.defaultRecentTurnLimit
    ) {
        self.pathResolver = pathResolver
        self.tailByteLimit = max(0, tailByteLimit)
        self.headByteLimit = max(0, headByteLimit)
        self.recentTurnLimit = max(0, recentTurnLimit)
    }

    public func readEvidence(product: TranscriptProduct, nativeSessionID: String, workingDirectory: String?, now: Date) -> TranscriptEvidenceProjection? {
        guard let path = pathResolver.transcriptPath(product: product, nativeSessionID: nativeSessionID, workingDirectory: workingDirectory) else { return nil }
        return readEvidence(atPath: path, product: product, now: now)
    }

    /// Direct-path entry point. Exposed publicly for real-transcript
    /// verification and for a caller that already holds a resolved (or
    /// cached) path and wants to skip re-resolution.
    public func readEvidence(atPath path: String, product: TranscriptProduct, now: Date = Date()) -> TranscriptEvidenceProjection? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = (try? handle.seekToEnd()), size > 0 else { return nil }

        let tailLength = min(size, UInt64(tailByteLimit))
        guard (try? handle.seek(toOffset: size - tailLength)) != nil,
              let tailData = try? handle.read(upToCount: Int(tailLength)) else { return nil }
        let truncated = tailLength < size

        let extractor = TranscriptLineExtractorFactory.extractor(for: product)
        var model: String?
        var usage: TranscriptUsageProjection?
        var latestAgentMessage: String?
        var latestUserPrompt: String?
        var turns: [TranscriptTurnProjection] = []

        for line in linesMostRecentFirst(of: tailData) {
            guard let object = decodeJSONObject(line) else { continue }
            let occurredAt = TranscriptTimestamp.parse(object["timestamp"] as? String)
            let facts = extractor.facts(from: object, occurredAt: occurredAt)
            if model == nil { model = facts.model }
            if usage == nil { usage = facts.usage }
            if let turn = facts.turn {
                if turns.count < recentTurnLimit { turns.append(turn) }
                if latestAgentMessage == nil, turn.role == .assistant { latestAgentMessage = turn.text }
                if latestUserPrompt == nil, turn.role == .user { latestUserPrompt = turn.text }
            }
            let haveEnoughTurns = turns.count >= recentTurnLimit
            if model != nil, usage != nil, latestAgentMessage != nil, latestUserPrompt != nil, haveEnoughTurns { break }
        }

        // model can appear only once, early in a long transcript (e.g. a
        // system/init line far outside the tail window) — peek the head.
        if model == nil, truncated, headByteLimit > 0 {
            model = peekHeadModel(handle: handle, product: product, limit: headByteLimit)
        }

        let evidence = TranscriptEvidenceProjection(
            readAt: now,
            truncated: truncated,
            modelFromTranscript: model,
            latestUsage: usage,
            latestAgentMessageText: latestAgentMessage,
            latestUserPromptText: latestUserPrompt,
            // Collected most-recent-first; restore chronological order.
            recentTurns: turns.reversed()
        )
        return evidence.hasAnyEvidence ? evidence : nil
    }

    private func peekHeadModel(handle: FileHandle, product: TranscriptProduct, limit: Int) -> String? {
        guard (try? handle.seek(toOffset: 0)) != nil, let headData = try? handle.read(upToCount: limit) else { return nil }
        let extractor = TranscriptLineExtractorFactory.extractor(for: product)
        let text = String(decoding: headData, as: UTF8.self)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = decodeJSONObject(line) else { continue }
            if let model = extractor.facts(from: object, occurredAt: nil).model { return model }
        }
        return nil
    }

    /// Splits raw tail bytes into lines, newest-last-in-file-first. Any
    /// fragment at the very start of the buffer (the tail boundary can land
    /// mid-line, and a truncated multi-byte UTF-8 sequence there decodes to
    /// replacement characters rather than failing) is not special-cased —
    /// it simply fails JSON parsing downstream and is skipped like any other
    /// malformed line.
    private func linesMostRecentFirst(of data: Data) -> [Substring] {
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: true).reversed()
    }

    private func decodeJSONObject(_ line: Substring) -> [String: Any]? {
        guard !line.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }
}

enum TranscriptTimestamp {
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: raw)
    }
}
