import Foundation
import SessionDomain
import AdapterPort

public struct FixtureTraceStep: Sendable, CustomStringConvertible {
    public let label: String
    public let outcome: String
    public var description: String { "\(label): \(outcome)" }

    public init(label: String, outcome: String) {
        self.label = label
        self.outcome = outcome
    }
}

public struct FixtureScenarioResult: Sendable {
    public let name: String
    public let steps: [FixtureTraceStep]
    public let succeeded: Bool
}

/// The required-evidence scenarios from the AB-118 ticket: one positive
/// fixture trace, plus a negative capture for duplicate delivery, invalid
/// ownership, incompatible contract, malformed shape, oversized payload, and
/// transport loss. Every scenario runs through `AdapterIntakePort` only.
public enum FixtureScenarios {
    public static func readOnlyDiscovery() -> FixtureScenarioResult {
        let result = AdapterFixture.discoverReadOnly()
        switch result {
        case .candidates(let candidates):
            let safe = candidates.allSatisfy { $0.probePlan.isSafe && $0.selectable }
            return FixtureScenarioResult(
                name: "readOnlyDiscovery",
                steps: [FixtureTraceStep(label: "discover", outcome: "\(candidates.count) selectable candidate(s), no mutation")],
                succeeded: safe
            )
        case .rejected(let error):
            return FixtureScenarioResult(name: "readOnlyDiscovery", steps: [FixtureTraceStep(label: "discover", outcome: "rejected(\(error))")], succeeded: false)
        }
    }

    public static func interfaceChangedNarrowing(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        let outcome = await fixture.negotiateInterfaceChanged()
        switch outcome {
        case .compatible(let snapshot):
            let observation = snapshot.capabilities.first { $0.id == WellKnownCapability.sessionObservation }
            let action = snapshot.capabilities.first { $0.id == WellKnownCapability.sessionAction }
            let succeeded = observation?.availability == .available && action?.availability == .interfaceChanged
            return FixtureScenarioResult(
                name: "interfaceChangedNarrowing",
                steps: [FixtureTraceStep(label: "negotiate", outcome: "observe=\(String(describing: observation?.availability)), act=\(String(describing: action?.availability))")],
                succeeded: succeeded
            )
        default:
            return FixtureScenarioResult(name: "interfaceChangedNarrowing", steps: [FixtureTraceStep(label: "negotiate", outcome: "(outcome)")], succeeded: false)
        }
    }

    public static func observationKillSwitch(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        guard let snapshot = await fixture.negotiateCompatible() else {
            return FixtureScenarioResult(name: "observationKillSwitch", steps: [FixtureTraceStep(label: "negotiate", outcome: "incompatible")], succeeded: false)
        }
        let closed = await fixture.close(.observe, for: snapshot)
        let outcome = await fixture.deliverSessionDeclared(snapshot: closed, nativeSessionID: "sess-kill-switch")
        let succeeded: Bool
        if case .rejected(.killSwitchClosed) = outcome { succeeded = true } else { succeeded = false }
        return FixtureScenarioResult(name: "observationKillSwitch", steps: [FixtureTraceStep(label: "deliver", outcome: "(outcome)")], succeeded: succeeded)
    }

    public static func positiveObservation(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        var steps: [FixtureTraceStep] = []

        guard let snapshot = await fixture.negotiateCompatible() else {
            return FixtureScenarioResult(
                name: "positiveObservation",
                steps: [FixtureTraceStep(label: "negotiate", outcome: "incompatible")],
                succeeded: false
            )
        }
        steps.append(FixtureTraceStep(label: "negotiate", outcome: "compatible(snapshot: \(snapshot.id.rawValue))"))

        let nativeSessionID = "sess_positive_demo"
        var ok = true

        let declared = await fixture.deliverSessionDeclared(
            snapshot: snapshot,
            nativeSessionID: nativeSessionID,
            displayTitle: "Refactor billing service"
        )
        steps.append(FixtureTraceStep(label: "sessionDeclared", outcome: "\(declared)"))
        if case .committed = declared {} else { ok = false }

        let started = await fixture.deliverActivity(snapshot: snapshot, nativeSessionID: nativeSessionID, kind: .started)
        steps.append(FixtureTraceStep(label: "activity.started", outcome: "\(started)"))
        if case .committed = started {} else { ok = false }

        let waiting = await fixture.deliverActivity(snapshot: snapshot, nativeSessionID: nativeSessionID, kind: .waiting)
        steps.append(FixtureTraceStep(label: "activity.waiting", outcome: "\(waiting)"))
        if case .committed = waiting {} else { ok = false }

        return FixtureScenarioResult(name: "positiveObservation", steps: steps, succeeded: ok)
    }

