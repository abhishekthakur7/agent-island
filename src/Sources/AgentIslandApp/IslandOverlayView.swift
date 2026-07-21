import SwiftUI
import Combine
import SessionDomain
import PresentationRuntime

/// SwiftUI supplies only the visible Island silhouette. AppKit owns its
/// lifetime, placement, input, accessibility withdrawal, and activation
/// behavior in `IslandOverlayController`.
struct IslandOverlayView: View {
    let presentation: IslandOverlayPresentation
    let geometry: IslandOverlayGeometry
    let cards: [AgentSessionCardSnapshot]
    let ledgerRevision: Int64
    let keyboardEngaged: Bool
    let focusedSessionIndex: Int?
    let clickBehavior: AtlasClickBehavior
    let displayPreferences: AtlasDisplayPreferences
    let shortcutInvocationAnnouncement: String?
    let jumpBackAnnouncement: String?
    let usage: UsagePresentationModel.Rendered
    /// AB-161 §1.4: AB-157's multi-provider, multi-window quota model,
    /// threaded from the composition root (`IslandOverlayController` owns a
    /// `ProviderQuotaBoardModel`, defaulting to the honest
    /// `UnavailableProviderQuotaPort` — see that model's doc comment).
    /// Defaults to an empty board so every existing call site (previews,
    /// tests, other in-flight tickets' construction sites) keeps compiling
    /// without threading this explicitly.
    var quotaBoard: ProviderQuotaBoard = .empty(observedAt: Date())
    /// AC-1.4-c: the refresh/sync glyph's tap target — calls
    /// `ProviderQuotaBoardModel.refresh()` at the composition root.
    var onRefreshQuotaBoard: () -> Void = {}
    /// AC-1.4-g: opens the detailed usage view (§1.12 — not yet built; that
    /// is AB-162). A clean, documented seam: `nil` degrades to a harmless
    /// no-op tap, and the composition root may wire it to Settings in the
    /// meantime. AB-162 replaces this closure with one that opens the
    /// menu-bar popover; nothing here needs to change when it does.
    var onOpenUsageDetails: (() -> Void)? = nil
    let onPrimaryClick: () -> Void
    /// AB-160 §1.10: the focused session card's `⌃G ↗` jump control. A
    /// separate closure from `onPrimaryClick` on purpose — see
    /// `IslandOverlayController.jumpToFocusedSession()`'s doc comment for
    /// why this must not be gated behind the general `clickBehavior`
    /// preference `onPrimaryClick` respects.
    let onJumpToSession: () -> Void
    let lastClickOutcome: PresentationClickOutcome?
    let onExpand: () -> Void
    let onCollapse: () -> Void
    let onSettings: () -> Void
    let onEngageKeyboard: () -> Void
    /// AB-154: the real global mute (`SoundPolicy.immediateMute`, surfaced by
    /// `NotificationPolicySettingsModel.immediateMute`), mirrored in by the
    /// composition root (`IslandOverlayController.isMuted` /
    /// `AppDelegate`'s `notificationSettings.$policy` subscription). The
    /// Overlay renders this and asks to flip it; it owns no sound/mute
    /// subsystem of its own.
    let isMuted: Bool
    let onToggleMute: () -> Void

    @StateObject private var horizon = HorizonController()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var attentionCount: Int { cards.filter { $0.attention == .pending }.count }
    private var isExpanded: Bool { presentation == .expanded || presentation == .focused }
    private var contentScale: CGFloat { CGFloat(displayPreferences.contentScale) }
    private var adaptation: AccessibilityAdaptation {
        AccessibilityAdaptation(
            reduceTransparency: reduceTransparency,
            increasedContrast: contrast == .increased,
            textScale: dynamicTypeSize.isAccessibilitySize ? 1.3 : 1
        )
    }

    /// AB-153: the dropdown panel's open/close motion — content-layer scale
    /// anchored top-center, unfolding out of the notch (agent-notch's
    /// `animatePanelLayer`, `/Users/abhishekthakur/Developer/agent-notch/main.swift:863-890`).
    /// The AppKit window frame is already resized instantly by
    /// `IslandOverlayController` before this content mounts (`setFrame(_:display:)`
    /// with no animator proxy) — this transition only ever scales the SwiftUI
    /// content already sitting inside that fixed frame. Reduce Motion drops the
    /// scale entirely in favor of a short plain fade.
    private var expandedPanelTransition: AnyTransition {
        reduceMotion ? .opacity.animation(.easeInOut(duration: 0.15)) : .dropdownUnfold
    }

