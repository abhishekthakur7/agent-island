import Foundation

public enum AlertPrimaryPresentation: String, Codable, Hashable, Sendable, Equatable {
    case focusedReveal
    case collapsedGlow
    case inlineOnly
    case suppressed
}

public enum NotificationPermissionState: String, Codable, Hashable, Sendable, Equatable {
    case unknown
    case granted
    case denied
}

public typealias NotificationPermission = NotificationPermissionState

public enum AlertEventPreference: String, Codable, Hashable, Sendable, Equatable, CaseIterable {
    case focusedReveal
    case collapsedGlow
    case inlineOnly
    case off
}

public enum NotificationEvaluationReason: String, Codable, Hashable, Sendable, Equatable, CaseIterable {
    case eligible
    case duplicate
    case stale
    case hardFiltered
    case quietScene
    case quietHoursSoundOnly
    case exactForeground
    case eventPreference
    case notificationPermission
    case guardedPresentation
    case restartRestored
    case masterDisabled
}

public enum NotificationEvaluationStep: String, Codable, Hashable, Sendable, Equatable, CaseIterable {
    case deduplicationAndCurrentness
    case hardFilter
    case quietScene
    case quietHoursSoundPolicy
    case exactForeground
    case eventPreference
    case notificationPermission
}

/// A source-proven exact foreground observation.  `same title`, app-only
/// foreground, and historical locators intentionally cannot be represented as
/// exact relevance.
public struct ExactForegroundRelevance: Codable, Hashable, Sendable, Equatable {
    public let sessionIdentity: AgentSessionIdentity?
    public let revalidated: Bool
    public let directInspection: Bool
    public let appOnly: Bool
    public let observedAt: Date?

    public init(sessionIdentity: AgentSessionIdentity? = nil, revalidated: Bool = false, directInspection: Bool = false, appOnly: Bool = false, observedAt: Date? = nil) {
        self.sessionIdentity = sessionIdentity
        self.revalidated = revalidated
        self.directInspection = directInspection
        self.appOnly = appOnly
        self.observedAt = observedAt
    }

    public func isExact(for candidate: AlertCandidate) -> Bool {
        guard revalidated, (directInspection || !appOnly), sessionIdentity == candidate.owner.sessionIdentity else { return false }
        return true
    }

    public static let none = Self()
}

public struct AlertCandidateFilterPolicy: Codable, Hashable, Sendable, Equatable {
    public var showLauncher: Bool
    public var showProbe: Bool
    public var showBuiltInInternalWork: Bool
    public var showDirectory: Bool
    public var showFirstPrompt: Bool
    public var showSourcedChildCompletion: Bool

    public init(showLauncher: Bool = false, showProbe: Bool = false, showBuiltInInternalWork: Bool = false, showDirectory: Bool = true, showFirstPrompt: Bool = true, showSourcedChildCompletion: Bool = true) {
        self.showLauncher = showLauncher
        self.showProbe = showProbe
        self.showBuiltInInternalWork = showBuiltInInternalWork
        self.showDirectory = showDirectory
        self.showFirstPrompt = showFirstPrompt
        self.showSourcedChildCompletion = showSourcedChildCompletion
    }

    public static let `default` = Self()

    public func allows(_ origin: AlertCandidateOrigin) -> Bool {
        switch origin {
        case .normal: true
        case .launcher: showLauncher
        case .probe: showProbe
        case .builtInInternalWork: showBuiltInInternalWork
        case .directory: showDirectory
        case .firstPrompt: showFirstPrompt
        case .sourcedChildRun: showSourcedChildCompletion
        }
    }
}

public struct NotificationPermissionPolicy: Codable, Hashable, Sendable, Equatable {
    public var system: NotificationPermissionState
    public var byClass: [AlertCandidateClass: NotificationPermissionState]

    public init(system: NotificationPermissionState = .unknown, byClass: [AlertCandidateClass: NotificationPermissionState] = [:]) {
        self.system = system
        self.byClass = byClass
    }

    public func state(for semanticClass: AlertCandidateClass) -> NotificationPermissionState {
        byClass[semanticClass] ?? system
    }
}

public struct NotificationPolicy: Codable, Hashable, Sendable, Equatable {
    public var masterEnabled: Bool
    public var preferences: [AlertCandidateClass: AlertEventPreference]
    public var filters: AlertCandidateFilterPolicy
    public var permission: NotificationPermissionPolicy
    public var sound: SoundPolicy
    public var revealCompletion: Bool
    public var revealAttention: Bool
    public var suppressWhenExactForeground: Bool

    public init(
        masterEnabled: Bool = true,
        preferences: [AlertCandidateClass: AlertEventPreference] = [:],
        filters: AlertCandidateFilterPolicy = .default,
        permission: NotificationPermissionPolicy = .init(),
        sound: SoundPolicy = .default,
        revealCompletion: Bool = true,
        revealAttention: Bool = true,
        suppressWhenExactForeground: Bool = true
    ) {
        self.masterEnabled = masterEnabled
        self.preferences = preferences
        self.filters = filters
        self.permission = permission
        self.sound = sound
        self.revealCompletion = revealCompletion
        self.revealAttention = revealAttention
        self.suppressWhenExactForeground = suppressWhenExactForeground
    }

