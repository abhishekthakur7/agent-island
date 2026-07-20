import Foundation

/// The exact qualifier actually achieved by Jump Back.  Ordering is part of
/// the contract: a lower level is never implied by a higher-looking label.
public enum HostNavigationLevel: Int, CaseIterable, Comparable, Hashable, Sendable, Codable {
    case unavailable = 0
    case appOnly = 1
    case windowBestEffort = 2
    case workspaceOrFile = 3
    case exactTab = 4
    case exactSurface = 5

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var isExact: Bool {
        self == .exactSurface || self == .exactTab
    }

    public var isFallback: Bool { self != .exactSurface && self != .exactTab }

    public var label: String {
        switch self {
        case .exactSurface: "exactSurface"
        case .exactTab: "exactTab"
        case .workspaceOrFile: "workspaceOrFile"
        case .windowBestEffort: "windowBestEffort"
        case .appOnly: "appOnly"
        case .unavailable: "unavailable"
        }
    }
}

public typealias JumpBackLevel = HostNavigationLevel
public typealias JumpBackQualifier = HostNavigationLevel

public enum HostPermissionState: String, CaseIterable, Hashable, Sendable, Codable {
    case notRequired
    case granted
    case denied
    case unknown

    public var allowsNavigation: Bool {
        self == .notRequired || self == .granted
    }
}

public enum HostApplicationState: String, CaseIterable, Hashable, Sendable, Codable {
    case available
    case absent
    case closed
    case endpointLost
    case unknown
}

public enum HostLocatorState: String, CaseIterable, Hashable, Sendable, Codable {
    case live
    case historical
    case recreated
    case closed
    case invalidated
    case permissionDenied
    case ambiguous
    case unavailable
}

/// Read-only, host-specific evidence supplied by a concrete Host adapter.  A
/// probe must set the relevant proof fields deliberately; the policy below
/// never derives exactness from titles, paths, PIDs, geometry, Spaces, AX
/// labels, or URL schemes.
public struct HostRuntimeObservation: Hashable, Sendable, Codable {
    public let host: HostKind
    public let hostVersion: String
    public let integrationMode: String
    public let endpointID: String?
    public let incarnation: HostIncarnation?
    public let applicationState: HostApplicationState
    public let permission: HostPermissionState
    public let locatorState: HostLocatorState
    public let provenLevels: Set<HostNavigationLevel>
    public let candidateCount: Int
    public let liveSessionConnected: Bool
    public let liveSessionID: String?
    public let currentTabID: String?
    public let extensionInstanceID: String?
    public let connectedExtensionTerminalID: String?
    public let connectedExtensionTerminal: Bool
    public let runtimeHandle: String?
    public let runtimeVersion: String?
    public let childSurfaceFocusProven: Bool
    public let workspaceOrFileProven: Bool
    public let provenWorkspaceID: String?
    public let provenFileID: String?
    public let currentAXCandidateToken: String?
    public let accessibilityOptIn: Bool

    public init(
        host: HostKind,
        hostVersion: String = "unknown",
        integrationMode: String,
        endpointID: String? = nil,
        incarnation: HostIncarnation? = nil,
        applicationState: HostApplicationState = .available,
        permission: HostPermissionState = .notRequired,
        locatorState: HostLocatorState = .live,
        provenLevels: Set<HostNavigationLevel> = [],
        candidateCount: Int = 1,
        liveSessionConnected: Bool = false,
        liveSessionID: String? = nil,
        currentTabID: String? = nil,
        extensionInstanceID: String? = nil,
        connectedExtensionTerminalID: String? = nil,
        connectedExtensionTerminal: Bool = false,
        runtimeHandle: String? = nil,
        runtimeVersion: String? = nil,
        childSurfaceFocusProven: Bool = false,
        workspaceOrFileProven: Bool = false,
        provenWorkspaceID: String? = nil,
        provenFileID: String? = nil,
        currentAXCandidateToken: String? = nil,
        accessibilityOptIn: Bool = false
    ) {
        self.host = host
        self.hostVersion = hostVersion
        self.integrationMode = integrationMode
        self.endpointID = endpointID
        self.incarnation = incarnation
        self.applicationState = applicationState
        self.permission = permission
        self.locatorState = locatorState
        self.provenLevels = provenLevels
        self.candidateCount = max(0, candidateCount)
        self.liveSessionConnected = liveSessionConnected
        self.liveSessionID = liveSessionID
        self.currentTabID = currentTabID
        self.extensionInstanceID = extensionInstanceID
        self.connectedExtensionTerminalID = connectedExtensionTerminalID
        self.connectedExtensionTerminal = connectedExtensionTerminal
        self.runtimeHandle = runtimeHandle
        self.runtimeVersion = runtimeVersion
        self.childSurfaceFocusProven = childSurfaceFocusProven
        self.workspaceOrFileProven = workspaceOrFileProven
        self.provenWorkspaceID = provenWorkspaceID
        self.provenFileID = provenFileID
        self.currentAXCandidateToken = currentAXCandidateToken
        self.accessibilityOptIn = accessibilityOptIn
    }

