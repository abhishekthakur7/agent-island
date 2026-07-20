import Foundation

/// A Host is the local application that presents an Agent Session.  Host
/// identity is intentionally independent from the Product-owned
/// `AgentSessionIdentity`.
public enum HostKind: String, CaseIterable, Hashable, Sendable, Codable {
    case iterm2
    case cursor
    case warp
    case orca
    case unknown

    public var displayName: String {
        switch self {
        case .iterm2: "iTerm2"
        case .cursor: "Cursor"
        case .warp: "Warp"
        case .orca: "Orca"
        case .unknown: "Unknown Host"
        }
    }
}

/// Compatibility aliases keep the vocabulary useful at presentation and
/// integration boundaries without introducing another identity type.
public typealias Host = HostKind

public extension HostKind {
    static var iTerm2: Self { .iterm2 }
}

public struct HostContextID: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
}

public struct HostIncarnationID: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
}

/// A restart-safe Host incarnation.  A new process, extension reload, or
/// runtime recreation must receive a new ID (and normally a new generation).
public struct HostIncarnation: Hashable, Sendable, Codable {
    public let id: HostIncarnationID
    public let generation: Int
    public let startedAt: Date?

    public init(id: HostIncarnationID, generation: Int = 0, startedAt: Date? = nil) {
        self.id = id
        self.generation = generation
        self.startedAt = startedAt
    }

    public init(_ id: String, generation: Int = 0, startedAt: Date? = nil) {
        self.init(id: HostIncarnationID(id), generation: generation, startedAt: startedAt)
    }
}

public enum HostContextInvalidationReason: String, CaseIterable, Hashable, Sendable, Codable {
    case hostRestarted
    case endpointLost
    case permissionRevoked
    case locatorClosed
    case locatorRecreated
    case extensionReloaded
    case runtimeChanged
    case modeChanged
    case capabilityChanged
    case hostUnavailable
    case systemWake
    case displayTopologyChanged
    case manuallyReplaced
}

public enum HostContextValidity: Hashable, Sendable, Codable {
    case historical
    case live
    case invalidated(HostContextInvalidationReason)
}

/// A typed, source-proven Host locator.  It deliberately has no title, CWD,
/// PID, geometry, Space, AX label, or URL identity.  The opaque values are
/// supplied by the documented Host surface itself and are only useful while
/// their incarnation remains live.
public enum HostLocator: Hashable, Sendable, Codable {
    case iterm2LiveSession(sessionID: String)
    case iterm2Tab(tabID: String)
    case cursorExtensionTerminal(terminalID: String, extensionInstanceID: String)
    case cursorWorkspace(workspaceID: String, fileID: String?)
    /// Native Cursor Agent threads have no exact selector; this case records
    /// evidence only and is never a target for exact navigation.
    case cursorNativeThread
    case warpApplication
    case warpAXWindow(candidateToken: String)
    case orcaRuntimeTab(runtimeHandle: String, tabID: String, runtimeVersion: String)
    case orcaWorkspace(workspaceID: String, fileID: String?)
    case appOnly

    public var host: HostKind {
        switch self {
        case .iterm2LiveSession, .iterm2Tab: .iterm2
        case .cursorExtensionTerminal, .cursorWorkspace, .cursorNativeThread: .cursor
        case .warpApplication, .warpAXWindow: .warp
        case .orcaRuntimeTab, .orcaWorkspace: .orca
        case .appOnly: .unknown
        }
    }

    public var isHistoricalOnly: Bool {
        if case .cursorNativeThread = self { return true }
        return false
    }

    public var requiresAccessibility: Bool {
        if case .warpAXWindow = self { return true }
        return false
    }

    public var isOpaqueTarget: Bool {
        switch self {
        case .cursorNativeThread, .warpApplication, .appOnly: false
        default: true
        }
    }

    public var candidateToken: String? {
        if case .warpAXWindow(let token) = self { return token }
        return nil
    }

    // Descriptive spellings used by host adapters and fixtures.
    public static func cursorExtensionLiveTerminal(terminalID: String, extensionInstanceID: String) -> Self {
        .cursorExtensionTerminal(terminalID: terminalID, extensionInstanceID: extensionInstanceID)
    }

    public static func iTerm2LiveSession(sessionID: String) -> Self {
        .iterm2LiveSession(sessionID: sessionID)
    }

    public static func iTerm2Tab(tabID: String) -> Self {
        .iterm2Tab(tabID: tabID)
    }

    public static func warpWindow(candidateToken: String) -> Self {
        .warpAXWindow(candidateToken: candidateToken)
    }

    public static func orcaTab(runtimeHandle: String, tabID: String, runtimeVersion: String) -> Self {
        .orcaRuntimeTab(runtimeHandle: runtimeHandle, tabID: tabID, runtimeVersion: runtimeVersion)
    }
}

public enum HostEvidenceKind: String, CaseIterable, Hashable, Sendable, Codable {
    case documentedRuntime
    case liveSessionAPI
    case connectedExtension
    case workspaceOrFileProof
    case accessibilityProbe
    case applicationPresence
}

/// Provenance for one locator association.  `endpointID` is an opaque
/// source endpoint label, not a URL or an inferred target identity.
public struct HostLocatorProvenance: Hashable, Sendable, Codable {
    public let host: HostKind
    public let hostVersion: String
    public let endpointID: String?
    public let evidence: HostEvidenceKind
    public let observedAt: Date
    public let sourceID: String?