    public static let `default` = Self()

    public func preference(for semanticClass: AlertCandidateClass) -> AlertEventPreference {
        if semanticClass == .attention, !revealAttention { return .inlineOnly }
        if semanticClass == .completion, !revealCompletion { return .inlineOnly }
        return preferences[semanticClass] ?? Self.defaultPreference(for: semanticClass)
    }

    private static func defaultPreference(for semanticClass: AlertCandidateClass) -> AlertEventPreference {
        switch semanticClass {
        case .attention, .errorContextLimit: .focusedReveal
        case .completion, .sessionStart: .focusedReveal
        case .reminder: .collapsedGlow
        case .childCompletion: .inlineOnly
        case .acknowledgement, .spam: .inlineOnly
        }
    }
}

public struct AlertEvaluationContext: Sendable {
    public let policy: NotificationPolicy
    public let quietScene: QuietScene
    public let exactForeground: ExactForegroundRelevance
    public let currentRevision: Int64
    public let latestRevisionByCandidate: [AlertCandidateID: Int64]
    public let now: Date
    public let interactionGuardedCandidateID: AlertCandidateID?
    public let restoredFromRestart: Bool
    /// Optional display-only Usage Snapshot evidence. It is intentionally
    /// ignored by evaluation; missing/stale usage cannot gate alerts.
    public let usageAvailable: Bool?

    public init(
        policy: NotificationPolicy = .default,
        quietScene: QuietScene = .inactive,
        exactForeground: ExactForegroundRelevance = .none,
        currentRevision: Int64 = 0,
        latestRevisionByCandidate: [AlertCandidateID: Int64] = [:],
        now: Date = Date(),
        interactionGuardedCandidateID: AlertCandidateID? = nil,
        restoredFromRestart: Bool = false,
        usageAvailable: Bool? = nil
    ) {
        self.policy = policy
        self.quietScene = quietScene
        self.exactForeground = exactForeground
        self.currentRevision = currentRevision
        self.latestRevisionByCandidate = latestRevisionByCandidate
        self.now = now
        self.interactionGuardedCandidateID = interactionGuardedCandidateID
        self.restoredFromRestart = restoredFromRestart
        self.usageAvailable = usageAvailable
    }
}

public struct AlertPrimaryFacet: Codable, Hashable, Sendable, Equatable {
    public let candidateID: AlertCandidateID
    public let presentation: AlertPrimaryPresentation
    public let dwell: AlertCandidateDwell?

    public init(candidateID: AlertCandidateID, presentation: AlertPrimaryPresentation, dwell: AlertCandidateDwell? = nil) {
        self.candidateID = candidateID
        self.presentation = presentation
        self.dwell = dwell
    }
}

public struct NotificationBannerFacet: Codable, Hashable, Sendable, Equatable {
    public let candidateID: AlertCandidateID
    public let state: VisibleLifecycleState
    public let label: String?

    public init(candidateID: AlertCandidateID, state: VisibleLifecycleState, label: String?) {
        self.candidateID = candidateID
        self.state = state
        self.label = label
    }
}

/// One primary facet, at most one sound, and at most one macOS banner.  Every
/// facet carries the same candidate ID so later revisions can retarget one
/// surface rather than stack independent work.
public struct AlertPresentationDecision: Codable, Hashable, Sendable, Equatable {
    public let candidateID: AlertCandidateID
    public let primary: AlertPrimaryFacet
    public let sound: SoundDecision?
    public let banner: NotificationBannerFacet?
    public let reason: NotificationEvaluationReason
    public let steps: [NotificationEvaluationStep]

    public init(candidateID: AlertCandidateID, primary: AlertPrimaryFacet, sound: SoundDecision?, banner: NotificationBannerFacet?, reason: NotificationEvaluationReason, steps: [NotificationEvaluationStep]) {
        self.candidateID = candidateID
        self.primary = primary
        self.sound = sound
        self.banner = banner
        self.reason = reason
        self.steps = steps
    }

    public var hasAutomaticFacet: Bool {
        primary.presentation != .suppressed || sound?.isPlaying == true || banner != nil
    }
}

public struct RedactedNotificationEvaluationDiagnostic: Codable, Hashable, Sendable, Equatable {
    public let candidateID: String
    public let reason: NotificationEvaluationReason
    public let steps: [NotificationEvaluationStep]

    public init(_ decision: AlertPresentationDecision) {
        self.candidateID = String(decision.candidateID.description.prefix(256))
        self.reason = decision.reason
        self.steps = decision.steps
    }
}

