import Foundation
import SessionDomain

/// Optional Claude-only Status Line bridge. It has no discovery side effect,
/// never replaces a person's configured Status Line, and is not a claim about
/// any other Agent Product. Its one marked JSON/JSONC entry is installed only
/// from a fresh, explicitly approved Integration Installation plan.
public final class ClaudeStatusLineBridgeInstallationCoordinator: @unchecked Sendable {
    public static let integrationMode = "claudeCode.documentedStatusLineUsage"

    public init() {}

    public func discover(installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, manifest: OwnershipManifest? = nil, snapshot: NegotiationSnapshot? = nil) -> IntegrationInstallationDiscovery {
        let selector = ClaudeStatusLineBridgeEditor.selector()
        let inspection = ClaudeStatusLineBridgeEditor.inspect(at: scope.url, selector: selector)
        let compatibility = compatible(snapshot) ? IntegrationInstallationCompatibility.compatible : .unknown
        let state: IntegrationInstallationDiscoveryState = switch inspection.state {
        case .notConfigured: .notConfigured
        case .ownedIntact where manifest?.proving(selector, at: scope.path) != nil: .ownedIntact
        case .ownedIntact, .ownedDrifted: .ownedDrifted
        case .externalCandidate: .externalCandidate
        case .shadowedManaged: .shadowedManaged
        case .unsupported: .unsupported
        case .unavailable: .unavailable
        }
        return IntegrationInstallationDiscovery(installationID: installationID, product: ClaudeCodeIntegration.productNamespace, integrationMode: Self.integrationMode, scope: scope, state: state, inspection: inspection, compatibility: compatibility, affectedCapabilities: [WellKnownCapability.usageObservation], safeToMutate: state == .notConfigured && compatible(snapshot))
    }

    public func makePlan(id: String, installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, snapshot: NegotiationSnapshot, now: Date = Date(), expiresIn: TimeInterval = 300) -> IntegrationInstallationPlan {
        let source = ExactEntryEditor.snapshot(at: scope.url)
        let enabled = compatible(snapshot)
        return IntegrationInstallationPlan(id: id, installationID: installationID, action: .enable, product: ClaudeCodeIntegration.productNamespace, integrationMode: Self.integrationMode, scope: scope, sourcePath: scope.path, entries: [ClaudeStatusLineBridgeEditor.selector()], compatibility: enabled ? .compatible : .interfaceChanged, productVersion: snapshot.productVersion, interfaceVersion: snapshot.interfaceVersion, sourceFingerprint: source.fingerprint, affectedCapabilities: [WellKnownCapability.usageObservation], capabilityEvidence: IntegrationInstallationCapabilityEvidence(snapshot: snapshot, capabilityIDs: [WellKnownCapability.usageObservation], configurationAvailable: enabled), rollback: "Remove only the manifest-proven Agent Island Claude Status Line entry.", manualRemedy: "Existing Claude Status Line output is preserved. If a Status Line is already configured, leave it unchanged or review it manually.", createdAt: now, expiresAt: now.addingTimeInterval(expiresIn))
    }

