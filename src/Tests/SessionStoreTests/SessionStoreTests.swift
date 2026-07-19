import XCTest
import Foundation
@testable import SessionDomain
@testable import SessionStore
@testable import ProtectedStore

final class SessionStoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)

    private func snapshot(major: Int = 1) -> NegotiationSnapshot {
        NegotiationSnapshot(
            id: NegotiationSnapshotID("snapshot-1"),
            contractVersion: ContractVersion(major: major, minor: 0),
            adapterKind: "fixture.first-party",
            adapterBuildVersion: "0.1.0",
            productNamespace: ProductNamespace("claude-code"),
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            integrationMode: "fixtureObservation",
            capabilities: [CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available)],
            negotiatedAt: fixedDate
        )
    }

    private func envelope(snapshot: NegotiationSnapshot, nativeSessionID: String = "sess_1", eventID: String = "evt_1", family: EventFamily = .sessionDeclared, activityKind: SessionActivityKind? = nil) -> RawEventEnvelope {
        RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: snapshot.integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: "claude-code",
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(eventID),
            family: family,
            sourceVariant: "claudeCode.sessionDeclared",
            activityKind: activityKind,
            classification: .operationalMetadata,
            payloadByteSize: 64
        )
    }

    func testCommitPublishesBeforeReturningAndTagsLedgerRevision() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)

        let outcome = await store.intake(envelope(snapshot: snap), receiptTime: fixedDate)

        guard case .committed(let revision) = outcome else {
            return XCTFail("expected commit, got \(outcome)")
        }
        XCTAssertEqual(revision, 1)

        var received: ProjectionRevision?
        for await value in await store.presentationStream() {
            received = value
            break
        }
        XCTAssertEqual(received?.ledgerRevision, 1)
        XCTAssertEqual(received?.sessions.count, 1)
    }

    func testDuplicateStableDeliveryIsIgnoredNotCommittedTwice() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)

        let first = await store.intake(envelope(snapshot: snap, eventID: "evt_dup"), receiptTime: fixedDate)
        let second = await store.intake(envelope(snapshot: snap, eventID: "evt_dup"), receiptTime: fixedDate)

        guard case .committed(let firstRevision) = first else { return XCTFail("expected first commit") }
        guard case .duplicateIgnored(let secondRevision) = second else { return XCTFail("expected duplicate ignored, got \(second)") }
        XCTAssertEqual(firstRevision, secondRevision)

        var received: ProjectionRevision?
        for await value in await store.presentationStream() {
            received = value
            break
        }
        XCTAssertEqual(received?.sessions.count, 1)
    }

    func testRejectedEnvelopeProducesNoCardAndNoRevisionBump() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)

        let badEnvelope = RawEventEnvelope(
            negotiationSnapshotID: snap.id,
            integrationInstanceID: snap.integrationInstanceID,
            contractVersion: snap.contractVersion,
            productNamespace: "claude-code",
            nativeSessionID: nil,
            eventIdentity: .stable("evt_bad"),
            family: .sessionDeclared,
            sourceVariant: "claudeCode.sessionDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 64
        )

        let outcome = await store.intake(badEnvelope, receiptTime: fixedDate)
        XCTAssertEqual(outcome, .rejected(.missingOrAmbiguousOwnerIdentity))

        var received: ProjectionRevision?
        for await value in await store.presentationStream() {
            received = value
            break
        }
        XCTAssertEqual(received?.ledgerRevision, 0)
        XCTAssertEqual(received?.sessions.count, 0)
    }

    func testRejectionIsRecordedAsRedactedDiagnosticOnly() async {
        let store = SessionStore()
        let snap = snapshot()
        await store.registerNegotiation(snap)

        let badEnvelope = RawEventEnvelope(
            negotiationSnapshotID: snap.id,
            integrationInstanceID: snap.integrationInstanceID,
            contractVersion: snap.contractVersion,
            productNamespace: "claude-code",
            nativeSessionID: nil,
            eventIdentity: .stable("evt_bad"),
            family: .sessionDeclared,
            sourceVariant: "claudeCode.sessionDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 64
        )
        _ = await store.intake(badEnvelope, receiptTime: fixedDate)

        let diagnostics = await store.diagnostics
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].kind, .envelopeRejected)
        XCTAssertEqual(diagnostics[0].reason, .missingOrAmbiguousOwnerIdentity)
    }

    // MARK: - AB-119 protected-store-backed restart behavior
    //
    // NOTE: this sandbox has no XCTest runner (see src/README.md); these
    // compile against the real SQLCipher target but must run under full
    // Xcode/CI, same documented constraint as the AB-117 spike.

    private func makeProtectedStore(root: URL, name: String = "store") -> ProtectedStore {
        ProtectedStore(configuration: ProtectedStoreConfiguration(
            databaseURL: root.appendingPathComponent("\(name).sqlite"),
            keychainAccount: "ab119-sessionstore-\(UUID().uuidString)"
        ))
    }

    func testDurableCommitReproducesSameIdentityAfterCleanRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab119-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = ProtectedStoreConfiguration(databaseURL: root.appendingPathComponent("store.sqlite"), keychainAccount: "ab119-restart-\(UUID().uuidString)")
        let snap = snapshot()

        let first = try SessionStore(protectedStore: ProtectedStore(configuration: configuration))
        await first.registerNegotiation(snap)
        let outcome = await first.intake(envelope(snapshot: snap, activityKind: .started, family: .sessionActivity), receiptTime: fixedDate)
        guard case .committed = outcome else { return XCTFail("expected commit, got \(outcome)") }

        let second = try SessionStore(protectedStore: ProtectedStore(configuration: configuration))
        var revision: ProjectionRevision?
        for await value in await second.presentationStream() {
            revision = value
            break
        }

        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("sess_1"))
        let card = revision?.sessions[identity]
        XCTAssertNotNil(card, "the same native identity must reappear after a clean restart, not a replacement built from display metadata")
        XCTAssertEqual(card?.identity, identity)
    }

    func testNonTerminalSessionIsDegradedAfterRestartUntilFreshFactArrives() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab119-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = ProtectedStoreConfiguration(databaseURL: root.appendingPathComponent("store.sqlite"), keychainAccount: "ab119-degrade-\(UUID().uuidString)")
        let snap = snapshot()
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("sess_1"))

        let first = try SessionStore(protectedStore: ProtectedStore(configuration: configuration))
        await first.registerNegotiation(snap)
        _ = await first.intake(envelope(snapshot: snap, activityKind: .started, family: .sessionActivity), receiptTime: fixedDate)
        _ = await first.intake(envelope(snapshot: snap, eventID: "evt_working", activityKind: .working, family: .sessionActivity), receiptTime: fixedDate)

        // Restart: no lease, callback token, or Host locator can have
        // survived, so the previously "working" session must present as
        // unresolved/degraded, never silently as still working.
        let second = try SessionStore(protectedStore: ProtectedStore(configuration: configuration))
        var revision: ProjectionRevision?
        for await value in await second.presentationStream() {
            revision = value
            break
        }
        XCTAssertEqual(revision?.sessions[identity]?.execution, .unresolved)
        XCTAssertEqual(revision?.sessions[identity]?.observation, .degraded)

        // A fresh, documented source observation resolves it again — the
        // degraded placeholder never overrides new canonical evidence.
        await second.registerNegotiation(snap)
        _ = await second.intake(envelope(snapshot: snap, eventID: "evt_completed", activityKind: .completed, family: .sessionActivity), receiptTime: fixedDate)
        var resolved: ProjectionRevision?
        for await value in await second.presentationStream() {
            resolved = value
            break
        }
        XCTAssertEqual(resolved?.sessions[identity]?.execution, .terminalCompleted)
    }

    func testTerminalSessionIsNotDegradedAfterRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab119-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = ProtectedStoreConfiguration(databaseURL: root.appendingPathComponent("store.sqlite"), keychainAccount: "ab119-terminal-\(UUID().uuidString)")
        let snap = snapshot()
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("sess_1"))

        let first = try SessionStore(protectedStore: ProtectedStore(configuration: configuration))
        await first.registerNegotiation(snap)
        _ = await first.intake(envelope(snapshot: snap, activityKind: .started, family: .sessionActivity), receiptTime: fixedDate)
        _ = await first.intake(envelope(snapshot: snap, eventID: "evt_completed", activityKind: .completed, family: .sessionActivity), receiptTime: fixedDate)

        let second = try SessionStore(protectedStore: ProtectedStore(configuration: configuration))
        var revision: ProjectionRevision?
        for await value in await second.presentationStream() {
            revision = value
            break
        }
        XCTAssertEqual(revision?.sessions[identity]?.execution, .terminalCompleted, "a terminal outcome must never be manufactured or degraded by a restart")
    }

    func testStorageFailureReturnsStorageUnavailableWithoutMutatingLedger() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab119-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let protectedStore = makeProtectedStore(root: root)
        let store = try SessionStore(protectedStore: protectedStore)
        let snap = snapshot()
        await store.registerNegotiation(snap)

        protectedStore.deleteKeychainKeyForTestOnly()

        let outcome = await store.intake(envelope(snapshot: snap), receiptTime: fixedDate)
        XCTAssertEqual(outcome, .storageUnavailable(.keychainKeyMissing))

        var revision: ProjectionRevision?
        for await value in await store.presentationStream() {
            revision = value
            break
        }
        XCTAssertEqual(revision?.ledgerRevision, 0, "a failed durable write must leave the in-memory ledger exactly as it was")
        XCTAssertEqual(revision?.sessions.count, 0)
    }
}
