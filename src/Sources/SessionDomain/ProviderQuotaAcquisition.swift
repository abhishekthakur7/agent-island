import Foundation

/// AB-157's acquisition seam: the one typed entry point a caller uses to
/// obtain a `ProviderQuotaBoard` (`ProviderQuotaState.swift`). No call site
/// outside this file should construct a `ProviderQuotaBoard` by guessing at
/// numbers — it either comes from a `ProviderQuotaPort` implementation, or it
/// is legitimately empty.
///
/// ## The sourcing gap this seam exists to name honestly
///
/// Provider quota state — Claude's rolling 5-hour/weekly limits, Codex's
/// equivalent windows, Cursor's monthly plan meter, OpenCode's token/cost
/// meter — is **not available from any evidence path this codebase already
/// has**:
///   - **Not a documented hook.** Every `NormalizedEventFact` is admitted
///     only after `SessionDomainValidator` checks a granted Adapter
///     capability (`Envelope.swift`, `Negotiation.swift`); no Claude/Codex/
///     Cursor Adapter negotiates a "provider quota" capability today, and
///     none of the documented hook payloads carry a plan-window percentage
///     or reset time.
///   - **Not a transcript read.** `TranscriptEvidenceProjection` /
///     `TranscriptUsageProjection` (`TranscriptEvidence.swift`) carry real
///     per-message token counts and a real model string — genuinely useful
///     for parts of the Metrics tab's token/model/token-class depth (see
///     `TranscriptDerivedQuotaMetrics` below) — but never an account-level
///     plan-window percentage or reset/refill instant. A token count cannot
///     be turned into "percent of the 5-hour window consumed" without
///     inventing the window's total allowance, which this codebase does not
///     have and must not guess.
///   - **Not the statusline.** No statusline payload this codebase parses
///     carries provider account/plan state either.
///
/// The overlay redesign doc itself calls this out as "the one genuinely
/// unsourced input" behind §1.4, and "the deepest data ask in the document"
/// for §1.12.1. This file's job is not to solve that — there is no real
/// source to wire today — but to make the gap a typed, discoverable seam
/// instead of a temptation to fabricate numbers at a UI call site.
///
/// ## What ships today
///
/// `UnavailableProviderQuotaPort` — the only `ProviderQuotaPort`
/// implementation in this codebase. It always returns
/// `ProviderQuotaBoard.empty(observedAt:)`. Every field in
/// `ProviderQuotaState.swift` is optional specifically so this is a fully
/// legitimate, representable answer: a later UI renders "no providers" /
/// `--` honestly rather than crashing on a missing case or silently
/// defaulting to `0%`.
public protocol ProviderQuotaPort: Sendable {
    /// Returns the best currently-known `ProviderQuotaBoard`. An
    /// implementation with no real source must return an empty board, never
    /// an invented percentage, reset time, or token count — the entire
    /// reason this protocol exists is so a caller can depend on "no data" or
    /// "not yet built" being told the truth about the input, not painted over.
    func currentBoard(at date: Date) -> ProviderQuotaBoard
}

/// The only `ProviderQuotaPort` this codebase ships (see the type doc
/// above for why). Always answers with an empty board — no providers, no
/// windows, no token usage, no metrics.
///
/// ## Extension point for a future real source
///
/// When a real source is found — for example a documented `claude usage`-
/// shaped CLI/API call, or a Codex/Cursor/OpenCode account endpoint — add a
/// **new** type conforming to `ProviderQuotaPort` next to this one (e.g.
/// `ClaudeAccountProviderQuotaPort`) rather than editing this type to return
/// real-looking values. The composition root
/// (`AgentIslandApp/AppDelegate.swift`, alongside where it already
/// constructs `UsageSettingsModel`) is the only place that should decide
/// which port a `ProviderQuotaBoardModel` (`UsagePresentation.swift`) is
/// built with; nothing about `ProviderQuotaBoard`, `ProviderQuotaSnapshot`,
/// or a renderer needs to change, since every field the model exposes is
/// already independently optional/absence-eligible.
public struct UnavailableProviderQuotaPort: ProviderQuotaPort {
    public init() {}

    public func currentBoard(at date: Date) -> ProviderQuotaBoard {
        .empty(observedAt: date)
    }
}

