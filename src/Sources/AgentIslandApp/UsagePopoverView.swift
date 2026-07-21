import SwiftUI
import SessionDomain

/// AB-162 — §1.12 menu-bar popover + §1.12.1 Metrics tab.
///
/// This is the SwiftUI content hosted by the `NSPopover` that
/// `AppDelegate.installMenu()` attaches to the existing `NSStatusItem`
/// (replacing that status item's old `NSMenu`-on-click behavior — see that
/// method's doc comment for the click-routing split). It is also the
/// destination AB-161's `overlay.onOpenUsageDetails` seam re-points to
/// (previously a `showSettings(nil)` placeholder).
///
/// Data source: the SAME `ProviderQuotaBoardModel` instance AB-161 already
/// constructs in `AppDelegate` (`quotaBoardModel`) and feeds to the overlay —
/// this view takes it as a plain `@ObservedObject`, not a second model.
/// `ProviderQuotaBoardModel`'s only shipping port is
/// `UnavailableProviderQuotaPort`, so every snapshot this view reads is
/// currently empty; every optional below therefore renders honestly as
/// `--` / an empty progress bar / an empty histogram / an omitted row, never
/// a fabricated number (`ProviderQuotaState.swift`'s own sourcing-gap doc
/// comment governs this).
struct UsagePopoverView: View {
    @ObservedObject var quotaModel: ProviderQuotaBoardModel
    @StateObject private var tabModel = UsagePopoverTabModel()
    var onRefresh: () -> Void
    var onSettings: () -> Void

