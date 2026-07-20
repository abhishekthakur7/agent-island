import Foundation
import Security
import SessionDomain

public struct ProtectedStoreConfiguration: Sendable {
    public let databaseURL: URL
    public let keychainAccount: String

    public init(databaseURL: URL, keychainAccount: String) {
        self.databaseURL = databaseURL
        self.keychainAccount = keychainAccount
    }
}

/// Everything read back from the protected store at open. `facts` and
/// `negotiations` are the canonical evidence; `projectionCacheFault`, when
/// non-nil, records that the cached projection snapshot was unusable and was
/// discarded in favor of deterministically rebuilding from `facts` — it never
/// prevents an otherwise-healthy reopen (AB-119 AC6).
public struct LoadedState: Sendable {
    public let facts: [NormalizedEventFact]
    public let negotiations: [NegotiationSnapshot]
    public let projectionCacheFault: RedactedStorageDiagnostic?
    public let historyContent: [LoadedHistoryContent]
    public let historyRecaps: [LoadedHistoryRecap]
    public let historyBoundaries: [SessionHistoryDeletionBoundary]
    public let cursorACPControlledSessions: [CursorACPRecordedSession]
    public let cursorACPActionState: ActionAttemptStoreSnapshot?

    public init(
        facts: [NormalizedEventFact],
        negotiations: [NegotiationSnapshot],
        projectionCacheFault: RedactedStorageDiagnostic?,
        historyContent: [LoadedHistoryContent] = [],
        historyRecaps: [LoadedHistoryRecap] = [],
        historyBoundaries: [SessionHistoryDeletionBoundary] = [],
        cursorACPControlledSessions: [CursorACPRecordedSession] = [],
        cursorACPActionState: ActionAttemptStoreSnapshot? = nil
    ) {
        self.facts = facts
        self.negotiations = negotiations
        self.projectionCacheFault = projectionCacheFault
        self.historyContent = historyContent
        self.historyRecaps = historyRecaps
        self.historyBoundaries = historyBoundaries
        self.cursorACPControlledSessions = cursorACPControlledSessions
        self.cursorACPActionState = cursorACPActionState
    }
}

public struct LoadedHistoryContent: Sendable {
    public let identity: AgentSessionIdentity
    public let content: SessionHistoryContent

    public init(identity: AgentSessionIdentity, content: SessionHistoryContent) {
        self.identity = identity
        self.content = content
    }
}

public struct LoadedHistoryRecap: Sendable {
    public let identity: AgentSessionIdentity
    public let recap: SourcedSessionRecap

    public init(identity: AgentSessionIdentity, recap: SourcedSessionRecap) {
        self.identity = identity
        self.recap = recap
    }
}

/// The encrypted, per-installation-Keychain-keyed canonical store for Agent
/// Session facts, negotiation provenance, and the replaceable projection
/// cache. Single-writer per ADR 0008: only `SessionStore`'s actor isolation
/// ever calls into an instance of this type.
public final class ProtectedStore: @unchecked Sendable {
    private let configuration: ProtectedStoreConfiguration
    private let keychain: PerInstallKeychainKey
    private let fileManager = FileManager.default

    public init(configuration: ProtectedStoreConfiguration) {
        self.configuration = configuration
        self.keychain = PerInstallKeychainKey(account: configuration.keychainAccount)
    }

    public var stagingURL: URL { configuration.databaseURL.appendingPathExtension("staging") }
    private var rollbackURL: URL { configuration.databaseURL.appendingPathExtension("rollback") }

