import Foundation

public enum UserDataExportFormat: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case json
    case jsonLines
}

/// Export classes are explicit and independently selectable. Product
/// configuration, credentials, leases, callback handles, and tokens have no
/// case and therefore cannot be accidentally selected.
public enum UserDataExportDataClass: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case sessionFacts
    case sessionProjection
    case sessionHistory
    case interactionContent
    case diagnostics
    case presentationPreferences
    case ownershipManifests
    case generatedSchema
    case cache
}

public struct UserDataExportDateScope: Codable, Equatable, Hashable, Sendable {
    public let from: Date?
    public let through: Date?

    public init(from: Date? = nil, through: Date? = nil) {
        self.from = from
        self.through = through
    }

    public func contains(_ date: Date) -> Bool {
        if let from, date < from { return false }
        if let through, date > through { return false }
        return true
    }

    public var isValid: Bool { from == nil || through == nil || from! <= through! }
}

public struct UserDataExportDestination: Codable, Equatable, Hashable, Sendable {
    public let file: URL

    public init(file: URL) throws {
        guard file.isFileURL else { throw UserDataExportError.destinationNotLocal }
        self.file = file.standardizedFileURL
    }

    public init(filePath: String) throws { try self.init(file: URL(fileURLWithPath: filePath)) }
}

public struct UserDataExportSelection: Codable, Equatable, Hashable, Sendable {
    public static let schemaVersion = 1
    public let sessions: [AgentSessionIdentity]
    public let dateScope: UserDataExportDateScope
    public let dataClasses: Set<UserDataExportDataClass>
    public let schema: Int
    public let format: UserDataExportFormat
    public let includeInteractionContent: Bool

    public init(
        sessions: [AgentSessionIdentity],
        dateScope: UserDataExportDateScope = UserDataExportDateScope(),
        dataClasses: Set<UserDataExportDataClass> = [.sessionFacts, .sessionProjection, .sessionHistory],
        schema: Int = UserDataExportSelection.schemaVersion,
        format: UserDataExportFormat = .json,
        includeInteractionContent: Bool = false
    ) {
        self.sessions = sessions.sorted { lhs, rhs in
            let l = "\(lhs.productNamespace.rawValue)\u{001F}\(lhs.nativeSessionID.rawValue)"
            let r = "\(rhs.productNamespace.rawValue)\u{001F}\(rhs.nativeSessionID.rawValue)"
            return l < r
        }
        self.dateScope = dateScope
        self.dataClasses = dataClasses
        self.schema = schema
        self.format = format
        self.includeInteractionContent = includeInteractionContent
    }

    public var contentSelected: Bool {
        includeInteractionContent || dataClasses.contains(.interactionContent)
    }

    public var normalized: Self {
        var classes = dataClasses
        if includeInteractionContent { classes.insert(.interactionContent) }
        return Self(sessions: sessions, dateScope: dateScope, dataClasses: classes, schema: schema, format: format, includeInteractionContent: includeInteractionContent)
    }
}

public enum UserDataExportError: Error, Codable, Equatable, Hashable, Sendable {
    case destinationNotLocal
    case destinationUnavailable
    case invalidSelection
    case confirmationRequired
    case stalePreview
    case noVerifiedRecords
    case writeFailed
    case integrityFailed
}

public struct UserDataExportPreview: Codable, Equatable, Hashable, Sendable {
    public let selection: UserDataExportSelection
    public let selectedSessionCount: Int
    public let verifiedRecordCount: Int
    public let selectedDataClasses: [UserDataExportDataClass]
    public let interactionContentSelected: Bool
    public let interactionContentConfirmationRequired: Bool
    public let previewDigest: String

    public init(selection: UserDataExportSelection, selectedSessionCount: Int, verifiedRecordCount: Int, previewDigest: String) {
        self.selection = selection.normalized
        self.selectedSessionCount = selectedSessionCount
        self.verifiedRecordCount = verifiedRecordCount
        self.selectedDataClasses = self.selection.dataClasses.sorted { $0.rawValue < $1.rawValue }
        self.interactionContentSelected = self.selection.contentSelected
        self.interactionContentConfirmationRequired = self.selection.contentSelected
        self.previewDigest = previewDigest
    }

    public var confirmation: UserDataExportConfirmation {
        UserDataExportConfirmation(previewDigest: previewDigest, confirmed: false, interactionContentConfirmed: false)
    }
}

public struct UserDataExportConfirmation: Codable, Equatable, Hashable, Sendable {
    public let previewDigest: String
    public let confirmed: Bool
    public let interactionContentConfirmed: Bool

    public init(previewDigest: String, confirmed: Bool = false, interactionContentConfirmed: Bool = false) {
        self.previewDigest = previewDigest
        self.confirmed = confirmed
        self.interactionContentConfirmed = interactionContentConfirmed
    }

    public func confirming(includeInteractionContent: Bool = false) -> Self {
        Self(previewDigest: previewDigest, confirmed: true, interactionContentConfirmed: includeInteractionContent)
    }

