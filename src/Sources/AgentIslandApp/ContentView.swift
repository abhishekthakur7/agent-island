import SwiftUI
import SessionDomain
import AdapterPort
import AdapterFixtureKit
import PresentationRuntime

struct ContentView: View {
    @ObservedObject var presentation: PresentationRuntime
    @ObservedObject var fixtureController: FixtureController
    @ObservedObject var horizon: HorizonController

    var body: some View {
        HSplitView {
            sessionsColumn
            fixtureColumn
        }
        .frame(minWidth: 1_180, minHeight: 700)
    }

    private var sessionsColumn: some View {
        HorizonMonitorView(cards: presentation.cards, ledgerRevision: presentation.ledgerRevision, controller: horizon)
            .frame(minWidth: 760)
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
                fixtureButton("Horizon 30-session working set", scenario: FixtureScenarios.horizonWorkingSet)
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