    /// Convenience for fixtures that only want to state a proven ladder
    /// level; every level remains explicit evidence, never inferred matching.
    public init(
        host: HostKind,
        integrationMode: String,
        incarnation: HostIncarnation? = nil,
        permission: HostPermissionState = .notRequired,
        levels: Set<HostNavigationLevel>,
        candidateCount: Int = 1
    ) {
        self.init(
            host: host,
            integrationMode: integrationMode,
            incarnation: incarnation,
            permission: permission,
            provenLevels: levels,
            candidateCount: candidateCount,
            liveSessionConnected: levels.contains(.exactSurface),
            connectedExtensionTerminal: levels.contains(.exactSurface),
            workspaceOrFileProven: levels.contains(.workspaceOrFile),
            accessibilityOptIn: levels.contains(.windowBestEffort)
        )
    }
}

public enum HostNavigationRevalidationReason: String, CaseIterable, Hashable, Sendable, Codable {
    case ready
    case notExplicitPersonAction
    case missingAssociation
    case ownerMismatch
    case hostMismatch
    case hostUnavailable
    case hostAbsent
    case modeChanged
    case navigationCapabilityMissing
    case navigationCapabilityUnavailable
    case staleCapability
    case navigationPermissionDenied
    case accessibilityPermissionDenied
    case locatorHistorical
    case locatorClosed
    case locatorInvalidated
    case locatorRecreated
    case incarnationChanged
    case endpointChanged
    case hostVersionChanged
    case extensionReloaded
    case runtimeVersionChanged
    case ambiguousCandidates
    case noSeparatelyProvenFallback
    case unsupportedHost
    case dispatchFailed
    case unknown

    public var redactedDescription: String {
        switch self {
        case .ready: "Host Context evidence was revalidated."
        case .notExplicitPersonAction: "Jump Back requires an explicit person action."
        case .missingAssociation: "No Host Context evidence is associated with this Agent Session."
        case .ownerMismatch: "The Host Context is owned by a different Agent Session."
        case .hostMismatch: "Current Host evidence does not match the recorded Host."
        case .hostUnavailable, .hostAbsent: "The recorded Host is unavailable."
        case .modeChanged: "The Integration Installation mode changed."
        case .navigationCapabilityMissing: "Host navigation capability was not negotiated."
        case .navigationCapabilityUnavailable: "Host navigation capability is unavailable."
        case .staleCapability: "Host navigation capability evidence is stale."
        case .navigationPermissionDenied, .accessibilityPermissionDenied: "Required Host permission is unavailable."
        case .locatorHistorical: "The locator is historical and needs live revalidation."
        case .locatorClosed: "The recorded Host surface is closed."
        case .locatorInvalidated: "The recorded Host locator was invalidated."
        case .locatorRecreated: "The Host surface was recreated; its old locator cannot be reused."
        case .incarnationChanged: "The Host incarnation changed."
        case .endpointChanged: "The Host endpoint changed."
        case .hostVersionChanged: "The Host version changed."
        case .extensionReloaded: "The connected Host extension was reloaded."
        case .runtimeVersionChanged: "The Host runtime version no longer matches."
        case .ambiguousCandidates: "More than one current Host candidate was proven."
        case .noSeparatelyProvenFallback: "No separately proven lower navigation level is available."
        case .unsupportedHost: "This Host has no documented navigation contract."
        case .dispatchFailed: "The Host did not accept the navigation request."
        case .unknown: "Host navigation could not be revalidated."
        }
    }
}

