import Foundation
import Security
import Darwin
import StorageCore
import SQLCipher

public struct StoreConfiguration: Sendable {
    public let databaseURL: URL
    public let keychainAccount: String

    public init(databaseURL: URL, keychainAccount: String) {
        self.databaseURL = databaseURL
        self.keychainAccount = keychainAccount
    }
}

public final class PerInstallKeychainKey {
    private static let service = "com.agentisland.sqlcipher-protected-store-spike"
    private let account: String

    public init(account: String) { self.account = account }

    public func loadExisting() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let key = result as? Data, key.count == 32 else {
            throw ProtectedStoreFailure.missingKeychainKey
        }
        return key
    }

    /// Bootstrap only. Normal launch must use `loadExisting`, never recreate a
    /// missing key and thereby make old protected bytes appear unrecoverable.
    public func createIfMissing() throws -> Data {
        if let existing = try? loadExisting() { return existing }
        var key = Data(repeating: 0, count: 32)
        let randomStatus = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw ProtectedStoreFailure.missingKeychainKey }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem { return try loadExisting() }
        guard status == errSecSuccess else { throw ProtectedStoreFailure.missingKeychainKey }
        return key
    }

    public func deleteForTestOnly() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

/// This synchronous disposable spike is intentionally process-local and
/// single-writer; it is not Sendable and offers no cross-task database handle.
public final class ProtectedStore {
    private let configuration: StoreConfiguration
    private let keychain: PerInstallKeychainKey
    private let fileManager = FileManager.default

    public init(configuration: StoreConfiguration) {
        self.configuration = configuration
        self.keychain = PerInstallKeychainKey(account: configuration.keychainAccount)
    }

    public var stagingURL: URL { configuration.databaseURL.appendingPathExtension("staging") }
    private var rollbackURL: URL { configuration.databaseURL.appendingPathExtension("rollback") }

    public func bootstrap(records: [FixtureRecord]) throws -> DerivedProjection {
        try prepareParentDirectory()
        guard !fileManager.fileExists(atPath: configuration.databaseURL.path) else { return try openAndRebuildProjection() }
        guard !fileManager.fileExists(atPath: stagingURL.path) else { throw ProtectedStoreFailure.interruptedWrite }
        let key = try keychain.createIfMissing()
        let database = try CipherDatabase(url: configuration.databaseURL, key: key, create: true)
        defer { database.close() }
        try database.configureAndRequireSQLCipher()
        try database.replaceAtomically(records: records, schemaVersion: MigrationPolicy.currentSchema)
        try database.verify(expectedSchema: MigrationPolicy.currentSchema)
        return try ProjectionBuilder.rebuild(records: database.readRecords())
    }

    /// Evidence-harness setup only. It creates the immediately previous spike
    /// schema so the real staged migration path can be exercised; it is not
    /// callable by an application launch flow.
    public func bootstrapLegacySchemaForEvidenceOnly(records: [FixtureRecord]) throws {
        try prepareParentDirectory()
        guard !fileManager.fileExists(atPath: configuration.databaseURL.path) else { throw ProtectedStoreFailure.invalidSource }
        let key = try keychain.createIfMissing()
        let database = try CipherDatabase(url: configuration.databaseURL, key: key, create: true)
        defer { database.close() }
        try database.configureAndRequireSQLCipher()
        try database.replaceAtomically(records: records, schemaVersion: 1)
        try database.verify(expectedSchema: 1)
    }

    /// Durable write: SQLCipher transaction in DELETE journal mode, FULL sync,
    /// and all records/schema metadata committed together or not at all.
    public func write(records: [FixtureRecord], crashBeforeCommit: Bool = false) throws -> DerivedProjection {
        let database = try openVerifiedDatabase()
        defer { database.close() }
        try database.replaceAtomically(records: records, schemaVersion: MigrationPolicy.currentSchema, crashBeforeCommit: crashBeforeCommit)
        try database.verify(expectedSchema: MigrationPolicy.currentSchema)
        return try ProjectionBuilder.rebuild(records: database.readRecords())
    }

    public func openAndRebuildProjection() throws -> DerivedProjection {
        let database = try openVerifiedDatabase()
        defer { database.close() }
        return try ProjectionBuilder.rebuild(records: database.readRecords())
    }

    public func encryptedAtRest() throws -> Bool {
        let bytes = try Data(contentsOf: configuration.databaseURL, options: .mappedIfSafe)
        // An SQLCipher file must not expose SQLite's plaintext file signature.
        return !bytes.starts(with: Data("SQLite format 3\0".utf8))
    }

    /// A real SQLCipher proof must reject the same ciphertext under an
    /// unrelated key; this guards against a library that merely accepts the
    /// SQLCipher PRAGMA names but does not encrypt pages.
    public func rejectsWrongKeyForEvidence() throws -> Bool {
        var wrongKey = Data(repeating: 0, count: 32)
        guard wrongKey.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess else {
            throw ProtectedStoreFailure.encryptionUnavailable
        }
        do {
            let database = try CipherDatabase(url: configuration.databaseURL, key: wrongKey, create: false)
            defer { database.close() }
            try database.configureAndRequireSQLCipher()
            try database.verify(expectedSchema: nil)
            return false
        } catch {
            return true
        }
    }

