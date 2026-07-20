import Foundation
import SessionDomain

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
    case interfaceChanged
    case permissionDenied
    case killSwitchClosed
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

    /// Projects the Atlas render state into the same closed operational
    /// evidence consumed by Diagnostic Bundle generation. No integration
    /// identity, Product version string, path, title, or payload is copied.
    public static func evidence(
        integration: AtlasIntegrationState,
        at date: Date? = nil,
        correlation: DiagnosticCorrelationID = .generated()
    ) -> DiagnosticEvidence {
        let record = render(integration: integration, at: date)
        let outcome: DiagnosticOutcome = switch record.outcome {
        case .accepted: .accepted
        case .filtered: .filtered
        case .deduplicated: .deduplicated
        case .downgraded: .downgraded
        case .degraded: .degraded
        case .unavailable: .unavailable
        case .failed: .failed
        }
        let reason: DiagnosticReason = switch record.reason {
        case .intentDisabled: .policyFiltered
        case .deliveryVerified: .deliveryVerified
        case .notDetected: .configurationUnavailable
        case .authenticationRequired: .permissionDenied
        case .setupRequired: .configurationUnavailable
        case .evidenceStale: .staleEvidence
        case .capabilityDegraded: .capabilityDowngraded
        case .capabilityUnavailable: .transportUnavailable
        case .incompatibleVersion: .incompatibleContract
        case .interfaceChanged: .incompatibleContract
        case .permissionDenied: .permissionDenied
        case .killSwitchClosed: .killSwitchClosed
        case .localPreviewOnly: .policyFiltered
        case .storageUnavailable: .storageUnavailable
        }
        let capability: DiagnosticCapability? = switch record.affectedCapability {
        case .observation: .observation
        case .attention: .attention
        case .action: .action
        case .navigation: .navigation
        case .configuration: .configuration
        case nil: nil
        }
        let next: DiagnosticSafeNextStep = switch record.safeNextStep {
        case .none: .none
        case .enableIntent: .enableIntent
        case .configure: .configure
        case .authenticate: .authenticate
        case .repair: .repair
        case .retry: .retry
        case .update: .update
        case .inspect: .inspect
        case .observe: .inspect
        }
        let health: DiagnosticHealthDimensions
        if let vector = integration.healthVector {
            let summary: IntegrationHealthSummary = switch integration.summary {
            case .notEnabled, .detectedNotEnabled, .unknown: .disabled
            case .authenticationRequired: .unavailable
            case .setupRequired: .setupRequired
            case .healthy: .healthy
            case .degraded: .degraded
            case .unavailable: .unavailable
            case .incompatible: .incompatible
            }
            let next: HealthSafeNextStep = switch vector.safeNextStep {
            case .none: .none
            case .enableIntent: .enableIntent
            case .configure: .configure
            case .repair: .repair
            case .retry: .retry
            case .update: .update
            case .inspect, .useNativeHost: .inspect
            }
            health = DiagnosticHealthDimensions(
                intent: vector.intent == .enabled ? .verified : .disabled,
                configurationLoad: vector.loadPolicy,
                interfaceCompatibility: vector.reachability == .degraded ? .degraded : .verified,
                permissions: vector.configured == .denied ? .denied : vector.configured,
                transport: vector.reachability,
                eventFreshness: vector.delivery,
                actionReadiness: vector.actionReadiness,
                hostNavigation: vector.navigationReadiness,
                summary: summary,
                safeNextStep: next
            )
        } else {
            health = .unknown
        }
        return DiagnosticEvidence(operation: .inspect, outcome: outcome, scope: DiagnosticScope(component: .integration, owner: .integration, capability: capability), reason: reason, occurredAt: record.observedAt ?? date ?? Date(), correlationID: correlation, health: health, safeNextStep: next)
    }

    /// Snapshot diagnostics intentionally pass through the same closed record
    /// as settings state.  Product versions and enum evidence are retained;
    /// snapshot IDs, paths, tokens, and interaction content never enter the
    /// render model.
    public static func render(snapshot: NegotiationSnapshot) -> AtlasDiagnosticRenderRecord {
        let health: AtlasIntegrationHealth = switch snapshot.health.summary {
        case .disabled: .unknown
        case .setupRequired: .setupRequired
        case .healthy: .healthy
        case .degraded: .degraded
        case .unavailable: .unavailable
        case .incompatible: .incompatible
        }
        let freshness: AtlasEvidenceFreshness = snapshot.health.delivery == .verified ? .current : .stale
        let reason: AtlasDiagnosticReason = switch snapshot.compatibility {
        case .incompatibleMajor: .incompatibleVersion
        case .interfaceChanged: .interfaceChanged
        case .unknown: .capabilityDegraded
        case .compatible where snapshot.killSwitches.isEnabled(.observe) == false || snapshot.killSwitches.isEnabled(.act) == false || snapshot.killSwitches.isEnabled(.configure) == false || snapshot.killSwitches.isEnabled(.navigate) == false: .killSwitchClosed
        case .compatible where snapshot.health.configured == .denied: .permissionDenied
        case .compatible where snapshot.health.summary == .healthy: .deliveryVerified
        case .compatible where snapshot.health.summary == .setupRequired: .setupRequired
        case .compatible: .capabilityDegraded
        }
        let outcome: AtlasDiagnosticOutcome = switch reason {
        case .deliveryVerified: .accepted
        case .incompatibleVersion, .interfaceChanged: .failed
        case .killSwitchClosed: .filtered
        case .permissionDenied, .capabilityDegraded: .degraded
        default: .unavailable
        }
        let affectedID = snapshot.health.affectedCapabilities.first
        let affected: AtlasIntegrationCapability? = switch affectedID {
        case WellKnownCapability.sessionObservation: .observation
        case WellKnownCapability.sessionAction: .action
        case WellKnownCapability.configuration: .configuration
        case WellKnownCapability.hostNavigation: .navigation
        default: nil
        }
        let next: AtlasIntegrationSafeNextStep = switch snapshot.health.safeNextStep {
        case .none: .none
        case .enableIntent: .enableIntent
        case .configure: .configure
        case .repair: .repair
        case .retry: .retry
        case .update: .update
        case .inspect, .useNativeHost: .inspect
        }
        return AtlasDiagnosticRenderRecord(component: .integration, outcome: outcome, reason: reason, health: health, freshness: freshness, affectedCapability: affected, safeNextStep: next, observedAt: snapshot.health.evidenceAt)
    }

    public static func evidence(snapshot: NegotiationSnapshot, at date: Date? = nil, correlation: DiagnosticCorrelationID = .generated()) -> DiagnosticEvidence {
        let record = render(snapshot: snapshot)
        let state = AtlasIntegrationState(kind: .claudeCode, snapshot: snapshot, enabledIntent: true)
        return evidence(integration: state, at: date ?? record.observedAt, correlation: correlation)
    }
}

