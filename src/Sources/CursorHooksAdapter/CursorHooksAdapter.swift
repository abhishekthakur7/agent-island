import Foundation
import SessionDomain
import AdapterPort

/// Cursor Hooks have no public, end-user installation contract in the Cursor
/// documentation verified on 2026-07-20.  This adapter deliberately models
/// that negative result instead of guessing a settings filename, event name,
/// payload shape, timeout, or locator.
public enum CursorHooksIntegration {
    public static let productNamespace = ProductNamespace("cursor")
    public static let integrationMode = "cursor.documentedHooksObservation"
    public static let adapterKind = "cursor.documented-hooks"
    public static let adapterBuildVersion = "1.0.0"
    public static let catalogRevision = "cursor-hooks.catalog.v1"
    public static let observationCapability = "cursor.hooks.sessionObservation"
    public static let capabilityProvenance = "https://docs.cursor.com/agent/hooks (not found 2026-07-20); https://cursor.com/sitemap.xml (no public hook contract)"
}

public struct CursorHooksContractEvidence: Hashable, Sendable, Codable {
    public enum Availability: String, Hashable, Sendable, Codable { case unavailable, incompatible }
    public let productVersion: String
    public let interfaceVersion: String
    public let availability: Availability
    public let observedAt: Date

    public init(productVersion: String = "unknown", interfaceVersion: String = "unknown", availability: Availability = .unavailable, observedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.productVersion = productVersion
        self.interfaceVersion = interfaceVersion
        self.availability = availability
        self.observedAt = observedAt
    }

    /// No supported Cursor version/interface can currently promote this to
    /// compatible: there is no documented configuration or envelope schema.
    public var compatibility: NegotiationCompatibility { availability == .incompatible ? .interfaceChanged : .unknown }
    public var probe: NegotiationProbeEvidence {
        .init(compatibility: compatibility, productVersion: productVersion, interfaceVersion: interfaceVersion, setup: .unavailable, observedAt: observedAt)
    }
}

/// Raw native identifiers stay inside this local-only carrier.  It has no
/// description, diagnostic, Codable conformance, or projection conversion.
struct CursorProtectedIdentity: Sendable, Hashable {
    let conversationID: String
    let generationID: String?
}

public enum CursorHookRejection: String, Error, Hashable, Sendable, Codable {
    case unsupportedContract
    case malformedEnvelope
    case oversizedEnvelope
    case unavailable
    case timeout
    case transportFailure
    case ambiguousOwnership
    case deliveryGap
    case duplicateOrCollision
    case unresolvedSubagentStop
}

public struct CursorHookDiagnostic: Hashable, Sendable, Codable {
    public let reason: CursorHookRejection
    public let observedAt: Date
    public init(_ reason: CursorHookRejection, observedAt: Date = Date()) { self.reason = reason; self.observedAt = observedAt }
    public var redactedDescription: String { "cursor-hooks:\(reason.rawValue)" }
}

public enum CursorHookIntakeOutcome: Sendable {
    case unavailable(CursorHookDiagnostic)
    case degraded(CursorHookDiagnostic)
    case rejected(CursorHookDiagnostic)
}

/// The only permitted decoder is a bounded gate.  It deliberately does not
/// parse unknown JSON because every field would be unsupported content or
/// identity until Cursor publishes a contract.
public enum CursorHookEnvelope {
    public static let maximumBytes = 65_536
    public static func validate(_ data: Data, contract: CursorHooksContractEvidence) -> Result<Void, CursorHookRejection> {
        guard data.count <= maximumBytes else { return .failure(.oversizedEnvelope) }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return .failure(.malformedEnvelope) }
        return .failure(contract.availability == .unavailable ? .unsupportedContract : .unavailable)
    }
}

/// Outer AdapterPort boundary. It owns no store and cannot dispatch Cursor
/// actions.  A documented contract is a prerequisite for any fact delivery.
public actor CursorHooksAdapter {
    public let integrationInstanceID: IntegrationInstanceID
    public let evidence: CursorHooksContractEvidence

    public init(integrationInstanceID: IntegrationInstanceID, evidence: CursorHooksContractEvidence = .init()) {
        self.integrationInstanceID = integrationInstanceID; self.evidence = evidence
    }

    public func negotiationRequest() -> NegotiationRequest {
        let capability = CapabilityRecord(
            id: CursorHooksIntegration.observationCapability,
            direction: .observe,
            availability: .unavailable,
            scope: .installation,
            maturity: .unknown,
            constraints: .init(values: ["contract": "no-public-cursor-hooks-contract"], requiresLiveEvidence: true),
            provenance: .init(integrationInstanceID: integrationInstanceID, productNamespace: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode),
            freshness: .stale,
            fallback: .unavailable,
            semanticVariant: "unavailable"
        )
        return .init(integrationInstanceID: integrationInstanceID, adapterKind: CursorHooksIntegration.adapterKind, adapterBuildVersion: CursorHooksIntegration.adapterBuildVersion, productNamespace: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode, offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0), requestedCapabilities: [capability.id], catalogRevision: CursorHooksIntegration.catalogRevision, productVersion: evidence.productVersion, interfaceVersion: evidence.interfaceVersion, probeEvidence: evidence.probe, requestedCapabilityRecords: [capability], compatibility: evidence.compatibility)
    }

    public func receive(_ data: Data) -> CursorHookIntakeOutcome {
        switch CursorHookEnvelope.validate(data, contract: evidence) {
        case .failure(.oversizedEnvelope): return .degraded(.init(.oversizedEnvelope))
        case .failure(.malformedEnvelope): return .degraded(.init(.malformedEnvelope))
        case .failure(let reason): return .unavailable(.init(reason))
        case .success: return .rejected(.init(.unsupportedContract))
        }
    }
}

/// Read-only installation lifecycle. Absence of a documented filename/schema
/// means discovery may inspect no Product configuration and every mutation is
/// blocked before a path, manifest, helper, or marker can be created.
public struct CursorHooksInstallationCoordinator: Sendable {
    public init() {}
    public func discover(installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, evidence: CursorHooksContractEvidence = .init()) -> IntegrationInstallationDiscovery {
        let source = ExactEntryFileSnapshot(path: "", exists: false, symlinkTarget: nil, resolvedPath: nil, content: nil, fingerprint: .init(content: nil))
        return .init(installationID: installationID, product: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode, scope: scope, state: .unsupported, inspection: .init(state: .unsupported, source: source, matchingEntryCount: 0, reason: .unsupported), compatibility: .unknown, affectedCapabilities: [CursorHooksIntegration.observationCapability], safeToMutate: false)
    }

    public func apply() -> IntegrationInstallationApplyResult { .init(status: .unavailable, reason: .unsupported) }
    public func disable() -> IntegrationInstallationApplyResult { .init(status: .unavailable, reason: .unsupported) }
    public func repair() -> IntegrationInstallationApplyResult { .init(status: .unavailable, reason: .unsupported) }
    public func remove() -> IntegrationInstallationApplyResult { .init(status: .unavailable, reason: .unsupported) }
    public func verify() -> IntegrationInstallationApplyResult { .init(status: .unavailable, reason: .unsupported) }
}

/// There is no Cursor Hook action channel, action lease, action route, or
/// dispatch type. Attention is honest native-host-only presentation.
public struct CursorAttentionPresentation: Hashable, Sendable, Codable {
    public let availability: String
    public let jumpBackLevel: String
    public let dispatchCount: Int
    public init() {
        availability = "Unavailable: respond in Cursor."
        jumpBackLevel = "App-only: Cursor Hooks provide no documented live locator."
        dispatchCount = 0
    }
}