/// The complete evidence returned immediately before a navigation attempt.
/// Each `provenLevels` entry is separately proven by the Host adapter and may
/// be used for a lower fallback only when the stronger attempt fails.
public struct HostNavigationRevalidation: Hashable, Sendable, Codable {
    public let associationID: HostContextID
    public let sessionIdentity: AgentSessionIdentity
    public let host: HostKind
    public let integrationMode: String
    public let capabilityID: String?
    public let capabilityRevision: Int?
    public let permission: HostPermissionState
    public let locatorState: HostLocatorState
    public let incarnation: HostIncarnation?
    public let provenLevels: Set<HostNavigationLevel>
    public let candidateCount: Int
    public let evaluatedAt: Date
    public let ownershipMatches: Bool
    public let hostMatches: Bool
    public let modeMatches: Bool
    public let capabilityGranted: Bool
    public let permissionGranted: Bool
    public let locatorMatches: Bool
    public let incarnationMatches: Bool
    public let reason: HostNavigationRevalidationReason

    public init(
        associationID: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        host: HostKind,
        integrationMode: String,
        capabilityID: String? = WellKnownCapability.hostNavigation,
        capabilityRevision: Int? = nil,
        permission: HostPermissionState,
        locatorState: HostLocatorState,
        incarnation: HostIncarnation? = nil,
        provenLevels: Set<HostNavigationLevel> = [],
        candidateCount: Int = 0,
        evaluatedAt: Date,
        ownershipMatches: Bool = true,
        hostMatches: Bool = true,
        modeMatches: Bool = true,
        capabilityGranted: Bool = true,
        permissionGranted: Bool? = nil,
        locatorMatches: Bool = true,
        incarnationMatches: Bool = true,
        reason: HostNavigationRevalidationReason = .ready
    ) {
        self.associationID = associationID
        self.sessionIdentity = sessionIdentity
        self.host = host
        self.integrationMode = integrationMode
        self.capabilityID = capabilityID
        self.capabilityRevision = capabilityRevision
        self.permission = permission
        self.locatorState = locatorState
        self.incarnation = incarnation
        self.provenLevels = provenLevels
        self.candidateCount = max(0, candidateCount)
        self.evaluatedAt = evaluatedAt
        self.ownershipMatches = ownershipMatches
        self.hostMatches = hostMatches
        self.modeMatches = modeMatches
        self.capabilityGranted = capabilityGranted
        self.permissionGranted = permissionGranted ?? permission.allowsNavigation
        self.locatorMatches = locatorMatches
        self.incarnationMatches = incarnationMatches
        self.reason = reason
    }

    public var isReady: Bool {
        // Lower fallbacks (application/workspace) remain valid when an exact
        // locator is stale or recreated.  Ownership, mode, capability, and
        // permission are never relaxed; those gates protect against routing
        // to another Agent Session.
        ownershipMatches && hostMatches && modeMatches && capabilityGranted && permissionGranted && !provenLevels.isEmpty &&
            (locatorMatches && incarnationMatches || provenLevels.contains(.appOnly) || provenLevels.contains(.workspaceOrFile))
    }

    public var achievedLevels: [HostNavigationLevel] {
        provenLevels.sorted(by: >)
    }
}

/// A typed host target handed to the Host implementation.  It contains no
/// Product action, input, lease, or lifecycle operation.
public struct HostNavigationTarget: Hashable, Sendable, Codable {
    public let sessionIdentity: AgentSessionIdentity
    public let associationID: HostContextID
    public let host: HostKind
    public let locator: HostLocator
    public let level: HostNavigationLevel
    public let revalidatedAt: Date

