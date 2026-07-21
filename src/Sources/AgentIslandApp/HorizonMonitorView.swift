import AppKit
import SwiftUI
import Combine
import Foundation
import PresentationRuntime
import SessionDomain

/// AB-159 §1.6 AC-1.6-d: there is no violet token in `IslandTheme` yet — the
/// ticket explicitly calls for a local constant here (≈#9985F5) rather than
/// inventing a new theme-wide token for a single row state.
private let horizonActivityViolet = Color(red: 0.60, green: 0.52, blue: 0.96)

/// Horizon is a presentation-only view over revisioned, source-proven card
/// snapshots. It deliberately has no action or navigation dependencies: a
/// selection only opens local inline detail and never claims an Agent Product
/// action succeeded.
final class HorizonController: ObservableObject {
    @Published var isExpanded = true
    @Published var selectedID: String?

    /// AB-159 §1.6 AC-1.6-g: the subagent disclosure's expanded/collapsed
    /// state per card. A separate, independent property from `selectedID`
    /// (the inline-detail selection) — expanding the subagent list must not
    /// select the row, and selecting the row must not affect this disclosure.
    /// This lives on `HorizonController` rather than a SwiftUI `@State` on
    /// `HorizonMonitorView` because this build's command-line toolchain
    /// cannot expand the `@State` macro (`SwiftUIMacros` plugin unavailable
    /// outside Xcode.app — the same class of limitation already noted for
    /// `#Preview` in `IslandGlyphs.swift`); `@Published`/`@ObservedObject`
    /// compile fine here and this class is already the view's per-instance
    /// controller object.
    @Published var expandedSubagentIDs: Set<String> = []
}

struct HorizonMonitorView: View {
    let cards: [AgentSessionCardSnapshot]
    let ledgerRevision: Int64
    @ObservedObject var controller: HorizonController
    /// Presentation-only metrics supplied by Display settings. These do not
    /// alter the revisioned projection or any Product-owned state.
    var contentScale: Double = 1
    var completionCardHeight: Double = 220
    /// AB-163 §1.6: the Display-settings toggles that gate individual line-2
    /// metadata-strip fields on `HorizonSessionRow` (`showModelMetadata` →
    /// model, `showWorktreeMetadata` → branch, `showSubagentRunMetadata` →
    /// count — see `HorizonMetadataField.strip(for:displayPreferences:)`).
    /// Defaults to `.default` so every pre-existing call site (this ticket's
    /// scope is additive) keeps compiling without threading this explicitly;
    /// `IslandOverlayView` — the one call site that actually owns a real
    /// `AtlasDisplayPreferences` — passes its own value through instead.
    var displayPreferences: AtlasDisplayPreferences = .default
    /// AB-160 §1.10: the focused card's `⌃G ↗` jump control. `nil` in
    /// contexts with no navigation port to wire (e.g. `ContentView`'s dev
    /// fixture harness) — the control still renders unconditionally either
    /// way (§1.11: never gated), it simply has nothing to invoke.
    var onJumpToSession: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var attentionCount: Int {
        cards.filter { $0.attention == .pending }.count
    }

    private var focusCandidate: AgentSessionCardSnapshot? {
        cards.min { focusRank($0) < focusRank($1) }
    }

    private var density: HorizonRowDensity {
        switch cards.count {
        case 24...: return .dense
        case 12...: return .compact
        default: return .comfortable
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HorizonSummaryBar(
                cards: cards,
                attentionCount: attentionCount,
                isExpanded: controller.isExpanded,
                onToggle: {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 1)) {
                        controller.isExpanded.toggle()
                    }
                }
            )

