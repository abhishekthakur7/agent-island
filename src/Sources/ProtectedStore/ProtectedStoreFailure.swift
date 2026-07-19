import SessionDomain

/// Fail-closed reasons for the encrypted local canonical store (ADR 0008).
/// None of these carry a path, key, SQL fragment, or Interaction Content —
/// they are safe to log, display, or attach to a Diagnostic Bundle as-is.
public enum ProtectedStoreFailure: Error, Equatable, Sendable {
    case missingKeychainKey
    /// A transient Keychain access problem (locked keychain, daemon busy, an
    /// ACL/interaction failure) — distinct from `missingKeychainKey`. Never
    /// conflate the two: this one must not offer a destructive discard/purge
    /// choice, since the key was never actually shown to be gone.
    case keychainUnavailable
    case corruptDatabase
    case interruptedWrite
    case unsupportedSchema(found: Int, supported: Int)
    case integrityCheckFailed
    case migrationFailed
    case encryptionUnavailable
    case invalidSource

    public var diagnosticCode: String {
        switch self {
        case .missingKeychainKey: "storage.keychain_key_missing"
        case .keychainUnavailable: "storage.keychain_unavailable"
        case .corruptDatabase: "storage.database_corrupt"
        case .interruptedWrite: "storage.interrupted_write"
        case .unsupportedSchema: "storage.schema_incompatible"
        case .integrityCheckFailed: "storage.integrity_failed"
        case .migrationFailed: "storage.migration_failed"
        case .encryptionUnavailable: "storage.sqlcipher_unavailable"
        case .invalidSource: "storage.source_invalid"
        }
    }

    /// The reduced, domain-safe reason `SessionStore` surfaces through
    /// `IntakeOutcome.storageUnavailable` — deliberately coarser than this
    /// type so `SessionDomain` never needs to know about SQLCipher/Keychain.
    public var redacted: StorageFailureReason {
        switch self {
        case .missingKeychainKey: .keychainKeyMissing
        case .keychainUnavailable: .unavailable
        case .corruptDatabase, .integrityCheckFailed, .encryptionUnavailable, .invalidSource: .integrityCheckFailed
        case .interruptedWrite: .interruptedWrite
        case .unsupportedSchema: .unsupportedSchema
        case .migrationFailed: .migrationFailed
        }
    }

    /// Whether this failure represents genuinely lost/corrupt state for
    /// which an explicit person-led discard/purge choice is appropriate
    /// (AB-119 AC5). A transient access problem never qualifies.
    public var isSafeToOfferDestructivePurge: Bool {
        self != .keychainUnavailable
    }
}

/// A redacted, structured diagnostic for one protected-store operation.
/// Never carries paths, SQL, keys, or record payloads — only a stable reason
/// code, the operation name, and (when relevant) the schema version.
public struct RedactedStorageDiagnostic: Sendable, Equatable {
    public let code: String
    public let operation: String
    public let schemaVersion: Int?

    public init(code: String, operation: String, schemaVersion: Int? = nil) {
        self.code = code
        self.operation = operation
        self.schemaVersion = schemaVersion
    }
}
