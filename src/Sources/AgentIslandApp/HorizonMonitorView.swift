import SwiftUI
import Combine
import PresentationRuntime
import SessionDomain

/// Horizon is a presentation-only view over revisioned, source-proven card
/// snapshots. It deliberately has no action or navigation dependencies: a
/// selection only opens local inline detail and never claims an Agent Product
/// action succeeded.
final class HorizonController: ObservableObject {
    @Published var isExpanded = true
    @Published var selectedID: String?
}

struct HorizonMonitorView: View {
    let cards: [AgentSessionCardSnapshot]
    let ledgerRevision: Int64
    @ObservedObject var controller: HorizonController
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
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Horizon Agent Session monitor")
    }

    private var expandedFlow: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: density == .comfortable ? 5 : 0) {
                if let focusCandidate {
                    HorizonFocusedSession(card: focusCandidate)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }

                if cards.isEmpty {
                    ContentUnavailableView(
                        "No Agent Sessions observed",
                        systemImage: "circle.dashed",
                        description: Text("Horizon will show source-proven Agent Session observations here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 0) {
                            HorizonSessionRow(
                                card: card,
                                isSelected: controller.selectedID == card.id,
                                density: card.id == focusCandidate?.id ? .comfortable : density,
                                onSelect: { controller.selectedID = controller.selectedID == card.id ? nil : card.id }
                            )

                            if controller.selectedID == card.id {
                                HorizonSelectedDetail(card: card)
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
                .foregroundStyle(.secondary)
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
        return cards.isEmpty ? "Waiting for observations" : "Status available"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attentionCount > 0 ? "exclamationmark.diamond.fill" : "diamond")
                .foregroundStyle(attentionCount > 0 ? .orange : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                Text("\(cards.count) Agent Session\(cards.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

private struct HorizonFocusedSession: View {
    let card: AgentSessionCardSnapshot

    private var heading: String {
        if card.attention == .pending { return "Focused: attention needs you" }
        if card.visibleLifecycle == .completed { return "Focused: completion" }
        return "Focused: current activity"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            HorizonIdentityLine(card: card, density: .comfortable)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.22))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(heading). \(HorizonLabels.rowLabel(for: card))")
    }
}

private enum HorizonRowDensity {
    case comfortable
    case compact
    case dense
}

private struct HorizonSessionRow: View {
    let card: AgentSessionCardSnapshot
    let isSelected: Bool
    let density: HorizonRowDensity
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 9) {
                HorizonStateMark(card: card)
                    .frame(width: 18)

                HorizonIdentityLine(card: card, density: density)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(HorizonLabels.relativeTime(card.sourceLastUpdated))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, density == .comfortable ? 9 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottom) { Divider().opacity(density == .comfortable ? 0.7 : 0.35) }
        .accessibilityLabel(HorizonLabels.rowLabel(for: card))
        .accessibilityHint(isSelected ? "Selected. Activate to hide inline detail." : "Activate to show inline detail.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct HorizonIdentityLine: View {
    let card: AgentSessionCardSnapshot
    let density: HorizonRowDensity

    private var includesTitle: Bool { density != .dense }
    private var includesHost: Bool { density == .comfortable }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if includesTitle, let title = card.displayTitle {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HorizonStatusOwnershipLine(card: card, includesHost: includesHost)

            if density == .compact, let title = card.displayTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

/// Status and ownership are protected under width pressure. Host is omitted
/// before either of them, and title is omitted at high working-set density.
private struct HorizonStatusOwnershipLine: View {
    let card: AgentSessionCardSnapshot
    let includesHost: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if includesHost, let host = card.hostLabel {
                line(host: host)
            }
            line(host: nil)
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func line(host: String?) -> some View {
        HStack(spacing: 6) {
            Text(HorizonLabels.status(card))
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .layoutPriority(2)
            Text("Owner: \(card.productNamespace)")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let host {
                Text("Host: \(host)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

private struct HorizonSelectedDetail: View {
    let card: AgentSessionCardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Agent Session")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text("Source identity: \(card.productNamespace) / \(card.nativeSessionID)")
                .font(.caption.monospaced())
                .textSelection(.enabled)

            Text("Continuity: \(card.lineage.rawValue) • Observation: \(card.observation.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if card.visibleLifecycle == .completed {
                HorizonCompletionRecap()
            }

            if !card.subagentRuns.isEmpty {
                HorizonSubagentRuns(card: card)
            }
        }
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected detail for \(card.nativeSessionID)")
    }
}

/// The current boundary supplies operational metadata only. Keep completion
/// honest by reserving a recap slot instead of inventing Product result text.
private struct HorizonCompletionRecap: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "text.alignleft")
                .accessibilityHidden(true)
            Text("No source-proven completion recap received")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Subagent Run \(run.nativeSubagentRunID)")
                            .font(.caption.monospaced())
                        Text(HorizonLabels.execution(run.execution))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let ownerTurnID = run.ownerNativeTurnID {
                        Text("Under Turn \(ownerTurnID)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
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

private struct HorizonStateMark: View {
    let card: AgentSessionCardSnapshot

    private var symbol: String {
        switch card.visibleLifecycle {
        case .working: return "diamond"
        case .needsAttention: return "exclamationmark.diamond.fill"
        case .completed: return "checkmark.diamond"
        case .stopped: return "stop.circle"
        case .failed: return "xmark.octagon"
        case .unresolved: return "questionmark.diamond"
        }
    }

    private var tint: Color {
        switch card.visibleLifecycle {
        case .working: return .blue
        case .needsAttention: return .orange
        case .completed: return .green
        case .stopped, .unresolved: return .secondary
        case .failed: return .red
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
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

    static func rowLabel(for card: AgentSessionCardSnapshot) -> String {
        let title = card.displayTitle.map { ", \($0)" } ?? ""
        let host = card.hostLabel.map { ", Host \($0)" } ?? ""
        return "\(status(card)) Agent Session\(title), Owner \(card.productNamespace)\(host), \(relativeTime(card.sourceLastUpdated))"
    }

    static func relativeTime(_ date: Date?) -> String {
        guard let date else { return "time unavailable" }
        return date.formatted(.relative(presentation: .named))
    }
}