    public init(
        sessionIdentity: AgentSessionIdentity,
        associationID: HostContextID,
        host: HostKind,
        locator: HostLocator,
        level: HostNavigationLevel,
        revalidatedAt: Date
    ) {
        self.sessionIdentity = sessionIdentity
        self.associationID = associationID
        self.host = host
        self.locator = locator
        self.level = level
        self.revalidatedAt = revalidatedAt
    }
}

public enum HostNavigationDispatch: Hashable, Sendable, Codable {
    case reached
    case rejected(HostNavigationRevalidationReason)
}

/// Typed inward-facing Host navigation port.  Implementations may activate a
/// documented Host surface, but this contract has no API for clicks,
/// keystrokes, terminal input, Product actions, or Action Leases.
public protocol HostNavigationPort: Sendable {
    func revalidate(
        _ association: HostContextAssociation,
        for sessionIdentity: AgentSessionIdentity,
        negotiation: NegotiationSnapshot?,
        at date: Date
    ) -> HostNavigationRevalidation

    func navigate(_ target: HostNavigationTarget, at date: Date) -> HostNavigationDispatch
}

public typealias HostLocatorPort = HostNavigationPort

/// Pure host matrix policy.  Concrete adapters supply only read-only current
/// observations; this policy supplies the documented, capability-honest
/// ladder for iTerm2, Cursor, Warp, and Orca.
public enum HostNavigationPolicy {
    public static func revalidate(
        association: HostContextAssociation,
        sessionIdentity: AgentSessionIdentity,
        negotiation: NegotiationSnapshot?,
        observation: HostRuntimeObservation,
        at date: Date
    ) -> HostNavigationRevalidation {
        let capability = negotiation?.capabilities.first { $0.id == WellKnownCapability.hostNavigation && $0.direction == .navigate }
        let negotiationOwnerMatches = negotiation?.integrationInstanceID == association.integrationInstanceID &&
            negotiation?.productNamespace == association.sessionIdentity.productNamespace &&
            negotiation?.integrationMode == association.integrationMode
        let capabilityGranted = negotiationOwnerMatches && negotiation?.grants(WellKnownCapability.hostNavigation, direction: .navigate) == true
        let permissionGranted = observation.permission.allowsNavigation
        // Accessibility is required only for Warp's optional window
        // qualifier.  A denied AX grant still leaves the documented app-only
        // fallback available when the Host application itself is present.
        let effectivePermissionGranted = permissionGranted ||
            (association.host == .warp && association.locator.requiresAccessibility && observation.applicationState == .available)
        let ownerMatches = association.sessionIdentity == sessionIdentity
        let hostMatches = association.host == observation.host && association.provenance.host == observation.host
        let modeMatches = association.integrationMode == observation.integrationMode
        let locatorMatches = association.locator.host == observation.host || association.locator == .appOnly
        let incarnationMatches: Bool = {
            guard let current = observation.incarnation else { return false }
            return current == association.incarnation
        }()

        var reason: HostNavigationRevalidationReason = .ready
        if !ownerMatches { reason = .ownerMismatch }
        else if !hostMatches { reason = .hostMismatch }
        else if !modeMatches { reason = .modeChanged }
        else if negotiation == nil { reason = .navigationCapabilityMissing }
        else if !negotiationOwnerMatches { reason = .ownerMismatch }
        else if !capabilityGranted {
            if let capability, capability.freshness != .current { reason = .staleCapability }
            else if capability == nil { reason = .navigationCapabilityMissing }
            else { reason = .navigationCapabilityUnavailable }
        } else if !effectivePermissionGranted {
            reason = association.locator.requiresAccessibility ? .accessibilityPermissionDenied : .navigationPermissionDenied
        } else if observation.applicationState != .available {
            reason = observation.applicationState == .absent ? .hostAbsent : .hostUnavailable
        } else if !locatorMatches {
            reason = .locatorInvalidated
        } else if association.isInvalidated {
            reason = .locatorInvalidated
        } else if observation.locatorState != .live {
            reason = switch observation.locatorState {
            case .historical: .locatorHistorical
            case .closed: .locatorClosed
            case .recreated: .locatorRecreated
            case .invalidated: .locatorInvalidated
            case .permissionDenied: .navigationPermissionDenied
            case .ambiguous: .ambiguousCandidates
            case .unavailable: .hostUnavailable
            case .live: .ready
            }
        } else if !incarnationMatches {
            reason = .incarnationChanged
        } else if association.hostVersion != "unknown", observation.hostVersion != "unknown", association.hostVersion != observation.hostVersion {
            reason = .hostVersionChanged
        } else if let endpoint = association.provenance.endpointID, endpoint != observation.endpointID {
            reason = .endpointChanged
        }

        var levels: Set<HostNavigationLevel> = []
        let fallbackSafeReasons: Set<HostNavigationRevalidationReason> = [
            .locatorHistorical, .locatorClosed, .locatorInvalidated,
            .locatorRecreated, .incarnationChanged, .endpointChanged,
            .hostVersionChanged, .extensionReloaded, .runtimeVersionChanged
        ]
        if reason == .ready || fallbackSafeReasons.contains(reason) {
            levels = provenLevels(for: association, observation: observation)
            if reason != .ready {
                levels.remove(.exactSurface)
                levels.remove(.exactTab)
                levels.remove(.windowBestEffort)
            }
            if levels.isEmpty { reason = .noSeparatelyProvenFallback }
        }

        return HostNavigationRevalidation(
            associationID: association.id,
            sessionIdentity: sessionIdentity,
            host: association.host,
            integrationMode: association.integrationMode,
            capabilityID: capability?.id,
            capabilityRevision: capability?.revision,
            permission: observation.permission,
            locatorState: observation.locatorState,
            incarnation: observation.incarnation,
            provenLevels: levels,
            candidateCount: observation.candidateCount,
            evaluatedAt: date,
            ownershipMatches: ownerMatches,
            hostMatches: hostMatches,
            modeMatches: modeMatches,
            capabilityGranted: capabilityGranted,
            permissionGranted: effectivePermissionGranted,
            locatorMatches: locatorMatches,
            incarnationMatches: incarnationMatches,
            reason: reason
        )
    }

