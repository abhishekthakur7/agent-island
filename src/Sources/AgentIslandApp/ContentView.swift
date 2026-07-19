import SwiftUI
import SessionDomain
import AdapterPort
import AdapterFixtureKit
import PresentationRuntime

struct ContentView: View {
    @ObservedObject var presentation: PresentationRuntime
    @ObservedObject var fixtureController: FixtureController

    var body: some View {
        HSplitView {
            sessionsColumn
            fixtureColumn
        }
        .frame(minWidth: 760, minHeight: 440)
    }

    private var sessionsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Sessions").font(.headline)

            if presentation.cards.isEmpty {
                Text("No Agent Session observed yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(presentation.cards) { card in
                    AgentSessionCardView(card: card)
                }
                .listStyle(.inset)
            }

            Text("Ledger revision: \(presentation.ledgerRevision)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 340)
    }

    private var fixtureColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adapter fixture").font(.headline)
            Text("Every button below submits through the same typed intake boundary a real Adapter uses.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                fixtureButton("Positive observation", scenario: FixtureScenarios.positiveObservation)
                fixtureButton("Duplicate stable delivery", scenario: FixtureScenarios.duplicateStableDelivery)
                fixtureButton("Invalid ownership", scenario: FixtureScenarios.invalidOwnership)
                fixtureButton("Incompatible contract", scenario: FixtureScenarios.incompatibleContract)
                fixtureButton("Malformed shape", scenario: FixtureScenarios.malformedShape)
                fixtureButton("Oversized payload", scenario: FixtureScenarios.oversizedPayload)
                fixtureButton("Transport loss", scenario: FixtureScenarios.transportLoss)
            }
            .disabled(fixtureController.isRunning)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(fixtureController.log.enumerated()), id: \.offset) { _, result in
                        FixtureResultView(result: result)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 380)
    }

    private func fixtureButton(
        _ title: String,
        scenario: @escaping (any AdapterIntakePort) async -> FixtureScenarioResult
    ) -> some View {
        Button(title) {
            fixtureController.run(scenario)
        }
    }
}

private struct AgentSessionCardView: View {
    let card: AgentSessionCardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.displayTitle ?? card.nativeSessionID)
                .font(.body.weight(.medium))

            HStack(spacing: 8) {
                Text(card.productNamespace)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hostLabel = card.hostLabel {
                    Text(hostLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(card.visibleLifecycle.rawValue)
                    .font(.caption.bold())
                if card.attention != .none {
                    Text(card.attention.rawValue)
                        .font(.caption)
                }
                Text(card.observation.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(card.nativeSessionID)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct FixtureResultView: View {
    let result: FixtureScenarioResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(result.succeeded ? "PASS" : "FAIL")  \(result.name)")
                .font(.caption.bold())
                .foregroundStyle(result.succeeded ? .green : .red)
            ForEach(Array(result.steps.enumerated()), id: \.offset) { _, step in
                Text(step.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 6)
    }
}
