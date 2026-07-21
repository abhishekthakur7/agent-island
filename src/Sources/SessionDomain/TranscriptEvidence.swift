import Foundation

/// One transcript-derived Turn excerpt, in chronological order. This is
/// presentation excerpt evidence only: unlike `TurnProjection` (a
/// source-proven, hook-derived Turn lifecycle fact), it carries no
/// ownership, ordering, or lifecycle authority — it is simply "this text
/// appeared in the transcript file, attributed to this role."
public struct TranscriptTurnProjection: Sendable, Equatable, Codable {
    public enum Role: String, Sendable, Codable, Equatable {
        case user
        case assistant
    }

    public let role: Role
    public let text: String
    public let occurredAt: Date?

    public init(role: Role, text: String, occurredAt: Date?) {
        self.role = role
        self.text = boundedTranscriptText(text)
        self.occurredAt = occurredAt
    }
}

/// One message's reported token usage, read directly from the transcript's
/// own per-message evidence (Claude's `message.usage` block, or Codex's
/// `token_count` event). Field names follow Claude's documented usage shape;
/// a Codex reader maps its own field names onto the same shape (Codex's
/// `cached_input_tokens`/`cache_write_input_tokens` from the most recent
/// `last_token_usage` delta) so a consumer never needs a per-Product usage
/// type. This is transcript-derived evidence, not `UsageSnapshot` (which is
/// display-only provider quota evidence from a live negotiated Adapter
/// capability, an unrelated concept).
public struct TranscriptUsageProjection: Sendable, Equatable, Codable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreationInputTokens: Int

    public init(inputTokens: Int, outputTokens: Int, cacheReadInputTokens: Int = 0, cacheCreationInputTokens: Int = 0) {
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cacheReadInputTokens = max(0, cacheReadInputTokens)
        self.cacheCreationInputTokens = max(0, cacheCreationInputTokens)
    }

    public var totalTokens: Int { inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens }
}

/// A bound applied to every free-text field so a pathological transcript
/// line can never balloon a projection held in memory or written to the
/// protected store. Generous enough for a full multi-paragraph agent message
/// or prompt.
let transcriptEvidenceMaxTextBytes = 20_000

func boundedTranscriptText(_ text: String) -> String {
    guard text.utf8.count > transcriptEvidenceMaxTextBytes else { return text }
    return String(decoding: Array(text.utf8.prefix(transcriptEvidenceMaxTextBytes)), as: UTF8.self) + "…"
}

/// Transcript-derived evidence for one Agent Session, read directly from the
/// Agent Product's own on-disk transcript file (`~/.claude/projects/**/*.jsonl`,
/// `~/.codex/sessions/**/*.jsonl`) rather than through a documented hook or a
/// negotiated Adapter capability.
///
/// ## Why this is a separate type, not more `NormalizedEventFact`s
///
/// Every other piece of session evidence in this domain is a
/// `NormalizedEventFact`: admitted only after `SessionDomainValidator` checks
/// contract compatibility, a granted capability, and Product/owner identity
/// (ADR 0001). A transcript read has none of that — it is a local file the
/// Agent Product happens to write for its own purposes. There is no
/// negotiation, no capability grant, no delivery guarantee, and no schema
/// contract; the file may be rotated, truncated mid-write, briefly absent, or
/// shaped differently across Product versions. `CONTEXT.md`'s own definition
/// of Normalized Event Fact — "evidence from which Agent Island derives
/// state" with "provenance, ordering evidence, and classification" — simply
/// does not describe what a best-effort filesystem tail read can promise.
///
/// Folding transcript data into `NormalizedEventFact`/`SessionProjection`'s
/// existing hook-sourced fields would let an unproven, best-effort read
/// silently masquerade as a source-proven observation. Instead this bag is:
///
/// - **A separate type.** `SessionProjection.transcriptEvidence` is the only
///   place transcript data reaches a caller; nothing here is folded into
///   `execution`, `observation`, `displayTitle`, or any other hook-sourced
///   field, and it never flows through `SessionDomainValidator`.
/// - **Nullable at the container.** `nil` means "no transcript was read for
///   this session" (not yet resolved, resolution failed, or reading failed).
///   It is never defaulted to an empty-but-present bag, which would be
///   indistinguishable from "we read it and it was genuinely empty."
/// - **Best-effort per field.** Within a non-nil bag, every field is still
///   independently optional: a partial or degraded read (e.g. a truncated
///   tail with no visible `usage` block yet) is represented as partial data,
///   not as a failure of the whole bag.
///
/// This is content-shaped evidence (`CONTEXT.md`'s "Interaction Content":
/// prompts, responses, project/file references), unlike the
/// `PayloadClassification.operationalMetadata` most `NormalizedEventFact`s
/// carry. It must never be included in a `DiagnosticBundle` or leave the
/// device through `ServiceEgressPort` without the same explicit review any
/// other Interaction Content would require.
///
/// See `docs/adr/0001-transcript-reading-second-evidence-path.md` for the
/// full design record (status: proposed — including the `docs/adr/`
/// numbering convention itself, since the directory did not exist before
/// this ticket).
public struct TranscriptEvidenceProjection: Sendable, Equatable, Codable {
    public let readAt: Date
    /// True when the read stopped at the tail byte boundary before reaching
    /// the start of the file, so earlier context beyond what is captured
    /// here may exist but was not inspected. Never `true` for a file whose
    /// entire content fit within the tail read.
    public let truncated: Bool
    /// The model string as reported inside the transcript itself. This is
    /// deliberately independent of any hook-parsed model string — see the
    /// ADR for why the two are not unified in this ticket.
    public let modelFromTranscript: String?
    /// The most recent message's reported usage, regardless of whether that
    /// message also had visible text (a tool-only turn still spends tokens).
    public let latestUsage: TranscriptUsageProjection?
    public let latestAgentMessageText: String?
    public let latestUserPromptText: String?
    /// Bounded, chronological (oldest first) recent Turn excerpts, limited to
    /// genuine human/agent text turns — synthetic tool-result "user" turns
    /// and text-less tool-use/thinking-only assistant turns are excluded.
    public let recentTurns: [TranscriptTurnProjection]

    public init(
        readAt: Date,
        truncated: Bool,
        modelFromTranscript: String? = nil,
        latestUsage: TranscriptUsageProjection? = nil,
        latestAgentMessageText: String? = nil,
        latestUserPromptText: String? = nil,
        recentTurns: [TranscriptTurnProjection] = []
    ) {
        self.readAt = readAt
        self.truncated = truncated
        self.modelFromTranscript = modelFromTranscript
        self.latestUsage = latestUsage
        self.latestAgentMessageText = latestAgentMessageText.map(boundedTranscriptText)
        self.latestUserPromptText = latestUserPromptText.map(boundedTranscriptText)
        self.recentTurns = recentTurns
    }

    /// True when the reader produced no usable field at all. A caller should
    /// generally prefer `nil` over publishing a bag in this state, but this
    /// is exposed so a caller can decide.
    public var hasAnyEvidence: Bool {
        modelFromTranscript != nil || latestUsage != nil || latestAgentMessageText != nil || latestUserPromptText != nil || !recentTurns.isEmpty
    }
}
