import Foundation
import SQLCipher

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Current on-disk schema. `MigrationPolicy` is the only thing that needs to
/// change when a later ticket adds a new persisted shape.
enum MigrationPolicy {
    static let currentSchema = 1

    static func validateVersion(_ version: Int) throws {
        guard version > 0, version <= currentSchema else {
            throw version > currentSchema
                ? ProtectedStoreFailure.unsupportedSchema(found: version, supported: currentSchema)
                : ProtectedStoreFailure.invalidSource
        }
    }
}

/// Thin synchronous SQLCipher wrapper. Not Sendable on its own merit — it is
/// only ever touched from within `SessionStore`'s actor isolation, which is
/// what makes it single-writer (ADR 0008), matching the spike's proven shape.
final class CipherDatabase {
    private var handle: OpaquePointer?

    init(url: URL, key: Data, create: Bool) throws {
        var db: OpaquePointer?
        let flags = Int32(SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0) | SQLITE_OPEN_FULLMUTEX)
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw ProtectedStoreFailure.corruptDatabase
        }
        handle = db
        do {
            try execute("PRAGMA key = \"x'\(key.map { String(format: "%02x", $0) }.joined())'\";")
        } catch {
            close()
            throw ProtectedStoreFailure.corruptDatabase
        }
    }

    deinit { close() }

    func close() {
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    /// A normal macOS SQLite link must never be silently accepted as the
    /// canonical store: this requires the real SQLCipher PRAGMA surface.
    func configureAndRequireSQLCipher() throws {
        guard let version = try scalarText("PRAGMA cipher_version;"), !version.isEmpty else {
            throw ProtectedStoreFailure.encryptionUnavailable
        }
        try execute("PRAGMA cipher_memory_security = ON;")
        try execute("PRAGMA journal_mode = DELETE;")
        try execute("PRAGMA synchronous = FULL;")
        try execute("PRAGMA foreign_keys = ON;")
    }

    func createSchemaIfNeeded() throws {
        try execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL) WITHOUT ROWID;")
        try execute("CREATE TABLE IF NOT EXISTS facts (receipt_ordinal INTEGER PRIMARY KEY NOT NULL, payload BLOB NOT NULL);")
        try execute("CREATE TABLE IF NOT EXISTS negotiations (snapshot_id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL) WITHOUT ROWID;")
        try execute("""
        CREATE TABLE IF NOT EXISTS projection_cache (
            product_namespace TEXT NOT NULL,
            native_session_id TEXT NOT NULL,
            ledger_revision INTEGER NOT NULL,
            payload BLOB NOT NULL,
            PRIMARY KEY (product_namespace, native_session_id)
        ) WITHOUT ROWID;
        """)
    }

    func writeSchemaVersion(_ version: Int) throws {
        try execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', '\(version)');")
    }

    func schemaVersion() throws -> Int {
        guard let value = try scalarText("SELECT value FROM meta WHERE key = 'schema_version';"), let version = Int(value) else {
            throw ProtectedStoreFailure.corruptDatabase
        }
        return version
    }

    /// SQLCipher + SQLite page-level integrity, then a schema-version sanity
    /// check. Never treats a readable-but-wrong-shaped file as healthy.
    ///
    /// `cipher_integrity_check` returns one row *per problem found* — zero
    /// rows means no problems, not a single "ok" row like `integrity_check`.
    func verify() throws {
        guard try scalarText("PRAGMA cipher_integrity_check;") == nil else {
            throw ProtectedStoreFailure.integrityCheckFailed
        }
        guard let integrity = try scalarText("PRAGMA integrity_check;"), integrity.lowercased() == "ok" else {
            throw ProtectedStoreFailure.integrityCheckFailed
        }
        try MigrationPolicy.validateVersion(try schemaVersion())
    }

    func insertFact(receiptOrdinal: Int64, payload: Data) throws {
        try insertBlob(sql: "INSERT INTO facts(receipt_ordinal, payload) VALUES (?, ?);") { statement in
            guard sqlite3_bind_int64(statement, 1, receiptOrdinal) == SQLITE_OK else { throw ProtectedStoreFailure.corruptDatabase }
        } payload: { payload }

    }

    func upsertProjectionCache(productNamespace: String, nativeSessionID: String, ledgerRevision: Int64, payload: Data) throws {
        guard let handle else { throw ProtectedStoreFailure.corruptDatabase }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO projection_cache(product_namespace, native_session_id, ledger_revision, payload) VALUES (?, ?, ?, ?);"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ProtectedStoreFailure.corruptDatabase }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, productNamespace, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, nativeSessionID, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_int64(statement, 3, ledgerRevision) == SQLITE_OK
        else { throw ProtectedStoreFailure.corruptDatabase }
        let result = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32(payload.count), SQLITE_TRANSIENT) }
        guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw ProtectedStoreFailure.corruptDatabase }
    }

    func upsertNegotiation(snapshotID: String, payload: Data) throws {
        try insertBlob(sql: "INSERT OR REPLACE INTO negotiations(snapshot_id, payload) VALUES (?, ?);") { statement in
            guard sqlite3_bind_text(statement, 1, snapshotID, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw ProtectedStoreFailure.corruptDatabase }
        } payload: { payload }
    }

    func readFactPayloads() throws -> [Data] {
        try readBlobs(sql: "SELECT payload FROM facts ORDER BY receipt_ordinal;")
    }

    func readNegotiationPayloads() throws -> [Data] {
        try readBlobs(sql: "SELECT payload FROM negotiations ORDER BY snapshot_id;")
    }

    /// Best-effort: a caller decides whether a decode failure here means
    /// "discard the cache and rebuild from facts" (AB-119 AC6) rather than
    /// failing the whole reopen.
    func readProjectionCachePayloads() throws -> [Data] {
        try readBlobs(sql: "SELECT payload FROM projection_cache;")
    }

    func execute(_ sql: String) throws {
        guard let handle else { throw ProtectedStoreFailure.corruptDatabase }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            sqlite3_free(error)
            throw ProtectedStoreFailure.corruptDatabase
        }
    }

    func scalarText(_ sql: String) throws -> String? {
        guard let handle else { throw ProtectedStoreFailure.corruptDatabase }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ProtectedStoreFailure.corruptDatabase }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) }
    }

    private func insertBlob(sql: String, bindLeading: (OpaquePointer) throws -> Void, payload: () -> Data) throws {
        guard let handle else { throw ProtectedStoreFailure.corruptDatabase }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ProtectedStoreFailure.corruptDatabase }
        defer { sqlite3_finalize(statement) }
        try bindLeading(statement)
        let data = payload()
        let lastIndex = sqlite3_bind_parameter_count(statement)
        let result = data.withUnsafeBytes { sqlite3_bind_blob(statement, lastIndex, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
        guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw ProtectedStoreFailure.corruptDatabase }
    }

    private func readBlobs(sql: String) throws -> [Data] {
        guard let handle else { throw ProtectedStoreFailure.corruptDatabase }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ProtectedStoreFailure.corruptDatabase }
        defer { sqlite3_finalize(statement) }
        var results: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard let pointer = sqlite3_column_blob(statement, 0), count > 0 else { throw ProtectedStoreFailure.corruptDatabase }
            results.append(Data(bytes: pointer, count: count))
        }
        guard sqlite3_errcode(handle) == SQLITE_OK || sqlite3_errcode(handle) == SQLITE_DONE else { throw ProtectedStoreFailure.corruptDatabase }
        return results
    }
}
