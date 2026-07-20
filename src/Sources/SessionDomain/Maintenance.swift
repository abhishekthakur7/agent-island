import Foundation

/// Maintenance flows are deliberately separate so a local preference reset
/// can never be confused with setup removal or Product/session deletion.
public enum MaintenanceFlow: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case resetPresentationPreferences
    case deleteDiagnostics
    case deletePreferences
    case deleteGeneratedSchema
    case deleteCache
    case deleteManifests
    case removeManifestProvenSetup
    case deleteInactiveSessionHistory
    case deleteActiveLocalHistory
    case completeCleanup
}

public enum MaintenanceLocalCategory: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case presentationPreferences
    case diagnostics
    case preferences
    case generatedSchema
    case cache
    case manifests
    case inactiveSessionHistory
    case activeLocalHistory
}

public enum MaintenanceActionTone: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case ordinary
    case warning
    case destructive
}

public enum MaintenanceIntegrityState: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case verified
    case failed
    case unavailable
}

public struct MaintenanceManifestScope: Codable, Equatable, Hashable, Sendable {
    public let manifestID: String
    public let exactEntryCount: Int
    public let ownedArtifactCount: Int
    public let lifecycle: OwnershipManifestLifecycle
    public let residualKnown: Bool

    public init(manifestID: String, exactEntryCount: Int, ownedArtifactCount: Int, lifecycle: OwnershipManifestLifecycle = .active, residualKnown: Bool = false) {
        self.manifestID = manifestID
        self.exactEntryCount = max(0, exactEntryCount)
        self.ownedArtifactCount = max(0, ownedArtifactCount)
        self.lifecycle = lifecycle
        self.residualKnown = residualKnown
    }

    public init(_ manifest: OwnershipManifest, residualKnown: Bool = false) {
        self.init(manifestID: manifest.id, exactEntryCount: manifest.entries.count, ownedArtifactCount: manifest.artifacts.count, lifecycle: manifest.lifecycle, residualKnown: residualKnown)
    }
}

public struct MaintenanceRequest: Codable, Equatable, Hashable, Sendable {
    public let flow: MaintenanceFlow
    public let localCategories: Set<MaintenanceLocalCategory>
    public let manifestScopes: [MaintenanceManifestScope]
    public let sessionIDs: [AgentSessionIdentity]
    public let integrity: MaintenanceIntegrityState

    public init(
        flow: MaintenanceFlow,
        localCategories: Set<MaintenanceLocalCategory> = [],
        manifestScopes: [MaintenanceManifestScope] = [],
        sessionIDs: [AgentSessionIdentity] = [],
        integrity: MaintenanceIntegrityState = .verified
    ) {
        self.flow = flow
        self.localCategories = localCategories
        self.manifestScopes = manifestScopes
        self.sessionIDs = sessionIDs
        self.integrity = integrity
    }

    public static func resetPresentationPreferences() -> Self {
        Self(flow: .resetPresentationPreferences, localCategories: [.presentationPreferences])
    }

    public static func removeSetup(_ manifests: [MaintenanceManifestScope]) -> Self {
        Self(flow: .removeManifestProvenSetup, manifestScopes: manifests)
    }

    public static func completeCleanup(_ manifests: [MaintenanceManifestScope] = []) -> Self {
        Self(flow: .completeCleanup, localCategories: Set(MaintenanceLocalCategory.allCases), manifestScopes: manifests)
    }
}

public struct MaintenancePreview: Codable, Equatable, Hashable, Sendable {
    public let request: MaintenanceRequest
    public let localCategories: [MaintenanceLocalCategory]
    public let externalManifestScopes: [MaintenanceManifestScope]
    public let exactSessionIDs: [AgentSessionIdentity]
    public let stateRevision: Int64
    public let previewDigest: String
    public let tone: MaintenanceActionTone
    public let residualAmbiguity: Bool
    public let integrityFailure: Bool