    public static func duplicateStableDelivery(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        var steps: [FixtureTraceStep] = []

        guard let snapshot = await fixture.negotiateCompatible() else {
            return FixtureScenarioResult(
                name: "duplicateStableDelivery",
                steps: [FixtureTraceStep(label: "negotiate", outcome: "incompatible")],
                succeeded: false
            )
        }

        let nativeSessionID = "sess_duplicate_demo"
        let stableID = "evt_duplicate_001"

        let first = await fixture.deliverSessionDeclared(snapshot: snapshot, nativeSessionID: nativeSessionID, stableEventID: stableID)
        steps.append(FixtureTraceStep(label: "firstDelivery", outcome: "\(first)"))

        let second = await fixture.deliverSessionDeclared(snapshot: snapshot, nativeSessionID: nativeSessionID, stableEventID: stableID)
        steps.append(FixtureTraceStep(label: "duplicateDelivery", outcome: "\(second)"))

        var succeeded = false
        if case .committed = first, case .duplicateIgnored = second {
            succeeded = true
        }
        return FixtureScenarioResult(name: "duplicateStableDelivery", steps: steps, succeeded: succeeded)
    }

    public static func invalidOwnership(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        var steps: [FixtureTraceStep] = []

        guard let snapshot = await fixture.negotiateCompatible() else {
            return FixtureScenarioResult(
                name: "invalidOwnership",
                steps: [FixtureTraceStep(label: "negotiate", outcome: "incompatible")],
                succeeded: false
            )
        }

        let outcome = await fixture.deliverMissingOwnerIdentity(snapshot: snapshot)
        steps.append(FixtureTraceStep(label: "deliverMissingOwnerIdentity", outcome: "\(outcome)"))

        var succeeded = false
        if case .rejected(.missingOrAmbiguousOwnerIdentity) = outcome {
            succeeded = true
        }
        return FixtureScenarioResult(name: "invalidOwnership", steps: steps, succeeded: succeeded)
    }

    public static func incompatibleContract(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        var steps: [FixtureTraceStep] = []
        var ok = false

        let negotiation = await fixture.negotiateIncompatible()
        if case .incompatible(let reason) = negotiation {
            steps.append(FixtureTraceStep(label: "negotiate.incompatibleMajor", outcome: "\(reason)"))
            ok = true
        } else {
            steps.append(FixtureTraceStep(label: "negotiate.incompatibleMajor", outcome: "unexpectedly compatible"))
        }

        let bogus = await fixture.deliverWithArbitrarySnapshotID(
            NegotiationSnapshotID("unregistered-snapshot"),
            nativeSessionID: "sess_incompatible_demo"
        )
        steps.append(FixtureTraceStep(label: "deliverAfterIncompatibleNegotiation", outcome: "\(bogus)"))
        if case .rejected(.unknownNegotiationSnapshot) = bogus {} else { ok = false }

        return FixtureScenarioResult(name: "incompatibleContract", steps: steps, succeeded: ok)
    }

    public static func malformedShape(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        var steps: [FixtureTraceStep] = []

        guard let snapshot = await fixture.negotiateCompatible() else {
            return FixtureScenarioResult(
                name: "malformedShape",
                steps: [FixtureTraceStep(label: "negotiate", outcome: "incompatible")],
                succeeded: false
            )
        }

        let outcome = await fixture.deliverMalformedActivity(snapshot: snapshot, nativeSessionID: "sess_malformed_demo")
        steps.append(FixtureTraceStep(label: "deliverMalformedActivity", outcome: "\(outcome)"))

        var succeeded = false
        if case .rejected(.malformedShape) = outcome {
            succeeded = true
        }
        return FixtureScenarioResult(name: "malformedShape", steps: steps, succeeded: succeeded)
    }

