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
        return try loadState(from: database)
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

        return LoadedState(facts: facts, negotiations: negotiations, projectionCacheFault: projectionCacheFault)
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
