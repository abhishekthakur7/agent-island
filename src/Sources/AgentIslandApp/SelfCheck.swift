import Foundation
import SessionDomain
import AdapterPort
import SessionStore
import ProtectedStore
import ApplicationRuntime
import AdapterFixtureKit

/// Headless evidence capture for `swift run AgentIslandApp --self-check`.
/// Exercises the required-evidence scenarios end to end (this sandbox's
/// Command Line Tools install has no XCTest/full-Xcode runner — see
/// src/README.md) and asserts the two invariants a scenario-level outcome
/// alone can't prove: transport loss never reaches a terminal projection,
/// a duplicate stable delivery never produces a second card, and Horizon's
/// 30-session fixture retains its attention, completion, and child evidence.
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
            FixtureScenarios.horizonWorkingSet,
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
            _ = await FixtureScenarios.horizonWorkingSet(port: runtime)
            var observed: ProjectionRevision?
            for await revision in runtime.presentationStream() {
                observed = revision
                break
            }
            let sessions: [SessionProjection] = observed.map { Array($0.sessions.values) } ?? []
            let attention = sessions.filter { $0.attention == .pending }.count
            let completion = sessions.filter { $0.execution == .terminalCompleted }.count
            let children = sessions.reduce(0) { $0 + $1.subagentRuns.count }
            let passed = sessions.count == 30 && attention == 1 && completion == 1 && children == 1
            print("[\(passed ? "PASS" : "FAIL")] horizonWorkingSet.projectionInvariant sessions=\(sessions.count) attention=\(attention) completed=\(completion) children=\(children)")
            if !passed { allPassed = false }
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

        do {
            let results = await AB119Evidence.run()
            for (name, passed) in results {
                print("[\(passed ? "PASS" : "FAIL")] \(name)")
                if !passed { allPassed = false }
            }
        }

        do {
            let results = await AB130Evidence.run()
            for (name, passed) in results {
                print("[\(passed ? "PASS" : "FAIL")] \(name)")
                if !passed { allPassed = false }
            }
        }

        do {
            let results = await AB135Evidence.run()
            for (name, passed) in results {
                print("[\(passed ? "PASS" : "FAIL")] \(name)")
                if !passed { allPassed = false }
            }
        }

        print(allPassed ? "SELF-CHECK PASSED" : "SELF-CHECK FAILED")
        return allPassed ? 0 : 1
    }
}