    public init(request: MaintenanceRequest, stateRevision: Int64, at: Date = Date()) {
        self.request = request
        self.localCategories = MaintenancePlanner.categories(for: request)
        self.externalManifestScopes = request.manifestScopes
        self.exactSessionIDs = request.sessionIDs
        self.stateRevision = stateRevision
        self.tone = MaintenancePlanner.tone(for: request.flow)
        self.residualAmbiguity = request.manifestScopes.contains { $0.residualKnown || $0.lifecycle == .drifted || $0.lifecycle == .partial }
        self.integrityFailure = request.integrity != .verified
        let canonical = "\(request.flow.rawValue)|\(stateRevision)|\(localCategories.map(\.rawValue).joined(separator: ","))|\(request.manifestScopes.map(\.manifestID).sorted().joined(separator: ","))|\(request.sessionIDs.map { "\($0.productNamespace.rawValue):\($0.nativeSessionID.rawValue)" }.sorted().joined(separator: ","))"
        self.previewDigest = ExactEntryDigest.value(Data(canonical.utf8))
    }

    public var confirmation: MaintenanceConfirmation {
        MaintenanceConfirmation(previewDigest: previewDigest, stateRevision: stateRevision)
    }

    public var externalManifestDescription: String {
        externalManifestScopes.isEmpty ? "No external manifest-proven setup selected." : "Only the selected manifest-proven exact entries and individually receipted artifacts are in scope."
    }
}

public struct MaintenanceConfirmation: Codable, Equatable, Hashable, Sendable {
    public let previewDigest: String
    public let stateRevision: Int64
    public let confirmed: Bool

    public init(previewDigest: String, stateRevision: Int64, confirmed: Bool = false) {
        self.previewDigest = previewDigest
        self.stateRevision = stateRevision
        self.confirmed = confirmed
    }

    public func confirming() -> Self { Self(previewDigest: previewDigest, stateRevision: stateRevision, confirmed: true) }
}

public enum MaintenanceOutcome: Codable, Equatable, Hashable, Sendable {
    case applied(localCategories: [MaintenanceLocalCategory], manifestScopes: [MaintenanceManifestScope], sessions: [AgentSessionIdentity])
    case confirmationRequired
    case stalePreview
    case invalidScope
    case blockedByIntegrity(category: MaintenanceLocalCategory)
    case partialWithResidual(manifestScopes: [MaintenanceManifestScope])
    case unavailable
}

public struct MaintenanceState: Codable, Equatable, Hashable, Sendable {
    public private(set) var revision: Int64
    public private(set) var removedCategories: Set<MaintenanceLocalCategory>
    public private(set) var removedSessions: Set<AgentSessionIdentity>
    public private(set) var removedManifestIDs: Set<String>
    public private(set) var integrityFailures: Set<MaintenanceLocalCategory>

    public init(revision: Int64 = 0, removedCategories: Set<MaintenanceLocalCategory> = [], removedSessions: Set<AgentSessionIdentity> = [], removedManifestIDs: Set<String> = [], integrityFailures: Set<MaintenanceLocalCategory> = []) {
        self.revision = revision
        self.removedCategories = removedCategories
        self.removedSessions = removedSessions
        self.removedManifestIDs = removedManifestIDs
        self.integrityFailures = integrityFailures
    }

    public mutating func markIntegrityFailure(_ category: MaintenanceLocalCategory) {
        integrityFailures.insert(category)
        revision &+= 1
    }

    fileprivate mutating func apply(_ preview: MaintenancePreview) {
        removedCategories.formUnion(preview.localCategories)
        removedSessions.formUnion(preview.exactSessionIDs)
        removedManifestIDs.formUnion(preview.externalManifestScopes.map(\.manifestID))
        revision &+= 1
    }
}

