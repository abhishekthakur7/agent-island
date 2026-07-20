import SwiftUI
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
    let onPrimaryClick: () -> Void
    let lastClickOutcome: PresentationClickOutcome?
    let onExpand: () -> Void
    let onCollapse: () -> Void
    let onSettings: () -> Void
    let onEngageKeyboard: () -> Void

    @StateObject private var horizon = HorizonController()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 2)
                    .padding(1)
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeInOut(duration: adaptation.crossFadeDuration), value: presentation)
    }

    @ViewBuilder private var leftWing: some View {
        if isExpanded {
            surface
        } else {
            collapsedSummary
        }
    }

    @ViewBuilder private var rightWing: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 8 * contentScale) {
                Text("Island Overlay")
                    .font(.system(size: 17 * contentScale, weight: .semibold))
                Text("Selected display only")
                    .font(.system(size: 12 * contentScale))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                overlayControls
            }
            .padding(14 * contentScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(IslandSurface())
        } else {
            Button(action: onPrimaryClick) {
                Label(clickBehavior == .jumpBack ? "Jump Back" : "Inspect / Expand", systemImage: "chevron.down")
                    .font(.system(size: 15 * contentScale, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 56 * contentScale)
            }
            .buttonStyle(.plain)
            .modifier(IslandSurface())
            .accessibilityLabel(clickBehavior == .jumpBack ? "Jump Back when revalidated" : "Inspect or expand Agent Sessions")
        }
    }

    private var surface: some View {
        Group {
            if isExpanded {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12 * contentScale) {
                        VStack(alignment: .leading, spacing: 2 * contentScale) {
                            Text(presentation == .focused ? "Focused Agent Session" : "Agent Sessions")
                                .font(.system(size: 17 * contentScale, weight: .semibold))
                            Text("\(cards.count) current Agent Sessions on the selected display")
                                .font(.system(size: 12 * contentScale))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        overlayControls
                    }
                    .padding(14 * contentScale)
                    if usage.canAppearInExpandedHeader {
                        UsageSnapshotHeader(rendered: usage, contentScale: contentScale)
                            .padding(.horizontal, 14 * contentScale)
                            .padding(.bottom, 10 * contentScale)
                    }
                    Divider()
                    HorizonMonitorView(
                        cards: cards,
                        ledgerRevision: ledgerRevision,
                        controller: horizon,
                        contentScale: displayPreferences.contentScale,
                        completionCardHeight: displayPreferences.completionCardHeight
                    )
                        .padding(10 * contentScale)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .modifier(IslandSurface())
            } else {
                collapsedSummary
            }
        }
    }

    private var collapsedSummary: some View {
        Button(action: onPrimaryClick) {
            HStack(spacing: 8 * contentScale) {
                Image(systemName: attentionCount > 0 ? "exclamationmark.circle.fill" : "sparkles")
                    .foregroundStyle(attentionCount > 0 ? .orange : .cyan)
                Text(attentionCount > 0 ? "\(attentionCount) need attention" : "\(cards.count) Agent Sessions")
                    .font(.system(size: 15 * contentScale, weight: .semibold))
                if displayPreferences.collapsedLayout == .detailed, let card = cards.first {
                    sourcedMetadata(for: card)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16 * contentScale)
            .frame(maxWidth: .infinity, minHeight: 56 * contentScale)
        }
        .buttonStyle(.plain)
        .modifier(IslandSurface())
        .accessibilityLabel(collapsedAccessibilityLabel)
    }

    private var focusedSessionAccessibility: String {
        guard let index = focusedSessionIndex, !cards.isEmpty else { return "No Agent Session focused" }
        return "Focused Agent Session " + String(index + 1) + " of " + String(cards.count)
    }

    private var collapsedAccessibilityLabel: String {
        let action = clickBehavior == .jumpBack ? "Jump Back when revalidated" : "Inspect or expand"
        return "\(attentionCount) Attention Requests; \(cards.count) Agent Sessions. \(action)"
    }

    @ViewBuilder private func sourcedMetadata(for card: AgentSessionCardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // These fields are not part of the current source projection. An
            // explicit unavailable label keeps toggles observable without
            // deriving metadata from paths or titles.
            if displayPreferences.showProjectMetadata { Text("Project unavailable") }
            if displayPreferences.showWorktreeMetadata { Text("Worktree unavailable") }
            if displayPreferences.showModelMetadata { Text("Model unavailable") }
            if displayPreferences.showSubagentRunMetadata, !card.subagentRuns.isEmpty { Text("\(card.subagentRuns.count) Subagent Runs") }
            if displayPreferences.showActivityMetadata {
                if let updated = card.sourceLastUpdated { Text(updated, style: .relative) }
                else { Text("Activity time unavailable") }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var overlayControls: some View {
        VStack(alignment: .trailing, spacing: 5 * contentScale) {
            Button("Keyboard", action: onEngageKeyboard)
                .accessibilityHint("Engages keyboard navigation in the visible Island Overlay")
            HStack(spacing: 8 * contentScale) {
                Button("Settings", action: onSettings)
                Button("Collapse", action: onCollapse)
            }
            if keyboardEngaged {
                Text("Keyboard engaged • Escape collapses")
                    .font(.caption2)
                    .accessibilityLabel("Keyboard engagement active. Escape collapses the overlay.")
            }
            if let shortcutInvocationAnnouncement {
                Text(shortcutInvocationAnnouncement)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Shortcut result: \(shortcutInvocationAnnouncement)")
            }
            if let lastClickOutcome {
                Text(lastClickOutcome.presentationLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(lastClickOutcome.presentationLabel)
            }
            if let jumpBackAnnouncement {
                Text(jumpBackAnnouncement)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Jump Back result: \(jumpBackAnnouncement)")
            }
        }
    }
}

private struct UsageSnapshotHeader: View {
    let rendered: UsagePresentationModel.Rendered
    let contentScale: CGFloat

    var body: some View {
        guard let snapshot = rendered.snapshot else { return AnyView(EmptyView()) }
        let value = rendered.valueKind.value(in: snapshot)
        return AnyView(
            HStack(spacing: 8 * contentScale) {
                Image(systemName: rendered.state == .stale ? "clock.badge.exclamationmark" : "chart.bar")
                    .foregroundStyle(rendered.state == .stale ? .orange : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Usage Snapshot · \(snapshot.provider)")
                        .font(.system(size: 12 * contentScale, weight: .semibold))
                    Text(detail(snapshot: snapshot, value: value))
                        .font(.system(size: 11 * contentScale))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(rendered.state.rawValue.capitalized)
                    .font(.system(size: 11 * contentScale, weight: .medium))
                    .foregroundStyle(rendered.state == .stale ? .orange : .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Usage Snapshot from \(snapshot.provider). \(detail(snapshot: snapshot, value: value)). \(rendered.state.rawValue).")
        )
    }

    private func detail(snapshot: UsageSnapshot, value: Double?) -> String {
        let amount = value.map { "\(rendered.valueKind.title): \($0.formatted(.number.precision(.fractionLength(0))))%" } ?? "\(rendered.valueKind.title) unavailable"
        var text = "\(amount) · observed \(snapshot.observedAt.formatted(date: .abbreviated, time: .shortened))"
        if let resetsAt = snapshot.resetsAt { text += " · resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))" }
        return text
    }
}

private struct IslandSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(contrast == .increased ? Color.primary : Color.white.opacity(0.18), lineWidth: contrast == .increased ? 1.5 : 1) }
            .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
    }
}