    public static func oversizedPayload(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        var steps: [FixtureTraceStep] = []

        guard let snapshot = await fixture.negotiateCompatible() else {
            return FixtureScenarioResult(
                name: "oversizedPayload",
                steps: [FixtureTraceStep(label: "negotiate", outcome: "incompatible")],
                succeeded: false
            )
        }

        let outcome = await fixture.deliverOversizedPayload(snapshot: snapshot, nativeSessionID: "sess_oversized_demo")
        steps.append(FixtureTraceStep(label: "deliverOversizedPayload", outcome: "\(outcome)"))

        var succeeded = false
        if case .rejected(.payloadTooLarge) = outcome {
            succeeded = true
        }
        return FixtureScenarioResult(name: "oversizedPayload", steps: steps, succeeded: succeeded)
    }

    public static func transportLoss(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        var steps: [FixtureTraceStep] = []

        guard let snapshot = await fixture.negotiateCompatible() else {
            return FixtureScenarioResult(
                name: "transportLoss",
                steps: [FixtureTraceStep(label: "negotiate", outcome: "incompatible")],
                succeeded: false
            )
        }

        let nativeSessionID = "sess_transport_loss_demo"
        var ok = true

        let started = await fixture.deliverActivity(snapshot: snapshot, nativeSessionID: nativeSessionID, kind: .started)
        steps.append(FixtureTraceStep(label: "activity.started", outcome: "\(started)"))
        if case .committed = started {} else { ok = false }

        let boundary = await fixture.reportTransportLost(snapshot: snapshot, nativeSessionID: nativeSessionID)
        steps.append(FixtureTraceStep(label: "observationBoundary.transportLost", outcome: "\(boundary)"))
        if case .committed = boundary {} else { ok = false }

        return FixtureScenarioResult(name: "transportLoss", steps: steps, succeeded: ok)
    }

    /// A source-proven 30-session working set for Horizon's density and
    /// hierarchy states. It deliberately supplies only title/Host and native
    /// child identity: unavailable project, model, prompt, task, and recap
    /// fields must remain absent in presentation.
    public static func horizonWorkingSet(port: any AdapterIntakePort) async -> FixtureScenarioResult {
        let fixture = AdapterFixture(port: port)
        guard let snapshot = await fixture.negotiateCompatible() else {
            return FixtureScenarioResult(
                name: "horizonWorkingSet",
                steps: [FixtureTraceStep(label: "negotiate", outcome: "incompatible")],
                succeeded: false
            )
        }

        var succeeded = true
        for index in 0..<30 {
            let sessionID = String(format: "sess_horizon_%02d", index)
            let declared = await fixture.deliverSessionDeclared(
                snapshot: snapshot,
                nativeSessionID: sessionID,
                displayTitle: "Horizon fixture session \(index + 1)",
                hostLabel: index.isMultiple(of: 2) ? "iTerm2" : nil
            )
            let started = await fixture.deliverActivity(snapshot: snapshot, nativeSessionID: sessionID, kind: .started)
            if case .committed = declared {} else { succeeded = false }
            if case .committed = started {} else { succeeded = false }
        }

        let attention = await fixture.deliverAttentionRequest(
            snapshot: snapshot,
            nativeSessionID: "sess_horizon_00",
            nativeAttentionRequestID: "attention_horizon_00",
            kind: .opened
        )
        let completed = await fixture.deliverActivity(snapshot: snapshot, nativeSessionID: "sess_horizon_01", kind: .completed)
        let child = await fixture.deliverSubagentRunDeclared(
            snapshot: snapshot,
            nativeSessionID: "sess_horizon_02",
            nativeTurnID: "turn_horizon_02",
            nativeSubagentRunID: "subagent_horizon_02"
        )
        let childWorking = await fixture.deliverSubagentActivity(
            snapshot: snapshot,
            nativeSessionID: "sess_horizon_02",
            nativeSubagentRunID: "subagent_horizon_02",
            kind: .working
        )
        for outcome in [attention, completed, child, childWorking] {
            if case .committed = outcome {} else { succeeded = false }
        }

        return FixtureScenarioResult(
            name: "horizonWorkingSet",
            steps: [
                FixtureTraceStep(label: "workingSet", outcome: "30 source-proven Agent Sessions"),
                FixtureTraceStep(label: "attention", outcome: "one pending Attention Request"),
                FixtureTraceStep(label: "completion", outcome: "one completed Agent Session"),
                FixtureTraceStep(label: "subagentRun", outcome: "one source-proven child without task detail"),
            ],
            succeeded: succeeded
        )
    }
}
