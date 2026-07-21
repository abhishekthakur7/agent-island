import Foundation

/// AB-157 — the multi-provider, multi-window model behind the overlay
/// redesign's usage cluster (`docs/agents/tasks/overlay-visual-redesign.md`
/// §1.4), the menu-bar popover (§1.12), and its "Metrics" tab (§1.12.1).
///
/// ## What this models
///
/// Each agent Product sells its own **subscription-plan quota** — Claude's
/// rolling 5-hour and weekly limits, Codex's equivalent windows, Cursor's
/// monthly plan meter, OpenCode's token/request/cost meter. This is:
///   - **the provider's own rolling limit**, not Agent Island's own usage
///     accounting or anything derived from `NormalizedEventFact`s;
///   - **not per-session** — it is scoped to the person's account with that
///     provider, shared across every Agent Session that provider runs;
///   - **not billing** — Agent Island ships with no paywall (§1.11); nothing
///     here is an entitlement, a license check, or a price.
///
/// ## Relationship to `UsageSnapshot` (`UsageSnapshot.swift`)
///
/// `UsageSnapshot` remains exactly what it always was — one provider, one
/// `usedPercent`/`remainingPercent`, one `resetsAt` — because
/// `UsagePresentationModel`/`UsageSnapshotHeader`/`AppDelegate` already
/// depend on that exact shape. It cannot express multiple providers,
/// multiple named windows, token-metered usage, or the Metrics-tab depth
/// (per-model split, per-token-class breakdown, a histogram). Rather than
/// bend that type to do double duty, this file adds a genuinely richer,
/// additive sibling model. `UsageSnapshot` is not deprecated by this file —
/// it is simply a different, narrower concept that happens to predate this
/// one.
///
/// ## Sourcing — read this before wiring a UI to these types
///
/// Provider quota state is **not available** from any evidence path this
/// codebase already has: not a documented hook (no Adapter negotiates a
/// "provider quota" capability today), not a transcript read
/// (`TranscriptEvidenceProjection` carries per-message token counts and a
/// model string, never an account-level plan-window percentage or reset
/// time), not the statusline. See `ProviderQuotaAcquisition.swift` for the
/// acquisition seam that keeps this honest: every optional field below is
/// optional specifically so "no data" can be represented as absence
/// (`nil`/empty), never as an invented `0%` or a guessed reset time.

// MARK: - Provider identity

/// The four agent Products the redesign doc names as usage-cluster/popover
/// participants (§1.4 AC-1.4-a, §1.12 AC-1.12-b/c). A plain `String`
/// (as `UsageSnapshot.provider` uses) would let a typo silently create a
/// phantom column in the compact multi-provider cluster; this closed set
/// mirrors the fixed brand marks (`IslandTheme.claudeBrand`, `.codexBrand`,
/// `.cursorBrand`, `.openCodeBrand`) the app layer already has one-per-value.
public enum QuotaProvider: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case claude
    case codex
    case cursor
    case openCode

    /// The label the redesign doc's mockups render (`Claude`, `Codex`,
    /// `Cursor`, `OpenCode`) — never derived from `rawValue` casing tricks so
    /// a future case can pick whatever `rawValue` it needs for `Codable`
    /// wire stability without touching display text.
    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .openCode: return "OpenCode"
        }
    }
}

// MARK: - Percent-metered quota windows (§1.4, §1.12)

/// The three named rolling windows the redesign doc renders literally as
/// `5H` / `7D` / `MO` (AC-1.4-b, AC-1.12-b). Closed on purpose: the doc never
/// shows a fourth window shape, and an open-ended `String` window name would
/// make `5h`/`5H`/`five-hour` all distinct keys by accident.
public enum QuotaWindowKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case fiveHour = "5H"
    case sevenDay = "7D"
    case month = "MO"

    /// The literal short label every renderer prints. Equal to `rawValue`;
    /// named separately so a call site reads as intent (`kind.label`) rather
    /// than reaching into `Codable` wire representation by convention.
    public var label: String { rawValue }
}