    /// Staged migration: validate source, build/validate encrypted target,
    /// atomically replace, reopen/verify, and restore the preserved source if
    /// promotion verification fails. No source bytes are mutated beforehand.
    public func migrateIfNeeded(crashAfterStageVerification: Bool = false, failAfterStageVerification: Bool = false, failAfterPromotion: Bool = false) throws {
        try refuseInterruptedStage()
        let source = try openVerifiedDatabase()
        let sourceVersion: Int
        let records: [FixtureRecord]
        do {
            sourceVersion = try source.schemaVersion()
            records = try source.readRecords()
            try MigrationPolicy.validateSource(version: sourceVersion, recordCount: records.count)
        } catch let error as ProtectedStoreFailure {
            source.close(); throw error
        } catch {
            source.close(); throw ProtectedStoreFailure.migrationFailed
        }
        source.close()
        guard MigrationPolicy.needsMigration(version: sourceVersion) else { return }

        let key = try keychain.loadExisting()
        try? fileManager.removeItem(at: stagingURL)
        do {
            let target = try CipherDatabase(url: stagingURL, key: key, create: true)
            try target.configureAndRequireSQLCipher()
            try target.replaceAtomically(records: records, schemaVersion: MigrationPolicy.currentSchema)
            try target.verify(expectedSchema: MigrationPolicy.currentSchema)
            target.close()
            if crashAfterStageVerification || ProcessInfo.processInfo.environment["AB117_KILL_AFTER_STAGE_VERIFY"] == "1" { kill(getpid(), SIGKILL) }
            if failAfterStageVerification || ProcessInfo.processInfo.environment["AB117_INJECT_STAGE_FAILURE"] == "1" { throw ProtectedStoreFailure.migrationFailed }
            try promoteVerifiedStage(injectFailure: failAfterPromotion)
        } catch let error as ProtectedStoreFailure {
            throw error == .interruptedWrite ? error : .migrationFailed
        } catch {
            throw ProtectedStoreFailure.migrationFailed
        }
    }

    /// Explicit recovery action after an interrupted stage. It refuses to
    /// discard evidence until the promoted/source database has been verified.
    public func discardInterruptedStageAfterVerifyingPrimary() throws {
        guard fileManager.fileExists(atPath: stagingURL.path) else { return }
        let primary = try openVerifiedDatabase(allowStaging: true)
        primary.close()
        try fileManager.removeItem(at: stagingURL)
    }

    /// Only the smoke harness calls this to exercise the interrupted-write
    /// failure route. It does not alter the primary database.
    public func createInterruptedStageForTestOnly() throws {
        try Data("incomplete-stage".utf8).write(to: stagingURL, options: .atomic)
    }

    public func diagnostic(for error: Error, operation: String) -> RedactedDiagnostic {
        let failure = (error as? ProtectedStoreFailure) ?? .corruptDatabase
        return RedactedDiagnostic(code: failure.diagnosticCode, operation: operation)
    }