    public init(
        host: HostKind,
        hostVersion: String = "unknown",
        endpointID: String? = nil,
        evidence: HostEvidenceKind,
        observedAt: Date,
        sourceID: String? = nil
    ) {
        self.host = host
        self.hostVersion = hostVersion
        self.endpointID = endpointID
        self.evidence = evidence
        self.observedAt = observedAt
        self.sourceID = sourceID
    }
}

/// One many-to-many historical association between an Agent Session and a
/// Host Context.  This record is evidence, not a replacement for Product
/// session identity and not Product lifecycle state.
public struct HostContextAssociation: Hashable, Sendable, Codable {
    public let id: HostContextID
    public let sessionIdentity: AgentSessionIdentity
    public let host: HostKind
    public let hostVersion: String
    public let integrationInstanceID: IntegrationInstanceID
    public let integrationMode: String
    public let incarnation: HostIncarnation
    public let locator: HostLocator
    public let provenance: HostLocatorProvenance
    public let validity: HostContextValidity
    public let firstObservedAt: Date
    public let lastValidatedAt: Date?
    public let invalidatedAt: Date?

    public init(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        host: HostKind,
        hostVersion: String = "unknown",
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        incarnation: HostIncarnation,
        locator: HostLocator,
        provenance: HostLocatorProvenance,
        validity: HostContextValidity = .historical,
        firstObservedAt: Date,
        lastValidatedAt: Date? = nil,
        invalidatedAt: Date? = nil
    ) {
        self.id = id
        self.sessionIdentity = sessionIdentity
        self.host = host
        self.hostVersion = hostVersion
        self.integrationInstanceID = integrationInstanceID
        self.integrationMode = integrationMode
        self.incarnation = incarnation
        self.locator = locator
        self.provenance = provenance
        self.validity = validity
        self.firstObservedAt = firstObservedAt
        self.lastValidatedAt = lastValidatedAt
        self.invalidatedAt = invalidatedAt
    }

    public var isLive: Bool {
        if case .live = validity { return true }
        return false
    }

    public var isInvalidated: Bool {
        if case .invalidated = validity { return true }
        return false
    }

    public func validated(at date: Date) -> Self {
        Self(
            id: id,
            sessionIdentity: sessionIdentity,
            host: host,
            hostVersion: hostVersion,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            incarnation: incarnation,
            locator: locator,
            provenance: provenance,
            validity: .live,
            firstObservedAt: firstObservedAt,
            lastValidatedAt: date,
            invalidatedAt: nil
        )
    }

    public func invalidated(_ reason: HostContextInvalidationReason, at date: Date) -> Self {
        Self(
            id: id,
            sessionIdentity: sessionIdentity,
            host: host,
            hostVersion: hostVersion,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            incarnation: incarnation,
            locator: locator,
            provenance: provenance,
            validity: .invalidated(reason),
            firstObservedAt: firstObservedAt,
            lastValidatedAt: lastValidatedAt,
            invalidatedAt: date
        )
    }

    public func historical() -> Self {
        Self(
            id: id,
            sessionIdentity: sessionIdentity,
            host: host,
            hostVersion: hostVersion,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            incarnation: incarnation,
            locator: locator,
            provenance: provenance,
            validity: .historical,
            firstObservedAt: firstObservedAt,
            lastValidatedAt: lastValidatedAt,
            invalidatedAt: invalidatedAt
        )
    }
}

/// Small value store for many-to-many Host evidence.  The store has no
/// matching heuristics: lookup is only by the exact Product-owned session
/// identity (and, when supplied, an exact Host Context ID).
public struct HostContextEvidenceStore: Hashable, Sendable, Codable {
    private var values: [HostContextAssociation]

    public init(_ associations: [HostContextAssociation] = []) {
        self.values = associations
    }

    public var associations: [HostContextAssociation] { values }

    public mutating func record(_ association: HostContextAssociation) {
        if let index = values.firstIndex(where: { $0.id == association.id }) {
            values[index] = association
        } else {
            values.append(association)
        }
    }

    public mutating func invalidate(_ id: HostContextID, reason: HostContextInvalidationReason, at date: Date) {
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        values[index] = values[index].invalidated(reason, at: date)
    }

    public mutating func invalidateAll(
        host: HostKind? = nil,
        incarnation: HostIncarnationID? = nil,
        reason: HostContextInvalidationReason,
        at date: Date
    ) {
        for index in values.indices where
            (host == nil || values[index].host == host) &&
            (incarnation == nil || values[index].incarnation.id == incarnation) {
            values[index] = values[index].invalidated(reason, at: date)
        }
    }

    /// Sleep/wake is a live-locator boundary.  It never mutates Product
    /// lifecycle or action authority; it only marks Host evidence stale.
    public mutating func markSystemWake(at date: Date) {
        invalidateAll(reason: .systemWake, at: date)
    }

    public func association(_ id: HostContextID) -> HostContextAssociation? {
        values.first { $0.id == id }
    }

    public func associations(for identity: AgentSessionIdentity) -> [HostContextAssociation] {
        values.filter { $0.sessionIdentity == identity }
    }
}

public typealias HostContextRegistry = HostContextEvidenceStore
public typealias HostContext = HostContextAssociation
public typealias HostContextEvidence = HostContextAssociation
public typealias HostContextInvalidation = HostContextInvalidationReason
