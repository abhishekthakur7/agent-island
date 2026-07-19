import Foundation

public enum AtlasDiagnosticComponent: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case settings
    case onboarding
    case integration
    case preview
    case storage
    case overlay
}

public enum AtlasDiagnosticOutcome: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case accepted
    case filtered
    case deduplicated
    case downgraded
    case degraded
    case unavailable
    case failed
}

public enum AtlasDiagnosticReason: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case intentDisabled
    case deliveryVerified
    case notDetected
    case authenticationRequired
    case setupRequired
    case evidenceStale
    case capabilityDegraded
    case capabilityUnavailable
    case incompatibleVersion
    case localPreviewOnly
    case storageUnavailable
}

/// A closed, render-safe diagnostic projection.  It has no arbitrary text,
/// path, token, external identifier, or raw payload field by construction.
public struct AtlasDiagnosticRenderRecord: Codable, Equatable, Hashable, Sendable {
    public let component: AtlasDiagnosticComponent
    public let outcome: AtlasDiagnosticOutcome
    public let reason: AtlasDiagnosticReason
    public let health: AtlasIntegrationHealth
    public let freshness: AtlasEvidenceFreshness
    public let affectedCapability: AtlasIntegrationCapability?
    public let safeNextStep: AtlasIntegrationSafeNextStep
    public let observedAt: Date?

    public init(
        component: AtlasDiagnosticComponent,
        outcome: AtlasDiagnosticOutcome,
        reason: AtlasDiagnosticReason,
        health: AtlasIntegrationHealth = .unknown,
        freshness: AtlasEvidenceFreshness = .unknown,
        affectedCapability: AtlasIntegrationCapability? = nil,
        safeNextStep: AtlasIntegrationSafeNextStep = .inspect,
        observedAt: Date? = nil
    ) {
        self.component = component
        self.outcome = outcome
        self.reason = reason
        self.health = health
        self.freshness = freshness
        self.affectedCapability = affectedCapability
        self.safeNextStep = safeNextStep
        self.observedAt = observedAt
    }
}

public enum AtlasDiagnosticsSanitizer {
    public static func render(
        integration: AtlasIntegrationState,
        at date: Date? = nil
    ) -> AtlasDiagnosticRenderRecord {
        let outcome: AtlasDiagnosticOutcome
        let reason: AtlasDiagnosticReason
        switch integration.summary {
        case .notEnabled, .detectedNotEnabled:
            outcome = .filtered
            reason = .intentDisabled
        case .authenticationRequired:
            outcome = .degraded
            reason = .authenticationRequired
        case .setupRequired:
            outcome = .degraded
            reason = .setupRequired
        case .healthy:
            outcome = .accepted
            reason = .deliveryVerified
        case .degraded:
            outcome = .degraded
            reason = .capabilityDegraded
        case .unavailable:
            outcome = .unavailable
            reason = .capabilityUnavailable
        case .incompatible:
            outcome = .failed
            reason = .incompatibleVersion
        case .unknown:
            outcome = .unavailable
            reason = .notDetected
        }
        return AtlasDiagnosticRenderRecord(
            component: .integration,
            outcome: outcome,
            reason: reason,
            health: integration.health,
            freshness: integration.freshness,
            affectedCapability: integration.affectedCapability,
            safeNextStep: integration.safeNextStep,
            observedAt: date ?? integration.evidence?.observedAt
        )
    }

    /// Kept as an explicit operation so future adapters can only hand the UI
    /// this closed record.  Since its shape is already allowlisted, sanitizing
    /// is a value-preserving operation with no string scanning loopholes.
    public static func sanitize(_ record: AtlasDiagnosticRenderRecord) -> AtlasDiagnosticRenderRecord { record }
}

public typealias AtlasDiagnosticRecord = AtlasDiagnosticRenderRecord

public enum AtlasDiagnostics {
    public static func render(integration: AtlasIntegrationState, at date: Date? = nil) -> AtlasDiagnosticRenderRecord {
        AtlasDiagnosticsSanitizer.render(integration: integration, at: date)
    }

    public static func sanitize(_ record: AtlasDiagnosticRenderRecord) -> AtlasDiagnosticRenderRecord {
        AtlasDiagnosticsSanitizer.sanitize(record)
    }
}
