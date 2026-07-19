import Foundation

public enum AtlasIntegrationKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case claudeCode
    case codexCLI
    case cursor

    public var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codexCLI: "Codex CLI"
        case .cursor: "Cursor"
        }
    }
}

public enum AtlasIntegrationAuthentication: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case unknown
    case notRequired
    case required
    case authorized
    case denied
    case expired
}

public enum AtlasIntegrationHealth: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case unknown
    case healthy
    case degraded
    case setupRequired
    case unavailable
    case incompatible
}

public enum AtlasEvidenceFreshness: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case unknown
    case current
    case stale
}

public enum AtlasIntegrationCapability: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case observation
    case attention
    case action
    case navigation
    case configuration
}

public enum AtlasIntegrationSummary: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case notEnabled
    case detectedNotEnabled
    case authenticationRequired
    case setupRequired
    case healthy
    case degraded
    case unavailable
    case incompatible
    case unknown
}

public enum AtlasIntegrationSafeNextStep: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case enableIntent
    case observe
    case authenticate
    case configure
    case repair
    case retry
    case update
    case inspect
    case none

    public static var enable: Self { .enableIntent }
    public static var setup: Self { .configure }
}

public struct AtlasIntegrationEvidence: Codable, Equatable, Hashable, Sendable {
    public var health: AtlasIntegrationHealth
    public var freshness: AtlasEvidenceFreshness
    public var observedAt: Date?

    public init(
        health: AtlasIntegrationHealth = .unknown,
        freshness: AtlasEvidenceFreshness = .unknown,
        observedAt: Date? = nil
    ) {
        self.health = health
        self.freshness = freshness
        self.observedAt = observedAt
    }
}

public struct AtlasIntegrationState: Codable, Equatable, Hashable, Sendable {
    public var kind: AtlasIntegrationKind
    public var enabledIntent: Bool
    public var detected: Bool
    public var authentication: AtlasIntegrationAuthentication
    public var evidence: AtlasIntegrationEvidence?
    public var capabilities: Set<AtlasIntegrationCapability>
    public var affectedCapability: AtlasIntegrationCapability?

    public init(
        kind: AtlasIntegrationKind,
        enabledIntent: Bool = false,
        detected: Bool = false,
        authentication: AtlasIntegrationAuthentication = .unknown,
        evidence: AtlasIntegrationEvidence? = nil,
        capabilities: Set<AtlasIntegrationCapability> = [],
        affectedCapability: AtlasIntegrationCapability? = nil
    ) {
        self.kind = kind
        self.enabledIntent = enabledIntent
        self.detected = detected
        self.authentication = authentication
        self.evidence = evidence
        self.capabilities = capabilities
        self.affectedCapability = affectedCapability
    }

    public static var defaults: [Self] { AtlasIntegrationKind.allCases.map { Self(kind: $0) } }

    public var summary: AtlasIntegrationSummary {
        guard enabledIntent else { return detected ? .detectedNotEnabled : .notEnabled }
        if authentication == .required || authentication == .denied || authentication == .expired {
            return .authenticationRequired
        }
        guard let evidence else { return detected ? .setupRequired : .unknown }
        switch evidence.health {
        case .healthy: return .healthy
        case .degraded: return .degraded
        case .setupRequired: return .setupRequired
        case .unavailable: return .unavailable
        case .incompatible: return .incompatible
        case .unknown: return detected ? .setupRequired : .unknown
        }
    }

    public var safeNextStep: AtlasIntegrationSafeNextStep {
        switch summary {
        case .notEnabled, .detectedNotEnabled: .enableIntent
        case .authenticationRequired: .authenticate
        case .setupRequired: .configure
        case .healthy: .none
        case .degraded: .repair
        case .unavailable: .retry
        case .incompatible: .update
        case .unknown: .observe
        }
    }

    public var health: AtlasIntegrationHealth { evidence?.health ?? .unknown }
    public var freshness: AtlasEvidenceFreshness { evidence?.freshness ?? .unknown }
    public var authenticationState: AtlasIntegrationAuthentication {
        get { authentication }
        set { authentication = newValue }
    }
    public var auth: AtlasIntegrationAuthentication {
        get { authentication }
        set { authentication = newValue }
    }

    /// Evidence is a separate projection and can never turn intent on/off.
    public mutating func apply(
        evidence: AtlasIntegrationEvidence,
        capabilities: Set<AtlasIntegrationCapability>? = nil,
        affectedCapability: AtlasIntegrationCapability? = nil
    ) {
        self.evidence = evidence
        if let capabilities { self.capabilities = capabilities }
        self.affectedCapability = affectedCapability
    }

    public func applying(evidence: AtlasIntegrationEvidence, capabilities: Set<AtlasIntegrationCapability>? = nil, affectedCapability: AtlasIntegrationCapability? = nil) -> Self {
        var value = self
        value.apply(evidence: evidence, capabilities: capabilities, affectedCapability: affectedCapability)
        return value
    }

    public func normalized() -> Self {
        var value = self
        if let affectedCapability, !value.capabilities.contains(affectedCapability) {
            value.affectedCapability = nil
        }
        if value.authentication == .authorized && !value.enabledIntent {
            // Authorization evidence is retained, but it does not imply intent.
            value.authentication = .authorized
        }
        return value
    }

    public static func normalizedCollection(_ values: [Self]) -> [Self] {
        // UserDefaults is not trusted input. Resolve duplicate legacy/corrupt
        // rows deterministically instead of using `uniqueKeysWithValues`,
        // which traps and could prevent the app from launching.
        var byKind: [AtlasIntegrationKind: Self] = [:]
        for value in values {
            byKind[value.kind] = value.normalized()
        }
        for state in defaults where byKind[state.kind] == nil { byKind[state.kind] = state }
        return AtlasIntegrationKind.allCases.compactMap { byKind[$0] }
    }
}

public typealias AtlasIntegration = AtlasIntegrationState
