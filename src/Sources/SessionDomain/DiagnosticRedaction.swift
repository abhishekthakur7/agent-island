import Foundation

/// The only component scopes that may enter operational diagnostics.  These
/// are intentionally coarse: a Product-native identifier, title, path, Host
/// locator, command, or callback token is never needed to explain health.
public enum DiagnosticComponent: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case intake
    case integration
    case installation
    case history
    case storage
    case hostNavigation
    case presentation
    case export
    case maintenance
}

public enum DiagnosticCapability: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case observation
    case attention
    case action
    case configuration
    case navigation
    case storage
    case diagnostics
    case userDataExport
    case maintenance
}

public enum DiagnosticOwnerScope: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case integration
    case installation
    case session
    case turn
    case host
    case store
    case localOnly
    case unknown
}

/// A closed scope projection. It has no identifier field by construction.
public struct DiagnosticScope: Codable, Equatable, Hashable, Sendable {
    public let component: DiagnosticComponent
    public let owner: DiagnosticOwnerScope
    public let capability: DiagnosticCapability?

    public init(component: DiagnosticComponent, owner: DiagnosticOwnerScope = .localOnly, capability: DiagnosticCapability? = nil) {
        self.component = component
        self.owner = owner
        self.capability = capability
    }
}

public enum DiagnosticOperation: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case accept
    case filter
    case deduplicate
    case quarantine
    case downgrade
    case reject
    case unavailable
    case degrade
    case fail
    case inspect
    case export
    case maintain
}

/// These outcomes cover every boundary result in the local contracts. They
/// are evidence of Agent Island's operation, never a claim about Product
/// lifecycle or Product-side success.
public enum DiagnosticOutcome: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case accepted
    case filtered
    case deduplicated
    case quarantined
    case downgraded
    case rejected
    case unavailable
    case degraded
    case failed
}

public enum DiagnosticReason: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case deliveryVerified
    case policyFiltered
    case duplicateDelivery
    case quarantinedInput
    case capabilityDowngraded
    case validationRejected
    case unknownNegotiation
    case incompatibleContract
    case capabilityNotGranted
    case ownerAmbiguous
    case malformedInput
    case payloadTooLarge
    case interactionContentUnsupported
    case staleEvidence
    case killSwitchClosed
    case configurationUnavailable
    case permissionDenied
    case transportUnavailable
    case eventFreshnessLost
    case actionUnavailable
    case navigationUnavailable
    case storageUnavailable
    case integrityFailure
    case schemaFailure
    case migrationFailure
    case confirmationRequired
    case stalePreview
    case manifestDrift
    case ambiguousOwnership
    case destinationInvalid
    case integrityManifestFailure
    case operationFailed
    case unknown
}

public enum DiagnosticSafeNextStep: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case none
    case inspect
    case enableIntent
    case authenticate
    case configure
    case repair
    case retry
    case update
    case useNativeHost
    case preserveBytes
    case exportVerified
    case reviewScope
    case confirmAgain
    case manualRemedy
}

/// The local trace value is deliberately transformed at construction. A
/// Product identifier or callback token supplied by an Adapter therefore
/// cannot leak into a bundle even if a caller mistakenly passes it here.
public struct DiagnosticCorrelationID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ source: String) {
        let digest = ExactEntryDigest.value(Data(source.utf8))
        self.value = "corr-\(digest)"
    }

    public static func generated() -> Self { Self(UUID().uuidString) }
    public var description: String { value }
}

/// The dimensions remain independent so a healthy observation path cannot
/// accidentally imply action readiness, configuration ownership, or exact
/// Host navigation.
public struct DiagnosticHealthDimensions: Codable, Equatable, Hashable, Sendable {
    public let intent: HealthDimensionStatus
    public let configurationLoad: HealthDimensionStatus
    public let interfaceCompatibility: HealthDimensionStatus
    public let permissions: HealthDimensionStatus
    public let transport: HealthDimensionStatus
    public let eventFreshness: HealthDimensionStatus
    public let actionReadiness: HealthDimensionStatus
    public let hostNavigation: HealthDimensionStatus
    public let summary: IntegrationHealthSummary
    public let safeNextStep: HealthSafeNextStep