    public func confirmingInteractionContent() -> Self {
        Self(previewDigest: previewDigest, confirmed: true, interactionContentConfirmed: true)
    }
}

/// A verified projection assembled by the local store. It has no Action
/// Lease, callback token, raw Product configuration, or credentials field.
public struct VerifiedUserDataRecord: Codable, Sendable {
    public let identity: AgentSessionIdentity
    public let facts: [NormalizedEventFact]
    public let projection: SessionProjection?
    public let history: SessionHistoryRecord?
    public let interactionContent: [SessionHistoryContent]

    public init(identity: AgentSessionIdentity, facts: [NormalizedEventFact] = [], projection: SessionProjection? = nil, history: SessionHistoryRecord? = nil, interactionContent: [SessionHistoryContent] = []) {
        self.identity = identity
        self.facts = facts.sorted { $0.receiptOrdinal < $1.receiptOrdinal }
        self.projection = projection
        self.history = history
        self.interactionContent = interactionContent
    }
}

public struct UserDataExportIntegrityManifest: Codable, Equatable, Hashable, Sendable {
    public static let schemaVersion = 1
    public let schema: Int
    public let generatedAt: Date
    public let selectedSessionCount: Int
    public let verifiedRecordCount: Int
    public let contentIncluded: Bool
    public let byteCount: Int
    public let digest: String

    public init(generatedAt: Date, selectedSessionCount: Int, verifiedRecordCount: Int, contentIncluded: Bool, byteCount: Int, digest: String) {
        self.schema = Self.schemaVersion
        self.generatedAt = generatedAt
        self.selectedSessionCount = selectedSessionCount
        self.verifiedRecordCount = verifiedRecordCount
        self.contentIncluded = contentIncluded
        self.byteCount = byteCount
        self.digest = digest
    }
}

public struct UserDataExportEnvelope: Codable, Sendable {
    public let schema: Int
    public let generatedAt: Date
    public let selection: UserDataExportSelection
    public let records: [VerifiedUserDataRecord]
    public let integrity: UserDataExportIntegrityManifest

    public init(schema: Int, generatedAt: Date, selection: UserDataExportSelection, records: [VerifiedUserDataRecord], integrity: UserDataExportIntegrityManifest) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.selection = selection
        self.records = records
        self.integrity = integrity
    }
}

public struct UserDataExportArtifacts: Codable, Equatable, Hashable, Sendable {
    public let data: URL
    public let integrityManifest: URL

    public init(data: URL, integrityManifest: URL) {
        self.data = data
        self.integrityManifest = integrityManifest
    }
}

public enum UserDataExportWriter {
    public static func preview(selection: UserDataExportSelection, verifiedRecords: [VerifiedUserDataRecord], at date: Date = Date()) throws -> UserDataExportPreview {
        let normalized = selection.normalized
        guard normalized.schema == UserDataExportSelection.schemaVersion, normalized.dateScope.isValid, !normalized.sessions.isEmpty else { throw UserDataExportError.invalidSelection }
        let selected = filteredRecords(normalized, from: verifiedRecords)
        let digest = try selectionDigest(normalized, records: selected)
        return UserDataExportPreview(selection: normalized, selectedSessionCount: normalized.sessions.count, verifiedRecordCount: selected.count, previewDigest: digest)
    }