    var body: some View {
        Group {
            if geometry.isBuiltIn {
                HStack(spacing: geometry.protectedGap) {
                    leftWing
                    rightWing
                }
            } else {
                surface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityHint(keyboardEngaged ? "Keyboard engagement active. Tab moves through visible controls; Escape collapses." : "Activate Keyboard to begin bounded Overlay engagement.")
        .accessibilityValue(focusedSessionAccessibility)
        .overlay {
            if keyboardEngaged {
                RoundedRectangle(cornerRadius: IslandTheme.Radius.dropdown, style: .continuous)
                    .strokeBorder(IslandTheme.statusBlocked.opacity(0.85), lineWidth: 2)
                    .padding(1)
                    .accessibilityHidden(true)
            }
        }
        // AB-153: this ambient crossfade still governs the collapsed pill and
        // incidental chrome (e.g. the keyboard-focus ring below). The
        // expanded dropdown panel's own mount/unmount now carries its own
        // explicit `expandedPanelTransition` (scale-from-notch, asymmetric
        // easing) which takes precedence over this ambient animation for
        // that subtree — see `AnyTransition.dropdownUnfold`.
        .animation(.easeInOut(duration: adaptation.crossFadeDuration), value: presentation)
    }

    // AB-158 §1.2: when EXPANDED, `surface` already branches on `isExpanded`
    // internally, so forwarding to it (rather than re-branching) keeps the
    // expand/collapse mount point for this wing at a single tree location —
    // `expandedPanelTransition` attaches to exactly one node instead of
    // stacking with a redundant outer crossfade. When COLLAPSED, the ticket's
    // "map left wing → status/agent + activity glyph, right wing → 'N
    // Sessions' count" note means this wing must NOT reuse the combined
    // `collapsedSummary` pill (that's the non-built-in single-pill case) —
    // it gets its own left-only flap instead.
    @ViewBuilder private var leftWing: some View {
        if isExpanded {
            surface
        } else {
            collapsedLeftFlap
        }
    }

    @ViewBuilder private var rightWing: some View {
        if isExpanded {
            // AB-154 §1.3: "Island Overlay" / "Selected display only" were the
            // same stale title+subtitle pattern the primary `surface` header
            // just dropped (AC-1.3-a/b). This wing now renders the identical
            // shared `expandedHeaderRow` so both expanded call sites read
            // consistently, per the ticket's scope-boundaries note.
            VStack(alignment: .leading, spacing: 0) {
                expandedHeaderRow
                Spacer(minLength: 0)
            }
            .padding(14 * contentScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(IslandSurface(variant: .dropdownPanel))
            .transition(expandedPanelTransition)
            // AC-1.3-d: the header's text buttons are gone, but the actions
            // they drove must stay reachable — exposed here as named
            // VoiceOver/keyboard-rotor actions on the expanded panel itself.
            // Escape-collapse is unaffected: it is handled independently by
            // `IslandOverlayController`'s NSEvent monitor, not by this view.
            .accessibilityAction(named: Text("Engage Keyboard Navigation")) { onEngageKeyboard() }
            .accessibilityAction(named: Text("Collapse Overlay")) { onCollapse() }
        } else {
            // AB-158 §1.2 AC-1.2-c: this flap is the built-in display's RIGHT
            // wing — "Inspect / Expand" is gone; it now shows only the
            // session count, right-aligned toward the physical notch gap.
            collapsedRightFlap
        }
    }

    /// AB-158 §1.2: the built-in display's LEFT flap when collapsed —
    /// status/agent + activity glyph only (AC-1.2-b/d/e). No session count
    /// here; that lives in `collapsedRightFlap`.
    private var collapsedLeftFlap: some View {
        Button(action: onPrimaryClick) {
            HStack(spacing: 0) {
                collapsedLeadingContent
                Spacer(minLength: 8 * contentScale)
            }
            .padding(.horizontal, 16 * contentScale)
            .frame(maxWidth: .infinity, minHeight: 56 * contentScale, alignment: .leading)
        }
        .buttonStyle(.plain)
        .modifier(IslandSurface())
        .accessibilityLabel(collapsedLeftFlapAccessibilityLabel)
    }

    /// AB-158 §1.2 AC-1.2-c: the built-in display's RIGHT flap when
    /// collapsed — "N Sessions" only, right-aligned.
    private var collapsedRightFlap: some View {
        Button(action: onPrimaryClick) {
            HStack(spacing: 0) {
                Spacer(minLength: 8 * contentScale)
                collapsedSessionsCountLabel
            }
            .padding(.horizontal, 16 * contentScale)
            .frame(maxWidth: .infinity, minHeight: 56 * contentScale, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .modifier(IslandSurface())
        .accessibilityLabel(collapsedRightFlapAccessibilityLabel)
    }

    private var surface: some View {
        Group {
            if isExpanded {
                VStack(spacing: 0) {
                    expandedHeaderRow
                        .padding(14 * contentScale)
                    Divider()
                    HorizonMonitorView(
                        cards: cards,
                        ledgerRevision: ledgerRevision,
                        controller: horizon,
                        contentScale: displayPreferences.contentScale,
                        completionCardHeight: displayPreferences.completionCardHeight,
                        displayPreferences: displayPreferences,
                        onJumpToSession: onJumpToSession
                    )
                        .padding(10 * contentScale)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .modifier(IslandSurface(variant: .dropdownPanel))
                .transition(expandedPanelTransition)
                // AC-1.3-d: see the matching comment in `rightWing` — same
                // reachability preservation, shared here for the primary panel.
                .accessibilityAction(named: Text("Engage Keyboard Navigation")) { onEngageKeyboard() }
                .accessibilityAction(named: Text("Collapse Overlay")) { onCollapse() }
            } else {
                collapsedSummary
            }
        }
    }

    /// AB-158 §1.2: the non-built-in display's single collapsed pill —
    /// left-side status/glyph content plus the right-side "N Sessions"
    /// count in one row (AC-1.2-a through -f). The built-in display instead
    /// splits this same content across `collapsedLeftFlap`/`collapsedRightFlap`.
    private var collapsedSummary: some View {
        Button(action: onPrimaryClick) {
            HStack(spacing: 8 * contentScale) {
                collapsedLeadingContent
                Spacer(minLength: 8 * contentScale)
                collapsedSessionsCountLabel
            }
            .padding(.horizontal, 16 * contentScale)
            .frame(maxWidth: .infinity, minHeight: 56 * contentScale)
        }
        .buttonStyle(.plain)
        .modifier(IslandSurface())
        .accessibilityLabel(collapsedAccessibilityLabel)
    }

    /// AB-158 §1.2: the most-relevant session to summarize in the collapsed
    /// pill, real `cards` state only — an attention-pending session first
    /// (it's the one the user most needs to see), else the first actively
    /// working session, else simply the first session. `nil` only when
    /// `cards` is genuinely empty.
    private var primaryCard: AgentSessionCardSnapshot? {
        cards.first(where: { $0.attention == .pending })
            ?? cards.first(where: { $0.visibleLifecycle == .working })
            ?? cards.first
    }

    /// AC-1.2-e's green activity glyph is keyed off this — real
    /// `visibleLifecycle`, not a guess.
    private var isPrimaryCardWorking: Bool {
        primaryCard?.visibleLifecycle == .working
    }

    /// AB-158 §1.2 AC-1.2-d: the collapsed pill's dynamic left-side status,
    /// derived only from real `cards` state — never fabricated.
    /// 1. If `primaryCard` has active subagent runs, name that ("Waiting on
    ///    N subagents", #7). "Active" mirrors the same working/waiting
    ///    filter `AlertCandidate.hasActiveChild` already uses
    ///    (`SessionDomain/AlertCandidate.swift:290`) — the identical real
    ///    signal another part of the app already trusts for "has an active
    ///    child," not a new invented rule.
    /// 2. Otherwise, name `primaryCard`'s Product as a real agent name
    ///    (`Claude`, amber, #11) via `agentDisplayName`.
    /// 3. If there is genuinely no session, fall back to a neutral, honest
    ///    "No Sessions" — never an invented agent name (the ticket's
    ///    explicit "never fabricate" instruction).
    private var collapsedStatus: (text: String, color: Color) {
        guard let card = primaryCard else {
            return ("No Sessions", IslandTheme.textSecondary)
        }
        let activeSubagents = card.subagentRuns.filter { $0.execution == .working || $0.execution == .waiting }.count
        if activeSubagents > 0 {
            let noun = activeSubagents == 1 ? "subagent" : "subagents"
            return ("Waiting on \(activeSubagents) \(noun)", IslandTheme.textSecondary)
        }
        return (Self.agentDisplayName(forProductNamespace: card.productNamespace), IslandTheme.accentAttention)
    }

    /// Real Product namespaces are adapter-owned raw strings — never a fixed
    /// enum (`ClaudeCodeAdapter.productNamespace` = "claude-code",
    /// `CodexCLIAdapter`/`CodexAppServerAdapter` = "codex-cli"/
    /// "codex-app-server", `CursorHooksAdapter`/`CursorACPAdapter` =
    /// "cursor"/"cursor.acp") — so this is a prefix map, not an exhaustive
    /// switch. An unrecognized namespace still renders its own real value
    /// (Title-cased), never a placeholder agent name.
    private static func agentDisplayName(forProductNamespace namespace: String) -> String {
        let lower = namespace.lowercased()
        if lower.hasPrefix("claude") { return "Claude" }
        if lower.hasPrefix("codex") { return "Codex" }
        if lower.hasPrefix("cursor") { return "Cursor" }
        if lower.hasPrefix("opencode") { return "OpenCode" }
        guard let first = namespace.first else { return "Agent" }
        return String(first).uppercased() + namespace.dropFirst()
    }

    /// AB-158 §1.2: the collapsed pill's shared LEFT-side content — small
    /// gray pixel-grid glyph (AC-1.2-b), the dynamic status text
    /// (AC-1.2-d), and, while `primaryCard` is actively working, the green
    /// activity glyph (AC-1.2-e). Shared by the non-built-in single pill
    /// (`collapsedSummary`) and the built-in display's left flap
    /// (`collapsedLeftFlap`) so both geometries read consistently, per the
    /// ticket's factoring note.
    @ViewBuilder private var collapsedLeadingContent: some View {
        HStack(spacing: 8 * contentScale) {
            IslandPixelGridGlyph()
                .accessibilityHidden(true)
            islandMonoLabel(collapsedStatus.text, size: 15 * contentScale, color: collapsedStatus.color)
            if isPrimaryCardWorking {
                IslandGreenActivityGlyph()
                    .accessibilityHidden(true)
            }
        }
    }

    /// AB-158 §1.2 AC-1.2-c: the collapsed pill's shared RIGHT-side "N
    /// Sessions" count, monospaced `textPrimary`. Shared the same way as
    /// `collapsedLeadingContent`.
    private var collapsedSessionsCountLabel: some View {
        islandMonoLabel("\(cards.count) Sessions", size: 15 * contentScale, color: IslandTheme.textPrimary, bold: true)
    }

    private var focusedSessionAccessibility: String {
        guard let index = focusedSessionIndex, !cards.isEmpty else { return "No Agent Session focused" }
        return "Focused Agent Session " + String(index + 1) + " of " + String(cards.count)
    }

    /// AB-158 §1.2: shared click-behavior hint text for every collapsed
    /// pill/flap's accessibility label — unchanged wording/meaning from
    /// before this ticket, just factored into one place since it's now
    /// quoted by three call sites instead of one.
    private var collapsedClickHint: String {
        clickBehavior == .jumpBack ? "Jump Back when revalidated" : "Inspect or expand"
    }

    /// The non-built-in single pill's full accessibility label — the
    /// dynamic status (so VoiceOver hears "Working…"/the agent name, per
    /// the ticket's accessibility note) plus the pre-existing attention
    /// count, session count, and click hint, verbatim.
    private var collapsedAccessibilityLabel: String {
        "\(collapsedStatus.text). \(attentionCount) Attention Requests; \(cards.count) Agent Sessions. \(collapsedClickHint)"
    }

    /// The built-in display's LEFT flap accessibility label — status only;
    /// the count lives on the right flap instead of being repeated here.
    private var collapsedLeftFlapAccessibilityLabel: String {
        "\(collapsedStatus.text). \(collapsedClickHint)"
    }

    /// The built-in display's RIGHT flap accessibility label — count only.
    private var collapsedRightFlapAccessibilityLabel: String {
        "\(cards.count) Agent Sessions. \(collapsedClickHint)"
    }

    /// AB-154 §1.3: the single shared header row for both expanded call
    /// sites (`surface`'s primary panel, and the built-in-notch `rightWing`
    /// flap). LEFT: the literal session count, bold monospaced `textPrimary`
    /// (AC-1.3-a). CENTER: AB-161 §1.4's multi-agent usage-stats cluster —
    /// AB-154 left this slot reserved and empty for exactly this ticket.
    /// RIGHT: the icon cluster (`overlayControls`).
    private var expandedHeaderRow: some View {
        HStack(alignment: .center, spacing: 10 * contentScale) {
            islandMonoLabel("\(cards.count) Sessions", size: 17 * contentScale, color: IslandTheme.textPrimary, bold: true)

            Spacer(minLength: 8 * contentScale)
            usageStatsCluster
            Spacer(minLength: 8 * contentScale)

            overlayControls
        }
    }

    /// AB-161 §1.4: the reserved center slot's content. A **focused** single
    /// session (AC-1.4-e) shows the DETAILED single-provider form for that
    /// session's own agent Product; every other expanded state (empty,
    /// multi-session list, permission-requested, etc. — #2/#8/#9) shows the
    /// COMPACT multi-provider cluster (AC-1.4-a/b/c/d). Both forms share the
    /// same "View usage details" hover affordance (AC-1.4-g).
    @ViewBuilder private var usageStatsCluster: some View {
        UsageDetailsHoverAffordance(contentScale: contentScale, onOpenUsageDetails: onOpenUsageDetails) {
            if presentation == .focused, let provider = focusedSessionQuotaProvider {
                DetailedProviderUsageView(
                    provider: provider,
                    snapshot: quotaBoard.snapshot(for: provider),
                    contentScale: contentScale
                )
            } else {
                CompactUsageStatsClusterView(
                    board: quotaBoard,
                    contentScale: contentScale,
                    onRefresh: onRefreshQuotaBoard
                )
            }
        }
    }

    /// AC-1.4-e: the focused session's own agent Product, mapped to the
    /// `QuotaProvider` whose windows the detailed form renders. Reuses the
    /// exact same prefix mapping as `agentDisplayName(forProductNamespace:)`
    /// below — real Product namespaces only, never a guess — just returning
    /// the typed `QuotaProvider` instead of a display string. `nil` when no
    /// session is focused, or when a focused session's namespace doesn't map
    /// to any of the four known quota providers (falls back to the compact
    /// cluster in that case, never a fabricated provider).
    private var focusedSessionQuotaProvider: QuotaProvider? {
        guard let index = focusedSessionIndex, cards.indices.contains(index) else { return nil }
        return Self.quotaProvider(forProductNamespace: cards[index].productNamespace)
    }

    private static func quotaProvider(forProductNamespace namespace: String) -> QuotaProvider? {
        let lower = namespace.lowercased()
        if lower.hasPrefix("claude") { return .claude }
        if lower.hasPrefix("codex") { return .codex }
        if lower.hasPrefix("cursor") { return .cursor }
        if lower.hasPrefix("opencode") { return .openCode }
        return nil
    }

    /// AB-154 §1.3: the header's right-edge icon cluster — a global mute
    /// toggle immediately left of a Settings gear (AC-1.3-c), both
    /// icon-only, `textSecondary`, flush to the trailing inset via the
    /// enclosing header row's own padding. Shared by both expanded headers
    /// (`surface` + `rightWing`) per the ticket's "refactor the shared
    /// `overlayControls`" guidance, which is how one change fixes both call
    /// sites at once.
    ///
    /// The header's previous text buttons ("Keyboard"/"Settings"/"Collapse")
    /// and their status-announcement lines lived in this same property.
    /// They are gone from the *visible* row (a clean single-row header per
    /// AC-1.3-e has no room for them), but nothing they carried is lost:
    /// `onEngageKeyboard`/`onCollapse` are now reachable as named
    /// accessibility actions on the enclosing expanded panel (see `surface`
    /// / `rightWing`), and the four status strings are preserved verbatim
    /// for VoiceOver by `statusAnnouncementElement` below.
    private var overlayControls: some View {
        HStack(spacing: 14 * contentScale) {
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 22 * contentScale, height: 22 * contentScale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 22 * contentScale, height: 22 * contentScale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .font(.system(size: 15 * contentScale, weight: .medium))
        .foregroundStyle(IslandTheme.textSecondary)
        .background(statusAnnouncementElement)
    }

    /// AB-154: an invisible (zero-size), accessibility-only carrier for the
    /// four status announcements that used to render as small visible
    /// `Text` lines under the old header buttons (keyboard-engagement hint,
    /// shortcut-invocation result, last click outcome, Jump Back result).
    /// The new header is a clean single row with no visual room for them
    /// (and #2/#8/#18 show none), but VoiceOver users still need the
    /// information, so each is kept — verbatim, same wording as before — as
    /// one combined label on a zero-frame element. Rendered only when at
    /// least one is present, so VoiceOver is never handed an empty
    /// announcement.
    @ViewBuilder private var statusAnnouncementElement: some View {
        let segments = statusAnnouncementSegments
        if !segments.isEmpty {
            Text(verbatim: "")
                .frame(width: 0, height: 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(segments.joined(separator: ". "))
        }
    }

    private var statusAnnouncementSegments: [String] {
        var segments: [String] = []
        if keyboardEngaged {
            segments.append("Keyboard engagement active. Escape collapses the overlay.")
        }
        if let shortcutInvocationAnnouncement {
            segments.append("Shortcut result: \(shortcutInvocationAnnouncement)")
        }
        if let lastClickOutcome {
            segments.append(lastClickOutcome.presentationLabel)
        }
        if let jumpBackAnnouncement {
            segments.append("Jump Back result: \(jumpBackAnnouncement)")
        }
        return segments
    }
}

// MARK: - AB-161 §1.4 — multi-agent usage-stats cluster
//
// Replaces the old single-provider `UsageSnapshotHeader` (one provider, one
// "Usage Snapshot · <provider>" title + a state pill) with the two forms the
// redesign doc specifies: a COMPACT multi-provider cluster for every
// non-focused expanded state, and a DETAILED single-provider form for the
// focused-session header. Both read from AB-157's `ProviderQuotaBoard`
// (`SessionDomain/ProviderQuotaState.swift`) — never from the retired
// single-value `UsageSnapshot` model. The `usage`/`UsagePresentationModel`
// plumbing on this view is left in place (still threaded by
// `IslandOverlayController`) since other code may still depend on it; this
// ticket only retires the internals that rendered it in this view.

/// AC-1.4-c/g: a small hover-tracking wrapper shared by both the compact and
/// detailed forms. `@State` is unavailable on this build's command-line
/// toolchain (see `HorizonMonitorView.swift`'s `HorizonController` doc
/// comment for the same constraint), so hover state lives on a tiny
/// `@StateObject`-held `ObservableObject` instead.
@MainActor
private final class UsageStatsHoverState: ObservableObject {
    @Published var isHovering = false
}

private struct UsageDetailsHoverAffordance<Content: View>: View {
    let contentScale: CGFloat
    let onOpenUsageDetails: (() -> Void)?
    let content: Content

    @StateObject private var hover = UsageStatsHoverState()

    init(contentScale: CGFloat, onOpenUsageDetails: (() -> Void)?, @ViewBuilder content: () -> Content) {
        self.contentScale = contentScale
        self.onOpenUsageDetails = onOpenUsageDetails
        self.content = content()
    }

    var body: some View {
        content
            // AC-1.4-g: "View usage details" floats BELOW the cluster on
            // hover via `.overlay`, which does not participate in the
            // parent's layout sizing — the header row never reflows/grows
            // when the affordance appears, it simply floats over whatever
            // sits underneath (the divider / session list).
            .overlay(alignment: .bottom) {
                if hover.isHovering {
                    Button {
                        onOpenUsageDetails?()
                    } label: {
                        Text("View usage details")
                            .font(IslandFont.mono(size: 10 * contentScale))
                            .foregroundStyle(IslandTheme.textSecondary)
                            .padding(.horizontal, 8 * contentScale)
                            .padding(.vertical, 3 * contentScale)
                            .background(IslandTheme.surfaceElevated, in: Capsule())
                            .overlay(Capsule().strokeBorder(IslandTheme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .offset(y: 18 * contentScale)
                    .transition(.opacity)
                }
            }
            .onHover { hovering in hover.isHovering = hovering }
            .animation(.easeOut(duration: 0.15), value: hover.isHovering)
    }
}

/// AC-1.4-a/b/c/d: the compact multi-provider cluster — a tappable refresh
/// glyph, then each percent-metered provider's brand mark + labeled window
/// percentages, monospaced `textSecondary` so columns align. Missing data
/// renders `--` (AC-1.4-b) — never `0%`, never hidden.
private struct CompactUsageStatsClusterView: View {
    let board: ProviderQuotaBoard
    let contentScale: CGFloat
    let onRefresh: () -> Void

    /// AB-161: which window kinds each provider's compact column renders —
    /// a fixed structural fact from the doc's own §1.4 note ("Claude &
    /// Codex → 5H+7D; Cursor → MO"), not derived from whether data happens
    /// to be present (an empty board must still show the right `--`
    /// columns, not zero columns). OpenCode is token-metered (no percent
    /// windows — see `ProviderQuotaState.swift`'s `TokenMeteredUsage`) and
    /// the doc's own compact-cluster example (#9) never shows a fourth
    /// column, so it has no column here.
    private static let columns: [(provider: QuotaProvider, windows: [QuotaWindowKind])] = [
        (.claude, [.fiveHour, .sevenDay]),
        (.codex, [.fiveHour, .sevenDay]),
        (.cursor, [.month]),
    ]

    var body: some View {
        HStack(spacing: 14 * contentScale) {
            Button(action: onRefresh) {
                Text("⟳")
                    .font(IslandFont.mono(size: 13 * contentScale, weight: .medium))
                    .foregroundStyle(IslandTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh usage")

            ForEach(Self.columns, id: \.provider) { column in
                ProviderCompactColumn(
                    provider: column.provider,
                    windows: column.windows,
                    snapshot: board.snapshot(for: column.provider),
                    contentScale: contentScale
                )
            }
        }
    }
}

private struct ProviderCompactColumn: View {
    let provider: QuotaProvider
    let windows: [QuotaWindowKind]
    let snapshot: ProviderQuotaSnapshot?
    let contentScale: CGFloat

    var body: some View {
        HStack(spacing: 6 * contentScale) {
            Text(provider.brandMarkGlyph)
                .font(IslandFont.mono(size: 13 * contentScale, weight: .semibold))
                .foregroundStyle(provider.brandMarkColor)
                .accessibilityHidden(true)

            ForEach(windows, id: \.self) { kind in
                windowLabel(kind)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func windowLabel(_ kind: QuotaWindowKind) -> some View {
        let percent = snapshot?.window(kind)?.percentConsumed
        return HStack(spacing: 2 * contentScale) {
            Text("\(kind.label):")
                .foregroundStyle(IslandTheme.textSecondary)
            if let percent {
                Text(Self.percentText(percent))
                    .foregroundStyle(IslandTheme.quotaColor(percentConsumed: percent))
            } else {
                Text("--")
                    .foregroundStyle(IslandTheme.textDim)
            }
        }
        .font(IslandFont.mono(size: 12 * contentScale, weight: .medium))
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private var accessibilityLabel: String {
        let parts = windows.map { kind -> String in
            if let percent = snapshot?.window(kind)?.percentConsumed {
                return "\(kind.label) \(Int(percent.rounded())) percent"
            }
            return "\(kind.label) no data"
        }
        return "\(provider.displayName): " + parts.joined(separator: ", ")
    }
}

/// AC-1.4-e: the focused-session header's detailed single-provider form —
/// a plain (non-badged — #18 is the newer capture and supersedes #10's
/// rounded-badge suggestion) brand mark, then each window's label, percent,
/// and compact time-until-reset, separated by `│`
/// (`5h 53% 8m │ 7d 25% 3d3h`).
private struct DetailedProviderUsageView: View {
    let provider: QuotaProvider
    let snapshot: ProviderQuotaSnapshot?
    let contentScale: CGFloat

    /// Same structural window list as the compact cluster's per-provider
    /// column — a provider's window shape doesn't change between the
    /// compact and detailed forms, only the amount of detail rendered per
    /// window.
    private var windows: [QuotaWindowKind] {
        switch provider {
        case .claude, .codex: return [.fiveHour, .sevenDay]
        case .cursor: return [.month]
        case .openCode: return []
        }
    }

    var body: some View {
        HStack(spacing: 8 * contentScale) {
            Text(provider.brandMarkGlyph)
                .font(IslandFont.mono(size: 13 * contentScale, weight: .semibold))
                .foregroundStyle(provider.brandMarkColor)
                .accessibilityHidden(true)

            ForEach(Array(windows.enumerated()), id: \.offset) { index, kind in
                if index > 0 {
                    Text("│").foregroundStyle(IslandTheme.textDim)
                }
                windowDetail(kind)
            }
        }
        .font(IslandFont.mono(size: 12 * contentScale, weight: .medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func windowDetail(_ kind: QuotaWindowKind) -> some View {
        let state = snapshot?.window(kind)
        return HStack(spacing: 4 * contentScale) {
            Text(kind.label.lowercased())
                .foregroundStyle(IslandTheme.textSecondary)
            if let percent = state?.percentConsumed {
                Text("\(Int(percent.rounded()))%")
                    .foregroundStyle(IslandTheme.quotaColor(percentConsumed: percent))
            } else {
                Text("--")
                    .foregroundStyle(IslandTheme.textDim)
            }
            Text(state?.compactTimeUntilReset ?? "--")
                .foregroundStyle(IslandTheme.textSecondary)
        }
    }

    private var accessibilityLabel: String {
        let parts = windows.map { kind -> String in
            let state = snapshot?.window(kind)
            let percentText = state?.percentConsumed.map { "\(Int($0.rounded())) percent" } ?? "no data"
            let timeText = state?.compactTimeUntilReset ?? "no reset time"
            return "\(kind.label.lowercased()) \(percentText), resets in \(timeText)"
        }
        return "\(provider.displayName) usage: " + parts.joined(separator: "; ")
    }
}

private struct IslandSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    /// AB-151: the panel/pill fill is the opaque `IslandTheme.surface`
    /// unconditionally — no translucent system material, and no
    /// `NSColor.windowBackgroundColor` fallback for reduced transparency,
    /// since an always-opaque surface has nothing left to reduce.
    ///
    /// AB-153: the EXPANDED panel and the COLLAPSED pill now follow
    /// different outlines, so this modifier is parameterized by `Variant`.
    /// The pill's shape/shadow are §1.2's ticket and are left exactly as
    /// AB-151 shipped them; only `.dropdownPanel` is new here.
    enum Variant: Equatable {
        /// The EXPANDED panel — square top edge flush with the notch, only
        /// the two bottom corners rounded at `IslandTheme.Radius.dropdown`
        /// (AC-1.1-b). Mirrors agent-notch's `NotchView.draw`
        /// (`/Users/abhishekthakur/Developer/agent-notch/main.swift:653-670`).
        /// No drop shadow: a dropdown flush with the notch shouldn't float
        /// (AC-1.1-a judgment call — the soft shadow fought the flush read).
        case dropdownPanel
        /// The COLLAPSED pill — unchanged uniform rounded rect + soft
        /// shadow, exactly as AB-151 left it. This is the default so every
        /// existing `.modifier(IslandSurface())` call site is unaffected.
        case pill
    }

    var variant: Variant = .pill

    /// Square top / rounded bottom outline. `UnevenRoundedRectangle` (macOS
    /// 13+; this package targets macOS 14) expresses per-corner radii
    /// directly, so both the fill and the border can share one shape
    /// instance instead of hand-rolling arcs — leading/trailing radii are
    /// identical here, so the shape is RTL-safe by symmetry.
    private var dropdownShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: IslandTheme.Radius.dropdown,
            bottomTrailingRadius: IslandTheme.Radius.dropdown,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    /// AB-158 §1.2 AC-1.2-a: a soft gray highlight brightening the collapsed
    /// pill's two OUTER edges (toward the screen edges), fading to nothing
    /// by the center. Layered ON TOP of the opaque `IslandTheme.surface`
    /// fill below — never replacing it, so the pill stays opaque near-black
    /// rather than reintroducing the washed-out translucent-gray look this
    /// ticket replaces (#1, the "before"). Both `.pill` call sites are
    /// collapsed-pill content only (`collapsedSummary`/`collapsedLeftFlap`/
    /// `collapsedRightFlap` in `IslandOverlayView.swift`), so this is safe to
    /// bake into the shared modifier rather than threading a new flag
    /// through every call site.
    private var collapsedWingGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.10), location: 0),
                .init(color: Color.white.opacity(0), location: 0.22),
                .init(color: Color.white.opacity(0), location: 0.78),
                .init(color: Color.white.opacity(0.10), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    func body(content: Content) -> some View {
        if variant == .dropdownPanel {
            content
                .background(IslandTheme.surface, in: dropdownShape)
                .overlay { dropdownShape.strokeBorder(IslandTheme.hairline, lineWidth: contrast == .increased ? 1.5 : 1) }
        } else {
            let pillShape = RoundedRectangle(cornerRadius: IslandTheme.Radius.dropdown, style: .continuous)
            content
                .background {
                    pillShape
                        .fill(IslandTheme.surface)
                        .overlay(pillShape.fill(collapsedWingGradient))
                }
                .overlay { pillShape.strokeBorder(IslandTheme.hairline, lineWidth: contrast == .increased ? 1.5 : 1) }
                .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
        }
    }
}

/// AB-153 §1.1-f: the expanded panel unfolds *out of* the notch — content
/// scales from a squashed (0.25, 0.06) footprint up to full size, anchored to
/// top-center, so growth reads as emerging from the menu bar rather than a
/// window fading in from nowhere. Ported from agent-notch's
/// `animatePanelLayer` (`/Users/abhishekthakur/Developer/agent-notch/main.swift:863-890`),
/// which explicitly avoids animating the NSWindow frame ("macOS interpolates
/// borderless window frames unreliably") and animates its CALayer instead —
/// the SwiftUI equivalent here is scaling the content view, never the hosting
/// panel's frame (that frame is already set synchronously, pre-sized, by
/// `IslandOverlayController.renderIfVisible()`).
private extension AnyTransition {
    static var dropdownUnfold: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.modifier(
                active: DropdownScaleModifier(x: 0.25, y: 0.06),
                identity: DropdownScaleModifier(x: 1, y: 1)
            )
            .combined(with: .opacity)
            .animation(.easeOut(duration: 0.22)),
            removal: AnyTransition.modifier(
                active: DropdownScaleModifier(x: 0.25, y: 0.06),
                identity: DropdownScaleModifier(x: 1, y: 1)
            )
            .combined(with: .opacity)
            .animation(.easeIn(duration: 0.22))
        )
    }
}

/// Anisotropic scale anchored top-center. SwiftUI's built-in
/// `AnyTransition.scale(scale:anchor:)` only takes one uniform factor; the
/// (0.25, 0.06) aspect from agent-notch needs independent x/y, hence this
/// small `Animatable` modifier wrapping `.scaleEffect(x:y:anchor:)`.
private struct DropdownScaleModifier: ViewModifier, @MainActor Animatable {
    var x: CGFloat
    var y: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }

    func body(content: Content) -> some View {
        content.scaleEffect(x: x, y: y, anchor: .top)
    }
}