    private static func provenLevels(for association: HostContextAssociation, observation: HostRuntimeObservation) -> Set<HostNavigationLevel> {
        var levels = observation.provenLevels
        switch association.host {
        case .iterm2:
            switch association.locator {
            case .iterm2LiveSession:
                guard observation.liveSessionConnected || levels.contains(.exactSurface) else { break }
                if case .iterm2LiveSession(let sessionID) = association.locator,
                   observation.liveSessionID != sessionID {
                    levels.remove(.exactSurface)
                    break
                }
                levels.insert(.exactSurface)
            case .iterm2Tab:
                if case .iterm2Tab(let tabID) = association.locator,
                   observation.currentTabID != tabID {
                    levels.remove(.exactTab)
                }
            default: break
            }
        case .cursor:
            switch association.locator {
            case .cursorExtensionTerminal(let terminalID, let extensionID):
                guard observation.connectedExtensionTerminal,
                      observation.extensionInstanceID == extensionID,
                      observation.connectedExtensionTerminalID == terminalID else {
                    levels.remove(.exactSurface)
                    levels.remove(.exactTab)
                    break
                }
                levels.insert(.exactSurface)
            case .cursorNativeThread:
                // Native Cursor threads have no exact selector.
                levels.remove(.exactSurface)
                levels.remove(.exactTab)
            case .cursorWorkspace(let workspaceID, let fileID):
                levels.remove(.exactSurface)
                levels.remove(.exactTab)
                if let provenWorkspaceID = observation.provenWorkspaceID, provenWorkspaceID != workspaceID {
                    levels.remove(.workspaceOrFile)
                }
                if let fileID, let provenFileID = observation.provenFileID, provenFileID != fileID {
                    levels.remove(.workspaceOrFile)
                }
            default: break
            }
            if association.locator.isHistoricalOnly { levels.remove(.exactSurface); levels.remove(.exactTab) }
            if observation.workspaceOrFileProven { levels.insert(.workspaceOrFile) }
        case .warp:
            levels.remove(.exactSurface)
            levels.remove(.exactTab)
            if case .warpAXWindow = association.locator,
               observation.accessibilityOptIn,
               observation.permission == .granted,
               observation.candidateCount == 1,
               observation.currentAXCandidateToken == association.locator.candidateToken,
               levels.contains(.windowBestEffort) {
                levels.insert(.windowBestEffort)
            } else {
                levels.remove(.windowBestEffort)
            }
            if case .warpApplication = association.locator { levels.insert(.appOnly) }
        case .orca:
            levels.remove(.exactSurface)
            levels.remove(.exactTab)
            if case .orcaRuntimeTab(let recordedHandle, _, let recordedVersion) = association.locator,
               let runtimeVersion = observation.runtimeVersion,
               let runtimeHandle = observation.runtimeHandle,
               !runtimeHandle.isEmpty,
               runtimeHandle == recordedHandle,
               runtimeVersion == recordedVersion {
                levels.insert(.exactTab)
                if observation.childSurfaceFocusProven { levels.insert(.exactSurface) }
            }
            if observation.workspaceOrFileProven { levels.insert(.workspaceOrFile) }
        case .unknown:
            return []
        }

        // Current application presence is an independently observed,
        // deliberately low-precision fallback.  It is not a claim about a
        // tab, thread, workspace, or file.
        if observation.applicationState == .available {
            levels.insert(.appOnly)
        }

        // A Host adapter must explicitly prove each fallback level.  A
        // stronger level does not manufacture lower evidence, except where a
        // documented Host contract explicitly supplies app availability.
        return levels.filter { level in
            switch level {
            case .exactSurface, .exactTab, .workspaceOrFile, .windowBestEffort:
                observation.provenLevels.contains(level) ||
                    (association.host == .iterm2 && level == .exactSurface && observation.liveSessionConnected) ||
                    (association.host == .cursor && level == .exactSurface && observation.connectedExtensionTerminal) ||
                    (association.host == .cursor && level == .workspaceOrFile && observation.workspaceOrFileProven) ||
                    (level == .workspaceOrFile && observation.workspaceOrFileProven) ||
                    (association.host == .warp && level == .windowBestEffort && observation.accessibilityOptIn && observation.candidateCount == 1) ||
                    (association.host == .orca && level == .exactTab && observation.runtimeVersion != nil)
            case .appOnly:
                observation.provenLevels.contains(.appOnly) || association.host == .warp || association.host == .orca
            case .unavailable: false
            }
        }
    }
}

