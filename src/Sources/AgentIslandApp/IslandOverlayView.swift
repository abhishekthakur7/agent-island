import SwiftUI
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
    let onExpand: () -> Void
    let onCollapse: () -> Void
    let onSettings: () -> Void
    let onEngageKeyboard: () -> Void

    @StateObject private var horizon = HorizonController()

    private var attentionCount: Int { cards.filter { $0.attention == .pending }.count }
    private var isExpanded: Bool { presentation == .expanded || presentation == .focused }

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
            VStack(alignment: .leading, spacing: 8) {
                Text("Island Overlay")
                    .font(.headline)
                Text("Selected display only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                overlayControls
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(IslandSurface())
        } else {
            Button(action: onExpand) {
                Label("Show", systemImage: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.plain)
            .modifier(IslandSurface())
            .accessibilityLabel("Show Agent Sessions")
        }
    }

    private var surface: some View {
        Group {
            if isExpanded {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(presentation == .focused ? "Focused Agent Session" : "Agent Sessions")
                                .font(.headline)
                            Text("\(cards.count) current Agent Sessions on the selected display")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        overlayControls
                    }
                    .padding(14)
                    Divider()
                    HorizonMonitorView(cards: cards, ledgerRevision: ledgerRevision, controller: horizon)
                        .padding(10)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .modifier(IslandSurface())
            } else {
                collapsedSummary
            }
        }
    }

    private var collapsedSummary: some View {
        Button(action: onExpand) {
            HStack(spacing: 8) {
                Image(systemName: attentionCount > 0 ? "exclamationmark.circle.fill" : "sparkles")
                    .foregroundStyle(attentionCount > 0 ? .orange : .cyan)
                Text(attentionCount > 0 ? "\(attentionCount) need attention" : "\(cards.count) Agent Sessions")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.plain)
        .modifier(IslandSurface())
        .accessibilityLabel("\(attentionCount) Attention Requests; \(cards.count) Agent Sessions. Show Agent Sessions")
    }

    private var overlayControls: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button("Keyboard", action: onEngageKeyboard)
                .accessibilityHint("Engages keyboard navigation in the visible Island Overlay")
            HStack(spacing: 8) {
                Button("Settings", action: onSettings)
                Button("Collapse", action: onCollapse)
            }
            if keyboardEngaged {
                Text("Keyboard engaged • Escape collapses")
                    .font(.caption2)
                    .accessibilityLabel("Keyboard engagement active. Escape collapses the overlay.")
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