public enum MaintenancePlanner {
    public static func categories(for request: MaintenanceRequest) -> [MaintenanceLocalCategory] {
        let explicit = request.localCategories
        let mapped: Set<MaintenanceLocalCategory> = switch request.flow {
        case .resetPresentationPreferences: [.presentationPreferences]
        case .deleteDiagnostics: [.diagnostics]
        case .deletePreferences: [.preferences]
        case .deleteGeneratedSchema: [.generatedSchema]
        case .deleteCache: [.cache]
        case .deleteManifests: [.manifests]
        case .removeManifestProvenSetup: []
        case .deleteInactiveSessionHistory: [.inactiveSessionHistory]
        case .deleteActiveLocalHistory: [.activeLocalHistory]
        case .completeCleanup: Set(MaintenanceLocalCategory.allCases)
        }
        return Array(explicit.union(mapped)).sorted { $0.rawValue < $1.rawValue }
    }

    public static func tone(for flow: MaintenanceFlow) -> MaintenanceActionTone {
        switch flow {
        case .resetPresentationPreferences, .deleteDiagnostics, .deletePreferences, .deleteGeneratedSchema, .deleteCache: .warning
        case .deleteManifests, .removeManifestProvenSetup, .deleteInactiveSessionHistory, .deleteActiveLocalHistory, .completeCleanup: .destructive
        }
    }

    public static func preview(_ request: MaintenanceRequest, state: MaintenanceState, at date: Date = Date()) -> MaintenancePreview {
        MaintenancePreview(request: request, stateRevision: state.revision, at: date)
    }

    public static func apply(_ preview: MaintenancePreview, confirmation: MaintenanceConfirmation, state: inout MaintenanceState) -> MaintenanceOutcome {
        guard confirmation.confirmed else { return .confirmationRequired }
        guard confirmation.previewDigest == preview.previewDigest, confirmation.stateRevision == state.revision else { return .stalePreview }
        guard !preview.exactSessionIDs.isEmpty || !preview.externalManifestScopes.isEmpty || !preview.localCategories.isEmpty else { return .invalidScope }
        if preview.integrityFailure {
            let category = preview.localCategories.first ?? (preview.externalManifestScopes.isEmpty ? .diagnostics : .manifests)
            return .blockedByIntegrity(category: category)
        }
        state.apply(preview)
        if preview.residualAmbiguity { return .partialWithResidual(manifestScopes: preview.externalManifestScopes) }
        return .applied(localCategories: preview.localCategories, manifestScopes: preview.externalManifestScopes, sessions: preview.exactSessionIDs)
    }
}

public struct MaintenanceAccessibilityModel: Codable, Equatable, Hashable, Sendable {
    public let title: String
    public let accessibilityLabel: String
    public let accessibilityHint: String
    public let tone: MaintenanceActionTone

    public init(flow: MaintenanceFlow) {
        self.tone = MaintenancePlanner.tone(for: flow)
        self.title = flow.title
        self.accessibilityLabel = "\(flow.title), \(tone.rawValue) maintenance action"
        self.accessibilityHint = switch tone {
        case .ordinary: "Changes only the selected local presentation category."
        case .warning: "Review the exact local category before confirming."
        case .destructive: "Review the exact local and manifest-proven scope before confirming."
        }
    }
}

public extension MaintenanceFlow {
    var title: String {
        switch self {
        case .resetPresentationPreferences: "Reset presentation preferences"
        case .deleteDiagnostics: "Delete diagnostics"
        case .deletePreferences: "Delete preferences"
        case .deleteGeneratedSchema: "Delete generated schema"
        case .deleteCache: "Delete cache"
        case .deleteManifests: "Delete local manifests"
        case .removeManifestProvenSetup: "Remove manifest-proven setup"
        case .deleteInactiveSessionHistory: "Delete selected inactive Session History"
        case .deleteActiveLocalHistory: "Delete active local history"
        case .completeCleanup: "Complete cleanup"
        }
    }
}

public typealias MaintenanceScopePreview = MaintenancePreview
public typealias MaintenanceScopeConfirmation = MaintenanceConfirmation