            if controller.isExpanded {
                Divider()
                expandedFlow
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(IslandTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(IslandTheme.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Horizon Agent Session monitor")
    }

    private var expandedFlow: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: density == .comfortable ? 5 : 0) {
                if let focusCandidate {
                    HorizonFocusedSession(card: focusCandidate, onJump: onJumpToSession)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }

                if cards.isEmpty {
                    // AB-155: plain monospaced text, no SF Symbol — mirrors
                    // agent-notch's single-line empty state in SHAPE only.
                    // Two-tier brightness: brand ("Agent Island") is the
                    // brightest tier here (`textSecondary`), the rest of the
                    // heading and the subline sit one/two steps dimmer
                    // (`textDim`) so the pair reads as one calm, centered
                    // waiting state rather than two competing labels.
                    VStack(spacing: 6) {
                        (
                            Text("Agent Island")
                                .foregroundStyle(IslandTheme.textSecondary)
                            + Text(" · waiting for sessions")
                                .foregroundStyle(IslandTheme.textDim)
                        )
                        .font(IslandFont.stat)

                        Text("Run an agent session and it'll show up here.")
                            .font(IslandFont.subline)
                            .foregroundStyle(IslandTheme.textDim)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 0) {
                            HorizonSessionRow(
                                card: card,
                                isSelected: controller.selectedID == card.id,
                                density: card.id == focusCandidate?.id ? .comfortable : density,
                                displayPreferences: displayPreferences,
                                onSelect: { controller.selectedID = controller.selectedID == card.id ? nil : card.id }
                            )

                            // AC-1.6-g: subagent disclosure — a DIFFERENT
                            // affordance from row selection below, so it uses
                            // its own local toggle rather than `selectedID`.
                            if !card.subagentRuns.isEmpty {
                                HorizonSubagentDisclosure(
                                    card: card,
                                    isExpanded: controller.expandedSubagentIDs.contains(card.id),
                                    onToggle: {
                                        if controller.expandedSubagentIDs.contains(card.id) {
                                            controller.expandedSubagentIDs.remove(card.id)
                                        } else {
                                            controller.expandedSubagentIDs.insert(card.id)
                                        }
                                    }
                                )
                            }

                            if controller.selectedID == card.id {
                                HorizonSelectedDetail(
                                    card: card,
                                    completionCardHeight: completionCardHeight,
                                    contentScale: contentScale
                                )
                                    .padding(.leading, 36)
                                    .padding(.trailing, 12)
                                    .padding(.bottom, 8)
                            }
                        }
                        .id(card.id)
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .frame(maxHeight: 620)
        .accessibilityLabel("Chronological Agent Session flow")
        .accessibilityHint("Selecting a session reveals source-proven detail inline without changing its order.")
        .overlay(alignment: .bottomTrailing) {
            Text("Revision \(ledgerRevision)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(IslandTheme.textDim)
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    private func focusRank(_ card: AgentSessionCardSnapshot) -> Int {
        if card.attention == .pending { return 0 }
        if card.visibleLifecycle == .completed { return 1 }
        return 2
    }
}

private struct HorizonSummaryBar: View {
    let cards: [AgentSessionCardSnapshot]
    let attentionCount: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    private var statusText: String {
        if attentionCount > 0 { return "\(attentionCount) needs you" }
        if cards.contains(where: { $0.visibleLifecycle == .working }) { return "Working" }
        if cards.contains(where: { $0.visibleLifecycle == .completed }) { return "Completed activity" }
        // AB-155: reconciled with the empty-body copy ("waiting for
        // sessions") so the summary bar and the panel body agree.
        return cards.isEmpty ? "Waiting for sessions" : "Status available"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attentionCount > 0 ? "exclamationmark.diamond.fill" : "diamond")
                .foregroundStyle(attentionCount > 0 ? .orange : IslandTheme.textSecondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                Text("\(cards.count) Agent Session\(cards.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(IslandTheme.textSecondary)
            }

            Spacer(minLength: 16)

            if attentionCount > 0 {
                Text("Attention \(attentionCount)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.16), in: Capsule())
            }

            Button(isExpanded ? "Collapse" : "Show all") {
                onToggle()
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isExpanded ? "Collapse Agent Sessions" : "Show all Agent Sessions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusText); \(cards.count) Agent Sessions; \(attentionCount) Attention Requests")
    }
}

/// AB-160 §1.10: the focused single-session rich card (#10/#18). Anatomy,
/// top→bottom: title row (state glyph + truncated task title + trailing
/// agent/model/host/elapsed pills + the always-rendered `⌃G ↗` jump
/// control) · a multi-line agent-message body · a "You:" prompt inset with
/// a right-aligned status · a scrollable transcript excerpt. Every piece of
/// Interaction Content (the agent message, the prompt, the transcript
/// turns) comes only from `card.transcriptEvidence`, which is `nil` far
/// more often than not today — see the AB-160 report's "reader not yet
/// wired" note. Each sub-piece renders its own honest empty state rather
/// than hiding, so the card's shape stays stable whether or not transcript
/// evidence has arrived yet.
private struct HorizonFocusedSession: View {
    let card: AgentSessionCardSnapshot
    let onJump: (() -> Void)?

    private var isWorking: Bool { card.visibleLifecycle == .working }

    /// AC-1.10-c: "Done" for the terminal/completed case, else the same
    /// real status vocabulary `HorizonSessionRow` already uses — never a
    /// blanket "Done" for a failed/stopped session.
    private var statusText: String {
        card.visibleLifecycle == .completed ? "Done" : HorizonLabels.status(card)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HorizonFocusedTitleRow(card: card, onJump: onJump)
            HorizonFocusedMessageBody(text: card.transcriptEvidence?.latestAgentMessageText)
            HorizonFocusedYouInset(
                promptText: card.transcriptEvidence?.latestUserPromptText,
                statusText: statusText,
                isWorking: isWorking
            )
            HorizonFocusedTranscriptExcerpt(turns: card.transcriptEvidence?.recentTurns ?? [])
        }
        .padding(12)
        // AB-160: `surface` (one step darker than the panel's own
        // `surfaceElevated` background) so the focused card reads as an
        // inset element sitting inside the panel, matching
        // `IslandTheme.surfaceElevated`'s own doc comment ("one step up
        // from `surface`") — the "You:" inset below then goes back up to
        // `surfaceElevated`, the next step up from THIS card's own
        // background, for a consistent two-level depth stack rather than
        // two light surfaces stacked on each other.
        .background(IslandTheme.surface, in: RoundedRectangle(cornerRadius: IslandTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IslandTheme.Radius.card, style: .continuous)
                .strokeBorder(IslandTheme.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = ["Focused Agent Session", HorizonLabels.rowLabel(for: card)]
        if let message = card.transcriptEvidence?.latestAgentMessageText, !message.isEmpty {
            parts.append("Agent message: \(message)")
        }
        if let prompt = card.transcriptEvidence?.latestUserPromptText, !prompt.isEmpty {
            parts.append("Your prompt: \(prompt), \(statusText)")
        }
        return parts.joined(separator: ". ")
    }
}

/// AC-1.10-a: title row. `HorizonStateMark` + the working-only green
/// activity glyph (AC-1.10-e) lead; the truncating task title fills the
/// remaining width (`layoutPriority(-1)` + `frame(maxWidth: .infinity)`,
/// the identical recipe `HorizonSessionRow`'s activity text already uses,
/// so the trailing pills and jump control are the protected, never-
/// truncated elements); the pills and jump control trail.
private struct HorizonFocusedTitleRow: View {
    let card: AgentSessionCardSnapshot
    let onJump: (() -> Void)?

    private var isWorking: Bool { card.visibleLifecycle == .working }

    /// AC-1.10-a: "the `task` portion = `card.displayTitle`; the `project`
    /// portion — use a real source if available … if there's no real
    /// project field, render just the task (do not invent a repo name)."
    /// `AgentSessionCardSnapshot` has no repo/workspace field — `hostLabel`
    /// (the launching app, e.g. "Cursor") and `productNamespace` (the agent
    /// product, e.g. "claude-code") are both already surfaced verbatim as
    /// their own dedicated pills below, and reusing either one again here as
    /// a fake "project" prefix would misrepresent an app/agent identity as a
    /// workspace name. So this takes the ticket's own explicit fallback:
    /// render just the task.
    private var title: String { card.displayTitle ?? card.nativeSessionID }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            HorizonStateMark(card: card)
                .frame(width: 15, height: 15)
                .accessibilityHidden(true)

            if isWorking {
                IslandGreenActivityGlyph()
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(IslandFont.mono(size: 13, weight: .semibold))
                .foregroundStyle(IslandTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HorizonFocusedPills(card: card)
            HorizonFocusedJumpButton(onJump: onJump)
        }
    }
}

/// AC-1.10-a's trailing pill cluster — agent (brand-tinted) / model / host /
/// elapsed. Model and host are both genuinely optional and omit cleanly
/// (never a fabricated "Opus 4.8" or invented host) — agent and elapsed
/// always have a real value (`HorizonLabels.agentDisplayName` never
/// fabricates past its own real-namespace prefix map, and
/// `HorizonLabels.compactElapsed` already renders "—" for a nil date).
private struct HorizonFocusedPills: View {
    let card: AgentSessionCardSnapshot

    private var agent: String { HorizonLabels.agentDisplayName(forProductNamespace: card.productNamespace) }
    private var agentTint: Color { HorizonLabels.brandTint(forProductNamespace: card.productNamespace) }

    var body: some View {
        HStack(spacing: 4) {
            HorizonPill(text: agent, tint: agentTint)
            if let model = card.transcriptEvidence?.modelFromTranscript,
               !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HorizonPill(text: model, tint: IslandTheme.textSecondary)
            }
            if let host = card.hostLabel, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HorizonPill(text: host, tint: IslandTheme.textSecondary)
            }
            HorizonPill(text: HorizonLabels.compactElapsed(card.sourceLastUpdated), tint: IslandTheme.textDim)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HorizonPill: View {
    let text: String
    var tint: Color = IslandTheme.textSecondary

    var body: some View {
        Text(text)
            .font(IslandFont.mono(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// AC-1.10-a: the `⌃G ↗` jump control. This ALWAYS renders — there is no
/// paywall/entitlement gate on Jump (§1.11) — regardless of whether `onJump`
/// is wired to a real handler in this context. See
/// `IslandOverlayController.jumpToFocusedSession()` for the real behavior
/// this maps to in the shipping app.
private struct HorizonFocusedJumpButton: View {
    let onJump: (() -> Void)?

    var body: some View {
        Button {
            onJump?()
        } label: {
            Text("⌃G ↗")
                .font(IslandFont.mono(size: 10, weight: .semibold))
                .foregroundStyle(IslandTheme.textSecondary)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(IslandTheme.hairline, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to session")
        .accessibilityHint("Keyboard shortcut Control G. Opens this session's terminal or IDE window when a Host association is available.")
    }
}

/// AC-1.10-b: the agent's current message as multi-line, wrapping body
/// text — never a one-line status. Honest empty state when transcript
/// evidence hasn't arrived (the common case today).
private struct HorizonFocusedMessageBody: View {
    let text: String?

    private var trimmed: String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    var body: some View {
        Text(trimmed ?? "No agent message captured yet.")
            .font(IslandFont.mono(size: 12))
            .foregroundStyle(trimmed == nil ? IslandTheme.textDim : IslandTheme.textSecondary)
            .multilineTextAlignment(.leading)
            .lineLimit(6)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// AC-1.10-c: the "You:" inset — a rounded `surfaceElevated` sub-card (one
/// step up from the focused card's own `surface` background) holding the
/// user's last prompt, with a right-aligned status (`Done` once terminal,
/// else a green working indicator). Honest empty state when no prompt has
/// been captured.
private struct HorizonFocusedYouInset: View {
    let promptText: String?
    let statusText: String
    let isWorking: Bool

    private var trimmed: String? {
        guard let promptText, !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return promptText
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("You:")
                .font(IslandFont.mono(size: 11, weight: .semibold))
                .foregroundStyle(IslandTheme.textSecondary)

            Text(trimmed ?? "No prompt captured yet.")
                .font(IslandFont.mono(size: 11))
                .foregroundStyle(trimmed == nil ? IslandTheme.textDim : IslandTheme.textPrimary)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                if isWorking {
                    IslandGreenActivityGlyph()
                        .accessibilityHidden(true)
                }
                Text(statusText)
                    .font(IslandFont.mono(size: 10, weight: .semibold))
                    .foregroundStyle(isWorking ? IslandTheme.allowGreen : IslandTheme.textSecondary)
            }
        }
        .padding(8)
        .background(IslandTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: IslandTheme.Radius.button, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// AC-1.10-d: the scrollable transcript excerpt. A bounded-height
/// `ScrollView` with a visible native scrollbar
/// (`.scrollIndicators(.visible)`) over `card.transcriptEvidence?.recentTurns`
/// — stored oldest-first, rendered in that same order. Each turn is
/// visually distinguished by role (green "You" label vs. dim "Agent"
/// label) rather than by inventing separate bubble chrome per role.
private struct HorizonFocusedTranscriptExcerpt: View {
    let turns: [TranscriptTurnProjection]

    var body: some View {
        if turns.isEmpty {
            Text("No transcript excerpt captured yet.")
                .font(IslandFont.mono(size: 11))
                .foregroundStyle(IslandTheme.textDim)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                        HorizonFocusedTranscriptTurnRow(turn: turn)
                    }
                }
                .padding(.trailing, 6)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: 130)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Transcript excerpt, \(turns.count) turns")
        }
    }
}

private struct HorizonFocusedTranscriptTurnRow: View {
    let turn: TranscriptTurnProjection

    private var isUser: Bool { turn.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(isUser ? "You" : "Agent")
                .font(IslandFont.mono(size: 9, weight: .bold))
                .foregroundStyle(isUser ? IslandTheme.allowGreen : IslandTheme.textSecondary)
                .frame(width: 34, alignment: .leading)
            Text(turn.text)
                .font(IslandFont.mono(size: 11))
                .foregroundStyle(isUser ? IslandTheme.textPrimary : IslandTheme.textSecondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "Agent"): \(turn.text)")
    }
}

private enum HorizonRowDensity {
    case comfortable
    case compact
    case dense
}

/// AB-159 §1.6: the dense "Line 1" activity row — `AC-1.6-a/b/d/e/f`.
/// Anatomy, left→right (all monospaced): state-tinted pixel-grid glyph ·
/// bold session/project name · a small window glyph · the truncating
/// activity/status element · right-aligned elapsed + (pending) `esc` hint +
/// launching-app icon + `›` expand chevron. Subagent disclosure (AC-1.6-g)
/// is a sibling under this row, not part of it — see `expandedFlow`'s
/// `ForEach`.
///
/// AB-163 §1.6 AC-1.6-c added **line 2**: a `VStack` under line 1 holding
/// `HorizonSessionMetadataStrip`, mounted only when
/// `HorizonMetadataField.strip(for:displayPreferences:)` produces at least
/// one field — so a row with nothing to show (no toggles on, no transcript
/// evidence yet) renders byte-identical to the pre-AB-163 single-line row,
/// with no residual gap under line 1.
private struct HorizonSessionRow: View {
    let card: AgentSessionCardSnapshot
    let isSelected: Bool
    let density: HorizonRowDensity
    let displayPreferences: AtlasDisplayPreferences
    let onSelect: () -> Void

    private var activity: HorizonActivityVariant { HorizonLabels.activityVariant(for: card) }

    /// AC-1.6-c's field list, in the #9 order. Computed once per body pass
    /// so both the "should line 2 mount at all" check and the strip's own
    /// content read the exact same list — no risk of the two disagreeing.
    private var metadataFields: [HorizonMetadataField] {
        HorizonMetadataField.strip(for: card, displayPreferences: displayPreferences)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    HorizonStateMark(card: card)
                        .frame(width: 18, height: 16)

                    Text(card.displayTitle ?? card.nativeSessionID)
                        .font(IslandFont.mono(size: 13, weight: .semibold))
                        .foregroundStyle(IslandTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    // AB-159: a small decorative "window" glyph between the
                    // session name and the activity element (AC-1.6-b's order).
                    // No reference screenshot ships with this ticket, so the
                    // exact iconography is a judgment call — a small dim SF
                    // Symbol standing in for "which window/terminal this is
                    // running in," kept purely decorative.
                    Image(systemName: "macwindow")
                        .font(.system(size: 9))
                        .foregroundStyle(IslandTheme.textDim)
                        .accessibilityHidden(true)

                    Text(activity.text)
                        .font(IslandFont.mono(size: 12))
                        .foregroundStyle(activity.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HorizonTrailingCluster(card: card)
                }

                // AC-1.6-c: line 2 only mounts when there is at least one
                // real field to show — never an empty strip reserving a
                // blank line under line 1.
                if !metadataFields.isEmpty {
                    HorizonSessionMetadataStrip(fields: metadataFields)
                        // Aligns line 2's leading edge under line 1's
                        // session name: the 18pt state-mark frame + this
                        // HStack's own 8pt spacing above.
                        .padding(.leading, 26)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, density == .comfortable ? 9 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? IslandTheme.hairline : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // AC-1.6-a: the dithered pixel separator replaces the flat 1px
        // `Divider()` this row used to overlay at its bottom edge.
        .overlay(alignment: .bottom) { IslandDitherSeparatorGlyph() }
        .accessibilityLabel(HorizonLabels.rowLabel(for: card))
        .accessibilityHint(isSelected ? "Selected. Activate to hide inline detail." : "Activate to show inline detail.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// AB-163 §1.6 AC-1.6-c: the session row's line-2 metadata strip — a
/// left-to-right run of small stats in #9's exact reading order: model ·
/// branch · tokens · context % · memory · disk I/O · cost · count · diff.
/// Monospaced, `IslandTheme.textSecondary` throughout except the diff
/// field's own green/red per-number colouring. Every field is independently
/// optional; `HorizonMetadataField.strip(for:displayPreferences:)` (below)
/// never appends one that lacks real data or whose Display-settings toggle
/// is off, so this plain `HStack` only ever spaces the fields that are
/// actually present — there is no separator glyph between fields (matching
/// `HorizonSessionRow`'s own line-1 convention of spacing, not literal `·`
/// characters, between elements) and so no dangling gap where an absent
/// field would have sat.
///
/// **Only three fields have a real data source today**: **model**
/// (`card.model` — transcript-derived, AB-160), **tokens**
/// (`card.transcriptEvidence?.latestUsage` — AB-156/160), and **count**
/// (`card.subagentRuns.count`). The rest render their correct glyph, colour,
/// and format the moment a real value exists, but that value is an
/// explicit, documented `nil` today:
///
/// - **branch**: no cwd/git-branch field exists anywhere on
///   `AgentSessionCardSnapshot`/`SessionProjection` (confirmed: no
///   `gitBranch`/`cwd` property on either type, and no adapter surfaces one
///   to the projection).
/// - **context %, cost, diff**: Claude Code's statusline JSON carries these
///   under real, *verified* field names —
///   `context_window.used_percentage`, `cost.total_cost_usd`,
///   `cost.total_lines_added`/`cost.total_lines_removed` — confirmed
///   against the official documentation
///   (`https://code.claude.com/docs/en/statusline.md`, "Full JSON schema"
///   section) rather than guessed. `ClaudeStatusLineBridge.swift` already
///   installs Agent Island as the person's Claude Code `statusLine` command
///   (`ClaudeStatusLineBridgeEditor.selector()` points at
///   `.../AgentIslandUsageStatusLine`), but that executable target does not
///   exist in this package yet (`Package.swift` has no such product/target)
///   and nothing reads, persists, or correlates the JSON it would receive
///   on stdin to a session. Building that consumer for real needs a new
///   executable target, a way for that short-lived per-invocation process
///   to hand its parsed JSON to this long-running app (no such IPC/store
///   exists today), and session-id correlation — a second evidence path on
///   the scale of AB-156 (transcript reading), not a line-2 layout ticket.
///   The same verified schema also carries `workspace.git_worktree`/
///   `worktree.branch`, so once this pipeline exists it can unblock
///   **branch** too, not just context %/cost/diff.
/// - **memory / disk I/O**: Q4④ — OS process metrics keyed by the
///   session's real PID, which nothing on the card carries today.
private struct HorizonSessionMetadataStrip: View {
    let fields: [HorizonMetadataField]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(fields) { field in
                field.body
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One field in the line-2 metadata strip. `.diff` is its own case (not
/// `.plain`) because AC-1.6-c calls for two independently-coloured numbers
/// (green added / red removed) rather than one tinted string.
private enum HorizonMetadataField: Identifiable {
    /// `icon` is `nil` for fields whose leading glyph is baked directly into
    /// `text` per #9's own literal examples (tokens' `↑`, cost's `$`,
    /// count's `▭`) rather than a separate SF Symbol.
    case plain(id: String, icon: String?, text: String)
    case diff(addedLines: Int, removedLines: Int)

    var id: String {
        switch self {
        case .plain(let id, _, _): return id
        case .diff: return "diff"
        }
    }

    @ViewBuilder
    var body: some View {
        switch self {
        case .plain(_, let icon, let text):
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundStyle(IslandTheme.textDim)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(IslandFont.mono(size: 11))
                    .foregroundStyle(IslandTheme.textSecondary)
            }
            .lineLimit(1)
            .fixedSize()
        case .diff(let added, let removed):
            (
                Text("+\(added) ").foregroundStyle(IslandTheme.allowGreen)
                + Text("−\(removed)").foregroundStyle(IslandTheme.denyRed)
            )
            .font(IslandFont.mono(size: 11))
            .lineLimit(1)
            .fixedSize()
        }
    }
}

private extension HorizonMetadataField {
    /// AC-1.6-c: builds the line-2 field list in the #9 order — model ·
    /// branch · tokens · context % · memory · disk I/O · cost · count ·
    /// diff. See `HorizonSessionMetadataStrip`'s doc comment for exactly
    /// which fields have a real source today and which are documented,
    /// honest `nil`s.
    static func strip(for card: AgentSessionCardSnapshot, displayPreferences: AtlasDisplayPreferences) -> [HorizonMetadataField] {
        var fields: [HorizonMetadataField] = []

        // model — real, transcript-derived (`card.model`, AB-160). Gated on
        // the one Display-settings toggle the ticket names explicitly.
        if displayPreferences.showModelMetadata,
           let model = card.model?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            fields.append(.plain(id: "model", icon: "cpu", text: model))
        }

        // branch — AB-163 gap (see `HorizonSessionMetadataStrip`'s doc
        // comment): no source exists. `branchName` is kept as an explicit
        // local `nil` — not omitted from the code — so the toggle gate and
        // glyph/format are real, reviewable, and ready the moment a source
        // is wired, rather than only a comment promising future behavior.
        let branchName: String? = nil
        if displayPreferences.showWorktreeMetadata, let branch = branchName {
            fields.append(.plain(id: "branch", icon: "arrow.triangle.branch", text: branch))
        }

        // tokens — real, transcript-derived (AB-156/160's `latestUsage`).
        // No Display-settings toggle names this field, so per the ticket's
        // own rule ("where no specific toggle maps to a field, render it
        // ungated") this is presence-gated only.
        if let usage = card.transcriptEvidence?.latestUsage {
            fields.append(.plain(id: "tokens", icon: nil, text: HorizonLabels.tokensText(usage)))
        }

        // context % — AB-163 gap: verified real field
        // (`context_window.used_percentage`), never wired to this card yet.
        let contextUsedPercent: Int? = nil
        if let percent = contextUsedPercent {
            fields.append(.plain(id: "context", icon: "gauge", text: "\(percent)%"))
        }

        // memory — Q4④ gap: OS process metrics keyed by a real per-session
        // PID the card doesn't carry. Never sourced.
        let memoryFootprintText: String? = nil
        if let memory = memoryFootprintText {
            fields.append(.plain(id: "memory", icon: "memorychip", text: memory))
        }

        // disk I/O — same Q4④ gap as memory.
        let diskIOText: String? = nil
        if let diskIO = diskIOText {
            fields.append(.plain(id: "disk", icon: "internaldrive", text: diskIO))
        }

        // cost — AB-163 gap: verified real field (`cost.total_cost_usd`),
        // never wired to this card yet.
        let sessionCostText: String? = nil
        if let cost = sessionCostText {
            fields.append(.plain(id: "cost", icon: nil, text: cost))
        }

        // count — `subagentRuns.count`, deliberately not `turns.count`:
        // mirrors the existing `showSubagentRunMetadata` toggle and the
        // `HorizonSubagentDisclosure` already on this same row, so the
        // count in line 2 and the disclosure directly below it always
        // agree. `turns.count` was rejected because a session's turn count
        // is usually large and already implied by elapsed time/activity —
        // it would not read as the same kind of "batch" stat #9's `▭`
        // glyph suggests.
        if displayPreferences.showSubagentRunMetadata, !card.subagentRuns.isEmpty {
            fields.append(.plain(id: "count", icon: nil, text: "▭ \(card.subagentRuns.count)"))
        }

        // diff — AB-163 gap: verified real fields
        // (`cost.total_lines_added`/`cost.total_lines_removed`), never
        // wired to this card yet.
        let diffStat: (added: Int, removed: Int)? = nil
        if let diff = diffStat {
            fields.append(.diff(addedLines: diff.added, removedLines: diff.removed))
        }

        return fields
    }
}

/// AC-1.6-b's right-hand cluster: elapsed (compact `2m`/`58m`/`Nh`/`now`),
/// the `esc` hint while attention is pending (AC-1.6-f), the launching-app
/// icon when resolvable (never fabricated), and the trailing `›` chevron.
private struct HorizonTrailingCluster: View {
    let card: AgentSessionCardSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Text(HorizonLabels.compactElapsed(card.sourceLastUpdated))
                .font(IslandFont.mono(size: 11))
                .foregroundStyle(IslandTheme.textDim)
                .lineLimit(1)
                .accessibilityHidden(true)

            if card.attention == .pending {
                Text("esc")
                    .font(IslandFont.mono(size: 10))
                    .foregroundStyle(IslandTheme.textDim)
                    .accessibilityHidden(true)
            }

            HorizonLaunchingAppIcon(hostLabel: card.hostLabel)

            Text("›")
                .font(IslandFont.mono(size: 13, weight: .semibold))
                .foregroundStyle(IslandTheme.textDim)
                .accessibilityHidden(true)
        }
    }
}

/// AC-1.6-b's launching-app icon. Resolved only from a real running
/// application whose `localizedName` matches `card.hostLabel` (e.g.
/// "Warp"/"iTerm2") via `NSWorkspace` — never a fabricated or generic
/// placeholder icon. When no match is found, this renders nothing: the
/// ticket explicitly prefers clean omission over a wrong or SF-Symbol
/// stand-in icon here.
private struct HorizonLaunchingAppIcon: View {
    let hostLabel: String?

    private var resolvedIcon: NSImage? {
        guard let hostLabel, !hostLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.caseInsensitiveCompare(hostLabel) == .orderedSame
        }?.icon
    }

    var body: some View {
        if let resolvedIcon {
            Image(nsImage: resolvedIcon)
                .resizable()
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        }
    }
}

/// AC-1.6-g: the `▸ N subagents` / `▾ N subagents` disclosure toggle under a
/// session row that has subagent runs, plus its expanded child rows. Copied
/// in shape from agent-notch's toggle button (`main.swift:332-348`) and
/// `childRow` (`main.swift:365-394`).
private struct HorizonSubagentDisclosure: View {
    let card: AgentSessionCardSnapshot
    let isExpanded: Bool
    let onToggle: () -> Void

    private var count: Int { card.subagentRuns.count }
    private var noun: String { count == 1 ? "subagent" : "subagents" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onToggle) {
                Text("\(isExpanded ? "▾" : "▸") \(count) \(noun)")
                    .font(IslandFont.mono(size: 10, weight: .semibold))
                    .foregroundStyle(IslandTheme.statusBlocked)
            }
            .buttonStyle(.plain)
            .padding(.leading, 24)
            .accessibilityLabel("\(count) \(noun), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint(isExpanded ? "Activate to collapse the subagent list." : "Activate to expand the subagent list.")

            if isExpanded {
                // agent-notch caps the expanded list at 8 children; mirrored
                // here verbatim.
                ForEach(card.subagentRuns.prefix(8), id: \.nativeSubagentRunID) { run in
                    HorizonSubagentChildRow(run: run)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// AC-1.6-g's expanded child row. `SubagentRunProjection` carries no
/// task-description field, so — HONESTY — this labels the child only by its
/// real `nativeSubagentRunID` and its real `execution` state
/// (`HorizonLabels.execution`), never a fabricated task string.
private struct HorizonSubagentChildRow: View {
    let run: SubagentRunProjection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(run.nativeSubagentRunID)
                .font(IslandFont.mono(size: 11, weight: .semibold))
                .foregroundStyle(IslandTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Text(HorizonLabels.execution(run.execution))
                .font(IslandFont.mono(size: 9))
                .foregroundStyle(IslandTheme.textDim)
                .lineLimit(1)
        }
        .padding(.leading, 28)
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Subagent \(run.nativeSubagentRunID), \(HorizonLabels.execution(run.execution))")
    }
}

private struct HorizonSelectedDetail: View {
    let card: AgentSessionCardSnapshot
    let completionCardHeight: Double
    let contentScale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Agent Session")
                .font(.caption.weight(.bold))
                .foregroundStyle(IslandTheme.textSecondary)

            Text("Source identity: \(card.productNamespace) / \(card.nativeSessionID)")
                .font(.caption.monospaced())
                .textSelection(.enabled)

            Text("Continuity: \(card.lineage.rawValue) • Observation: \(card.observation.rawValue)")
                .font(.caption)
                .foregroundStyle(IslandTheme.textSecondary)

            if card.visibleLifecycle == .completed {
                HorizonCompletionRecap(minHeight: completionCardHeight * contentScale)
            }

            if !card.subagentRuns.isEmpty {
                HorizonSubagentRuns(card: card)
            }
        }
        .padding(9)
        .background(IslandTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected detail for \(card.nativeSessionID)")
    }
}

/// The current boundary supplies operational metadata only. Keep completion
/// honest by reserving a recap slot instead of inventing Product result text.
private struct HorizonCompletionRecap: View {
    let minHeight: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "text.alignleft")
                .accessibilityHidden(true)
            Text("No source-proven completion recap received")
                .font(.caption)
        }
        .frame(minHeight: minHeight)
        .foregroundStyle(IslandTheme.textSecondary)
        .accessibilityLabel("No source-proven completion recap received")
    }
}

private struct HorizonSubagentRuns: View {
    let card: AgentSessionCardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Subagent Runs")
                .font(.caption.weight(.semibold))
            ForEach(card.subagentRuns, id: \.nativeSubagentRunID) { run in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(IslandTheme.textSecondary)
                            .accessibilityHidden(true)
                        Text("Subagent Run \(run.nativeSubagentRunID)")
                            .font(.caption.monospaced())
                        Text(HorizonLabels.execution(run.execution))
                            .font(.caption)
                            .foregroundStyle(IslandTheme.textSecondary)
                    }
                    if let ownerTurnID = run.ownerNativeTurnID {
                        Text("Under Turn \(ownerTurnID)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(IslandTheme.textDim)
                            .padding(.leading, 22)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Subagent Run \(run.nativeSubagentRunID), under Turn \(run.ownerNativeTurnID ?? "unavailable"), \(HorizonLabels.execution(run.execution))")
            }
        }
        .padding(.top, 2)
    }
}

/// AC-1.6-e: the row's leading square pixel-grid glyph, tinted by real
/// session state — salmon = Claude idle/identity, green = actively working,
/// blue/steel = blocked awaiting permission. This replaces the previous
/// six-way SF Symbol lifecycle glyph (diamond/exclamation/checkmark/stop/x/
/// question) with the AC's literal three-state mapping; the glyph was
/// already `accessibilityHidden` (purely decorative), so no VoiceOver
/// information is lost, and terminal states (completed/stopped/failed) still
/// read from the row's own status text.
private struct HorizonStateMark: View {
    let card: AgentSessionCardSnapshot

    private var tint: Color {
        if card.attention == .pending { return IslandTheme.statusBlocked }
        if card.visibleLifecycle == .working && card.execution == .working { return IslandTheme.allowGreen }
        return HorizonLabels.brandTint(forProductNamespace: card.productNamespace)
    }

    var body: some View {
        IslandPixelGridGlyph(tint: tint)
            .accessibilityHidden(true)
    }
}

/// AC-1.6-d: the row's activity/status element — three real-state-derived
/// variants, each visually distinct from the gray metadata around it, plus a
/// `quiet` fourth case for terminal/other states that AC-1.6-d does not
/// define a variant for (so those rows never render an empty activity slot).
/// HONESTY: none of these carry a fabricated shell command or task string —
/// see `HorizonLabels.activityVariant(for:)`.
private enum HorizonActivityVariant: Equatable {
    /// Actively running, no real command text available on the card yet
    /// (that's AB-163/transcript work) — a truthful "<Agent> Working" stands
    /// in, never an invented `rtk curl …` line.
    case running(String)
    /// `attention == .pending && execution == .waiting`, or simply
    /// `execution == .waiting` outside an attention request: the agent has
    /// yielded back to the user.
    case waitingOnYou(String)
    /// `attention == .pending` with the underlying execution still
    /// `.working` — read as blocked on a tool/permission gate. The literal
    /// command is Interaction Content, not on this card, so the copy stops
    /// at "Waiting to run…" rather than naming a fabricated command.
    case waitingOnPermission
    /// Terminal/other states: plain, real status text (`Completed`, `Failed`, …).
    case quiet(String)

    var color: Color {
        switch self {
        case .running: return horizonActivityViolet
        case .waitingOnYou: return IslandTheme.allowGreen
        case .waitingOnPermission, .quiet: return IslandTheme.textDim
        }
    }

    var text: String {
        switch self {
        case .running(let phrase): return phrase
        case .waitingOnYou(let phrase): return phrase
        case .waitingOnPermission: return "Waiting to run…"
        case .quiet(let phrase): return phrase
        }
    }
}

private enum HorizonLabels {
    static func status(_ card: AgentSessionCardSnapshot) -> String {
        switch card.visibleLifecycle {
        case .working: return card.execution == .waiting ? "Waiting" : "Working"
        case .needsAttention: return "Needs attention"
        case .completed: return "Completed"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        case .unresolved: return "Unresolved"
        }
    }

    static func execution(_ execution: ExecutionState) -> String {
        switch execution {
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .terminalCompleted: return "Completed"
        case .terminalFailed: return "Failed"
        case .terminalStopped: return "Stopped"
        case .unresolved: return "Unresolved"
        }
    }

    /// AC-1.6-d's variant selection. Precedence, in order:
    /// 1. `attention == .pending` — a blocking attention request. If the
    ///    underlying `execution` already moved to `.waiting`, the agent is
    ///    waiting on a reply (green); otherwise it's still `.working`
    ///    underneath, read as blocked on a permission/tool gate (dim gray).
    /// 2. `visibleLifecycle == .working && execution == .working` — actively
    ///    running, no attention request (violet).
    /// 3. `execution == .waiting` outside any attention request — the agent
    ///    yielded back to the user same as case 1's green branch.
    /// 4. Anything else (terminal/unresolved) — quiet, real status text.
    static func activityVariant(for card: AgentSessionCardSnapshot) -> HorizonActivityVariant {
        let agent = agentDisplayName(forProductNamespace: card.productNamespace)
        let waitingOnYouPhrase = "💬 \(agent) is waiting for your input"
        if card.attention == .pending {
            if card.execution == .waiting { return .waitingOnYou(waitingOnYouPhrase) }
            return .waitingOnPermission
        }
        if card.visibleLifecycle == .working && card.execution == .working {
            return .running("\(agent) Working")
        }
        if card.execution == .waiting {
            return .waitingOnYou(waitingOnYouPhrase)
        }
        return .quiet(status(card))
    }

    /// Mirrors `IslandOverlayView`'s private `agentDisplayName` (AB-158) in
    /// shape: a real Product-namespace prefix map, Title-cased fallback for
    /// anything unrecognized — never an invented agent name. Duplicated
    /// locally rather than shared because that helper is `private` to
    /// `IslandOverlayView` and this ticket's edit scope is this file only.
    static func agentDisplayName(forProductNamespace namespace: String) -> String {
        let lower = namespace.lowercased()
        if lower.hasPrefix("claude") { return "Claude" }
        if lower.hasPrefix("codex") { return "Codex" }
        if lower.hasPrefix("cursor") { return "Cursor" }
        if lower.hasPrefix("opencode") { return "OpenCode" }
        guard let first = namespace.first else { return "Agent" }
        return String(first).uppercased() + namespace.dropFirst()
    }

    /// AC-1.6-e's "salmon = Claude idle/identity" brand tint. Only Claude and
    /// Codex have dedicated brand tokens today (`IslandTheme.claudeBrand`/
    /// `codexBrand`); every other/unrecognized namespace falls back to the
    /// salmon Claude tone rather than inventing a new brand color for
    /// Cursor/OpenCode in this ticket's scope.
    static func brandTint(forProductNamespace namespace: String) -> Color {
        namespace.lowercased().hasPrefix("codex") ? IslandTheme.codexBrand : IslandTheme.claudeBrand
    }

    static func rowLabel(for card: AgentSessionCardSnapshot) -> String {
        let title = card.displayTitle.map { ", \($0)" } ?? ""
        let host = card.hostLabel.map { ", Host \($0)" } ?? ""
        let activityPhrase = activityVariant(for: card).text
        let subagentPhrase = card.subagentRuns.isEmpty
            ? ""
            : ", \(card.subagentRuns.count) subagent\(card.subagentRuns.count == 1 ? "" : "s")"
        return "\(status(card)) Agent Session\(title), Owner \(card.productNamespace)\(host), \(relativeTime(card.sourceLastUpdated)). \(activityPhrase)\(subagentPhrase)"
    }

    static func relativeTime(_ date: Date?) -> String {
        guard let date else { return "time unavailable" }
        return date.formatted(.relative(presentation: .named))
    }

    /// AC-1.6-b's compact elapsed format (`now`/`Nm`/`Nh`), mirroring
    /// agent-notch's `relative(_:)` (`main.swift:443-448`) verbatim so both
    /// apps read identically. Kept distinct from `relativeTime(_:)` above,
    /// which stays available for the verbose VoiceOver form.
    static func compactElapsed(_ date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }

    /// AB-163 §1.6 AC-1.6-c's tokens field. `TranscriptUsageProjection` is
    /// the most recent message's own reported usage — not a session-
    /// cumulative total (see that type's own doc comment) — so this formats
    /// one real message's numbers, never an invented running total.
    ///
    /// Field → display mapping, documented exactly:
    ///   - the leading `↑` number is every token *fed into* the model for
    ///     that message: `inputTokens + cacheReadInputTokens +
    ///     cacheCreationInputTokens` (fresh prompt tokens plus whatever was
    ///     read from or written to the prompt cache) — the large,
    ///     "prompt-side" number in #9's `↑ 6.9M / 55.0k`.
    ///   - the number after `/` is `outputTokens` — what the model
    ///     generated — the much smaller, "completion-side" number.
    static func tokensText(_ usage: TranscriptUsageProjection) -> String {
        let promptSide = usage.inputTokens + usage.cacheReadInputTokens + usage.cacheCreationInputTokens
        return "↑ \(formatTokenCount(promptSide)) / \(formatTokenCount(usage.outputTokens))"
    }

    /// One-decimal M/k suffixing, matching #9's `6.9M`/`55.0k` literally.
    static func formatTokenCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...:
            return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fk", Double(n) / 1_000)
        default:
            return "\(n)"
        }
    }
}