/// A small matrix-backed port useful for deterministic host-matrix tests and
/// for the first practical adapter implementations.  It performs no UI
/// automation; dispatch is an explicit, injectable result.
public final class MatrixHostNavigationPort: @unchecked Sendable, HostNavigationPort {
    private let observationProvider: @Sendable (HostContextAssociation, Date) -> HostRuntimeObservation
    private let dispatchProvider: @Sendable (HostNavigationTarget, Date) -> HostNavigationDispatch

    public init(
        observation: HostRuntimeObservation,
        dispatch: HostNavigationDispatch = .reached
    ) {
        self.observationProvider = { _, _ in observation }
        self.dispatchProvider = { _, _ in dispatch }
    }

    public init(
        observationProvider: @escaping @Sendable (HostContextAssociation, Date) -> HostRuntimeObservation,
        dispatchProvider: @escaping @Sendable (HostNavigationTarget, Date) -> HostNavigationDispatch = { _, _ in .reached }
    ) {
        self.observationProvider = observationProvider
        self.dispatchProvider = dispatchProvider
    }

    public func revalidate(
        _ association: HostContextAssociation,
        for sessionIdentity: AgentSessionIdentity,
        negotiation: NegotiationSnapshot?,
        at date: Date
    ) -> HostNavigationRevalidation {
        HostNavigationPolicy.revalidate(
            association: association,
            sessionIdentity: sessionIdentity,
            negotiation: negotiation,
            observation: observationProvider(association, date),
            at: date
        )
    }

    public func navigate(_ target: HostNavigationTarget, at date: Date) -> HostNavigationDispatch {
        dispatchProvider(target, date)
    }
}
