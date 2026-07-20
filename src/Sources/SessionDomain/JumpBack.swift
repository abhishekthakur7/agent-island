import Foundation

public enum JumpBackTrigger: String, CaseIterable, Hashable, Sendable, Codable {
    case explicitPersonAction
    case cardSelection
    case notificationDisplay
    case automaticReveal
    case reconciliation
    case overlayActivation
}

public struct JumpBackRequest: Hashable, Sendable, Codable {
    public let attemptID: String
    public let sessionIdentity: AgentSessionIdentity
    public let trigger: JumpBackTrigger
    public let selectedAssociationID: HostContextID?
    public let negotiation: NegotiationSnapshot?
    public let requestedAt: Date

    public init(
        attemptID: String = "",
        sessionIdentity: AgentSessionIdentity,
        trigger: JumpBackTrigger = .explicitPersonAction,
        selectedAssociationID: HostContextID? = nil,
        negotiation: NegotiationSnapshot?,
        requestedAt: Date
    ) {
        self.attemptID = attemptID
        self.sessionIdentity = sessionIdentity
        self.trigger = trigger
        self.selectedAssociationID = selectedAssociationID
        self.negotiation = negotiation
        self.requestedAt = requestedAt
    }
}

public enum JumpBackReason: Hashable, Sendable, Codable {
    case reached
    case reachedFallback(from: HostNavigationLevel, to: HostNavigationLevel)
    case revalidationFailed(HostNavigationRevalidationReason)
    case ambiguous(level: HostNavigationLevel)
    case dispatchFailed(HostNavigationRevalidationReason)
    case noAssociation
    case notExplicitPersonAction

    public var redactedDescription: String {
        switch self {
        case .reached: "Navigation reached the proven Host Context."
        case .reachedFallback(let from, let to): "The stronger Host target was unavailable; navigation reached the separately proven \(to.label) fallback from \(from.label)."
        case .revalidationFailed(let reason): reason.redactedDescription
        case .ambiguous(let level): "The \(level.label) Host target was ambiguous; no similar-looking context was selected."
        case .dispatchFailed(let reason): reason.redactedDescription
        case .noAssociation: "No Host Context evidence is associated with this Agent Session."
        case .notExplicitPersonAction: "Jump Back requires an explicit person action."
        }
    }
}

/// A redacted, durable-shaped record of the candidate and attempt.  The
/// coordinator does not persist it itself; the central shell can append this
/// value through its normal local store boundary.
public struct JumpBackAttemptRecord: Hashable, Sendable, Codable {
    public let attemptID: String
    public let sessionIdentity: AgentSessionIdentity
    public let trigger: JumpBackTrigger
    public let candidateAssociationID: HostContextID?
    public let candidateLocator: HostLocator?
    public let outcome: JumpBackOutcome

    public init(
        attemptID: String,
        sessionIdentity: AgentSessionIdentity,
        trigger: JumpBackTrigger,
        candidateAssociationID: HostContextID?,
        candidateLocator: HostLocator?,
        outcome: JumpBackOutcome
    ) {
        self.attemptID = attemptID
        self.sessionIdentity = sessionIdentity
        self.trigger = trigger
        self.candidateAssociationID = candidateAssociationID
        self.candidateLocator = candidateLocator
        self.outcome = outcome
    }
}

/// Visual, VoiceOver, and redacted diagnostic surfaces all derive from this
/// one truthful outcome.  Navigation has no Product action or lifecycle
/// authority and never restores an Action Lease.
public struct JumpBackOutcome: Hashable, Sendable, Codable {
    public let sessionIdentity: AgentSessionIdentity
    public let host: HostKind?
    public let qualifier: HostNavigationLevel
    public let achievedLevel: HostNavigationLevel
    public let occurredAt: Date
    public let reason: JumpBackReason
    public let candidateAssociationID: HostContextID?
    public let navigationPerformed: Bool

    public let productActionGranted: Bool
    public let actionLeaseRestored: Bool
    public let productLifecycleChanged: Bool

    public init(
        sessionIdentity: AgentSessionIdentity,
        host: HostKind?,
        qualifier: HostNavigationLevel,
        occurredAt: Date,
        reason: JumpBackReason,
        candidateAssociationID: HostContextID? = nil,
        navigationPerformed: Bool = false
    ) {
        self.sessionIdentity = sessionIdentity
        self.host = host
        self.qualifier = qualifier
        self.achievedLevel = qualifier
        self.occurredAt = occurredAt
        self.reason = reason
        self.candidateAssociationID = candidateAssociationID
        self.navigationPerformed = navigationPerformed
        self.productActionGranted = false
        self.actionLeaseRestored = false
        self.productLifecycleChanged = false
    }