    private func openVerifiedDatabase(allowStaging: Bool = false) throws -> CipherDatabase {
        if !allowStaging { try refuseInterruptedStage() }
        guard fileManager.fileExists(atPath: configuration.databaseURL.path) else { throw ProtectedStoreFailure.corruptDatabase }
        let key = try keychain.loadExisting()
        do {
            let database = try CipherDatabase(url: configuration.databaseURL, key: key, create: false)
            try database.configureAndRequireSQLCipher()
            try database.verify(expectedSchema: nil)
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

    private func promoteVerifiedStage(injectFailure: Bool) throws {
        guard fileManager.fileExists(atPath: stagingURL.path) else { throw ProtectedStoreFailure.migrationFailed }
        try? fileManager.removeItem(at: rollbackURL)
        do {
            _ = try fileManager.replaceItemAt(
                configuration.databaseURL,
                withItemAt: stagingURL,
                backupItemName: rollbackURL.lastPathComponent,
                options: .usingNewMetadataOnly
            )
            if injectFailure || ProcessInfo.processInfo.environment["AB117_INJECT_PROMOTE_FAILURE"] == "1" { throw ProtectedStoreFailure.migrationFailed }
            let reopened = try openVerifiedDatabase(allowStaging: true)
            defer { reopened.close() }
            try reopened.verify(expectedSchema: MigrationPolicy.currentSchema)
            try? fileManager.removeItem(at: rollbackURL)
        } catch {
            if fileManager.fileExists(atPath: rollbackURL.path) {
                _ = try? fileManager.replaceItemAt(configuration.databaseURL, withItemAt: rollbackURL)
            }
            throw ProtectedStoreFailure.migrationFailed
        }
    }
}

private final class CipherDatabase {
    private var handle: OpaquePointer?

    init(url: URL, key: Data, create: Bool) throws {
        var db: OpaquePointer?
        let flags = Int32(SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0) | SQLITE_OPEN_FULLMUTEX)
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else { throw ProtectedStoreFailure.corruptDatabase }
        handle = db
        do { try execute("PRAGMA key = \"x'\(key.map { String(format: "%02x", $0) }.joined())'\";") }
        catch { close(); throw ProtectedStoreFailure.corruptDatabase }
    }

    deinit { close() }
    func close() { if let handle { sqlite3_close_v2(handle); self.handle = nil } }

    func configureAndRequireSQLCipher() throws {
        guard let version = try scalarText("PRAGMA cipher_version;"), !version.isEmpty else { throw ProtectedStoreFailure.encryptionUnavailable }
        try execute("PRAGMA cipher_memory_security = ON;")
        try execute("PRAGMA journal_mode = DELETE;")
        try execute("PRAGMA synchronous = FULL;")
        try execute("PRAGMA foreign_keys = ON;")
    }

    func replaceAtomically(records: [FixtureRecord], schemaVersion: Int, crashBeforeCommit: Bool = false) throws {
        _ = try ProjectionBuilder.rebuild(records: records) // validate before mutation
        try execute("CREATE TABLE IF NOT EXISTS spike_meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL) WITHOUT ROWID;")
        try execute("CREATE TABLE IF NOT EXISTS spike_records (source_id TEXT PRIMARY KEY NOT NULL, ordinal INTEGER NOT NULL, payload BLOB NOT NULL) WITHOUT ROWID;")
        do {
            try execute("BEGIN IMMEDIATE;")
            try execute("DELETE FROM spike_records;")
            try execute("DELETE FROM spike_meta;")
            try execute("INSERT INTO spike_meta(key, value) VALUES ('schema_version', '\(schemaVersion)');")
            for record in records { try insert(record: record) }
            if crashBeforeCommit || ProcessInfo.processInfo.environment["AB117_KILL_BEFORE_COMMIT"] == "1" { kill(getpid(), SIGKILL) }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func schemaVersion() throws -> Int {
        guard let value = try scalarText("SELECT value FROM spike_meta WHERE key = 'schema_version';"), let version = Int(value) else {
            throw ProtectedStoreFailure.corruptDatabase
        }
        return version
    }

    func readRecords() throws -> [FixtureRecord] {
        guard let handle else { throw ProtectedStoreFailure.corruptDatabase }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT payload FROM spike_records ORDER BY ordinal, source_id;", -1, &statement, nil) == SQLITE_OK, let statement else { throw ProtectedStoreFailure.corruptDatabase }
        defer { sqlite3_finalize(statement) }
        var records: [FixtureRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard let pointer = sqlite3_column_blob(statement, 0), count > 0 else { throw ProtectedStoreFailure.corruptDatabase }
            records.append(try JSONDecoder().decode(FixtureRecord.self, from: Data(bytes: pointer, count: count)))
        }
        guard sqlite3_errcode(handle) == SQLITE_OK || sqlite3_errcode(handle) == SQLITE_DONE else { throw ProtectedStoreFailure.corruptDatabase }
        return records
    }

    func verify(expectedSchema: Int?) throws {
        guard let cipherResult = try scalarText("PRAGMA cipher_integrity_check;"), cipherResult.lowercased() == "ok",
              let integrity = try scalarText("PRAGMA integrity_check;"), integrity.lowercased() == "ok" else {
            throw ProtectedStoreFailure.integrityCheckFailed
        }
        let version = try schemaVersion()
        try MigrationPolicy.validateSource(version: version, recordCount: try readRecords().count)
        if let expectedSchema, version != expectedSchema { throw ProtectedStoreFailure.migrationFailed }
    }

    private func insert(record: FixtureRecord) throws {
        guard let handle else { throw ProtectedStoreFailure.corruptDatabase }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "INSERT INTO spike_records(source_id, ordinal, payload) VALUES (?, ?, ?);", -1, &statement, nil) == SQLITE_OK, let statement else { throw ProtectedStoreFailure.corruptDatabase }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, record.sourceID, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int(statement, 2, Int32(record.ordinal)) == SQLITE_OK else { throw ProtectedStoreFailure.corruptDatabase }
        let data = try JSONEncoder.sorted.encode(record)
        let result = data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
        guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw ProtectedStoreFailure.corruptDatabase }
    }

    private func execute(_ sql: String) throws {
        guard let handle else { throw ProtectedStoreFailure.corruptDatabase }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else { sqlite3_free(error); throw ProtectedStoreFailure.corruptDatabase }
    }

    private func scalarText(_ sql: String) throws -> String? {
        guard let handle else { throw ProtectedStoreFailure.corruptDatabase }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ProtectedStoreFailure.corruptDatabase }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension JSONEncoder {
    static var sorted: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return encoder }
}
