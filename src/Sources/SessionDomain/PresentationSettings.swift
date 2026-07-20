import Foundation

/// A foreground observation is valid only when the Host itself has just
/// revalidated the exact owning Host Context.  Presentation policy consumes
/// this evidence but never derives it from a title, path, nearby tab, app-only
/// activation, or a historical locator.
public struct ExactHostForegroundObservation: Codable, Equatable, Hashable, Sendable {
    public let sessionIdentity: AgentSessionIdentity
    public let hostContextID: HostContextID
    public let host: HostKind
    public let incarnation: HostIncarnation
    public let locator: HostLocator
    public let revalidated: Bool
    public let directInspection: Bool
    public let appOnly: Bool
    public let observedAt: Date

    public init(
        sessionIdentity: AgentSessionIdentity,
        hostContextID: HostContextID,
        host: HostKind,
        incarnation: HostIncarnation,
        locator: HostLocator,
        revalidated: Bool,
        directInspection: Bool = true,
        appOnly: Bool = false,
        observedAt: Date
    ) {
        self.sessionIdentity = sessionIdentity
        self.hostContextID = hostContextID
        self.host = host
        self.incarnation = incarnation
        self.locator = locator
        self.revalidated = revalidated
        self.directInspection = directInspection
        self.appOnly = appOnly
        self.observedAt = observedAt
    }

    /// The association must be live, owned by the candidate, and refer to
    /// the same Host incarnation and opaque locator as the fresh observation.
    public func isExact(for candidate: AgentSessionIdentity, in association: HostContextAssociation?) -> Bool {
        guard revalidated, directInspection, !appOnly,
              sessionIdentity == candidate,
              let association,
              association.id == hostContextID,
              association.sessionIdentity == candidate,
              association.host == host,
              association.incarnation == incarnation,
              association.locator == locator,
              association.isLive,
              association.lastValidatedAt != nil,
              !locator.isHistoricalOnly
        else { return false }
        return true
    }
}

public typealias ExactOwningHostForeground = ExactHostForegroundObservation

public enum LocalPresentationSuppression: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case none
    case noActiveSession
    case fullScreen
    case exactOwningHostForeground
}

/// Local presentation policy is intentionally separate from Session/Product
/// lifecycle policy.  It decides only whether a local Overlay may be visible.
public struct LocalPresentationPolicy: Codable, Equatable, Hashable, Sendable {
    public var hideWhenNoActiveSession: Bool
    public var hideInFullScreen: Bool
    public var suppressWhenExactHostForeground: Bool

    public init(
        hideWhenNoActiveSession: Bool = true,
        hideInFullScreen: Bool = true,
        suppressWhenExactHostForeground: Bool = true
    ) {
        self.hideWhenNoActiveSession = hideWhenNoActiveSession
        self.hideInFullScreen = hideInFullScreen
        self.suppressWhenExactHostForeground = suppressWhenExactHostForeground
    }

    public static let `default` = Self()

    public func suppression(
        hasActiveSession: Bool,
        isFullScreen: Bool,
        foreground: ExactHostForegroundObservation? = nil,
        owningAssociation: HostContextAssociation? = nil,
        candidate: AgentSessionIdentity? = nil
    ) -> LocalPresentationSuppression {
        if hideWhenNoActiveSession && !hasActiveSession { return .noActiveSession }
        if hideInFullScreen && isFullScreen { return .fullScreen }
        if suppressWhenExactHostForeground,
           let foreground,
           let candidate,
           foreground.isExact(for: candidate, in: owningAssociation) {
            return .exactOwningHostForeground
        }
        return .none
    }
}

public typealias PresentationPolicy = LocalPresentationPolicy

public enum PresentationClickAction: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case inspectExpand
    case jumpBack
}

public enum PresentationClickOutcome: Equatable, Hashable, Sendable {
    case inspectedOrExpanded
    case jumpBackUnavailable
    case jumpBackAchieved(HostNavigationLevel)

    public var achievedLevel: HostNavigationLevel? {
        switch self {
        case .inspectedOrExpanded: nil
        case .jumpBackUnavailable: .unavailable
        case let .jumpBackAchieved(level): level
        }
    }

    public var presentationLabel: String {
        switch self {
        case .inspectedOrExpanded: "Inspect or expand"
        case .jumpBackUnavailable: "Jump Back unavailable"
        case let .jumpBackAchieved(level): "Jump Back achieved \(level.label)"
        }
    }
}

public enum PresentationClickPolicy {
    /// An inspect click never reaches a Host port. A Jump Back click consumes
    /// only an already revalidated outcome and reports exactly what was
    /// achieved; absence or failure is unavailable, never implied success.
    public static func resolve(
        action: PresentationClickAction,
        jumpBackOutcome: JumpBackOutcome? = nil
    ) -> PresentationClickOutcome {
        switch action {
        case .inspectExpand:
            return .inspectedOrExpanded
        case .jumpBack:
            guard let jumpBackOutcome,
                  jumpBackOutcome.navigationPerformed,
                  jumpBackOutcome.achievedLevel != .unavailable
            else { return .jumpBackUnavailable }
            return .jumpBackAchieved(jumpBackOutcome.achievedLevel)
        }
    }
}

/// The settings UI may offer a custom destination only when a documented
/// grammar is supplied by the Host contract.  A bare URL or arbitrary string
/// never becomes a navigation rule.
public struct DocumentedHostDestinationGrammar: Codable, Equatable, Hashable, Sendable {
    public let host: HostKind
    public let identifier: String
    public let documented: Bool

    public init(host: HostKind, identifier: String, documented: Bool) {
        self.host = host
        self.identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.documented = documented
    }

    public var isOfferable: Bool {
        documented && !identifier.isEmpty && !identifier.contains("://")
    }
}

public enum HostDestinationOffer: Equatable, Hashable, Sendable {
    case noCustomRule(lowerFallback: HostNavigationLevel)
    case documentedRule(DocumentedHostDestinationGrammar)
}

public enum HostDestinationPolicy {
    public static func offer(
        host: HostKind,
        grammar: DocumentedHostDestinationGrammar?,
        lowerFallback: HostNavigationLevel = .appOnly
    ) -> HostDestinationOffer {
        guard let grammar, grammar.host == host, grammar.isOfferable else {
            return .noCustomRule(lowerFallback: lowerFallback)
        }
        return .documentedRule(grammar)
    }
}