    public var timestamp: Date { occurredAt }
    public var hostName: String { host?.displayName ?? "Unknown Host" }
    public var reasonText: String { reason.redactedDescription }

    /// Keep UI/VoiceOver wording aligned and explicit about fallback level.
    public var presentationLabel: String {
        if host == .warp {
            let achievement: String
            switch qualifier {
            case .windowBestEffort: achievement = "Brought forward one elected Warp window best-effort; the original Warp pane and tab were not verified."
            case .appOnly: achievement = "Opened Warp; the original Warp pane and tab were not verified."
            case .unavailable: achievement = "No supported Warp navigation was performed; the original Warp pane and tab were not verified."
            case .exactSurface, .exactTab, .workspaceOrFile: achievement = "Warp does not support this claimed Jump Back level."
            }
            return "Jump Back: Warp, \(qualifier.label). \(achievement) \(reasonText)"
        }
        let achievement: String
        switch qualifier {
        case .exactSurface: achievement = "Opened the exact Host surface."
        case .exactTab: achievement = "Opened the exact tab; select the pane."
        case .appOnly: achievement = "Opened the Host application; the original context was not verified."
        case .workspaceOrFile: achievement = "Opened the separately proven workspace or file; the original context was not verified."
        case .windowBestEffort: achievement = "Brought forward a best-effort Host window; the original context was not verified."
        case .unavailable: achievement = "No supported Host navigation was performed."
        }
        return "Jump Back: \(hostName), \(qualifier.label). \(achievement) \(reasonText)"
    }

    public var voiceOverLabel: String { presentationLabel }
    public var visualSummary: String { presentationLabel }
    public var redactedDiagnostic: String {
        "host=\(hostName) qualifier=\(qualifier.label) time=\(occurredAt.timeIntervalSince1970) reason=\(reasonText)"
    }
}

/// Coordinator enforcing the only entry point for Jump Back.  It looks up
/// evidence by exact Agent Session identity, revalidates immediately before
/// each dispatch, and tries only separately proven lower levels.
public struct JumpBackCoordinator: Sendable {
    private let evidence: HostContextEvidenceStore
    private let port: any HostNavigationPort

    public init(evidence: HostContextEvidenceStore, port: any HostNavigationPort) {
        self.evidence = evidence
        self.port = port
    }