public typealias AtlasDiagnosticRecord = AtlasDiagnosticRenderRecord

public enum AtlasDiagnostics {
    public static func render(integration: AtlasIntegrationState, at date: Date? = nil) -> AtlasDiagnosticRenderRecord {
        AtlasDiagnosticsSanitizer.render(integration: integration, at: date)
    }

    public static func sanitize(_ record: AtlasDiagnosticRenderRecord) -> AtlasDiagnosticRenderRecord {
        AtlasDiagnosticsSanitizer.sanitize(record)
    }

    public static func render(snapshot: NegotiationSnapshot) -> AtlasDiagnosticRenderRecord {
        AtlasDiagnosticsSanitizer.render(snapshot: snapshot)
    }

    public static func evidence(integration: AtlasIntegrationState, at date: Date? = nil, correlation: DiagnosticCorrelationID = .generated()) -> DiagnosticEvidence {
        AtlasDiagnosticsSanitizer.evidence(integration: integration, at: date, correlation: correlation)
    }

    public static func evidence(snapshot: NegotiationSnapshot, at date: Date? = nil, correlation: DiagnosticCorrelationID = .generated()) -> DiagnosticEvidence {
        AtlasDiagnosticsSanitizer.evidence(snapshot: snapshot, at: date, correlation: correlation)
    }
}