    /// Opens the existing protected store, or bootstraps a new empty one.
    /// Fails closed (throws `ProtectedStoreFailure`) rather than ever falling
    /// back to an unencrypted store or silently discarding prior bytes.
    public func openOrBootstrap() throws -> LoadedState {
        try prepareParentDirectory()
        try refuseInterruptedStage()

        guard fileManager.fileExists(atPath: configuration.databaseURL.path) else {
            let key = try keychain.createIfMissing()
            let database = try CipherDatabase(url: configuration.databaseURL, key: key, create: true)
            defer { database.close() }
            try database.configureAndRequireSQLCipher()
            try database.createSchemaIfNeeded()
            try database.writeSchemaVersion(MigrationPolicy.currentSchema)
            try database.verify()
            return LoadedState(facts: [], negotiations: [], projectionCacheFault: nil)
        }

        try migrateIfNeeded()
        let database = try openVerifiedDatabase()
        defer { database.close() }
        try database.createSchemaIfNeeded()
        try database.verify()
        return try loadState(from: database)
    }

    /// A wake/cold-resume integrity boundary. This is read-only with respect
    /// to evidence: it opens the existing encrypted bytes, checks SQLCipher,
    /// SQLite, and schema compatibility, and never recreates or overwrites a
    /// failed store.
    public func verifyForRecovery() throws {
        guard fileManager.fileExists(atPath: configuration.databaseURL.path) else {
            throw ProtectedStoreFailure.corruptDatabase
        }
        try refuseInterruptedStage()
        let database = try openVerifiedDatabase()
        defer { database.close() }
        try database.verify()
    }