/// One provider's state for one rolling quota window (e.g. Claude's `5H`).
///
/// Every field is independently optional and independently validated,
/// because a real source may legitimately report some but not all of them
/// (the doc's own example: Codex shows `5H --` — no percent, no time — while
/// its `7D` row has both). `percentConsumed == nil` must render as `--`
/// (AC-1.4-b), never as `0%` — this type has no way to produce a fabricated
/// zero because there is no default-to-zero path in the initializer.
public struct QuotaWindowState: Codable, Equatable, Hashable, Sendable {
    public let kind: QuotaWindowKind
    /// Percent of this window's allowance already consumed, 0...100. This is
    /// **consumption**, matching AC-1.4-f's threshold rule and
    /// `IslandTheme.quotaColor(percentConsumed:)`'s parameter name — it is
    /// deliberately not a "remaining" percentage (unlike `UsageSnapshot`,
    /// which carries both because its source data disagreed on which one
    /// was reported; every quota-window mockup in §1.4/§1.12 speaks in
    /// "consumed").
    public let percentConsumed: Double?
    /// Time remaining until this window resets/refills (e.g. the source for
    /// a rendered `8m` or `3d3h`). Independent of `resetsAt`: a source may
    /// report a countdown without an absolute instant, or vice versa.
    public let timeUntilReset: TimeInterval?
    /// The absolute reset/refill instant (e.g. the source for a rendered
    /// "refills Fri at 10:30 PM").
    public let resetsAt: Date?

    public init(
        kind: QuotaWindowKind,
        percentConsumed: Double? = nil,
        timeUntilReset: TimeInterval? = nil,
        resetsAt: Date? = nil
    ) {
        self.kind = kind
        self.percentConsumed = Self.validPercentage(percentConsumed)
        self.timeUntilReset = Self.validDuration(timeUntilReset)
        self.resetsAt = resetsAt
    }

    /// `true` only when a real percentage was supplied. A caller should
    /// render `--` (not `0%`, not blank) when this is `false` — matching
    /// AC-1.4-b/AC-1.12-b's "`--` = no data for that window".
    public var hasData: Bool { percentConsumed != nil }

    /// `nil` when there is no percentage to classify — a caller must not
    /// default an absent window to `.healthy`, since that would render an
    /// unsourced `--` window as a green bar.
    public var threshold: QuotaThreshold? {
        percentConsumed.map(QuotaThreshold.from(percentConsumed:))
    }

    private static func validPercentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0 ... 100).contains(value) else { return nil }
        return value
    }

    private static func validDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// The shared threshold rule behind AC-1.4-f/AC-1.12 quota coloring —
/// **0-60% green / 60-80% orange / 80%+ red** — expressed without importing
/// `SwiftUI`/`Color`. `SessionDomain` has no UI dependency (this file must
/// never `import SwiftUI` or `AppKit`); the app layer maps this enum onto
/// concrete colors via `IslandTheme.quotaColor(percentConsumed:)`, whose
/// three cut points are numerically identical to this type's — deliberately
/// kept as two independent expressions of one rule (a domain enum for any
/// non-UI caller, e.g. a future notification-priority decision, and the
/// existing `Color`-returning function for SwiftUI call sites) rather than
/// one calling the other across the module boundary that must not exist.
public enum QuotaThreshold: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case healthy
    case elevated
    case critical

    public static func from(percentConsumed: Double) -> QuotaThreshold {
        switch percentConsumed {
        case ..<60: return .healthy
        case ..<80: return .elevated
        default: return .critical
        }
    }
}

// MARK: - Token-metered usage (§1.12 OpenCode row)

/// OpenCode's usage shape, which the doc explicitly renders differently from
/// every percent-metered provider: `TOK 2.6M` + `26 req / 2.6M tokens /
/// $0.16` (AC-1.12-c) — no percentage, no progress bar, because OpenCode's
/// plan is metered directly in tokens/requests/cost rather than a
/// rolling-window allowance.
public struct TokenMeteredUsage: Codable, Equatable, Hashable, Sendable {
    public let requestCount: Int?
    public let tokenCount: Int?
    public let costUSD: Double?

    public init(requestCount: Int? = nil, tokenCount: Int? = nil, costUSD: Double? = nil) {
        self.requestCount = requestCount.map { max(0, $0) }
        self.tokenCount = tokenCount.map { max(0, $0) }
        self.costUSD = costUSD.flatMap { $0.isFinite ? max(0, $0) : nil }
    }

    public var hasData: Bool { requestCount != nil || tokenCount != nil || costUSD != nil }
}

// MARK: - Metrics-tab depth (§1.12.1)

/// One token class in the Metrics tab's colored-dot composition breakdown
/// (`input` / `output` / `cache write` / `cache read`, AC-1.12-g/i).
public enum TokenClass: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case input
    case output
    case cacheWrite
    case cacheRead

    /// Lowercase, space-separated — matches the doc's own rendering
    /// (`input`, `output`, `cache write`, `cache read`), not a `Cache Write`
    /// title-case a naive `rawValue` transform would produce.
    public var displayName: String {
        switch self {
        case .input: return "input"
        case .output: return "output"
        case .cacheWrite: return "cache write"
        case .cacheRead: return "cache read"
        }
    }
}