    public static func write(
        selection: UserDataExportSelection,
        verifiedRecords: [VerifiedUserDataRecord],
        confirmation: UserDataExportConfirmation,
        destination: UserDataExportDestination,
        at date: Date = Date()
    ) throws -> UserDataExportArtifacts {
        let preview = try preview(selection: selection, verifiedRecords: verifiedRecords, at: date)
        guard preview.verifiedRecordCount > 0 else { throw UserDataExportError.noVerifiedRecords }
        guard confirmation.confirmed, confirmation.previewDigest == preview.previewDigest else { throw UserDataExportError.confirmationRequired }
        if preview.interactionContentConfirmationRequired && !confirmation.interactionContentConfirmed {
            throw UserDataExportError.confirmationRequired
        }

        let records = filteredRecords(preview.selection, from: verifiedRecords)
            .map { record in
                let safeContent = UserDataExportRedaction.contentItems(record.interactionContent)
                guard preview.selection.contentSelected && confirmation.interactionContentConfirmed else {
                    return VerifiedUserDataRecord(identity: record.identity, facts: record.facts, projection: record.projection, history: record.history, interactionContent: [])
                }
                return VerifiedUserDataRecord(identity: record.identity, facts: record.facts, projection: record.projection, history: record.history, interactionContent: safeContent)
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let recordData = try encoder.encode(records)
        let digest = ExactEntryDigest.value(recordData)
        let manifest = UserDataExportIntegrityManifest(generatedAt: date, selectedSessionCount: preview.selectedSessionCount, verifiedRecordCount: records.count, contentIncluded: preview.selection.contentSelected && confirmation.interactionContentConfirmed, byteCount: recordData.count, digest: digest)
        let envelope = UserDataExportEnvelope(schema: preview.selection.schema, generatedAt: date, selection: preview.selection, records: records, integrity: manifest)
        let output: Data
        switch preview.selection.format {
        case .json:
            output = try encoder.encode(envelope)
        case .jsonLines:
            let lines = try records.map { try encoder.encode($0) }.map { String(data: $0, encoding: .utf8)! }.joined(separator: "\n") + "\n"
            output = Data(lines.utf8)
        }
        let fm = FileManager.default
        guard let parent = destination.file.deletingLastPathComponent().path as String?, fm.fileExists(atPath: parent) else { throw UserDataExportError.destinationUnavailable }
        let manifestURL = destination.file.appendingPathExtension("integrity.json")
        guard !fm.fileExists(atPath: destination.file.path), !fm.fileExists(atPath: manifestURL.path) else { throw UserDataExportError.writeFailed }
        do {
            try output.write(to: destination.file, options: [.atomic])
            try encoder.encode(manifest).write(to: manifestURL, options: [.atomic])
            return UserDataExportArtifacts(data: destination.file, integrityManifest: manifestURL)
        } catch {
            try? fm.removeItem(at: destination.file)
            try? fm.removeItem(at: manifestURL)
            throw UserDataExportError.writeFailed
        }
    }

    private static func selectionDigest(_ selection: UserDataExportSelection, records: [VerifiedUserDataRecord]) throws -> String {
        // Product-native IDs are opaque and may contain delimiter/control
        // characters. Confirmation therefore hashes a canonical structured
        // payload, never a delimiter-concatenated string. Every collection is
        // ordered before encoding so Set hash iteration cannot affect it.
        struct Identity: Codable {
            let productNamespace: String
            let nativeSessionID: String
        }
        struct Record: Codable {
            let identity: Identity
            let factCount: Int
        }
        struct Payload: Codable {
            let schema: Int
            let format: String
            let includeInteractionContent: Bool
            let dateScopeFrom: Date?
            let dateScopeThrough: Date?
            let sessions: [Identity]
            let dataClasses: [String]
            let records: [Record]
        }
        let identity: (AgentSessionIdentity) -> Identity = {
            Identity(productNamespace: $0.productNamespace.rawValue, nativeSessionID: $0.nativeSessionID.rawValue)
        }
        let sortedRecords = records.sorted {
            let lhs = ($0.identity.productNamespace.rawValue, $0.identity.nativeSessionID.rawValue, $0.facts.count)
            let rhs = ($1.identity.productNamespace.rawValue, $1.identity.nativeSessionID.rawValue, $1.facts.count)
            return lhs < rhs
        }.map { Record(identity: identity($0.identity), factCount: $0.facts.count) }
        let payload = Payload(
            schema: selection.schema,
            format: selection.format.rawValue,
            includeInteractionContent: selection.includeInteractionContent,
            dateScopeFrom: selection.dateScope.from,
            dateScopeThrough: selection.dateScope.through,
            sessions: selection.sessions.map(identity),
            dataClasses: selection.dataClasses.map(\.rawValue).sorted(),
            records: sortedRecords
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return ExactEntryDigest.value(try encoder.encode(payload))
    }

    private static func filteredRecords(_ selection: UserDataExportSelection, from records: [VerifiedUserDataRecord]) -> [VerifiedUserDataRecord] {
        records.filter { record in
            guard selection.sessions.contains(record.identity) else { return false }
            let dates = record.facts.map(\.receiptTime)
            return dates.isEmpty || dates.contains(where: selection.dateScope.contains)
        }
    }
}

/// Content export is the one user-data path that may carry Interaction
/// Content, but credentials and volatile authority remain forbidden even
/// after the explicit content confirmation. This bounded scanner is defense
/// in depth; the data model still has no credential/lease/token field.
public enum UserDataExportRedaction {
    private static let secretMarkers = [
        "password=", "passwd=", "api_key=", "apikey=", "access_token=", "refresh_token=",
        "bearer ", "credential=", "client_secret=", "callback_token=", "action_lease=", "secret=", "password", "secret"
    ]
    private static let volatileMarkers = ["credential", "callback", "action_lease", "token", "lease"]

    public static func contentItems(_ items: [SessionHistoryContent]) -> [SessionHistoryContent] {
        items.filter { item in
            let text = String(data: item.bytes, encoding: .utf8)?.lowercased() ?? ""
            let id = item.contentID.lowercased()
            guard !secretMarkers.contains(where: { text.contains($0) }) else { return false }
            guard item.classification == .interactionContent else { return true }
            return !volatileMarkers.contains(where: { text.contains($0) || id.contains($0) })
        }
    }
}

public typealias UserDataExportRequest = UserDataExportSelection
public typealias UserDataExportScopePreview = UserDataExportPreview