public enum NotificationPolicyEvaluator {
    public static func evaluate(_ candidate: AlertCandidate, context: AlertEvaluationContext) -> AlertPresentationDecision {
        var steps: [NotificationEvaluationStep] = []

        // 1. Deduplication/currentness.
        steps.append(.deduplicationAndCurrentness)
        if context.restoredFromRestart {
            return suppressed(candidate, reason: .restartRestored, steps: steps)
        }
        if let latest = context.latestRevisionByCandidate[candidate.id] {
            if candidate.sourceRevision < latest { return suppressed(candidate, reason: .stale, steps: steps) }
            if candidate.sourceRevision == latest { return suppressed(candidate, reason: .duplicate, steps: steps) }
        }
        if context.currentRevision > 0, candidate.sourceRevision > context.currentRevision {
            return suppressed(candidate, reason: .stale, steps: steps)
        }

        // 2. Hard filters.
        steps.append(.hardFilter)
        guard context.policy.masterEnabled, context.policy.filters.allows(candidate.origin), hardFilterAllows(candidate) else {
            return suppressed(candidate, reason: context.policy.masterEnabled ? .hardFiltered : .masterDisabled, steps: steps)
        }

        // 3. Quiet Scene applies to every facet and never creates a backlog.
        steps.append(.quietScene)
        guard !context.quietScene.isActive else { return suppressed(candidate, reason: .quietScene, steps: steps) }

        // 4. Quiet-hours/mute affect sound only.
        steps.append(.quietHoursSoundPolicy)
        let sound = context.policy.sound.sound(for: candidate, at: context.now)

        // 5. Exact foreground relevance is session-scoped.
        steps.append(.exactForeground)
        if context.policy.suppressWhenExactForeground, context.exactForeground.isExact(for: candidate) {
            let primary = AlertPrimaryFacet(candidateID: candidate.id, presentation: .inlineOnly)
            return AlertPresentationDecision(candidateID: candidate.id, primary: primary, sound: nil, banner: nil, reason: .exactForeground, steps: steps)
        }

        // 6. Event preference.
        steps.append(.eventPreference)
        let preference = context.policy.preference(for: candidate.semanticClass)
        guard preference != .off else { return suppressed(candidate, reason: .eventPreference, steps: steps) }

        // A guarded Attention Request owns the focused surface. Lower classes
        // remain inline and cannot displace its draft or keyboard engagement.
        if let guarded = context.interactionGuardedCandidateID, guarded != candidate.id, candidate.semanticClass != .attention {
            return AlertPresentationDecision(candidateID: candidate.id, primary: AlertPrimaryFacet(candidateID: candidate.id, presentation: .inlineOnly), sound: nil, banner: nil, reason: .guardedPresentation, steps: steps)
        }

        // 7. Permission applies to eligible background notification classes.
        steps.append(.notificationPermission)
        let permission = context.policy.permission.state(for: candidate.semanticClass)
        let banner: NotificationBannerFacet?
        if candidate.semanticClass.isBackgroundNotificationEligible, permission == .granted {
            banner = NotificationBannerFacet(candidateID: candidate.id, state: candidate.payload.state, label: candidate.payload.label)
        } else {
            banner = nil
        }
        let primaryPresentation: AlertPrimaryPresentation
        switch preference {
        case .focusedReveal: primaryPresentation = .focusedReveal
        case .collapsedGlow: primaryPresentation = .collapsedGlow
        case .inlineOnly, .off: primaryPresentation = .inlineOnly
        }
        return AlertPresentationDecision(
            candidateID: candidate.id,
            primary: AlertPrimaryFacet(candidateID: candidate.id, presentation: primaryPresentation, dwell: candidate.dwell),
            sound: sound,
            banner: banner,
            reason: .eligible,
            steps: steps
        )
    }

    private static func suppressed(_ candidate: AlertCandidate, reason: NotificationEvaluationReason, steps: [NotificationEvaluationStep], sound: SoundDecision? = nil) -> AlertPresentationDecision {
        AlertPresentationDecision(candidateID: candidate.id, primary: AlertPrimaryFacet(candidateID: candidate.id, presentation: .suppressed), sound: sound?.isPlaying == true ? sound : nil, banner: nil, reason: reason, steps: steps)
    }

    private static func hardFilterAllows(_ candidate: AlertCandidate) -> Bool {
        guard candidate.owner.isValid, candidate.sourceRevision > 0 else { return false }
        switch candidate.sourceEventIdentity {
        case .stable(let value): guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        case .weak: return false
        }
        guard candidate.semanticClass != .completion ||
                (candidate.payload.state == .completed || candidate.payload.state == .failed || candidate.payload.state == .stopped) &&
                !candidate.payload.hasPendingAttention && !candidate.payload.hasActiveChild
        else { return false }
        return true
    }
}

public typealias NotificationPolicyDecision = AlertPresentationDecision
public typealias AlertEvaluation = AlertPresentationDecision