/// One row of the Metrics tab's per-token-class breakdown. Rows are omitted
/// from `ProviderQuotaMetrics.tokenClassBreakdown` entirely when a provider
/// doesn't report that class (AC-1.12-i: "Codex has no cache write row") —
/// this type carries no "absent" state of its own because the omission is
/// expressed by the row simply not existing in the array.
public struct TokenClassShare: Codable, Equatable, Hashable, Sendable {
    public let tokenClass: TokenClass
    public let percent: Double

    public init(tokenClass: TokenClass, percent: Double) {
        self.tokenClass = tokenClass
        self.percent = Self.clampPercent(percent)
    }

    private static func clampPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }
}

/// One row of the Metrics tab's per-model split (e.g. `Opus 4.8 72%`).
///
/// `Self.otherModelName` is the reserved tail-bucket name AC-1.12-g requires
/// ("an `other` bucket always absorbs the tail so the split sums to 100%").
/// This type does not enforce the 100%-sum invariant itself — a caller
/// assembling a real split is responsible for computing an honest `other`
/// remainder; this type only clamps an individual row to a valid percentage.
public struct ModelUsageShare: Codable, Equatable, Hashable, Sendable {
    public let modelName: String
    public let percent: Double

    public init(modelName: String, percent: Double) {
        self.modelName = modelName
        self.percent = Self.clampPercent(percent)
    }

    public static let otherModelName = "other"

    /// `true` for the reserved tail-bucket row.
    public var isOther: Bool { modelName == Self.otherModelName }

    private static func clampPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }
}

/// One point in the Metrics tab's usage histogram (§1.12.1's "usage
/// histogram — a small bar chart of recent usage, drawn on a dashed
/// baseline so an empty series still reads as a chart"). `value` is
/// deliberately unitless (tokens, requests, or percent — whatever the
/// provider's history reports) so this type stays usable across every
/// provider shape; a caller renders it relative to the series' own max, not
/// against a fixed scale.
public struct UsageHistogramPoint: Codable, Equatable, Hashable, Sendable {
    public let bucketStart: Date
    public let value: Double

    public init(bucketStart: Date, value: Double) {
        self.bucketStart = bucketStart
        self.value = value.isFinite ? max(0, value) : 0
    }
}

/// One row of a quota-metered provider's Metrics-tab "per-mode" split (the
/// doc's Cursor example: `Auto` / `API` rows alongside a used/remaining
/// pair, §1.12.1 "Quota-metered providers substitute ... per-mode rows").
/// Generic (not a Cursor-specific enum) so it costs a token-metered provider
/// nothing — it simply never populates this array.
public struct QuotaModeUsage: Codable, Equatable, Hashable, Sendable {
    public let modeName: String
    public let percentConsumed: Double?
    public let used: Int?
    public let remaining: Int?

    public init(modeName: String, percentConsumed: Double? = nil, used: Int? = nil, remaining: Int? = nil) {
        self.modeName = modeName
        self.percentConsumed = Self.validPercentage(percentConsumed)
        self.used = used.map { max(0, $0) }
        self.remaining = remaining.map { max(0, $0) }
    }

    private static func validPercentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0 ... 100).contains(value) else { return nil }
        return value
    }
}

/// The Metrics tab's full per-provider depth (§1.12.1) — everything beyond
/// the Active tab's window rows. `nil` at the `ProviderQuotaSnapshot` level
/// means "no Metrics-depth data was ever attempted for this provider"; a
/// non-nil value with every field empty/nil means "attempted, found
/// nothing" — the same nullable-container-vs-empty-fields distinction
/// `TranscriptEvidenceProjection` uses (see that type's doc comment).
public struct ProviderQuotaMetrics: Codable, Equatable, Hashable, Sendable {
    /// The headline token total for a "token-metered" Metrics card
    /// (AC-1.12-h: Claude/Codex/OpenCode lead with a token total in the
    /// Metrics tab even though Claude/Codex are percent-metered on the
    /// Active tab). `nil` for a provider whose Metrics headline is instead a
    /// percentage (Cursor) — that percentage is read off the `MO`
    /// `QuotaWindowState` already on the snapshot, not duplicated here.
    public let tokenTotal: Int?
    public let usageHistogram: [UsageHistogramPoint]
    public let tokenClassBreakdown: [TokenClassShare]
    public let modelSplit: [ModelUsageShare]
    /// Cursor-shaped per-mode rows (AC-1.12.1); empty for every other
    /// provider.
    public let modeBreakdown: [QuotaModeUsage]

