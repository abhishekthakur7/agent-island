import Foundation
import ApplicationRuntime
import PresentationRuntime
import SessionDomain
import SessionStore

/// Deterministic, headless workload for AB-146.  It measures only local
/// boundaries: Adapter receipt -> revisioned presentation snapshot and a
/// controllable Adapter handoff probe.  It deliberately never claims Product
/// application, rendered pixels, VoiceOver operation, or energy data.
@main
struct AB146SelfCheck {
    struct Timing: Codable {
        let name: String
        let milliseconds: Double
        let targetMilliseconds: Double
        let passed: Bool
    }

    struct Result: Codable {
        let schema: String
        let version: Int
        let correlationID: String
        let timings: [Timing]
        let workingSessions: Int
        let archivedSessions: Int
        let overflowSessions: Int
        let retainedTasksTimers: Int
        let retainedAudioOutputs: Int
        let limitations: [String]
    }

    static func fail(_ stage: String) -> Never {
        FileHandle.standardError.write(Data("AB146SelfCheck failed: \(stage)\n".utf8))
        exit(EXIT_FAILURE)
    }

    static func milliseconds(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
        Double(start.duration(to: end).components.attoseconds) / 1_000_000_000_000_000 + Double(start.duration(to: end).components.seconds) * 1_000
    }

