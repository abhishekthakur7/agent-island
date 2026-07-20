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
    let clickBehavior: AtlasClickBehavior
    let displayPreferences: AtlasDisplayPreferences
    let onPrimaryClick: () -> Void
    let lastClickOutcome: PresentationClickOutcome?
    let onExpand: () -> Void
    let onCollapse: () -> Void
    let onSettings: () -> Void
    let onEngageKeyboard: () -> Void

    @StateObject private var horizon = HorizonController()

    private var attentionCount: Int { cards.filter { $0.attention == .pending }.count }
    private var isExpanded: Bool { presentation == .expanded || presentation == .focused }
    private var contentScale: CGFloat { CGFloat(displayPreferences.contentScale) }

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
            if let lastClickOutcome {
                Text(lastClickOutcome.presentationLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(lastClickOutcome.presentationLabel)
            }
        }
    }
}

private struct IslandSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18)) }
            .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
    }
}