    public init(
        intent: HealthDimensionStatus = .unknown,
        configurationLoad: HealthDimensionStatus = .unknown,
        interfaceCompatibility: HealthDimensionStatus = .unknown,
        permissions: HealthDimensionStatus = .unknown,
        transport: HealthDimensionStatus = .unknown,
        eventFreshness: HealthDimensionStatus = .unknown,
        actionReadiness: HealthDimensionStatus = .unknown,
        hostNavigation: HealthDimensionStatus = .unknown,
        summary: IntegrationHealthSummary = .unavailable,
        safeNextStep: HealthSafeNextStep = .inspect
    ) {
        self.intent = intent
        self.configurationLoad = configurationLoad
        self.interfaceCompatibility = interfaceCompatibility
        self.permissions = permissions
        self.transport = transport
        self.eventFreshness = eventFreshness
        self.actionReadiness = actionReadiness
        self.hostNavigation = hostNavigation
        self.summary = summary
        self.safeNextStep = safeNextStep
    }

    public init(vector: IntegrationHealthVector) {
        self.init(
            intent: vector.intent,
            configurationLoad: vector.loadPolicy,
            interfaceCompatibility: vector.reachability == .degraded ? .degraded : .verified,
            permissions: vector.configured == .denied ? .denied : vector.configured,
            transport: vector.reachability,
            eventFreshness: vector.delivery,
            actionReadiness: vector.actionReadiness,
            hostNavigation: vector.navigationReadiness,
            summary: vector.summary,
            safeNextStep: vector.safeNextStep
        )
    }

    public static let unknown = Self()
}

/// Allowlisted operational evidence. There is deliberately no free-form
/// detail, payload, Product ID, title, path, command, locator, or secret
/// field. Unknown adapter fields cannot be represented by this type.
public struct DiagnosticEvidence: Codable, Equatable, Hashable, Sendable {
    public let operation: DiagnosticOperation
    public let outcome: DiagnosticOutcome
    public let scope: DiagnosticScope
    public let reason: DiagnosticReason
    public let occurredAt: Date
    public let correlationID: DiagnosticCorrelationID
    public let health: DiagnosticHealthDimensions
    public let safeNextStep: DiagnosticSafeNextStep

    public init(
        operation: DiagnosticOperation,
        outcome: DiagnosticOutcome,
        scope: DiagnosticScope,
        reason: DiagnosticReason,
        occurredAt: Date,
        correlationID: DiagnosticCorrelationID,
        health: DiagnosticHealthDimensions = .unknown,
        safeNextStep: DiagnosticSafeNextStep = .inspect
    ) {
        self.operation = operation
        self.outcome = outcome
        self.scope = scope
        self.reason = reason
        self.occurredAt = occurredAt
        self.correlationID = correlationID
        self.health = health
        self.safeNextStep = safeNextStep
    }

    public static func intake(
        outcome: DiagnosticOutcome,
        reason: DiagnosticReason,
        at date: Date,
        health: DiagnosticHealthDimensions = .unknown,
        capability: DiagnosticCapability? = .observation,
        next: DiagnosticSafeNextStep = .inspect
    ) -> Self {
        let operation: DiagnosticOperation = switch outcome {
        case .accepted: .accept
        case .filtered: .filter
        case .deduplicated: .deduplicate
        case .quarantined: .quarantine
        case .downgraded: .downgrade
        case .rejected: .reject
        case .unavailable: .unavailable
        case .degraded: .degrade
        case .failed: .fail
        }
        return Self(operation: operation, outcome: outcome, scope: DiagnosticScope(component: .intake, owner: .integration, capability: capability), reason: reason, occurredAt: date, correlationID: .generated(), health: health, safeNextStep: next)
    }
}

/// Defense in depth for text composed by a presentation layer. Diagnostic
/// records themselves are structural/allowlisted; this helper is only for
/// fixed human-readable labels and rejects lines that look like sensitive
/// material rather than trying to scrub it after the fact.
public enum DiagnosticRedaction {
    public static let forbiddenFieldNames: Set<String> = [
        "prompt", "response", "plan", "command", "path", "title", "project",
        "worktree", "model", "token", "credential", "secret", "locator",
        "payload", "callback", "externalID", "productID", "destination"
    ]

    public static func isSafeLabel(_ value: String) -> Bool {
        let lower = value.lowercased()
        return !forbiddenFieldNames.contains(where: { lower.contains($0.lowercased()) }) &&
            !value.contains("/") && !value.contains("\\") && !value.contains("\n") && !value.contains("\r")
    }
}

public typealias DiagnosticRedactedRecord = DiagnosticEvidence
public typealias DiagnosticHealth = DiagnosticHealthDimensions