    /// Fixed provider display order — Claude, Codex, Cursor, OpenCode — the
    /// same order the doc's #13/#15 mockups list them in and the same order
    /// `QuotaProvider.allCases` declares.
    private static let providers: [QuotaProvider] = [.claude, .codex, .cursor, .openCode]

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tabModel.selected {
                    case .active:
                        ForEach(Self.providers, id: \.self) { provider in
                            ActiveProviderCard(provider: provider, snapshot: quotaModel.snapshot(for: provider))
                        }
                    case .metrics:
                        ForEach(Self.providers, id: \.self) { provider in
                            MetricsProviderCard(provider: provider, snapshot: quotaModel.snapshot(for: provider))
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 420)
            hairline
            footer
        }
        .frame(width: 340)
        .background(IslandTheme.surface)
        .foregroundStyle(IslandTheme.textPrimary)
        // AC-1.12-e: force the opaque dark surface regardless of the
        // system appearance — the same hard rule `IslandTheme`'s doc
        // comment states for the overlay itself.
        .environment(\.colorScheme, .dark)
    }

    private var hairline: some View {
        Rectangle().fill(IslandTheme.hairline).frame(height: 1)
    }

    // MARK: - Header (AC-1.12-a)

    private var header: some View {
        HStack(spacing: 10) {
            Text("Agent Island")
                .font(IslandFont.mono(size: 14, weight: .semibold))
                .foregroundStyle(IslandTheme.textPrimary)
            Spacer()
            Button(action: onRefresh) {
                Text("⟳")
                    .font(IslandFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(IslandTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh usage")

            Button(action: onSettings) {
                Text("⚙")
                    .font(IslandFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(IslandTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(IslandTheme.surface)
    }

    // MARK: - Footer segmented toggle (AC-1.12-d)

    private var footer: some View {
        HStack(spacing: 4) {
            ForEach(UsagePopoverTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { tabModel.selected = tab }
                } label: {
                    Text(tab.title)
                        .font(IslandFont.mono(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(tabModel.selected == tab ? IslandTheme.textPrimary : IslandTheme.textSecondary)
                        .background(
                            tabModel.selected == tab ? IslandTheme.surfaceElevated : Color.clear,
                            in: RoundedRectangle(cornerRadius: IslandTheme.Radius.button)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tabModel.selected == tab ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(IslandTheme.surface)
    }
}

// MARK: - Tab selection (AC-1.12-d: an ObservableObject, not @State — this
// toolchain's SwiftUI macro plugins don't compile `@State`/`#Preview`.)

enum UsagePopoverTab: String, CaseIterable {
    case active
    case metrics

    var title: String {
        switch self {
        case .active: return "Active"
        case .metrics: return "Metrics"
        }
    }
}

@MainActor
final class UsagePopoverTabModel: ObservableObject {
    @Published var selected: UsagePopoverTab = .active
}

// MARK: - Shared window-shape + formatting helpers

/// Which percent-metered windows each provider renders — a fixed structural
/// fact (mirrors `DetailedProviderUsageView.windows` in
/// `IslandOverlayView.swift`), not derived from whether data happens to be
/// present. OpenCode has no percent windows at all — it is token-metered
/// (AC-1.12-c) — so its row list is empty here, and callers use that to
/// switch to the token-usage form.
private enum ProviderWindowShape {
    static func kinds(for provider: QuotaProvider) -> [QuotaWindowKind] {
        switch provider {
        case .claude, .codex: return [.fiveHour, .sevenDay]
        case .cursor: return [.month]
        case .openCode: return []
        }
    }
}

private enum UsagePopoverFormatting {
    /// The right-aligned reset/refill string for one window row. `5H`'s
    /// example data reads as a relative countdown ("Resets in 1h 24m");
    /// `7D`/`MO`'s reads as an absolute refill instant ("refills Fri at
    /// 10:30 PM" / "refills Aug 14 at 10:42 AM") — matching §1.12's literal
    /// example strings exactly. `--` when the window/model has neither.
    static func resetString(kind: QuotaWindowKind, window: QuotaWindowState?) -> String {
        guard let window else { return "--" }
        if kind == .fiveHour, let compact = window.compactTimeUntilReset {
            return "Resets in \(compact)"
        }
        if let resetsAt = window.resetsAt {
            return "refills \(formattedRefillDate(resetsAt))"
        }
        if let compact = window.compactTimeUntilReset {
            return "Resets in \(compact)"
        }
        return "--"
    }

    /// "EEE at h:mm a" within the next week (`Fri at 10:30 PM`), otherwise
    /// "MMM d at h:mm a" (`Aug 14 at 10:42 AM`) — the doc's own two forms.
    static func formattedRefillDate(_ date: Date, now: Date = Date()) -> String {
        let daysAway = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
        let formatter = DateFormatter()
        formatter.dateFormat = daysAway < 7 ? "EEE 'at' h:mm a" : "MMM d 'at' h:mm a"
        return formatter.string(from: date)
    }

    /// `5.0B` / `1.0B` / `2.6M` / `2.6K` — the doc's own token-total
    /// abbreviation forms (§1.12.1's headline figures, §1.12's `TOK 2.6M`).
    static func abbreviatedTokenCount(_ value: Int) -> String {
        let d = Double(value)
        switch d {
        case 1_000_000_000...: return String(format: "%.1fB", d / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
        case 1_000...: return String(format: "%.1fK", d / 1_000)
        default: return "\(value)"
        }
    }

    static func percentText(_ value: Double) -> String {
        value < 1 ? "<1%" : "\(Int(value.rounded()))%"
    }
}

// MARK: - Active tab (§1.12, AC-1.12-b/c)

private struct ActiveProviderCard: View {
    let provider: QuotaProvider
    let snapshot: ProviderQuotaSnapshot?

    private var windowKinds: [QuotaWindowKind] { ProviderWindowShape.kinds(for: provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderCardHeader(provider: provider)

            if windowKinds.isEmpty {
                // OpenCode: token-metered (AC-1.12-c).
                TokenUsageRow(usage: snapshot?.tokenUsage)
            } else {
                ForEach(windowKinds, id: \.self) { kind in
                    QuotaWindowRow(kind: kind, window: snapshot?.window(kind))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IslandTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: IslandTheme.Radius.card))
    }
}

private struct ProviderCardHeader: View {
    let provider: QuotaProvider

    var body: some View {
        HStack(spacing: 6) {
            Text(provider.brandMarkGlyph)
                .foregroundStyle(provider.brandMarkColor)
                .accessibilityHidden(true)
            Text(provider.displayName)
                .foregroundStyle(IslandTheme.textPrimary)
        }
        .font(IslandFont.mono(size: 13, weight: .semibold))
    }
}

/// One window row in the doc's literal #13 form: `<window> <N>% used` + a
/// green progress bar + a right-aligned reset/refill string (AC-1.12-b).
private struct QuotaWindowRow: View {
    let kind: QuotaWindowKind
    let window: QuotaWindowState?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(headline)
                    .foregroundStyle(window?.percentConsumed == nil ? IslandTheme.textDim : IslandTheme.textPrimary)
                Spacer()
                Text(UsagePopoverFormatting.resetString(kind: kind, window: window))
                    .foregroundStyle(IslandTheme.textSecondary)
                    .lineLimit(1)
            }
            .font(IslandFont.mono(size: 12, weight: .medium))

            QuotaProgressBar(percentConsumed: window?.percentConsumed)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var headline: String {
        guard let percent = window?.percentConsumed else { return "\(kind.label) --" }
        return "\(kind.label) \(Int(percent.rounded()))% used"
    }

    private var accessibilityLabel: String {
        let percentText = window?.percentConsumed.map { "\(Int($0.rounded())) percent used" } ?? "no data"
        return "\(kind.label): \(percentText), \(UsagePopoverFormatting.resetString(kind: kind, window: window))"
    }
}

/// AC-1.12-b's green progress bar. Renders a visible empty track (not a
/// hidden view) when there is no percentage — the doc's own "`5H --`
/// (empty bar)" case — and colors the fill via
/// `IslandTheme.quotaColor(percentConsumed:)` when there is one.
private struct QuotaProgressBar: View {
    let percentConsumed: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(IslandTheme.surface)
                if let percentConsumed {
                    Capsule()
                        .fill(IslandTheme.quotaColor(percentConsumed: percentConsumed))
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, percentConsumed / 100))))
                }
            }
        }
        .frame(height: 4)
    }
}

/// AC-1.12-c: `TOK <n>` + `<req> req / <tokens> tokens / $<cost>`, driven
/// entirely off `ProviderQuotaSnapshot.tokenUsage` — no percentage, no
/// progress bar.
private struct TokenUsageRow: View {
    let usage: TokenMeteredUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TOK \(headline)")
                .font(IslandFont.mono(size: 12, weight: .medium))
                .foregroundStyle(usage?.tokenCount == nil ? IslandTheme.textDim : IslandTheme.textPrimary)
            Text(detailLine)
                .font(IslandFont.mono(size: 11, weight: .regular))
                .foregroundStyle(IslandTheme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("OpenCode tokens: \(headline), \(detailLine)")
    }

    private var headline: String {
        usage?.tokenCount.map(UsagePopoverFormatting.abbreviatedTokenCount) ?? "--"
    }

    private var detailLine: String {
        guard let usage, usage.hasData else { return "--" }
        let req = usage.requestCount.map(String.init) ?? "--"
        let tokens = usage.tokenCount.map(UsagePopoverFormatting.abbreviatedTokenCount) ?? "--"
        let cost = usage.costUSD.map { String(format: "$%.2f", $0) } ?? "--"
        return "\(req) req / \(tokens) tokens / \(cost)"
    }
}

// MARK: - Metrics tab (§1.12.1, AC-1.12-f/g/h/i)

private struct MetricsProviderCard: View {
    let provider: QuotaProvider
    let snapshot: ProviderQuotaSnapshot?

    /// AC-1.12-h: Cursor is the one quota-metered provider that leads with a
    /// percentage + progress bar + refill date on the Metrics tab too;
    /// every other provider leads with a token total even where (like
    /// Claude/Codex) its Active-tab form is percent-metered.
    private var isQuotaMetered: Bool { provider == .cursor }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderCardHeader(provider: provider)

            if isQuotaMetered {
                quotaHeadline
            } else {
                Text(snapshot?.metrics?.tokenTotal.map(UsagePopoverFormatting.abbreviatedTokenCount) ?? "--")
                    .font(IslandFont.mono(size: 20, weight: .semibold))
                    .foregroundStyle(snapshot?.metrics?.tokenTotal == nil ? IslandTheme.textDim : IslandTheme.textPrimary)
            }

            MetricsHistogramView(points: snapshot?.metrics?.usageHistogram ?? [])

            // AC-1.12-i: rows absent from the model's array are omitted
            // entirely, never rendered as a fabricated `0%`.
            if let breakdown = snapshot?.metrics?.tokenClassBreakdown, !breakdown.isEmpty {
                TokenClassBreakdownView(rows: breakdown)
            }
            if let modelSplit = snapshot?.metrics?.modelSplit, !modelSplit.isEmpty {
                ModelSplitView(rows: modelSplit)
            }
            if isQuotaMetered, let modeRows = snapshot?.metrics?.modeBreakdown, !modeRows.isEmpty {
                ModeBreakdownView(rows: modeRows)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IslandTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: IslandTheme.Radius.card))
    }

    private var quotaHeadline: some View {
        let window = snapshot?.window(.month)
        return VStack(alignment: .leading, spacing: 6) {
            Text(window?.percentConsumed.map { "\(Int($0.rounded()))% monthly" } ?? "-- monthly")
                .font(IslandFont.mono(size: 20, weight: .semibold))
                .foregroundStyle(window?.percentConsumed == nil ? IslandTheme.textDim : IslandTheme.textPrimary)
            QuotaProgressBar(percentConsumed: window?.percentConsumed)
            Text(window?.resetsAt.map { "refills \(UsagePopoverFormatting.formattedRefillDate($0))" } ?? "--")
                .font(IslandFont.mono(size: 11, weight: .regular))
                .foregroundStyle(IslandTheme.textSecondary)
        }
    }
}

/// AC-1.12-g's usage histogram — a small bar chart drawn on a dashed
/// baseline so an empty series (the honest, shipping state) still reads as
/// a chart rather than blank space.
private struct MetricsHistogramView: View {
    let points: [UsageHistogramPoint]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height - 0.5))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 0.5))
                }
                .stroke(IslandTheme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                if !points.isEmpty {
                    let maxValue = max(points.map(\.value).max() ?? 0, 0.0001)
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(IslandTheme.textSecondary.opacity(0.7))
                                .frame(height: max(2, (geo.size.height - 1) * CGFloat(point.value / maxValue)))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .frame(height: 32)
        .accessibilityHidden(points.isEmpty)
    }
}

