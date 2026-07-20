import Foundation
import SessionDomain

/// Foreground local user-data export boundary. The caller supplies verified
/// records from the canonical store; this actor never reads Product files,
/// credentials, leases, callbacks, or arbitrary configuration.
public actor UserDataExportStore {
    private let verifiedRecords: [VerifiedUserDataRecord]

    public init(verifiedRecords: [VerifiedUserDataRecord] = []) {
        self.verifiedRecords = verifiedRecords
    }

    public func preview(selection: UserDataExportSelection, at date: Date = Date()) throws -> UserDataExportPreview {
        let filtered = records(matching: selection)
        return try UserDataExportWriter.preview(selection: selection, verifiedRecords: filtered, at: date)
    }

    public func write(
        selection: UserDataExportSelection,
        confirmation: UserDataExportConfirmation,
        destination: UserDataExportDestination,
        at date: Date = Date()
    ) throws -> UserDataExportArtifacts {
        let filtered = records(matching: selection)
        return try UserDataExportWriter.write(selection: selection, verifiedRecords: filtered, confirmation: confirmation, destination: destination, at: date)
    }

    public func verifiedSessionCount() -> Int { verifiedRecords.count }

    private func records(matching selection: UserDataExportSelection) -> [VerifiedUserDataRecord] {
        let scope = selection.dateScope
        return verifiedRecords.filter { record in
            guard selection.sessions.contains(record.identity) else { return false }
            let dates = record.facts.map(\.receiptTime)
            // Empty active projections are still selectable; they carry no
            // date evidence and remain visible for an explicit session scope.
            return dates.isEmpty || dates.contains(where: scope.contains)
        }
    }
}

public extension SessionStore {
    /// Builds a verified, non-content export snapshot from the public History
    /// boundary. SessionStore's protected fact ledger remains private; this
    /// projection intentionally cannot expose volatile authority or raw
    /// Product configuration.
    func verifiedUserDataRecords(for identities: [AgentSessionIdentity]) -> [VerifiedUserDataRecord] {
        var output: [VerifiedUserDataRecord] = []
        for identity in identities {
            if let history = historyRecord(for: identity) {
                output.append(VerifiedUserDataRecord(identity: identity, facts: history.facts, projection: history.projection, history: history, interactionContent: history.receivedContent))
            } else if let projection = workingSetProjections()[identity] {
                output.append(VerifiedUserDataRecord(identity: identity, projection: projection))
            }
        }
        return output
    }

    func makeUserDataExportStore(for identities: [AgentSessionIdentity]) -> UserDataExportStore {
        UserDataExportStore(verifiedRecords: verifiedUserDataRecords(for: identities))
    }
}
