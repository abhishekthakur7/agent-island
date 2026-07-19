import Foundation
import SessionDomain
import AdapterPort
import SessionStore
import ApplicationRuntime
import AdapterFixtureKit

/// Headless evidence capture for `swift run AgentIslandApp --self-check`.
/// Exercises the required-evidence scenarios end to end (this sandbox's
/// Command Line Tools install has no XCTest/full-Xcode runner — see
/// src/README.md) and asserts the two invariants a scenario-level outcome
/// alone can't prove: transport loss never reaches a terminal projection,
/// and a duplicate stable delivery never produces a second card.
enum SelfCheck {
    static func run() async -> Int32 {
        var allPassed = true

        func report(_ result: FixtureScenarioResult) {
            let mark = result.succeeded ? "PASS" : "FAIL"
            print("[\(mark)] \(result.name)")
            for step in result.steps {
                print("    - \(step)")
            }
            if !result.succeeded { allPassed = false }
        }

        let scenarios: [(any AdapterIntakePort) async -> FixtureScenarioResult] = [
            FixtureScenarios.positiveObservation,
            FixtureScenarios.duplicateStableDelivery,
            FixtureScenarios.invalidOwnership,
            FixtureScenarios.incompatibleContract,
            FixtureScenarios.malformedShape,
            FixtureScenarios.oversizedPayload,
        ]

        for scenario in scenarios {
            let store = SessionStore()
            let runtime = ApplicationRuntime(store: store)
            report(await scenario(runtime))
        }

        do {
            let store = SessionStore()
            let runtime = ApplicationRuntime(store: store)
            report(await FixtureScenarios.transportLoss(port: runtime))

            var observed: ProjectionRevision?
            for await revision in runtime.presentationStream() {
                observed = revision
                break
            }
            if let projection = observed?.sessions.values.first {
                let neverTerminal = !projection.execution.isTerminal
                let unavailable = projection.observation == .unavailable
                let passed = neverTerminal && unavailable
                print("[\(passed ? "PASS" : "FAIL")] transportLoss.projectionInvariant execution=\(projection.execution) observation=\(projection.observation)")
                if !passed { allPassed = false }
            } else {
                print("[FAIL] transportLoss.projectionInvariant no projection observed")
                allPassed = false
            }
        }

        do {
            let store = SessionStore()
            let runtime = ApplicationRuntime(store: store)
            _ = await FixtureScenarios.duplicateStableDelivery(port: runtime)

            var observed: ProjectionRevision?
            for await revision in runtime.presentationStream() {
                observed = revision
                break
            }
            let count = observed?.sessions.count ?? -1
            let passed = count == 1
            print("[\(passed ? "PASS" : "FAIL")] duplicateStableDelivery.singleCardInvariant sessions=\(count)")
            if !passed { allPassed = false }
        }

        print(allPassed ? "SELF-CHECK PASSED" : "SELF-CHECK FAILED")
        return allPassed ? 0 : 1
    }
}
