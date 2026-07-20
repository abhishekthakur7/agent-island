import Foundation
import SessionDomain

/// One-way future Service Egress seam.  Implementations receive an already
/// classified, purpose-consented copy and return only a redacted outcome.
/// There are deliberately no read, merge, lifecycle, action, configuration,
/// presentation, or store/key operations on this protocol.
public protocol ServiceEgressPort: Sendable {
    func dispatch(_ changeSet: ServiceEgressChangeSet) async -> ServiceEgressPortOutcome
}

public struct ServiceEgressPortOutcome: Codable, Equatable, Hashable, Sendable {
    public let status: ServiceEgressDispatchStatus
    public let reason: ServiceEgressDispatchReason

    public init(status: ServiceEgressDispatchStatus, reason: ServiceEgressDispatchReason) {
        self.status = status
        self.reason = reason
    }

    public static let delivered = Self(status: .delivered, reason: .delivered)
    public static let unavailable = Self(status: .unavailable, reason: .portUnavailable)
    public static let incompatible = Self(status: .incompatible, reason: .portIncompatible)
    public static let failed = Self(status: .failed, reason: .portFailed)
    public static let rejected = Self(status: .denied, reason: .portRejected)
}

public enum ServiceEgressOutboxError: String, Codable, Equatable, Hashable, Sendable, Error, CaseIterable {
    case duplicateChangeSet
}

/// A local, in-memory outbox seam.  Appending and draining are explicit
/// operations; there is no background worker, retry loop, or network identity.
public actor ServiceEgressOutbox {
    private var pendingChangeSets: [ServiceEgressChangeSet] = []

    public init() {}

    @discardableResult
    public func append(_ changeSet: ServiceEgressChangeSet) throws -> Bool {
        try changeSet.validate()
        guard !pendingChangeSets.contains(where: { $0.id == changeSet.id }) else {
            throw ServiceEgressOutboxError.duplicateChangeSet
        }
        pendingChangeSets.append(changeSet)
        return true
    }

    public func pending() -> [ServiceEgressChangeSet] { pendingChangeSets }

    /// Draining is a single attempt.  A port failure is recorded by the
    /// dispatcher and the change set is not silently retried.
    public func drain() -> [ServiceEgressChangeSet] {
        let drained = pendingChangeSets
        pendingChangeSets.removeAll()
        return drained
    }

    @discardableResult
    public func delete(purpose: ServiceEgressPurpose) -> Int {
        let before = pendingChangeSets.count
        pendingChangeSets.removeAll { $0.purpose == purpose }
        return before - pendingChangeSets.count
    }

    public func deleteAll() {
        pendingChangeSets.removeAll()
    }
}

/// Local consent state is separate per purpose and intentionally has no
/// destination/account configuration.  `delete` removes only that purpose's
/// consent record and queued copies.
public actor ServiceEgressConsentLedger {
    private var records: [ServiceEgressPurpose: ServiceEgressConsent] = [:]
    private var revokedWithoutGrant: [ServiceEgressPurpose: Date] = [:]

    public init() {}

    @discardableResult
    public func grant(_ consent: ServiceEgressConsent) -> ServiceEgressConsentSnapshot {
        records[consent.purpose] = consent
        revokedWithoutGrant.removeValue(forKey: consent.purpose)
        return snapshot(for: consent.purpose)
    }

    @discardableResult
    public func revoke(purpose: ServiceEgressPurpose, at date: Date) -> ServiceEgressConsentSnapshot {
        if let existing = records[purpose] {
            records[purpose] = existing.revoked(at: date)
            return snapshot(for: purpose)
        }
        revokedWithoutGrant[purpose] = date
        return ServiceEgressConsentSnapshot(purpose: purpose, status: .revoked, changedAt: date)
    }

    @discardableResult
    public func delete(purpose: ServiceEgressPurpose) -> ServiceEgressConsentSnapshot {
        records.removeValue(forKey: purpose)
        revokedWithoutGrant.removeValue(forKey: purpose)
        return snapshot(for: purpose)
    }

    public func consent(for purpose: ServiceEgressPurpose) -> ServiceEgressConsent? { records[purpose] }

    public func snapshot(for purpose: ServiceEgressPurpose) -> ServiceEgressConsentSnapshot {
        guard let consent = records[purpose] else {
            if let revokedAt = revokedWithoutGrant[purpose] {
                return ServiceEgressConsentSnapshot(purpose: purpose, status: .revoked, changedAt: revokedAt)
            }
            return ServiceEgressConsentSnapshot(purpose: purpose, status: .disabled)
        }
        return ServiceEgressConsentSnapshot(
            purpose: purpose,
            status: consent.isRevoked ? .revoked : .granted,
            version: consent.version,
            changedAt: consent.revokedAt ?? consent.grantedAt
        )
    }

    public func snapshots() -> [ServiceEgressConsentSnapshot] {
        ServiceEgressPurpose.allCases.map { snapshot(for: $0) }
    }
}