    /// Atomically commits one durable fact together with the projection
    /// snapshot it produces. An interruption before `COMMIT` (a thrown error
    /// or a process kill — SQLite rolls both back identically) leaves the
    /// prior ledger state fully intact — never a partial fact or a ghost
    /// projection (AB-119 AC1). See `ProtectedStoreTests.testFailedCommitLeavesNoPartialFact`.
    public func commit(fact: NormalizedEventFact, projection: SessionProjection) throws {
        let database = try openVerifiedDatabase()
        defer { database.close() }
        let factPayload = try JSONEncoder.sorted.encode(fact)
        let projectionPayload = try JSONEncoder.sorted.encode(projection)
        do {
            try database.execute("BEGIN IMMEDIATE;")
            try database.insertFact(receiptOrdinal: fact.receiptOrdinal, payload: factPayload)
            try database.upsertProjectionCache(
                productNamespace: fact.identity.productNamespace.rawValue,
                nativeSessionID: fact.identity.nativeSessionID.rawValue,
                ledgerRevision: fact.receiptOrdinal,
                payload: projectionPayload
            )
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    public func registerNegotiation(_ snapshot: NegotiationSnapshot) throws {
        let database = try openVerifiedDatabase()
        defer { database.close() }
        let payload = try JSONEncoder.sorted.encode(snapshot)
        try database.execute("BEGIN IMMEDIATE;")
        do {
            try database.upsertNegotiation(snapshotID: snapshot.id.rawValue, payload: payload)
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    /// Writes only the source-returned ACP native identity, scoped to the
    /// exact integration/snapshot. No external Cursor session is adopted.
    public func recordCursorACPControlledSession(_ session: CursorACPRecordedSession) throws {
        let database = try openVerifiedDatabase()
        defer { database.close() }
        let payload = try JSONEncoder.sorted.encode(session)
        try database.execute("BEGIN IMMEDIATE;")
        do {
            try database.upsertCursorACPControlledSession(identity: identityKey(session.identity), payload: payload)
            try database.execute("COMMIT;")
        } catch { try? database.execute("ROLLBACK;"); throw error }
    }

    /// Replaces the ACP Guided snapshot atomically. The snapshot has no
    /// Action Lease; it is persisted before a native response can be written.
    public func commitCursorACPActionState(_ state: ActionAttemptStoreSnapshot) throws {
        let database = try openVerifiedDatabase()
        defer { database.close() }
        // Defense in depth: even a future SessionStore caller cannot persist
        // a live Action Lease/callback handle through this storage boundary.
        let sanitized = ActionAttemptStoreSnapshot(queue: state.queue, attempts: state.attempts.map {
            ActionAttempt(id: $0.id, requestID: $0.requestID, owner: $0.owner, action: $0.action, leaseID: nil, reservedAt: $0.reservedAt, outcome: $0.outcome, rejectionReason: $0.rejectionReason, dispatchCount: $0.dispatchCount, completedAt: $0.completedAt, productEvidence: $0.productEvidence)
        })
        let payload = try JSONEncoder.sorted.encode(sanitized)
        try database.execute("BEGIN IMMEDIATE;")
        do {
            try database.upsertCursorACPActionState(payload: payload)
            try database.execute("COMMIT;")
        } catch { try? database.execute("ROLLBACK;"); throw error }
    }

    /// Persists one authorized piece of received Interaction Content. The
    /// caller has already validated Product ownership; this method only
    /// performs the protected durable write.
    public func commitHistoryContent(_ content: SessionHistoryContent, for identity: AgentSessionIdentity) throws {
        let database = try openVerifiedDatabase()
        defer { database.close() }
        try database.createSchemaIfNeeded()
        let payload = try JSONEncoder.sorted.encode(content)
        try database.execute("BEGIN IMMEDIATE;")
        do {
            try database.upsertHistoryContent(identity: identityKey(identity), contentID: content.contentID, payload: payload)
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    public func commitHistoryRecap(_ recap: SourcedSessionRecap, for identity: AgentSessionIdentity) throws {
        let database = try openVerifiedDatabase()
        defer { database.close() }
        try database.createSchemaIfNeeded()
        let payload = try JSONEncoder.sorted.encode(recap)
        try database.execute("BEGIN IMMEDIATE;")
        do {
            try database.upsertHistoryRecap(identity: identityKey(identity), payload: payload)
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    /// Removes selected local history and writes its replay boundary in one
    /// protected transaction. Product data, setup, and other identities are
    /// never touched.
    public func deleteHistory(facts: [NormalizedEventFact], boundary: SessionHistoryDeletionBoundary) throws {
        let database = try openVerifiedDatabase()
        defer { database.close() }
        try database.createSchemaIfNeeded()
        try database.execute("BEGIN IMMEDIATE;")
        do {
            try database.deleteFacts(receiptOrdinals: facts.map(\.receiptOrdinal), identity: identityKey(boundary.identity))
            try database.deleteHistoryContent(identity: identityKey(boundary.identity))
            try database.deleteHistoryRecap(identity: identityKey(boundary.identity))
            let payload = try JSONEncoder.sorted.encode(boundary)
            try database.upsertHistoryBoundary(identity: identityKey(boundary.identity), payload: payload)
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    public func diagnostic(for error: Error, operation: String) -> RedactedStorageDiagnostic {
        let failure = (error as? ProtectedStoreFailure) ?? .corruptDatabase
        return RedactedStorageDiagnostic(code: failure.diagnosticCode, operation: operation)
    }

    // MARK: - Fault-injection / evidence-only surface

    public func encryptedAtRest() throws -> Bool {
        let bytes = try Data(contentsOf: configuration.databaseURL, options: .mappedIfSafe)
        return !bytes.starts(with: Data("SQLite format 3\0".utf8))
    }

    /// A real SQLCipher proof must reject the same ciphertext under an
    /// unrelated key, guarding against a library that accepts the PRAGMA
    /// names without actually encrypting pages.
    public func rejectsWrongKeyForEvidence() throws -> Bool {
        var wrongKey = Data(repeating: 0, count: 32)
        guard wrongKey.withUnsafeMutableBytes({ SecRandomCopyBytesShim($0) }) else {
            throw ProtectedStoreFailure.encryptionUnavailable
        }
        do {
            let database = try CipherDatabase(url: configuration.databaseURL, key: wrongKey, create: false)
            defer { database.close() }
            try database.configureAndRequireSQLCipher()
            try database.verify()
            return false
        } catch {
            return true
        }
    }

    /// Deletes the protected database, its staging/rollback artifacts, and
    /// the per-installation Keychain key. Only ever called after an explicit,
    /// person-confirmed purge choice (AB-119 AC5) — never automatically, and
    /// never on a normal fail-closed path.
    public func discardAllLocalDataAfterPersonConfirmedPurge() {
        for url in [configuration.databaseURL, stagingURL, rollbackURL] {
            try? fileManager.removeItem(at: url)
        }
        keychain.delete()
    }

    /// Test-only: deletes just the Keychain key so a fault-injection test can
    /// exercise the missing-key fail-closed path without touching the rest
    /// of the store.
    public func deleteKeychainKeyForTestOnly() { keychain.delete() }

    /// Writes an undecodable projection_cache row without touching the fact
    /// ledger, so a test can exercise the "invalid projection snapshot"
    /// recovery path (AB-119 AC6) in isolation.
    public func corruptProjectionCacheForTestOnly() throws {
        let key = try keychain.loadExisting()
        let database = try CipherDatabase(url: configuration.databaseURL, key: key, create: false)
        defer { database.close() }
        try database.configureAndRequireSQLCipher()
        try database.execute("BEGIN IMMEDIATE;")
        try database.execute("DELETE FROM projection_cache;")
        try database.upsertProjectionCache(productNamespace: "corrupt", nativeSessionID: "corrupt", ledgerRevision: 0, payload: Data([0xFF, 0x00, 0xDE, 0xAD]))
        try database.execute("COMMIT;")
    }

    public func createInterruptedStageForTestOnly() throws {
        try Data("incomplete-stage".utf8).write(to: stagingURL, options: .atomic)
    }

    /// Explicit, non-destructive recovery after an interrupted migration
    /// stage: verifies the primary is intact before discarding the stage.
    public func discardInterruptedStageAfterVerifyingPrimary() throws {
        guard fileManager.fileExists(atPath: stagingURL.path) else { return }
        let primary = try openVerifiedDatabase(allowStaging: true)
        primary.close()
        try fileManager.removeItem(at: stagingURL)
    }

    // MARK: - Internals

    private func loadState(from database: CipherDatabase) throws -> LoadedState {
        let facts = try database.readFactPayloads().map { try JSONDecoder.sorted.decode(NormalizedEventFact.self, from: $0) }
        let negotiations = try database.readNegotiationPayloads().map { try JSONDecoder.sorted.decode(NegotiationSnapshot.self, from: $0) }

        var projectionCacheFault: RedactedStorageDiagnostic?
        do {
            let cachePayloads = try database.readProjectionCachePayloads()
            for payload in cachePayloads {
                _ = try JSONDecoder.sorted.decode(SessionProjection.self, from: payload)
            }
        } catch {
            projectionCacheFault = RedactedStorageDiagnostic(code: "storage.projection_snapshot_invalid", operation: "open")
        }

        let historyContent = try database.readHistoryContent().compactMap { identityKey, payload -> LoadedHistoryContent? in
            guard let identity = Self.identity(from: identityKey), let content = try? JSONDecoder.sorted.decode(SessionHistoryContent.self, from: payload) else { return nil }
            return LoadedHistoryContent(identity: identity, content: content)
        }
        let historyRecaps = try database.readHistoryRecaps().compactMap { identityKey, payload -> LoadedHistoryRecap? in
            guard let identity = Self.identity(from: identityKey), let recap = try? JSONDecoder.sorted.decode(SourcedSessionRecap.self, from: payload) else { return nil }
            return LoadedHistoryRecap(identity: identity, recap: recap)
        }
        let historyBoundaries = try database.readHistoryBoundaryPayloads().compactMap { _, payload in
            try? JSONDecoder.sorted.decode(SessionHistoryDeletionBoundary.self, from: payload)
        }
        let cursorACPControlledSessions = try database.readCursorACPControlledSessionPayloads().compactMap { try? JSONDecoder.sorted.decode(CursorACPRecordedSession.self, from: $0) }
        let cursorACPActionState = try database.readCursorACPActionStatePayload().flatMap { try? JSONDecoder.sorted.decode(ActionAttemptStoreSnapshot.self, from: $0) }
        return LoadedState(facts: facts, negotiations: negotiations, projectionCacheFault: projectionCacheFault, historyContent: historyContent, historyRecaps: historyRecaps, historyBoundaries: historyBoundaries, cursorACPControlledSessions: cursorACPControlledSessions, cursorACPActionState: cursorACPActionState)
    }

    private func identityKey(_ identity: AgentSessionIdentity) -> String {
        "\(identity.productNamespace.rawValue)\u{001F}\(identity.nativeSessionID.rawValue)"
    }

    private static func identity(from key: String) -> AgentSessionIdentity? {
        let parts = key.split(separator: "\u{001F}", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return AgentSessionIdentity(productNamespace: ProductNamespace(String(parts[0])), nativeSessionID: NativeSessionID(String(parts[1])))
    }

    /// Staged migration: validate the source without mutating it, build and
    /// verify an encrypted `.staging` target, atomically replace, reopen and
    /// re-verify, and restore the preserved `.rollback` copy if promotion
    /// verification fails. No source bytes are ever mutated ahead of a
    /// verified promotion.
    private func migrateIfNeeded() throws {
        try refuseInterruptedStage()
        let source = try openVerifiedDatabase()
        let sourceVersion: Int
        do {
            sourceVersion = try source.schemaVersion()
            try MigrationPolicy.validateVersion(sourceVersion)
        } catch let error as ProtectedStoreFailure {
            source.close()
            throw error
        } catch {
            source.close()
            throw ProtectedStoreFailure.migrationFailed
        }
        source.close()
        guard sourceVersion < MigrationPolicy.currentSchema else { return }

        let key = try keychain.loadExisting()
        try? fileManager.removeItem(at: stagingURL)
        do {
            let target = try CipherDatabase(url: stagingURL, key: key, create: true)
            try target.configureAndRequireSQLCipher()
            try target.createSchemaIfNeeded()
            try target.writeSchemaVersion(MigrationPolicy.currentSchema)
            try target.verify()
            target.close()
            try promoteVerifiedStage()
        } catch let error as ProtectedStoreFailure {
            throw error == .interruptedWrite ? error : .migrationFailed
        } catch {
            throw ProtectedStoreFailure.migrationFailed
        }
    }

    private func promoteVerifiedStage() throws {
        guard fileManager.fileExists(atPath: stagingURL.path) else { throw ProtectedStoreFailure.migrationFailed }
        try? fileManager.removeItem(at: rollbackURL)
        do {
            _ = try fileManager.replaceItemAt(
                configuration.databaseURL,
                withItemAt: stagingURL,
                backupItemName: rollbackURL.lastPathComponent,
                options: .usingNewMetadataOnly
            )
            let reopened = try openVerifiedDatabase(allowStaging: true)
            defer { reopened.close() }
            try reopened.verify()
            try? fileManager.removeItem(at: rollbackURL)
        } catch {
            if fileManager.fileExists(atPath: rollbackURL.path) {
                _ = try? fileManager.replaceItemAt(configuration.databaseURL, withItemAt: rollbackURL)
            }
            throw ProtectedStoreFailure.migrationFailed
        }
    }

    private func openVerifiedDatabase(allowStaging: Bool = false) throws -> CipherDatabase {
        if !allowStaging { try refuseInterruptedStage() }
        guard fileManager.fileExists(atPath: configuration.databaseURL.path) else { throw ProtectedStoreFailure.corruptDatabase }
        let key = try keychain.loadExisting()
        do {
            let database = try CipherDatabase(url: configuration.databaseURL, key: key, create: false)
            try database.configureAndRequireSQLCipher()
            try database.verify()
            return database
        } catch let error as ProtectedStoreFailure {
            throw error
        } catch {
            throw ProtectedStoreFailure.corruptDatabase
        }
    }

    private func refuseInterruptedStage() throws {
        if fileManager.fileExists(atPath: stagingURL.path) { throw ProtectedStoreFailure.interruptedWrite }
    }

    private func prepareParentDirectory() throws {
        try fileManager.createDirectory(at: configuration.databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}

private func SecRandomCopyBytesShim(_ buffer: UnsafeMutableRawBufferPointer) -> Bool {
    guard let baseAddress = buffer.baseAddress else { return false }
    return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress) == errSecSuccess
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var sorted: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
