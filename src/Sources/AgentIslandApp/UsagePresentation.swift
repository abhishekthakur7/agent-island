import Foundation
import Combine
import SwiftUI
import SessionDomain

/// A volatile, typed display boundary for Usage Snapshots. It deliberately
/// holds no SessionStore, notification, queue, action, or navigation port.
/// Adapters call this only after a live negotiated `usage.observation` claim
/// and after supplying a source-owned snapshot; no screen scraping or
/// arithmetic-derived usage can enter here.
@MainActor
final class UsagePresentationModel: ObservableObject {
    struct Source: Equatable {
        let snapshot: UsageSnapshot
        let negotiation: NegotiationSnapshot
        let sessionIdentity: AgentSessionIdentity?
        let receivedAt: Date

        var isLiveCompatible: Bool {
            negotiation.grants(WellKnownCapability.usageObservation, direction: .observe)
        }
    }

    struct Rendered: Equatable {
        let state: UsageSnapshotState
        let snapshot: UsageSnapshot?
        let valueKind: UsageValueKind
        let unavailableReason: String?

        var canAppearInExpandedHeader: Bool {
            snapshot != nil && [.fresh, .stale, .missing].contains(state)
        }
    }

    @Published private(set) var preferences: UsageDisplayPreferences
    @Published private(set) var rendered: Rendered

    var availableProviders: [String] {
        Array(Set(sources.values.filter(\.isLiveCompatible).map { $0.snapshot.provider })).sorted()
    }

    private var sources: [String: Source] = [:]
    private var selectedActiveSession: AgentSessionIdentity?
    private let staleAfter: TimeInterval

    init(preferences: UsageDisplayPreferences = .default, staleAfter: TimeInterval = 300) {
        self.preferences = preferences
        self.staleAfter = staleAfter
        self.rendered = Rendered(state: .unavailable, snapshot: nil, valueKind: preferences.valueKind, unavailableReason: "No live Agent Adapter has supplied Usage Snapshot evidence. Cursor Hooks and ACP do not expose usage observation.")
    }

    func updatePreferences(_ preferences: UsageDisplayPreferences, now: Date = Date()) {
        self.preferences = preferences
        recompute(now: now)
    }

    /// The caller's negotiation is checked again at the presentation seam;
    /// a Product name alone can never make a source eligible.
    func receive(_ source: Source, now: Date = Date()) {
        guard source.isLiveCompatible else { return }
        sources[source.snapshot.sourceID] = source
        recompute(now: now)
    }

    func withdraw(sourceID: String, now: Date = Date()) {
        sources.removeValue(forKey: sourceID)
        recompute(now: now)
    }

    /// Selection is provided as exact source-owned identity by composition.
    /// Nil/multiple selection never falls back to a plausible provider.
    func selectActiveSession(_ identity: AgentSessionIdentity?, now: Date = Date()) {
        selectedActiveSession = identity
        recompute(now: now)
    }

    func refresh(now: Date = Date()) { recompute(now: now) }

    private func recompute(now: Date) {
        // Only republish when the rendered value actually changes. `@Published`
        // fires `objectWillChange` on EVERY assignment regardless of equality,
        // and the overlay subscribes to this model's `objectWillChange` to
        // drive `renderIfVisible()` — which itself calls `selectActiveSession`
        // / `refresh` (→ `recompute`). An unconditional assign here therefore
        // closes an infinite render loop that pegs the main thread ("not
        // responding") whenever the overlay is actually visible. `Rendered` is
        // `Equatable`, so the guard breaks the cycle once state is stable.
        let next = computeRendered(now: now)
        if next != rendered { rendered = next }
    }