/// Coordinates consent checking and one-way delivery without knowing
/// anything about the canonical store.  Local callers enqueue after their
/// own commit; dispatch is a separate explicit operation and therefore cannot
/// delay or replace a fact commit.
public actor ServiceEgressDispatcher {
    private let port: (any ServiceEgressPort)?
    private let outbox: ServiceEgressOutbox
    private let consent: ServiceEgressConsentLedger
    private var diagnostics: [ServiceEgressDiagnostic] = []

    public init(
        port: (any ServiceEgressPort)? = nil,
        outbox: ServiceEgressOutbox = ServiceEgressOutbox(),
        consent: ServiceEgressConsentLedger = ServiceEgressConsentLedger()
    ) {
        self.port = port
        self.outbox = outbox
        self.consent = consent
    }

    public func enqueue(_ changeSet: ServiceEgressChangeSet) async throws {
        try await outbox.append(changeSet)
    }

    public func pending() async -> [ServiceEgressChangeSet] { await outbox.pending() }

    public func grant(_ record: ServiceEgressConsent) async -> ServiceEgressConsentSnapshot {
        await consent.grant(record)
    }

    public func revoke(purpose: ServiceEgressPurpose, at date: Date) async -> ServiceEgressConsentSnapshot {
        await consent.revoke(purpose: purpose, at: date)
    }

    /// Purpose-specific disable/delete.  It cannot affect another purpose or
    /// local canonical state.
    @discardableResult
    public func disableAndDelete(purpose: ServiceEgressPurpose, at date: Date) async -> Int {
        _ = await consent.delete(purpose: purpose)
        return await outbox.delete(purpose: purpose)
    }

    public func consentSnapshot(for purpose: ServiceEgressPurpose) async -> ServiceEgressConsentSnapshot {
        await consent.snapshot(for: purpose)
    }

    public func consentSnapshots() async -> [ServiceEgressConsentSnapshot] {
        await consent.snapshots()
    }

    public func diagnosticsSnapshot() -> [ServiceEgressDiagnostic] { diagnostics }

    /// Performs at most one attempt for each currently queued copy.  Absent,
    /// disabled, revoked, rejected, and failing ports all produce local
    /// redacted evidence and leave no delivery claim.
    @discardableResult
    public func dispatchPending(at date: Date) async -> [ServiceEgressDiagnostic] {
        let changeSets = await outbox.drain()
        var outcomes: [ServiceEgressDiagnostic] = []
        for changeSet in changeSets {
            let diagnostic: ServiceEgressDiagnostic
            guard let current = await consent.consent(for: changeSet.purpose) else {
                let snapshot = await consent.snapshot(for: changeSet.purpose)
                let reason: ServiceEgressDispatchReason = snapshot.status == .revoked ? .consentRevoked : .consentNotGranted
                diagnostic = ServiceEgressDiagnostic(changeSetID: changeSet.id, purpose: changeSet.purpose, status: .denied, reason: reason, occurredAt: date)
                outcomes.append(diagnostic)
                continue
            }
            guard current.version == changeSet.consentVersion,
                  current.grantedAt == changeSet.consentGrantedAt,
                  current.allowsDispatch(at: date)
            else {
                let reason: ServiceEgressDispatchReason
                if current.isRevoked {
                    reason = .consentRevoked
                } else if current.version != changeSet.consentVersion || current.grantedAt != changeSet.consentGrantedAt {
                    reason = .consentVersionChanged
                } else {
                    reason = .purposeDisabled
                }
                diagnostic = ServiceEgressDiagnostic(changeSetID: changeSet.id, purpose: changeSet.purpose, status: .denied, reason: reason, occurredAt: date)
                outcomes.append(diagnostic)
                continue
            }
            guard let port else {
                diagnostic = ServiceEgressDiagnostic(changeSetID: changeSet.id, purpose: changeSet.purpose, status: .unavailable, reason: .noPort, occurredAt: date)
                outcomes.append(diagnostic)
                continue
            }
            let portOutcome = await port.dispatch(changeSet)
            diagnostic = ServiceEgressDiagnostic(changeSetID: changeSet.id, purpose: changeSet.purpose, status: portOutcome.status, reason: portOutcome.reason, occurredAt: date)
            outcomes.append(diagnostic)
        }
        diagnostics.append(contentsOf: outcomes)
        return outcomes
    }
}