    public func approve(_ plan: IntegrationInstallationPlan, personIdentifier: String, at date: Date = Date()) throws -> IntegrationInstallationApproval {
        guard (plan.action == .enable || plan.action == .remove), plan.integrationMode == Self.integrationMode, plan.isFresh(at: date), !personIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw IntegrationInstallationPlanError.personApprovalRequired }
        return IntegrationInstallationApproval(plan: plan, personIdentifier: personIdentifier, approvedAt: date)
    }

    public func apply(_ approval: IntegrationInstallationApproval, currentSnapshot: NegotiationSnapshot, now: Date = Date()) -> IntegrationInstallationApplyResult {
        let plan = approval.plan
        guard plan.isFresh(at: now), plan.compatibility == .compatible, compatible(currentSnapshot), currentSnapshot.productNamespace == ClaudeCodeIntegration.productNamespace, currentSnapshot.productVersion == plan.productVersion, currentSnapshot.interfaceVersion == plan.interfaceVersion, plan.entries == [ClaudeStatusLineBridgeEditor.selector()] else { return IntegrationInstallationApplyResult(status: .blocked, reason: .policyDenied) }
        let path = URL(fileURLWithPath: plan.sourcePath)
        guard ExactEntryEditor.snapshot(at: path).fingerprint == plan.sourceFingerprint else { return IntegrationInstallationApplyResult(status: .stale, reason: .sourceChanged) }
        do {
            let receipt = try ClaudeStatusLineBridgeEditor.add(at: path, expected: plan.sourceFingerprint, now: now)
            let reread = ClaudeStatusLineBridgeEditor.inspect(at: path).state == .ownedIntact
            guard reread else { return IntegrationInstallationApplyResult(status: .blocked, reason: .verificationFailed) }
            let verification = OwnershipManifestVerificationEvidence(verifiedAt: now, reread: true, probeSucceeded: true, sourceFingerprint: ExactEntryEditor.snapshot(at: path).fingerprint, capabilityIDs: [WellKnownCapability.usageObservation])
            let manifest = OwnershipManifest(id: plan.manifestID, installationID: plan.installationID.rawValue, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, sourcePath: plan.sourcePath, entries: [receipt], productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion, policyFingerprint: plan.policyFingerprint, verification: verification, createdAt: now)
            let installation = IntegrationInstallation(id: plan.installationID, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, manifestID: manifest.id, lifecycle: .enabled, enabledIntent: true, capabilities: [WellKnownCapability.usageObservation])
            return IntegrationInstallationApplyResult(status: .applied, manifest: manifest, installation: installation)
        } catch {
            return IntegrationInstallationApplyResult(status: .blocked, reason: .sourceChanged)
        }
    }

    public func makeRemovalPlan(id: String, installationID: IntegrationInstanceID, manifest: OwnershipManifest, snapshot: NegotiationSnapshot, now: Date = Date(), expiresIn: TimeInterval = 300) -> IntegrationInstallationPlan {
        let source = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: manifest.sourcePath))
        return IntegrationInstallationPlan(id: id, installationID: installationID, action: .remove, product: manifest.product, integrationMode: manifest.integrationMode, scope: manifest.scope, sourcePath: manifest.sourcePath, entries: manifest.exactSelectors, compatibility: compatible(snapshot) ? .compatible : .interfaceChanged, productVersion: snapshot.productVersion, interfaceVersion: snapshot.interfaceVersion, sourceFingerprint: source.fingerprint, affectedCapabilities: [WellKnownCapability.usageObservation], capabilityEvidence: IntegrationInstallationCapabilityEvidence(snapshot: snapshot, capabilityIDs: [WellKnownCapability.usageObservation], configurationAvailable: compatible(snapshot)), rollback: "No replacement is made; remove only the manifest-proven entry.", manualRemedy: "Source drift or a changed Status Line requires manual review.", createdAt: now, expiresAt: now.addingTimeInterval(expiresIn), manifestID: manifest.id)
    }

    public func remove(_ approval: IntegrationInstallationApproval, manifest: OwnershipManifest, now: Date = Date()) -> OwnershipManifestRemovalReport {
        let plan = approval.plan
        guard plan.action == .remove, plan.isFresh(at: now), plan.manifestID == manifest.id, manifest.integrationMode == Self.integrationMode, let receipt = manifest.entries.first, ExactEntryEditor.snapshot(at: URL(fileURLWithPath: manifest.sourcePath)).fingerprint == plan.sourceFingerprint else {
            return OwnershipManifestRemovalReport(outcome: .notRemoved, residualEntries: manifest.exactSelectors, reason: .sourceChanged, manifest: manifest)
        }
        do {
            _ = try ClaudeStatusLineBridgeEditor.remove(receipt: receipt, at: URL(fileURLWithPath: manifest.sourcePath), expected: plan.sourceFingerprint, now: now)
            let reread = ClaudeStatusLineBridgeEditor.inspect(at: URL(fileURLWithPath: manifest.sourcePath)).state == .notConfigured
            guard reread else { return OwnershipManifestRemovalReport(outcome: .notRemoved, residualEntries: manifest.exactSelectors, reason: .verificationFailed, manifest: manifest) }
            return OwnershipManifestRemovalReport(outcome: .removed, removedEntries: [receipt.selector], manifest: manifest.replacing(lifecycle: .removed, at: now))
        } catch {
            return OwnershipManifestRemovalReport(outcome: .notRemoved, residualEntries: [receipt.selector], reason: .sourceChanged, manifest: manifest)
        }
    }

    private func compatible(_ snapshot: NegotiationSnapshot?) -> Bool {
        guard let snapshot else { return false }
        return snapshot.compatibility == .compatible && snapshot.grants(WellKnownCapability.configuration, direction: .configure)
    }
}
