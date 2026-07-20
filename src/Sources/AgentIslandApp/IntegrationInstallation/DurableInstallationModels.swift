import Foundation
import LocalProductDiscovery
import SessionDomain

/// The durable, non-secret record for one installation transaction. It keeps
/// transaction metadata alongside optional manifest-proven ownership evidence,
/// never an external configuration body.
struct DurableInstallationManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let installationID: String
    let product: DurableInstallationProduct
    let configurationPath: String
    let managedEntryIdentifiers: [String]
    let ownershipManifest: OwnershipManifest?
    let verifiedProductIdentity: VerifiedProductIdentity?
    let createdAt: Date
    let updatedAt: Date

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        installationID: String,
        product: DurableInstallationProduct,
        configurationPath: String,
        managedEntryIdentifiers: [String],
        ownershipManifest: OwnershipManifest? = nil,
        verifiedProductIdentity: VerifiedProductIdentity? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.installationID = installationID
        self.product = product
        self.configurationPath = configurationPath
        self.managedEntryIdentifiers = managedEntryIdentifiers
        self.ownershipManifest = ownershipManifest
        self.verifiedProductIdentity = verifiedProductIdentity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A compact write-ahead record.  It has no configuration body, credentials,
/// hook environment, or product-owned content.
struct DurableInstallationJournal: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    enum Phase: String, Codable, Sendable {
        case prepared
        case configWritten
        case manifestWritten
        case completed
        case rolledBack
    }

    let schemaVersion: Int
    let transactionID: String
    let installationID: String
    let phase: Phase
    let configurationPath: String
    let configurationDigest: String?
    let recordedAt: Date

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        transactionID: String,
        installationID: String,
        phase: Phase,
        configurationPath: String,
        configurationDigest: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.transactionID = transactionID
        self.installationID = installationID
        self.phase = phase
        self.configurationPath = configurationPath
        self.configurationDigest = configurationDigest
        self.recordedAt = recordedAt
    }
}

enum DurableInstallationProduct: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
}

enum DurableInstallationError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedSchema(found: Int, supported: Int)
    case invalidApplicationSupportDirectory(String)
    case unsafePath(String)
    case invalidFileType(String)
    case foreignOwner(path: String, owner: UInt32)
    case permissionDenied(path: String, mode: UInt16)
    case lockFailed(String)
    case io(operation: String, code: Int32)
    case encodingFailed
    case decodingFailed
    case configurationAmbiguous([String])
    case configurationMissing(String)
    case configurationChanged(String)
    case unsupportedMetadata(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(found, supported):
            "Unsupported durable installation schema \(found); this version supports \(supported)."
        case let .invalidApplicationSupportDirectory(path): "Invalid Application Support directory: \(path)"
        case let .unsafePath(path): "Refusing unsafe path: \(path)"
        case let .invalidFileType(path): "Expected a regular file or directory at: \(path)"
        case let .foreignOwner(path, owner): "Refusing \(path), owned by uid \(owner)."
        case let .permissionDenied(path, mode): "Refusing \(path), whose mode is \(String(mode, radix: 8))."
        case let .lockFailed(path): "Could not lock durable installation state at \(path)."
        case let .io(operation, code): "\(operation) failed (errno \(code))."
        case .encodingFailed: "Could not encode durable installation state."
        case .decodingFailed: "Could not decode durable installation state."
        case let .configurationAmbiguous(paths): "More than one configuration candidate exists: \(paths.joined(separator: ", "))."
        case let .configurationMissing(path): "Configuration does not exist: \(path)"
        case let .configurationChanged(path): "Configuration changed while preparing to write: \(path)"
        case let .unsupportedMetadata(path): "Refusing \(path) because extended attributes or ACLs require manual preservation."
        }
    }
}
