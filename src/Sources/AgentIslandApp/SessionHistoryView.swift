import SwiftUI
import SessionDomain

/// Presentation-only bounded Session History model. It exposes local
/// inspection and scope copy; no Product transcript, deletion, or action
/// authority is represented here.
@MainActor
final class SessionHistoryViewModel: ObservableObject {
    static let maximumVisibleEntries = 100

    @Published private(set) var summaries: [SessionHistorySummary] = []
    @Published var selectedIdentity: AgentSessionIdentity?

    func replace(with summaries: [SessionHistorySummary]) {
        self.summaries = Array(summaries.prefix(Self.maximumVisibleEntries))
        if let selectedIdentity, !self.summaries.contains(where: { $0.identity == selectedIdentity }) {
            self.selectedIdentity = nil
        }
    }

    func scopePreview(for identity: AgentSessionIdentity) -> String? {
        guard let summary = summaries.first(where: { $0.identity == identity }) else { return nil }
        let title = summary.displayTitle ?? "Untitled Agent Session"
        return "Delete local Session History for \(title)? This removes only Agent Island's retained local evidence (\(summary.factCount) facts). It does not delete the Agent Product session."
    }
}

struct SessionHistoryView: View {
    @ObservedObject var model: SessionHistoryViewModel

    var body: some View {
        List(model.summaries) { summary in
            Button {
                model.selectedIdentity = summary.identity
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.displayTitle ?? "Untitled Agent Session")
                        .font(.headline)
                    Text("Session History • \(summary.orderingSource == .productCreationTime ? "Product creation time" : "local first-observed time")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(summary.factCount) retained facts\(summary.hasRecap ? " • sourced recap available" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Session History for \(summary.displayTitle ?? "Untitled Agent Session")")
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 180)
        .overlay {
            if model.summaries.isEmpty {
                ContentUnavailableView("No local Session History", systemImage: "clock.arrow.circlepath", description: Text("Safely inactive Agent Sessions appear here without changing Product lifecycle."))
            }
        }
        .accessibilityLabel("Bounded local Session History")
    }
}