    private func computeRendered(now: Date) -> Rendered {
        guard preferences.isVisible else {
            return Rendered(state: .disabled, snapshot: nil, valueKind: preferences.valueKind, unavailableReason: "Usage display is off.")
        }
        let eligible = sources.values.filter(\.isLiveCompatible)
        let matching: [Source]
        switch preferences.providerSelection {
        case let .preferred(provider):
            matching = eligible.filter { $0.snapshot.provider == provider }
        case .followSelectedActiveSession:
            guard let selectedActiveSession else {
                return Rendered(state: .unavailable, snapshot: nil, valueKind: preferences.valueKind, unavailableReason: "No single selected active Agent Session has eligible Usage Snapshot evidence.")
            }
            matching = eligible.filter { $0.sessionIdentity == selectedActiveSession }
        }
        guard matching.count == 1, let source = matching.first else {
            return Rendered(state: .unavailable, snapshot: nil, valueKind: preferences.valueKind, unavailableReason: matching.isEmpty ? "The selected source is unavailable." : "More than one source matched; select a preferred provider.")
        }
        let snapshot = source.snapshot
        let state: UsageSnapshotState
        if !snapshot.hasSourcedValue || preferences.valueKind.value(in: snapshot) == nil {
            state = .missing
        } else if now.timeIntervalSince(snapshot.observedAt) > staleAfter {
            state = .stale
        } else {
            state = .fresh
        }
        return Rendered(state: state, snapshot: snapshot, valueKind: preferences.valueKind, unavailableReason: nil)
    }
}

/// Small local preferences boundary separate from Atlas presentation state.
/// It persists only a person's display choices, never Usage Snapshot values
/// or Product/session identifiers.
struct UsageSettingsRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "com.agentisland.usage.display-preferences") {
        self.defaults = defaults; self.key = key
    }

    func load() -> UsageDisplayPreferences {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(UsageDisplayPreferences.self, from: data) else { return .default }
        return value
    }

    func save(_ value: UsageDisplayPreferences) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

/// AB-157: the presentation-layer home for the multi-provider
/// `ProviderQuotaBoard` (`SessionDomain/ProviderQuotaState.swift`) — the
/// richer model behind §1.4's usage cluster, §1.12's menu-bar popover, and
/// §1.12.1's Metrics tab. It mirrors `UsagePresentationModel`'s shape (an
/// `ObservableObject` holding no `SessionStore`/notification/queue/
/// navigation port) but for a `ProviderQuotaPort` instead of a per-Adapter
/// `UsageSnapshot` stream, since provider quota state is account-scoped
/// rather than negotiated per Agent Session.
///
/// This ticket does not wire this model into the overlay or the menu-bar
/// popover — that is AB-161 (§1.4 usage cluster) and AB-162 (§1.12 popover +
/// Metrics tab). It exists now so those tickets have one ready observable
/// object and one call site (`refresh()`) to drive their views from, instead
/// of each independently deciding how a `ProviderQuotaPort` becomes
/// published SwiftUI state.
///
/// The default `port` is `UnavailableProviderQuotaPort` — see
/// `ProviderQuotaAcquisition.swift` for the sourcing gap that stands behind
/// that default. Wiring a real source later is a one-line change at whatever
/// call site constructs this model (see that file's "extension point" doc
/// comment); nothing here needs to change, because every field
/// `ProviderQuotaBoard` exposes is already independently optional.
@MainActor
final class ProviderQuotaBoardModel: ObservableObject {
    @Published private(set) var board: ProviderQuotaBoard

    private let port: ProviderQuotaPort

    init(port: ProviderQuotaPort = UnavailableProviderQuotaPort(), now: Date = Date()) {
        self.port = port
        self.board = port.currentBoard(at: now)
    }

    /// Re-polls `port` for the latest board. AB-161/162 are expected to call
    /// this from the same refresh affordance the compact cluster's `⟳` glyph
    /// (AC-1.4-c) and the popover's `⟳` (AC-1.12-a) already imply.
    func refresh(now: Date = Date()) {
        // Same guard as `UsagePresentationModel.recompute`: the overlay drives
        // `renderIfVisible()` off this model's `objectWillChange`, so publish
        // only on a real change to keep an equal board from ever re-triggering
        // a render. `ProviderQuotaBoard` is `Equatable`.
        let next = port.currentBoard(at: now)
        if next != board { board = next }
    }