    public func attempt(_ request: JumpBackRequest) -> JumpBackAttemptRecord {
        let associations = selectedAssociations(for: request)
        guard request.trigger == .explicitPersonAction else {
            let outcome = JumpBackOutcome(
                sessionIdentity: request.sessionIdentity,
                host: associations.first?.host,
                qualifier: .unavailable,
                occurredAt: request.requestedAt,
                reason: .notExplicitPersonAction
            )
            return record(request, candidate: nil, outcome: outcome)
        }

        guard !associations.isEmpty else {
            let outcome = JumpBackOutcome(
                sessionIdentity: request.sessionIdentity,
                host: nil,
                qualifier: .unavailable,
                occurredAt: request.requestedAt,
                reason: .noAssociation
            )
            return record(request, candidate: nil, outcome: outcome)
        }

        // Revalidation is deliberately repeated for each potential attempt.
        // This closes the race where a Host restarts between a stronger and a
        // lower fallback dispatch.
        var initial: [Candidate] = []
        for association in associations {
            let revalidation = port.revalidate(
                association,
                for: request.sessionIdentity,
                negotiation: request.negotiation,
                at: request.requestedAt
            )
            if revalidation.isReady {
                initial.append(Candidate(association: association, revalidation: revalidation))
            }
        }

        let provenLevels = Set(initial.flatMap { $0.revalidation.provenLevels })
        guard !provenLevels.isEmpty else {
            let first = associations.first!
            let check = port.revalidate(first, for: request.sessionIdentity, negotiation: request.negotiation, at: request.requestedAt)
            let outcome = JumpBackOutcome(
                sessionIdentity: request.sessionIdentity,
                host: first.host,
                qualifier: .unavailable,
                occurredAt: request.requestedAt,
                reason: .revalidationFailed(check.reason),
                candidateAssociationID: first.id
            )
            return record(request, candidate: nil, outcome: outcome)
        }

        var strongestFailed: HostNavigationLevel?
        var dispatchFailure: HostNavigationRevalidationReason?
        for level in HostNavigationLevel.allCases.sorted(by: >) where level != .unavailable {
            guard provenLevels.contains(level) else { continue }
            let candidates = initial.filter { $0.revalidation.provenLevels.contains(level) }
            guard candidates.count == 1 else {
                strongestFailed = strongestFailed ?? level
                continue
            }
            let candidate = candidates[0]
            // Immediate revalidation before this exact attempt, including
            // ownership, mode, capability, permission, incarnation, and
            // locator checks.
            let fresh = port.revalidate(
                candidate.association,
                for: request.sessionIdentity,
                negotiation: request.negotiation,
                at: request.requestedAt
            )
            // App activation is an independently observed, deliberately
            // non-targeted fallback. It remains safe when multiple panes or
            // tabs share a stale/duplicate locator; every more-specific level
            // still requires exactly one current documented candidate.
            let requiresUniqueCandidate = level != .appOnly
            guard fresh.isReady, fresh.provenLevels.contains(level), !requiresUniqueCandidate || fresh.candidateCount == 1 else {
                strongestFailed = strongestFailed ?? level
                continue
            }
            let target = HostNavigationTarget(
                sessionIdentity: request.sessionIdentity,
                associationID: candidate.association.id,
                host: candidate.association.host,
                locator: candidate.association.locator,
                level: level,
                revalidatedAt: fresh.evaluatedAt
            )
            switch port.navigate(target, at: request.requestedAt) {
            case .reached:
                let reason: JumpBackReason
                if let strongestFailed {
                    reason = .reachedFallback(from: strongestFailed, to: level)
                } else if level != .exactSurface && candidate.revalidation.reason != .ready {
                    reason = .reachedFallback(from: .exactSurface, to: level)
                } else {
                    reason = .reached
                }
                let outcome = JumpBackOutcome(
                    sessionIdentity: request.sessionIdentity,
                    host: candidate.association.host,
                    qualifier: level,
                    occurredAt: request.requestedAt,
                    reason: reason,
                    candidateAssociationID: candidate.association.id,
                    navigationPerformed: true
                )
                return record(request, candidate: candidate, outcome: outcome)
            case .rejected(let reason):
                strongestFailed = strongestFailed ?? level
                dispatchFailure = reason
            }
        }

        let candidate = initial.first
        let reason: JumpBackReason
        if let dispatchFailure {
            reason = .dispatchFailed(dispatchFailure)
        } else if let strongestFailed {
            reason = .ambiguous(level: strongestFailed)
        } else {
            reason = .revalidationFailed(.noSeparatelyProvenFallback)
        }
        let outcome = JumpBackOutcome(
            sessionIdentity: request.sessionIdentity,
            host: candidate?.association.host,
            qualifier: .unavailable,
            occurredAt: request.requestedAt,
            reason: reason,
            candidateAssociationID: candidate?.association.id
        )
        return record(request, candidate: candidate, outcome: outcome)
    }

    public func jumpBack(_ request: JumpBackRequest) -> JumpBackOutcome {
        attempt(request).outcome
    }

    private func selectedAssociations(for request: JumpBackRequest) -> [HostContextAssociation] {
        let all = evidence.associations(for: request.sessionIdentity)
        guard let selected = request.selectedAssociationID else { return all }
        return all.filter { $0.id == selected }
    }

    private func record(_ request: JumpBackRequest, candidate: Candidate?, outcome: JumpBackOutcome) -> JumpBackAttemptRecord {
        JumpBackAttemptRecord(
            attemptID: request.attemptID,
            sessionIdentity: request.sessionIdentity,
            trigger: request.trigger,
            candidateAssociationID: candidate?.association.id ?? outcome.candidateAssociationID,
            candidateLocator: candidate?.association.locator,
            outcome: outcome
        )
    }

    private struct Candidate: Sendable {
        let association: HostContextAssociation
        let revalidation: HostNavigationRevalidation
    }
}

public typealias JumpBackPort = HostNavigationPort
public typealias JumpBackNavigationCoordinator = JumpBackCoordinator
public typealias JumpBackResult = JumpBackOutcome
public typealias HostNavigationOutcome = JumpBackOutcome