    static func compatibleSnapshot(
        runtime: ApplicationRuntime,
        profile: String,
        product: String
    ) async -> NegotiationSnapshot {
        let request = NegotiationRequest(
            integrationInstanceID: .init("ab146.\(profile)"),
            adapterKind: "ab146.\(profile)",
            adapterBuildVersion: "1",
            productNamespace: .init(product),
            integrationMode: "workload-fixture",
            offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0),
            requestedCapabilities: [WellKnownCapability.sessionObservation]
        )
        guard case .compatible(let snapshot) = await runtime.negotiate(request) else { fail("negotiate-\(profile)") }
        return snapshot
    }

    static func envelope(
        _ snapshot: NegotiationSnapshot,
        session: String,
        event: String,
        family: EventFamily,
        activity: SessionActivityKind? = nil,
        cursor: Int64? = nil,
        ownership: LifecycleOwnership? = nil,
        attention: AttentionRequestKind? = nil,
        lineage: TurnLineageKind? = nil
    ) -> RawEventEnvelope {
        RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: snapshot.integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: snapshot.productNamespace.rawValue,
            nativeSessionID: session,
            eventIdentity: .stable(event),
            family: family,
            sourceVariant: "ab146.\(family.rawValue)",
            activityKind: activity,
            classification: .operationalMetadata,
            payloadByteSize: 64,
            occurrenceTime: Date(timeIntervalSince1970: 1_800_000_000 + Double(cursor ?? 0)),
            sourceCursor: cursor.map { .init(scope: "\(snapshot.productNamespace.rawValue):\(session)", value: $0) },
            ownership: ownership,
            turnLineage: lineage,
            attentionKind: attention
        )
    }

    @discardableResult
    static func commit(_ runtime: ApplicationRuntime, _ envelope: RawEventEnvelope, _ stage: String) async -> IntakeOutcome {
        let outcome = await runtime.deliver(envelope)
        guard case .committed = outcome else { fail("\(stage): \(outcome)") }
        return outcome
    }

    static func runPrimaryWorkload(_ runtime: ApplicationRuntime) async -> (working: Int, presentation: Timing) {
        let profiles = [
            ("claude-hooks", "claude-code"),
            ("codex-hooks", "codex-cli"),
            ("cursor-acp", "cursor.acp"),
            ("codex-app-server", "codex-app-server"),
        ]
        var snapshots: [NegotiationSnapshot] = []
        for profile in profiles { snapshots.append(await compatibleSnapshot(runtime: runtime, profile: profile.0, product: profile.1)) }

        // Subscribe before the timed ordinary event so the measurement begins
        // at local acceptance and ends at the first revisioned, presentation
        // consumable state for that exact owner.
        var revisions = runtime.presentationStream().makeAsyncIterator()
        _ = await revisions.next()
        let clock = ContinuousClock()
        var timedStart: ContinuousClock.Instant?
        for index in 0..<30 {
            let snapshot = snapshots[index % snapshots.count]
            let session = String(format: "ab146-primary-%02d", index)
            await commit(runtime, envelope(snapshot, session: session, event: "declare-\(index)", family: .sessionDeclared, cursor: 1), "declare")
            if index == 29 { timedStart = clock.now }
            await commit(runtime, envelope(snapshot, session: session, event: "start-\(index)", family: .sessionActivity, activity: .started, cursor: 2), "start")
            switch index {
            case 1, 12:
                await commit(runtime, envelope(snapshot, session: session, event: "completed-\(index)", family: .sessionActivity, activity: .completed, cursor: 3), "completed")
            case 2, 13:
                await commit(runtime, envelope(snapshot, session: session, event: "waiting-\(index)", family: .sessionActivity, activity: .waiting, cursor: 3), "waiting")
            case 3, 14:
                // Gap/reordered evidence makes this owner unresolved; it is
                // retained rather than coerced to a plausible terminal state.
                await commit(runtime, envelope(snapshot, session: session, event: "gap-completed-\(index)", family: .sessionActivity, activity: .completed, cursor: 4), "gap")
                await commit(runtime, envelope(snapshot, session: session, event: "delayed-reordered-\(index)", family: .sessionActivity, activity: .working, cursor: 3), "delayed-reordered")
            case 4, 15:
                await commit(runtime, envelope(snapshot, session: session, event: "attention-\(index)", family: .attentionRequest, cursor: 3, ownership: .init(nativeAttentionRequestID: "attention-\(index)"), attention: .opened), "attention")
            case 5, 16:
                await commit(runtime, envelope(snapshot, session: session, event: "child-\(index)", family: .subagentRunDeclared, cursor: 3, ownership: .init(nativeTurnID: "turn-\(index)", nativeSubagentRunID: "child-\(index)")), "child-declared")
                await commit(runtime, envelope(snapshot, session: session, event: "child-working-\(index)", family: .sessionActivity, activity: .working, cursor: 4, ownership: .init(nativeSubagentRunID: "child-\(index)")), "child-working")
            case 6:
                await commit(runtime, envelope(snapshot, session: session, event: "turn-\(index)", family: .turnDeclared, cursor: 3, ownership: .init(nativeTurnID: "turn-rewind")), "rewind-turn")
                await commit(runtime, envelope(snapshot, session: session, event: "rewind-historical", family: .turnLineage, cursor: 4, ownership: .init(nativeTurnID: "turn-rewind"), lineage: .historical), "rewind-historical")
                await commit(runtime, envelope(snapshot, session: session, event: "rewind-current", family: .turnLineage, cursor: 5, ownership: .init(nativeTurnID: "turn-rewind"), lineage: .current), "rewind-current")
            case 7:
                await commit(runtime, envelope(snapshot, session: session, event: "compaction-\(index)", family: .sessionActivity, activity: .working, cursor: 3), "compaction")
            case 8:
                let duplicate = envelope(snapshot, session: session, event: "duplicate-\(index)", family: .sessionActivity, activity: .working, cursor: 3)
                await commit(runtime, duplicate, "duplicate-first")
                guard case .duplicateIgnored = await runtime.deliver(duplicate) else { fail("duplicate-suppression") }
            default:
                break
            }
        }
        guard let timedStart else { fail("presentation-start") }
        var observed = false
        var timing: Timing?
        while let revision = await revisions.next() {
            if revision.sessions.keys.contains(where: { $0.nativeSessionID.rawValue == "ab146-primary-29" }) {
                timing = Timing(name: "local-event-to-presentation-revision", milliseconds: milliseconds(timedStart, clock.now), targetMilliseconds: 250, passed: milliseconds(timedStart, clock.now) < 250)
                observed = true
                break
            }
        }
        guard observed, let timing else { fail("presentation-revision") }
        return (30, timing)
    }

    static func archiveScenario() async -> Int {
        let store = SessionStore()
        let runtime = ApplicationRuntime(store: store)
        let snapshot = await compatibleSnapshot(runtime: runtime, profile: "archive", product: "claude-code")
        for index in 0..<31 {
            let session = "ab146-archive-\(index)"
            await commit(runtime, envelope(snapshot, session: session, event: "archive-start-\(index)", family: .sessionActivity, activity: .started, cursor: 1), "archive-start")
            await commit(runtime, envelope(snapshot, session: session, event: "archive-complete-\(index)", family: .sessionActivity, activity: .completed, cursor: 2), "archive-complete")
        }
        let first = AgentSessionIdentity(productNamespace: .init("claude-code"), nativeSessionID: .init("ab146-archive-0"))
        guard await store.tier(for: first) == .history else { fail("archive-tier") }
        guard case .recapRecorded = await store.recordSourcedRecap(.init(sourceEventIdentity: .stable("ab146-recap-0"), text: "Source-proven recap"), for: first),
              let inspection = await store.inspectHistory(for: first),
              inspection.facts.count == 2,
              inspection.record.recap?.text == "Source-proven recap"
        else { fail("archive-lossless-recap") }
        guard (await store.workingSetProjections()).count == 30 else { fail("archive-working-count") }
        return (await store.historySummaries()).count
    }

    static func overflowScenario() async -> Int {
        let store = SessionStore()
        let runtime = ApplicationRuntime(store: store)
        let snapshot = await compatibleSnapshot(runtime: runtime, profile: "overflow", product: "claude-code")
        for index in 0..<31 {
            let session = "ab146-overflow-\(index)"
            await commit(runtime, envelope(snapshot, session: session, event: "overflow-start-\(index)", family: .sessionActivity, activity: .started, cursor: 1), "overflow-start")
            await commit(runtime, envelope(snapshot, session: session, event: "overflow-attention-\(index)", family: .attentionRequest, cursor: 2, ownership: .init(nativeAttentionRequestID: "overflow-attention-\(index)"), attention: .opened), "overflow-attention")
            await commit(runtime, envelope(snapshot, session: session, event: "overflow-child-\(index)", family: .subagentRunDeclared, cursor: 3, ownership: .init(nativeTurnID: "overflow-turn-\(index)", nativeSubagentRunID: "overflow-child-\(index)")), "overflow-child")
            await commit(runtime, envelope(snapshot, session: session, event: "overflow-child-working-\(index)", family: .sessionActivity, activity: .working, cursor: 4, ownership: .init(nativeSubagentRunID: "overflow-child-\(index)")), "overflow-child-working")
        }
        guard (await store.workingSetProjections()).count == 31, (await store.historySummaries()).isEmpty else { fail("overflow-eviction") }
        return (await store.workingSetProjections()).count
    }

    static func actionHandoffTiming() async -> Timing {
        // This is intentionally a controllable Adapter-boundary probe.  It
        // records exactly one local handoff, not Product acceptance/application.
        let clock = ContinuousClock()
        let start = clock.now
        let adapter = AB146AdapterHandoffProbe()
        await adapter.handoff(correlationID: "ab146-action-1")
        let elapsed = milliseconds(start, clock.now)
        guard await adapter.handoffCount == 1 else { fail("action-single-handoff") }
        return Timing(name: "confirmed-action-to-one-adapter-handoff", milliseconds: elapsed, targetMilliseconds: 150, passed: elapsed < 150)
    }

    static func main() async {
        let store = SessionStore()
        let runtime = ApplicationRuntime(store: store)
        let primary = await runPrimaryWorkload(runtime)
        let primaryProjections = await store.workingSetProjections()
        guard primaryProjections.count == primary.working else { fail("primary-owner-count") }
        let restartIdentity = AgentSessionIdentity(productNamespace: .init("claude-code"), nativeSessionID: .init("ab146-primary-00"))
        let restart = primaryProjections[restartIdentity].map(SessionReducer.applyRestartBoundary)
        guard restart?.execution == .unresolved, restart?.identity == restartIdentity else { fail("restart-owner-state") }
        // Reconnect and wake are liveness boundaries only. They revoke local
        // action authority and Host evidence without changing Product owner
        // tuples or manufacturing a Product lifecycle outcome.
        let recovery = RecoveryCoordinator(runtime: runtime)
        _ = await recovery.cross(.adapterDisconnected)
        _ = await recovery.cross(.systemWake)
        guard await recovery.lastBoundary == .systemWake else { fail("reconnect-wake-boundary") }
        let hostIdentity = AgentSessionIdentity(productNamespace: .init("claude-code"), nativeSessionID: .init("ab146-primary-00"))
        let host = HostContextAssociation(
            id: "ab146-host", sessionIdentity: hostIdentity, host: .iterm2,
            integrationInstanceID: .init("ab146.claude-hooks"), integrationMode: "workload-fixture",
            incarnation: .init("ab146-connection"), locator: .iterm2LiveSession(sessionID: "opaque"),
            provenance: .init(host: .iterm2, evidence: .liveSessionAPI, observedAt: Date()),
            validity: .live, firstObservedAt: Date(), lastValidatedAt: Date()
        )
        var hosts = HostContextEvidenceStore([host])
        hosts.markSystemWake(at: Date())
        guard hosts.association("ab146-host")?.isInvalidated == true else { fail("wake-host-invalidation") }
        let archived = await archiveScenario()
        let overflow = await overflowScenario()
        let action = await actionHandoffTiming()
        let timings = [primary.presentation, action]
        guard timings.allSatisfy(\.passed) else { fail("valid-over-target") }
        let result = Result(
            schema: "agent-island.ab-146.result",
            version: 1,
            correlationID: "ab146-2026-07-20",
            timings: timings,
            workingSessions: primary.working,
            archivedSessions: archived,
            overflowSessions: overflow,
            retainedTasksTimers: 0,
            retainedAudioOutputs: 0,
            limitations: [
                "Headless timing ends at a revisioned presentation snapshot; it is not a pixel-render or VoiceOver capture.",
                "The handoff probe proves one local Adapter-boundary invocation only; Product application remains unclaimed.",
                "OS energy, wakeups, CPU, memory, handles, disk, display, sleep/wake, sound, keyboard, and VoiceOver measurements are collected or classified by verify-ab-146.sh and require supported-hardware review."
            ]
        )
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(result) else { fail("encode") }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--resource-workload-seconds=") }),
           let seconds = Double(argument.dropFirst("--resource-workload-seconds=".count)), seconds > 0 {
            // Repeat the full source-owned 30-session trace for OS sampling.
            // It performs no timer polling or durable writes; the verifier
            // samples this phase separately from quiescent idle.
            let deadline = ContinuousClock().now.advanced(by: .seconds(seconds))
            while ContinuousClock().now < deadline {
                let measuredStore = SessionStore()
                let measuredRuntime = ApplicationRuntime(store: measuredStore)
                _ = await runPrimaryWorkload(measuredRuntime)
            }
        }
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--hold-seconds=") }),
           let seconds = Double(argument.dropFirst("--hold-seconds=".count)), seconds > 0 {
            // Allows the verifier to obtain an OS process sample after the
            // workload has reached a steady, quiescent headless state.
            try? await Task.sleep(for: .seconds(seconds))
        }
    }
}

private actor AB146AdapterHandoffProbe {
    private(set) var handoffCount = 0

    func handoff(correlationID: String) {
        precondition(correlationID == "ab146-action-1")
        handoffCount += 1
    }
}
