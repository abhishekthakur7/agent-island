import Foundation
import SessionDomain

/// One fact extracted from a single transcript line. Extraction is
/// deliberately narrow and explicit about *why* a value was or wasn't
/// found — no field is guessed from unrelated JSON shape.
struct TranscriptLineFacts {
    var model: String?
    var usage: TranscriptUsageProjection?
    /// A qualifying, human-authored turn on this line — i.e. a genuine user
    /// prompt or an assistant message with visible text. `nil` for lines
    /// that are synthetic (tool_result feedback), text-less (tool-use or
    /// thinking-only turns), or not a message line at all.
    var turn: TranscriptTurnProjection?
}

/// Per-Product parsing of one already-JSON-decoded transcript line into the
/// facts this reader cares about. Implementations must never throw; a line
/// that doesn't match any known shape simply yields empty facts.
protocol TranscriptLineExtracting {
    func facts(from object: [String: Any], occurredAt: Date?) -> TranscriptLineFacts
}

/// Claude Code's `~/.claude/projects/**/*.jsonl` shape, confirmed against
/// real transcripts on this machine:
///
/// - Assistant: `{"type":"assistant","message":{"model":"claude-…","role":
///   "assistant","content":[{"type":"text","text":"…"}, …],"usage":
///   {"input_tokens":…,"output_tokens":…,"cache_read_input_tokens":…,
///   "cache_creation_input_tokens":…}}, …}`. A single assistant message may
///   have zero `"type":"text"` blocks (e.g. a pure tool-use or thinking
///   turn) while still carrying a `usage` block — `usage` and visible text
///   are extracted independently.
/// - User: `{"type":"user","message":{"role":"user","content":"…" |
///   [{"type":"text","text":"…"}, …]}, …}`. A `"user"` line can also be
///   synthetic tool-result feedback rather than a person's prompt — its
///   `content` array holds only `{"type":"tool_result",…}` blocks in that
///   case, which this extractor does not treat as a Turn.
struct ClaudeTranscriptLineExtractor: TranscriptLineExtracting {
    func facts(from object: [String: Any], occurredAt: Date?) -> TranscriptLineFacts {
        var facts = TranscriptLineFacts()
        guard let type = object["type"] as? String else { return facts }
        switch type {
        case "assistant":
            guard let message = object["message"] as? [String: Any] else { return facts }
            facts.model = message["model"] as? String
            facts.usage = usage(from: message["usage"] as? [String: Any])
            if let text = joinedText(from: message["content"], blockType: "text") {
                facts.turn = TranscriptTurnProjection(role: .assistant, text: text, occurredAt: occurredAt)
            }
        case "user":
            guard let message = object["message"] as? [String: Any] else { return facts }
            if let text = userText(from: message["content"]) {
                facts.turn = TranscriptTurnProjection(role: .user, text: text, occurredAt: occurredAt)
            }
        default:
            break
        }
        return facts
    }

    private func usage(from raw: [String: Any]?) -> TranscriptUsageProjection? {
        guard let raw else { return nil }
        // A usage block is present but every count could legitimately be
        // absent on a malformed/older line; require at least the two
        // primary counters so this doesn't manufacture a zeroed usage.
        guard let input = intValue(raw["input_tokens"]), let output = intValue(raw["output_tokens"]) else { return nil }
        return TranscriptUsageProjection(
            inputTokens: input,
            outputTokens: output,
            cacheReadInputTokens: intValue(raw["cache_read_input_tokens"]) ?? 0,
            cacheCreationInputTokens: intValue(raw["cache_creation_input_tokens"]) ?? 0
        )
    }

    /// A plain string is a genuine prompt. An array is a prompt only if it
    /// contains a `"type":"text"` block — an array holding only
    /// `tool_result`/other blocks is synthetic harness feedback, not
    /// something a person typed.
    private func userText(from content: Any?) -> String? {
        if let string = content as? String { return nonEmpty(string) }
        return joinedText(from: content, blockType: "text")
    }

    private func joinedText(from content: Any?, blockType: String) -> String? {
        guard let blocks = content as? [[String: Any]] else { return nil }
        let parts = blocks.compactMap { block -> String? in
            guard block["type"] as? String == blockType, let text = block["text"] as? String else { return nil }
            return text
        }
        guard !parts.isEmpty else { return nil }
        return nonEmpty(parts.joined(separator: "\n"))
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}

/// Codex CLI's `~/.codex/sessions/**/*.jsonl` shape, confirmed against real
/// rollout transcripts on this machine:
///
/// - `{"type":"event_msg","payload":{"type":"agent_message","message":"…"}}`
///   — the clean assistant text equivalent of Claude's text content blocks.
/// - `{"type":"event_msg","payload":{"type":"user_message","message":"…"}}`
///   — the clean user-prompt equivalent (distinct from the noisier
///   `response_item` role-tagged lines, which include harness-injected
///   developer/system content and are not used here).
/// - `{"type":"event_msg","payload":{"type":"token_count","info":
///   {"last_token_usage":{"input_tokens":…,"output_tokens":…,
///   "cached_input_tokens":…,"cache_write_input_tokens":…}}}}` — Codex
///   reports cumulative *and* last-turn usage; `last_token_usage` is the
///   per-turn delta, the closest analog to Claude's per-message `usage`.
/// - `{"type":"event_msg","payload":{"type":"thread_settings_applied",
///   "thread_settings":{"model":"…"}}}` — the current model.
struct CodexTranscriptLineExtractor: TranscriptLineExtracting {
    func facts(from object: [String: Any], occurredAt: Date?) -> TranscriptLineFacts {
        var facts = TranscriptLineFacts()
        guard object["type"] as? String == "event_msg", let payload = object["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String else { return facts }
        switch payloadType {
        case "agent_message":
            if let text = nonEmpty(payload["message"] as? String) {
                facts.turn = TranscriptTurnProjection(role: .assistant, text: text, occurredAt: occurredAt)
            }
        case "user_message":
            if let text = nonEmpty(payload["message"] as? String) {
                facts.turn = TranscriptTurnProjection(role: .user, text: text, occurredAt: occurredAt)
            }
        case "token_count":
            facts.usage = usage(from: (payload["info"] as? [String: Any])?["last_token_usage"] as? [String: Any])
        case "thread_settings_applied":
            facts.model = (payload["thread_settings"] as? [String: Any])?["model"] as? String
        default:
            break
        }
        return facts
    }

    private func usage(from raw: [String: Any]?) -> TranscriptUsageProjection? {
        guard let raw else { return nil }
        guard let input = intValue(raw["input_tokens"]), let output = intValue(raw["output_tokens"]) else { return nil }
        return TranscriptUsageProjection(
            inputTokens: input,
            outputTokens: output,
            cacheReadInputTokens: intValue(raw["cached_input_tokens"]) ?? 0,
            cacheCreationInputTokens: intValue(raw["cache_write_input_tokens"]) ?? 0
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}

enum TranscriptLineExtractorFactory {
    static func extractor(for product: TranscriptProduct) -> TranscriptLineExtracting {
        switch product {
        case .claudeCode: return ClaudeTranscriptLineExtractor()
        case .codexCLI: return CodexTranscriptLineExtractor()
        }
    }
}