    /// Convenience passthrough so a SwiftUI view can write
    /// `model.snapshot(for: .claude)` instead of `model.board.snapshot(for:)`.
    func snapshot(for provider: QuotaProvider) -> ProviderQuotaSnapshot? {
        board.snapshot(for: provider)
    }
}

// MARK: - AB-161 §1.4 UI-facing presentation helpers

/// AB-161 §1.4 AC-1.4-a: the plain monospaced brand-mark character + tint
/// each provider leads its usage-cluster entry with. `SessionDomain` must
/// never import SwiftUI (see `ProviderQuotaState.swift`'s doc comment), so
/// this UI-facing mapping lives here instead — the app layer's one
/// presentation home for `ProviderQuotaBoard`/`ProviderQuotaBoardModel`.
///
/// There are no dedicated brand-mark glyph views (unlike the pixel-drawn
/// glyphs in `IslandGlyphs.swift`) — per the ticket, a small tinted mono
/// character is the intentionally lightweight approach. Claude's `✳` and its
/// `claudeBrand` tint, and Cursor's "mono cube" framing, are named directly
/// by the ticket doc; Codex's exact mark and OpenCode's exact square are not
/// pinned to a literal character anywhere in the doc/images (only "a mark"/
/// "a square"), so `◆` (Codex) and `▪` (OpenCode) are judgment calls — kept
/// here, one place, so §1.12's popover (AB-162) reuses the identical marks
/// instead of re-deriving its own.
extension QuotaProvider {
    var brandMarkGlyph: String {
        switch self {
        case .claude: return "✳"
        case .codex: return "◆"
        case .cursor: return "◨"
        case .openCode: return "▪"
        }
    }

    var brandMarkColor: Color {
        switch self {
        case .claude: return IslandTheme.claudeBrand
        case .codex: return IslandTheme.codexBrand
        case .cursor: return IslandTheme.cursorBrand
        case .openCode: return IslandTheme.openCodeBrand
        }
    }
}

extension QuotaWindowState {
    /// AB-161 §1.4 AC-1.4-e: the compact time-until-reset string the
    /// detailed focused-session form renders (`8m`, `3d3h`). `nil` when
    /// there is no `timeUntilReset` to format — the caller renders `--` for
    /// that case, matching this module's "absence, never a fabricated
    /// value" rule.
    var compactTimeUntilReset: String? {
        guard let timeUntilReset else { return nil }
        return Self.formatCompact(duration: timeUntilReset)
    }

    private static func formatCompact(duration seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let totalHours = totalMinutes / 60
        if totalHours < 24 {
            let minutes = totalMinutes % 60
            return minutes > 0 ? "\(totalHours)h\(minutes)m" : "\(totalHours)h"
        }
        let days = totalHours / 24
        let hours = totalHours % 24
        return hours > 0 ? "\(days)d\(hours)h" : "\(days)d"
    }
}

@MainActor
final class UsageSettingsModel: ObservableObject {
    @Published private(set) var preferences: UsageDisplayPreferences
    let presentation: UsagePresentationModel
    private let repository: UsageSettingsRepository

    init(repository: UsageSettingsRepository = UsageSettingsRepository(), presentation: UsagePresentationModel? = nil) {
        self.repository = repository
        let preferences = repository.load()
        self.preferences = preferences
        self.presentation = presentation ?? UsagePresentationModel(preferences: preferences)
    }

    func update(_ change: (inout UsageDisplayPreferences) -> Void) {
        var next = preferences
        change(&next)
        guard next != preferences else { return }
        preferences = next
        repository.save(next)
        presentation.updatePreferences(next)
    }
}