/// AB-119 evidence: exercises the real encrypted `ProtectedStore` (this
/// sandbox has SQLCipher installed via Homebrew but no XCTest/full-Xcode
/// runner) against a temp directory and disposable Keychain accounts,
/// cleaning each one up as it finishes. Process-kill fault injection (the
/// AB-117 spike's `crashBeforeCommit`/`SIGKILL` path) is out of scope here —
/// the atomic-commit guarantee is instead proven by a mid-transaction
/// constraint failure, which SQLite rolls back identically to a process
/// kill; see `ProtectedStoreTests.testFailedCommitLeavesNoPartialFact`.
private enum AB119Evidence {
    static func run() async -> [(String, Bool)] {
        var results: [(String, Bool)] = []
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab119-self-check-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("sess_1"))
        let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)

        func snapshot() -> NegotiationSnapshot {
            NegotiationSnapshot(
                id: NegotiationSnapshotID("snapshot-1"),
                contractVersion: ContractVersion(major: 1, minor: 0),
                adapterKind: "fixture.first-party",
                adapterBuildVersion: "0.1.0",
                productNamespace: ProductNamespace("claude-code"),
                integrationInstanceID: IntegrationInstanceID("instance-1"),
                integrationMode: "fixtureObservation",
                capabilities: [CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available)],
                negotiatedAt: fixedDate
            )
        }

        func envelope(snap: NegotiationSnapshot, eventID: String, family: EventFamily, activityKind: SessionActivityKind?) -> RawEventEnvelope {
            RawEventEnvelope(
                negotiationSnapshotID: snap.id,
                integrationInstanceID: snap.integrationInstanceID,
                contractVersion: snap.contractVersion,
                productNamespace: "claude-code",
                nativeSessionID: "sess_1",
                eventIdentity: .stable(eventID),
                family: family,
                sourceVariant: "claudeCode.\(family.rawValue)",
                activityKind: activityKind,
                classification: .operationalMetadata,
                payloadByteSize: 64
            )
        }

        // 1. Bootstrap + durable commit + real encryption proof.
        do {
            let configuration = ProtectedStoreConfiguration(
                databaseURL: root.appendingPathComponent("encryption.sqlite"),
                keychainAccount: "ab119-selfcheck-encryption-\(UUID().uuidString)"
            )
            let protectedStore = ProtectedStore(configuration: configuration)
            defer { protectedStore.deleteKeychainKeyForTestOnly() }

            let store = try SessionStore(protectedStore: protectedStore)
            let snap = snapshot()
            await store.registerNegotiation(snap)
            let outcome = await store.intake(envelope(snap: snap, eventID: "evt_1", family: .sessionActivity, activityKind: .started), receiptTime: fixedDate)
            results.append(("ab119.durableCommit", outcome == .committed(ledgerRevision: 1)))
            results.append(("ab119.encryptedAtRest", (try? protectedStore.encryptedAtRest()) == true))
            results.append(("ab119.wrongKeyRejected", (try? protectedStore.rejectsWrongKeyForEvidence()) == true))
        } catch {
            results.append(("ab119.durableCommit", false))
        }

        // 2. Clean restart reproduces the same identity; a still-"working"
        //    session is presented degraded/unresolved until a fresh fact
        //    resolves it, never silently as still live.
        do {
            let configuration = ProtectedStoreConfiguration(
                databaseURL: root.appendingPathComponent("restart.sqlite"),
                keychainAccount: "ab119-selfcheck-restart-\(UUID().uuidString)"
            )
            defer { ProtectedStore(configuration: configuration).deleteKeychainKeyForTestOnly() }
            let snap = snapshot()

            let first = try SessionStore(protectedStore: ProtectedStore(configuration: configuration))
            await first.registerNegotiation(snap)
            _ = await first.intake(envelope(snap: snap, eventID: "evt_1", family: .sessionActivity, activityKind: .started), receiptTime: fixedDate)
            _ = await first.intake(envelope(snap: snap, eventID: "evt_2", family: .sessionActivity, activityKind: .working), receiptTime: fixedDate)

            let second = try SessionStore(protectedStore: ProtectedStore(configuration: configuration))
            var revision: ProjectionRevision?
            for await value in await second.presentationStream() {
                revision = value
                break
            }
            let card = revision?.sessions[identity]
            results.append(("ab119.restartReproducesSameIdentity", card?.identity == identity))
            results.append(("ab119.restartDegradesNonTerminalSession execution=\(card?.execution.rawValue ?? "nil") observation=\(card?.observation.rawValue ?? "nil")", card?.execution == .unresolved && card?.observation == .degraded))

            await second.registerNegotiation(snap)
            _ = await second.intake(envelope(snap: snap, eventID: "evt_3", family: .sessionActivity, activityKind: .completed), receiptTime: fixedDate)
            var resolved: ProjectionRevision?
            for await value in await second.presentationStream() {
                resolved = value
                break
            }
            results.append(("ab119.freshFactResolvesDegradedPlaceholder", resolved?.sessions[identity]?.execution == .terminalCompleted))
        } catch {
            results.append(("ab119.restartReproducesSameIdentity", false))
        }

        // 3. Fail-closed: a missing Keychain key must never launch with a
        //    silently reset store.
        do {
            let configuration = ProtectedStoreConfiguration(
                databaseURL: root.appendingPathComponent("missing-key.sqlite"),
                keychainAccount: "ab119-selfcheck-missing-key-\(UUID().uuidString)"
            )
            let bootstrapStore = ProtectedStore(configuration: configuration)
            _ = try bootstrapStore.openOrBootstrap()
            bootstrapStore.deleteKeychainKeyForTestOnly()

            do {
                _ = try SessionStore(protectedStore: ProtectedStore(configuration: configuration))
                results.append(("ab119.missingKeyFailsClosed", false))
            } catch let error as ProtectedStoreFailure {
                results.append(("ab119.missingKeyFailsClosed reason=\(error.diagnosticCode)", error == .missingKeychainKey))
            }
        } catch {
            results.append(("ab119.missingKeyFailsClosed", false))
        }

        // 4. A corrupt projection snapshot is discarded and rebuilt from
        //    facts — it never fails the whole reopen (AC6) and never
        //    silently overrides canonical evidence.
        do {
            let configuration = ProtectedStoreConfiguration(
                databaseURL: root.appendingPathComponent("corrupt-projection.sqlite"),
                keychainAccount: "ab119-selfcheck-corrupt-projection-\(UUID().uuidString)"
            )
            let protectedStore = ProtectedStore(configuration: configuration)
            defer { protectedStore.deleteKeychainKeyForTestOnly() }
            _ = try protectedStore.openOrBootstrap()
            let snap = snapshot()
            let fact = NormalizedEventFact(
                receiptOrdinal: 1,
                identity: identity,
                integrationInstanceID: IntegrationInstanceID("instance-1"),
                negotiationSnapshotID: snap.id,
                eventIdentity: .stable("evt_1"),
                family: .sessionActivity,
                sourceVariant: "claudeCode.sessionActivity",
                activityKind: .started,
                boundaryReason: nil,
                classification: .operationalMetadata,
                occurrenceTime: nil,
                receiptTime: fixedDate,
                displayTitle: nil,
                hostLabel: nil
            )
            try protectedStore.commit(fact: fact, projection: SessionReducer.reduce(history: [fact], ledgerRevision: 1))
            try protectedStore.corruptProjectionCacheForTestOnly()

            let loaded = try protectedStore.openOrBootstrap()
            results.append(("ab119.corruptProjectionSnapshotDoesNotFailReopen", loaded.facts == [fact]))
            results.append(("ab119.corruptProjectionSnapshotIsRecognizedNotSilentlyTrusted", loaded.projectionCacheFault != nil))
        } catch {
            results.append(("ab119.corruptProjectionSnapshotDoesNotFailReopen", false))
        }

        return results
    }
}