/// A secondary, optional, and strictly narrower source: turning REAL
/// transcript-derived evidence that already exists in this codebase
/// (`TranscriptUsageProjection`'s per-message token counts,
/// `TranscriptEvidenceProjection.modelFromTranscript`'s real model string)
/// into the parts of the Metrics tab's depth (§1.12.1) those counts can
/// honestly support.
///
/// This deliberately produces **no** quota-window percentages, no reset/
/// refill times, and no usage histogram — none of those exist in a
/// transcript. Do not use this type's output to populate
/// `ProviderQuotaSnapshot.windows`; it only ever produces a `metrics` value,
/// and callers must leave `windows`/`tokenUsage` alone (`nil`/empty) unless
/// a genuine `ProviderQuotaPort` source supplies them.
public enum TranscriptDerivedQuotaMetrics {
    /// Builds the Metrics-tab depth obtainable from one transcript read:
    /// - `tokenTotal` and the input/output/cache-write/cache-read
    ///   `tokenClassBreakdown`, computed as real percentages of the real
    ///   counts on `usage`.
    /// - A one-entry `modelSplit` naming the single model this read actually
    ///   observed, at 100%. There is deliberately **no `other` bucket**
    ///   here: `TranscriptEvidenceProjection` only ever reports the latest
    ///   message's model, so a caller has no honest per-model history to
    ///   split against — inventing an `other` remainder would imply
    ///   knowledge of other models this read never saw. A caller with
    ///   genuine multi-model history (e.g. aggregated across many transcript
    ///   reads) should build `ModelUsageShare` directly instead of routing
    ///   through this function.
    /// - An always-empty `usageHistogram`: a single "latest usage" read has
    ///   no time series to report.
    ///
    /// Cache-class rows are included only when their count is greater than
    /// zero. `TranscriptUsageProjection`'s cache fields default to `0` and
    /// are not independently optional, so this function cannot distinguish
    /// "this provider/turn never reports cache tokens" from "reported
    /// exactly zero this turn" — omitting on zero is the safer reading for a
    /// class that is frequently genuinely absent (e.g. a non-caching turn),
    /// matching AC-1.12-i's "omitted, not rendered as 0%" for rows a
    /// provider doesn't report. `input`/`output` are always included even
    /// when zero, since `TranscriptUsageProjection` reports those two
    /// unconditionally for every real turn it was built from.
    public static func metrics(from usage: TranscriptUsageProjection, model: String?) -> ProviderQuotaMetrics {
        let total = usage.totalTokens
        guard total > 0 else {
            let modelSplit = model.map { [ModelUsageShare(modelName: $0, percent: 100)] } ?? []
            return ProviderQuotaMetrics(modelSplit: modelSplit)
        }
        func percent(_ count: Int) -> Double { Double(count) / Double(total) * 100 }

        var classes: [TokenClassShare] = [
            TokenClassShare(tokenClass: .input, percent: percent(usage.inputTokens)),
            TokenClassShare(tokenClass: .output, percent: percent(usage.outputTokens)),
        ]
        if usage.cacheCreationInputTokens > 0 {
            classes.append(TokenClassShare(tokenClass: .cacheWrite, percent: percent(usage.cacheCreationInputTokens)))
        }
        if usage.cacheReadInputTokens > 0 {
            classes.append(TokenClassShare(tokenClass: .cacheRead, percent: percent(usage.cacheReadInputTokens)))
        }

        let modelSplit = model.map { [ModelUsageShare(modelName: $0, percent: 100)] } ?? []

        return ProviderQuotaMetrics(
            tokenTotal: total,
            usageHistogram: [],
            tokenClassBreakdown: classes,
            modelSplit: modelSplit
        )
    }

    /// Convenience wrapper: builds a full `ProviderQuotaSnapshot` for
    /// `provider`, with `windows`/`tokenUsage` left empty/`nil` (this source
    /// has no evidence for either) and `metrics` populated from
    /// `transcript.latestUsage` via `metrics(from:model:)` above. Returns
    /// `nil` when the transcript bag has no usage at all — matching this
    /// module's rule that "no data" is represented by absence, never a
    /// present-but-empty snapshot.
    public static func snapshot(
        provider: QuotaProvider,
        observedAt: Date,
        transcript: TranscriptEvidenceProjection
    ) -> ProviderQuotaSnapshot? {
        guard let usage = transcript.latestUsage else { return nil }
        return ProviderQuotaSnapshot(
            provider: provider,
            observedAt: observedAt,
            metrics: metrics(from: usage, model: transcript.modelFromTranscript)
        )
    }
}
