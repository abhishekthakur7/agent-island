import XCTest
import Foundation
@testable import SessionDomain
@testable import ProtectedStore

/// Exercises the encrypted canonical store in isolation, mirroring the
/// AB-117 spike's proven fault-injection shape but against the production
/// `ProtectedStore` API. Each test gets its own temp directory and a unique
/// Keychain account so tests never interfere with each other or a real
/// installation's key.
///
/// NOTE: this sandbox's Command Line Tools install has no XCTest runner
/// (see src/README.md / the AB-117 spike README) — these compile against the
/// real SQLCipher target but must be executed under full Xcode/CI.
final class ProtectedStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ab119-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore(name: String = "store", account: String? = nil) -> ProtectedStore {
        let configuration = ProtectedStoreConfiguration(
            databaseURL: root.appendingPathComponent("\(name).sqlite"),
            keychainAccount: account ?? "ab119-test-\(UUID().uuidString)"
        )
        return ProtectedStore(configuration: configuration)
    }

    private func fact(ordinal: Int64, identity: AgentSessionIdentity, eventID: String) -> NormalizedEventFact {
        NormalizedEventFact(
            receiptOrdinal: ordinal,
            identity: identity,
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            negotiationSnapshotID: NegotiationSnapshotID("snapshot-1"),
            eventIdentity: .stable(eventID),
            family: .sessionDeclared,
            sourceVariant: "test.sessionDeclared",
            activityKind: nil,
            boundaryReason: nil,
            classification: .operationalMetadata,
            occurrenceTime: nil,
            receiptTime: Date(timeIntervalSince1970: 1_752_000_000),
            displayTitle: "Test session",
            hostLabel: nil
        )
    }

    private let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("sess_1"))

    // MARK: - Bootstrap / encryption proof

    func testBootstrapCreatesRealEncryptedStore() throws {
        let store = makeStore()
        _ = try store.openOrBootstrap()

        XCTAssertTrue(try store.encryptedAtRest(), "database bytes must never carry the plaintext SQLite signature")
        XCTAssertTrue(try store.rejectsWrongKeyForEvidence(), "an unrelated key must not be able to open the same ciphertext")
    }

    // MARK: - Atomic durable commit

    func testCommitPersistsFactAndProjectionAtomicallyAndSurvivesReopen() throws {
        let configuration = ProtectedStoreConfiguration(databaseURL: root.appendingPathComponent("commit.sqlite"), keychainAccount: "ab119-commit-\(UUID().uuidString)")
        let store = ProtectedStore(configuration: configuration)
        _ = try store.openOrBootstrap()

        let committedFact = fact(ordinal: 1, identity: identity, eventID: "evt_1")
        let projection = SessionReducer.reduce(history: [committedFact], ledgerRevision: 1)
        try store.commit(fact: committedFact, projection: projection)

        let reopened = ProtectedStore(configuration: configuration)
        let loaded = try reopened.openOrBootstrap()

        XCTAssertEqual(loaded.facts, [committedFact])
        XCTAssertNil(loaded.projectionCacheFault)
    }

    /// A failed mid-transaction write (duplicate ordinal triggers a primary
    /// key violation before COMMIT) must roll back completely: no ghost
    /// card, no partial identity, no duplicate fact (AB-119 AC1). SQLite
    /// rolls back an aborted `BEGIN IMMEDIATE` transaction identically
    /// whether the interruption is a thrown error or a process kill, so this
    /// proves the same atomicity guarantee without needing to SIGKILL the
    /// test runner.
    func testFailedCommitLeavesNoPartialFact() throws {
        let store = makeStore()
        _ = try store.openOrBootstrap()

        let first = fact(ordinal: 1, identity: identity, eventID: "evt_1")
        try store.commit(fact: first, projection: SessionReducer.reduce(history: [first], ledgerRevision: 1))

        let colliding = fact(ordinal: 1, identity: identity, eventID: "evt_collides")
        XCTAssertThrowsError(try store.commit(fact: colliding, projection: SessionReducer.reduce(history: [colliding], ledgerRevision: 1)))

        let loaded = try store.openOrBootstrap()
        XCTAssertEqual(loaded.facts, [first], "the failed second commit must not have left a partial or duplicate row")
    }

    // MARK: - Fail-closed faults

    func testMissingKeychainKeyFailsClosed() throws {
        let account = "ab119-missing-key-\(UUID().uuidString)"
        let store = makeStore(account: account)
        _ = try store.openOrBootstrap()
        store.deleteKeychainKeyForTestOnly()

        let reopened = ProtectedStore(configuration: ProtectedStoreConfiguration(databaseURL: root.appendingPathComponent("store.sqlite"), keychainAccount: account))
        XCTAssertThrowsError(try reopened.openOrBootstrap()) { error in
            XCTAssertEqual(error as? ProtectedStoreFailure, .missingKeychainKey)
        }
    }

    func testCorruptCiphertextFailsClosed() throws {
        let configuration = ProtectedStoreConfiguration(databaseURL: root.appendingPathComponent("corrupt.sqlite"), keychainAccount: "ab119-corrupt-\(UUID().uuidString)")
        let store = ProtectedStore(configuration: configuration)
        _ = try store.openOrBootstrap()

        var bytes = try Data(contentsOf: configuration.databaseURL)
        guard bytes.count > 64 else { return XCTFail("expected a non-trivial database file") }
        for index in 16..<64 { bytes[index] = bytes[index] ^ 0xFF }
        try bytes.write(to: configuration.databaseURL)

        let reopened = ProtectedStore(configuration: configuration)
        XCTAssertThrowsError(try reopened.openOrBootstrap())
    }

    func testInterruptedStageFailsClosedThenRecoversNonDestructively() throws {
        let store = makeStore()
        _ = try store.openOrBootstrap()
        try store.createInterruptedStageForTestOnly()

        XCTAssertThrowsError(try store.openOrBootstrap()) { error in
            XCTAssertEqual(error as? ProtectedStoreFailure, .interruptedWrite)
        }

        try store.discardInterruptedStageAfterVerifyingPrimary()
        XCTAssertNoThrow(try store.openOrBootstrap())
    }

    // MARK: - Projection snapshot recovery (never fail-closed on its own)

    func testCorruptProjectionCacheIsDiscardedAndRebuiltWithoutFailingReopen() throws {
        let store = makeStore()
        _ = try store.openOrBootstrap()

        let committedFact = fact(ordinal: 1, identity: identity, eventID: "evt_1")
        try store.commit(fact: committedFact, projection: SessionReducer.reduce(history: [committedFact], ledgerRevision: 1))
        try store.corruptProjectionCacheForTestOnly()

        let loaded = try store.openOrBootstrap()
        XCTAssertEqual(loaded.facts, [committedFact], "canonical facts must be unaffected by a corrupt projection cache")
        XCTAssertNotNil(loaded.projectionCacheFault, "an unusable snapshot must be recognized and discarded, never silently trusted")
    }

    // MARK: - Negotiation provenance

    func testNegotiationSnapshotsSurviveReopen() throws {
        let store = makeStore()
        _ = try store.openOrBootstrap()

        let snapshot = NegotiationSnapshot(
            id: NegotiationSnapshotID("snapshot-1"),
            contractVersion: ContractVersion(major: 1, minor: 0),
            adapterKind: "fixture.first-party",
            adapterBuildVersion: "0.1.0",
            productNamespace: ProductNamespace("claude-code"),
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            integrationMode: "fixtureObservation",
            capabilities: [CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available)],
            negotiatedAt: Date(timeIntervalSince1970: 1_752_000_000)
        )
        try store.registerNegotiation(snapshot)

        let loaded = try store.openOrBootstrap()
        XCTAssertEqual(loaded.negotiations, [snapshot])
    }

    func testCursorACPIdentityAndActionSnapshotSurviveReopen() throws {
        let configuration = ProtectedStoreConfiguration(databaseURL: root.appendingPathComponent("acp.sqlite"), keychainAccount: "ab139-acp-\(UUID().uuidString)")
        let store = ProtectedStore(configuration: configuration)
        _ = try store.openOrBootstrap()
        let session = CursorACPRecordedSession(integrationInstanceID: .init("acp-installation"), negotiationSnapshotID: .init("acp-snapshot"), identity: .init(productNamespace: .init("cursor.acp"), nativeSessionID: .init("source-returned-id")))
        let owner = GuidedAttentionOwner(productNamespace: .init("cursor.acp"), nativeSessionID: .init("source-returned-id"), nativeAttentionRequestID: "source-request", integrationInstanceID: .init("acp-installation"), negotiationSnapshotID: .init("acp-snapshot"))
        let attempt = ActionAttempt(id: "one", requestID: .init(productNamespace: owner.productNamespace, nativeSessionID: owner.nativeSessionID, nativeAttentionRequestID: owner.nativeAttentionRequestID), owner: owner, action: .allow, leaseID: "volatile-not-restored", reservedAt: Date(timeIntervalSince1970: 1), outcome: .dispatching, dispatchCount: 1)
        try store.recordCursorACPControlledSession(session)
        try store.commitCursorACPActionState(.init(attempts: [attempt]))

        let reopened = try ProtectedStore(configuration: configuration).openOrBootstrap()
        XCTAssertEqual(reopened.cursorACPControlledSessions, [session])
        XCTAssertEqual(reopened.cursorACPActionState?.attempts.first?.leaseID, nil)
        XCTAssertEqual(reopened.cursorACPActionState?.attempts.first?.outcome, .dispatching)
    }
}
