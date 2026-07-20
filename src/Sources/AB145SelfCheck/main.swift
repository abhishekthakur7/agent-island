import Foundation
import AdapterFixtureKit
import ApplicationRuntime
import ProtectedStore
import SessionDomain
import SessionStore

@main
struct AB145SelfCheck {
    static func fail(_ stage: String) -> Never {
        FileHandle.standardError.write(Data("AB145SelfCheck failed: \(stage)\n".utf8))
        exit(EXIT_FAILURE)
    }

    static func main() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab145-self-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { fail("temporary-directory") }

        // Cold resume is facts-first: a previously waiting session remains
        // visible but deliberately unresolved until new source evidence.
        let configuration = ProtectedStoreConfiguration(databaseURL: root.appendingPathComponent("state.sqlite"), keychainAccount: "ab145-self-check-\(UUID().uuidString)")
        let store: SessionStore
        do { store = try SessionStore(protectedStore: ProtectedStore(configuration: configuration)) } catch { fail("initial-open") }
        let runtime = ApplicationRuntime(store: store, clock: { now })
        guard (await FixtureScenarios.positiveObservation(port: runtime)).succeeded else { fail("waiting-fixture") }
        let reopened: SessionStore
        do { reopened = try SessionStore(protectedStore: ProtectedStore(configuration: configuration)) } catch { fail("reopen") }
        let restored = await reopened.workingSetProjections().values.first
        guard restored?.execution == .unresolved, restored?.observation == .degraded else { fail("restart-unresolved") }

        // System wake invalidates opaque Host evidence without touching a
        // Product projection. A later explicit Jump Back must re-probe.
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("session"))
        let association = HostContextAssociation(
            id: "host", sessionIdentity: identity, host: .iterm2,
            integrationInstanceID: .init("integration"), integrationMode: "fixture",
            incarnation: .init("connection"), locator: .iterm2LiveSession(sessionID: "opaque"),
            provenance: .init(host: .iterm2, evidence: .liveSessionAPI, observedAt: now),
            validity: .live, firstObservedAt: now, lastValidatedAt: now
        )
        var hosts = HostContextEvidenceStore([association])
        hosts.markSystemWake(at: now.addingTimeInterval(1))
        guard hosts.association("host")?.isInvalidated == true else { fail("wake-invalidates-host") }

        // The public reconciliation vocabulary cannot express private state,
        // transcript/scrollback, fuzzy metadata, or automatic Host launch.
        guard Set(ReconciliationOperation.allCases) == [.read, .list, .replay, .status, .probe] else { fail("reconciliation-surface") }
        let coordinator = RecoveryCoordinator(runtime: runtime, clock: { now })
        _ = await coordinator.cross(.systemWake)
        guard await coordinator.lastBoundary == .systemWake else { fail("typed-wake-boundary") }
        print("AB145SelfCheck PASS protected restart boundary, wake locator invalidation, documented reconciliation-only surface")
    }
}