/// AC-1.12-g/i: the dotted input/output/cache-write/cache-read breakdown.
/// Dot colors are a judgment call (the doc names the list "colored-dot" but
/// never pins exact hues) — kept in one place so every card is consistent.
private struct TokenClassBreakdownView: View {
    let rows: [TokenClassShare]

    private static func dotColor(_ tokenClass: TokenClass) -> Color {
        switch tokenClass {
        case .input: return IslandTheme.statusBlocked
        case .output: return IslandTheme.allowGreen
        case .cacheWrite: return IslandTheme.accentAttention
        case .cacheRead: return IslandTheme.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.tokenClass) { row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.dotColor(row.tokenClass))
                        .frame(width: 6, height: 6)
                    Text(row.tokenClass.displayName)
                        .foregroundStyle(IslandTheme.textSecondary)
                    Spacer()
                    Text(UsagePopoverFormatting.percentText(row.percent))
                        .foregroundStyle(IslandTheme.textPrimary)
                }
                .font(IslandFont.mono(size: 11, weight: .regular))
            }
        }
    }
}

/// AC-1.12-g: the per-model split, ending in the model's reserved `other`
/// tail bucket (`ModelUsageShare.otherModelName`/`isOther`).
private struct ModelSplitView: View {
    let rows: [ModelUsageShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.modelName)
                        .foregroundStyle(row.isOther ? IslandTheme.textDim : IslandTheme.textSecondary)
                    Spacer()
                    Text("\(Int(row.percent.rounded()))%")
                        .foregroundStyle(IslandTheme.textPrimary)
                }
                .font(IslandFont.mono(size: 11, weight: .regular))
            }
        }
    }
}

/// §1.12.1: Cursor's per-mode rows (`Auto`, `API`) alongside its progress
/// bar + refill date. Empty for every token-metered provider.
private struct ModeBreakdownView: View {
    let rows: [QuotaModeUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.modeName).foregroundStyle(IslandTheme.textSecondary)
                    Spacer()
                    if let percent = row.percentConsumed {
                        Text("\(Int(percent.rounded()))%").foregroundStyle(IslandTheme.textPrimary)
                    } else {
                        Text("--").foregroundStyle(IslandTheme.textDim)
                    }
                }
                .font(IslandFont.mono(size: 11, weight: .regular))
            }
        }
    }
}