    public init(
        tokenTotal: Int? = nil,
        usageHistogram: [UsageHistogramPoint] = [],
        tokenClassBreakdown: [TokenClassShare] = [],
        modelSplit: [ModelUsageShare] = [],
        modeBreakdown: [QuotaModeUsage] = []
    ) {
        self.tokenTotal = tokenTotal.map { max(0, $0) }
        self.usageHistogram = usageHistogram
        self.tokenClassBreakdown = tokenClassBreakdown
        self.modelSplit = modelSplit
        self.modeBreakdown = modeBreakdown
    }

    public var hasAnyData: Bool {
        tokenTotal != nil || !usageHistogram.isEmpty || !tokenClassBreakdown.isEmpty
            || !modelSplit.isEmpty || !modeBreakdown.isEmpty
    }
}

// MARK: - Per-provider snapshot and the multi-provider board

/// One provider's full quota state at a point in time: its percent-metered
/// windows (Claude/Codex/Cursor), or its token-metered usage (OpenCode), or
/// (for the Metrics tab) both a window and a metrics depth at once — nothing
/// here forces a provider into exactly one shape, because the doc itself
/// doesn't (Cursor is percent-metered on the Active tab but still gets a
/// Metrics card with mode rows).
public struct ProviderQuotaSnapshot: Codable, Equatable, Hashable, Sendable {
    public let provider: QuotaProvider
    public let observedAt: Date
    /// Percent-metered windows this provider reported. Absence of a
    /// `QuotaWindowKind` from this array — not a zero-valued entry — is how
    /// "this provider doesn't have a `MO` window" is represented; a
    /// `QuotaWindowState` present in the array with `percentConsumed == nil`
    /// means something narrower: "we know of this window, but have no
    /// percentage for it right now" (the doc's `5H --` case).
    public let windows: [QuotaWindowState]
    /// OpenCode-shaped token/request/cost meter. `nil` for every
    /// percent-metered provider.
    public let tokenUsage: TokenMeteredUsage?
    /// The Metrics tab's depth for this provider, if resolved.
    public let metrics: ProviderQuotaMetrics?

    public init(
        provider: QuotaProvider,
        observedAt: Date,
        windows: [QuotaWindowState] = [],
        tokenUsage: TokenMeteredUsage? = nil,
        metrics: ProviderQuotaMetrics? = nil
    ) {
        self.provider = provider
        self.observedAt = observedAt
        self.windows = windows
        self.tokenUsage = tokenUsage
        self.metrics = metrics
    }

    /// Looks up one named window; `nil` when this provider's `windows`
    /// array never mentioned that kind at all (distinct from a mentioned
    /// window whose `percentConsumed` is `nil` — see the `windows` doc
    /// comment above).
    public func window(_ kind: QuotaWindowKind) -> QuotaWindowState? {
        windows.first { $0.kind == kind }
    }

    public var isTokenMetered: Bool { tokenUsage != nil }

    public var hasAnyData: Bool {
        windows.contains(where: \.hasData) || (tokenUsage?.hasData ?? false) || (metrics?.hasAnyData ?? false)
    }
}

/// All known providers' quota state at once — the single value §1.4's
/// compact multi-provider cluster and §1.12's popover both render from.
///
/// A provider missing from `snapshots` means "no data available for this
/// provider at all" (it should not appear as a column/card), which is a
/// distinct, coarser absence than a present `ProviderQuotaSnapshot` whose
/// individual windows are `nil`-percentage (it should appear, with `--`
/// cells). Callers needing "does Claude have a column at all" should check
/// `snapshot(for:) != nil`, not merely `.hasAnyData`, if that literal
/// distinction ever matters — today the two coincide because nothing
/// produces an all-absent snapshot in the first place (see
/// `ProviderQuotaAcquisition.swift`).
public struct ProviderQuotaBoard: Codable, Equatable, Hashable, Sendable {
    public let observedAt: Date
    public let snapshots: [ProviderQuotaSnapshot]

    public init(observedAt: Date, snapshots: [ProviderQuotaSnapshot] = []) {
        self.observedAt = observedAt
        self.snapshots = snapshots
    }

    public func snapshot(for provider: QuotaProvider) -> ProviderQuotaSnapshot? {
        snapshots.first { $0.provider == provider }
    }

    /// The empty board: every provider absent. This is what the shipped
    /// `UnavailableProviderQuotaPort` always returns — see that type's doc
    /// comment for why that is the honest default rather than a gap to be
    /// papered over with placeholder data.
    public static func empty(observedAt: Date) -> ProviderQuotaBoard {
        ProviderQuotaBoard(observedAt: observedAt, snapshots: [])
    }
}
