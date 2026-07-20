import Foundation

public enum IntegrationInstallationScopeKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case user
    case project
    case worktree
    case repository
    case customPath
}

/// One explicitly selected scope. Discovery creates no scope implicitly and
/// never recursively scans beyond this exact path.
public struct IntegrationInstallationScope: Codable, Equatable, Hashable, Sendable {
    public let kind: IntegrationInstallationScopeKind
    public let identifier: String
    public let path: String

    public init(kind: IntegrationInstallationScopeKind = .user, identifier: String, path: URL) {
        self.kind = kind
        self.identifier = identifier
        self.path = path.path
    }

    public init(kind: IntegrationInstallationScopeKind = .user, identifier: String, path: String) {
        self.kind = kind
        self.identifier = identifier
        self.path = path
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var isAdvanced: Bool { kind != .user }
}

public enum IntegrationInstallationDiscoveryState: String, Codable, Equatable, Hashable, Sendable {
    case notConfigured
    case ownedIntact
    case ownedDrifted
    case externalCandidate
    case shadowedManaged
    case unsupported
    case unavailable
}

public typealias IntegrationInstallationState = IntegrationInstallationDiscoveryState

public enum IntegrationInstallationLifecycle: String, Codable, Equatable, Hashable, Sendable {
    case discovered
    case planned
    case enabled
    case disabled
    case degraded
    case partial
    case removed
}

public enum IntegrationInstallationPlanAction: String, Codable, Equatable, Hashable, Sendable {
    case enable
    case repair
    case migrate
    case disable
    case remove
}

public enum IntegrationInstallationCompatibility: String, Codable, Equatable, Hashable, Sendable {
    case compatible
    case interfaceChanged
    case unknown
    case incompatible
    case killSwitchClosed
    case policyBlocked
}

public struct IntegrationInstallationCapabilityEvidence: Codable, Equatable, Hashable, Sendable {
    public let snapshotID: NegotiationSnapshotID?
    public let capabilityIDs: [String]
    public let configurationAvailable: Bool
    public let killSwitches: IntegrationKillSwitches

    public init(snapshot: NegotiationSnapshot? = nil, capabilityIDs: [String] = [], configurationAvailable: Bool = false, killSwitches: IntegrationKillSwitches = .enabled) {
        self.snapshotID = snapshot?.id
        self.capabilityIDs = capabilityIDs
        self.configurationAvailable = configurationAvailable
        self.killSwitches = snapshot?.killSwitches ?? killSwitches
    }
}

public struct IntegrationInstallationNonEffects: Codable, Equatable, Hashable, Sendable {
    public let productPermissions: Bool
    public let credentials: Bool
    public let unrelatedHooksAndExtensions: Bool
    public let productSessions: Bool
    public let unselectedRepositoryConfiguration: Bool
    public let productDataRoots: Bool

    public init(productPermissions: Bool = false, credentials: Bool = false, unrelatedHooksAndExtensions: Bool = false, productSessions: Bool = false, unselectedRepositoryConfiguration: Bool = false, productDataRoots: Bool = false) {
        self.productPermissions = productPermissions
        self.credentials = credentials
        self.unrelatedHooksAndExtensions = unrelatedHooksAndExtensions
        self.productSessions = productSessions
        self.unselectedRepositoryConfiguration = unselectedRepositoryConfiguration
        self.productDataRoots = productDataRoots
    }

    public static let explicit = Self()
}

public struct IntegrationInstallationPlan: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let installationID: IntegrationInstanceID
    public let action: IntegrationInstallationPlanAction
    public let product: ProductNamespace
    public let integrationMode: String
    public let scope: IntegrationInstallationScope
    public let sourcePath: String
    public let entries: [ExactEntrySelector]
    public let artifacts: [OwnershipManifestArtifactReceipt]
    public let compatibility: IntegrationInstallationCompatibility
    public let productVersion: String
    public let interfaceVersion: String
    public let policyFingerprint: ExactEntryFingerprint?
    public let sourceFingerprint: ExactEntrySourceFingerprint
    public let permissionSummary: [String]
    public let affectedCapabilities: [String]
    public let capabilityEvidence: IntegrationInstallationCapabilityEvidence
    public let rollback: String
    public let manualRemedy: String
    public let nonEffects: IntegrationInstallationNonEffects
    public let createdAt: Date
    public let expiresAt: Date
    public let manifestID: String

    public init(id: String, installationID: IntegrationInstanceID, action: IntegrationInstallationPlanAction = .enable, product: ProductNamespace, integrationMode: String, scope: IntegrationInstallationScope, sourcePath: String, entries: [ExactEntrySelector], artifacts: [OwnershipManifestArtifactReceipt] = [], compatibility: IntegrationInstallationCompatibility = .compatible, productVersion: String = "unknown", interfaceVersion: String = "unknown", policyFingerprint: ExactEntryFingerprint? = nil, sourceFingerprint: ExactEntrySourceFingerprint, permissionSummary: [String] = [], affectedCapabilities: [String] = [], capabilityEvidence: IntegrationInstallationCapabilityEvidence = IntegrationInstallationCapabilityEvidence(), rollback: String = "Remove only the manifest-proven exact entry and artifacts.", manualRemedy: String = "Inspect the selected scope and retry after resolving the reported state.", nonEffects: IntegrationInstallationNonEffects = .explicit, createdAt: Date = Date(), expiresAt: Date? = nil, manifestID: String? = nil) {
        self.id = id
        self.installationID = installationID
        self.action = action
        self.product = product
        self.integrationMode = integrationMode
        self.scope = scope
        self.sourcePath = sourcePath
        self.entries = entries
        self.artifacts = artifacts
        self.compatibility = compatibility
        self.productVersion = productVersion
        self.interfaceVersion = interfaceVersion
        self.policyFingerprint = policyFingerprint
        self.sourceFingerprint = sourceFingerprint
        self.permissionSummary = permissionSummary
        self.affectedCapabilities = affectedCapabilities
        self.capabilityEvidence = capabilityEvidence
        self.rollback = rollback
        self.manualRemedy = manualRemedy
        self.nonEffects = nonEffects
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(300)
        self.manifestID = manifestID ?? "\(id)-manifest"
    }

    public var isFresh: Bool { isFresh(at: Date()) }
    public func isFresh(at date: Date) -> Bool { date <= expiresAt }
    public var isReviewable: Bool { !entries.isEmpty && !sourcePath.isEmpty }
    public var selectedScope: IntegrationInstallationScope { scope }
    public var exactEntries: [ExactEntrySelector] { entries }
    public var permissions: [String] { permissionSummary }
    public var affectedCapabilityIDs: [String] { affectedCapabilities }
    public var explicitNonEffects: IntegrationInstallationNonEffects { nonEffects }
}

public struct IntegrationInstallationApproval: Codable, Equatable, Hashable, Sendable {
    public let plan: IntegrationInstallationPlan
    public let personIdentifier: String
    public let approvedAt: Date

    public init(plan: IntegrationInstallationPlan, personIdentifier: String, approvedAt: Date = Date()) {
        self.plan = plan
        self.personIdentifier = personIdentifier
        self.approvedAt = approvedAt
    }
}

public typealias IntegrationInstallationPlanApproval = IntegrationInstallationApproval

public struct IntegrationInstallationRevalidation: Codable, Equatable, Hashable, Sendable {
    public let sourceFingerprint: ExactEntrySourceFingerprint
    public let product: ProductNamespace
    public let productVersion: String
    public let interfaceVersion: String
    public let policyFingerprint: ExactEntryFingerprint?
    public let ownershipProven: Bool

    public init(sourceFingerprint: ExactEntrySourceFingerprint, product: ProductNamespace, productVersion: String, interfaceVersion: String, policyFingerprint: ExactEntryFingerprint? = nil, ownershipProven: Bool = true) {
        self.sourceFingerprint = sourceFingerprint
        self.product = product
        self.productVersion = productVersion
        self.interfaceVersion = interfaceVersion
        self.policyFingerprint = policyFingerprint
        self.ownershipProven = ownershipProven
    }
}

public enum IntegrationInstallationApplyStatus: String, Codable, Equatable, Hashable, Sendable {
    case applied
    case stale
    case unapproved
    case unavailable
    case degraded
    case partial
    case blocked
}

public struct IntegrationInstallationApplyResult: Codable, Equatable, Hashable, Sendable {
    public let status: IntegrationInstallationApplyStatus
    public let manifest: OwnershipManifest?
    public let installation: IntegrationInstallation?
    public let reason: ExactEntryFailureReason?

    public init(status: IntegrationInstallationApplyStatus, manifest: OwnershipManifest? = nil, installation: IntegrationInstallation? = nil, reason: ExactEntryFailureReason? = nil) {
        self.status = status
        self.manifest = manifest
        self.installation = installation
        self.reason = reason
    }

    public var outcome: IntegrationInstallationApplyStatus { status }
}

public struct IntegrationInstallationDiscovery: Codable, Equatable, Hashable, Sendable {
    public let installationID: IntegrationInstanceID
    public let product: ProductNamespace
    public let integrationMode: String
    public let scope: IntegrationInstallationScope
    public let state: IntegrationInstallationDiscoveryState
    public let inspection: ExactEntryInspection
    public let compatibility: IntegrationInstallationCompatibility
    public let affectedCapabilities: [String]
    public let safeToMutate: Bool

    public init(installationID: IntegrationInstanceID, product: ProductNamespace, integrationMode: String, scope: IntegrationInstallationScope, state: IntegrationInstallationDiscoveryState, inspection: ExactEntryInspection, compatibility: IntegrationInstallationCompatibility = .unknown, affectedCapabilities: [String] = [], safeToMutate: Bool = false) {
        self.installationID = installationID
        self.product = product
        self.integrationMode = integrationMode
        self.scope = scope
        self.state = state
        self.inspection = inspection
        self.compatibility = compatibility
        self.affectedCapabilities = affectedCapabilities
        self.safeToMutate = safeToMutate
    }

    public var status: IntegrationInstallationDiscoveryState { state }
}

/// Runtime disablement is local intent only; it does not touch external setup.
public struct IntegrationInstallation: Codable, Equatable, Hashable, Sendable {
    public let id: IntegrationInstanceID
    public let product: ProductNamespace
    public let integrationMode: String
    public let scope: IntegrationInstallationScope
    public let manifestID: String?
    public var lifecycle: IntegrationInstallationLifecycle
    public var enabledIntent: Bool
    public let capabilities: [String]
    public let health: IntegrationHealthVector?

    public init(id: IntegrationInstanceID, product: ProductNamespace, integrationMode: String, scope: IntegrationInstallationScope, manifestID: String? = nil, lifecycle: IntegrationInstallationLifecycle = .discovered, enabledIntent: Bool = false, capabilities: [String] = [], health: IntegrationHealthVector? = nil) {
        self.id = id
        self.product = product
        self.integrationMode = integrationMode
        self.scope = scope
        self.manifestID = manifestID
        self.lifecycle = lifecycle
        self.enabledIntent = enabledIntent
        self.capabilities = capabilities
        self.health = health
    }

    public func disabling() -> Self {
        var copy = self
        copy.enabledIntent = false
        copy.lifecycle = .disabled
        return copy
    }
}

public enum IntegrationInstallationPlanError: Error, Codable, Equatable, Hashable, Sendable {
    case invalidPlan
    case personApprovalRequired
}

/// Orchestrates the scoped lifecycle while keeping all filesystem mutation in
/// `ExactEntryEditor`. The lock is per Installation ID and held through the
/// immediate revalidation and exact write.
public final class IntegrationInstallationCoordinator: @unchecked Sendable {
    private final class InstallationLockState: @unchecked Sendable {
        let lock = NSLock()
        var locked: Set<String> = []
    }
    private static let lockState = InstallationLockState()

    public init() {}

    public func discover(installationID: IntegrationInstanceID, product: ProductNamespace, integrationMode: String, scope: IntegrationInstallationScope, selector: ExactEntrySelector, manifest: OwnershipManifest? = nil, snapshot: NegotiationSnapshot? = nil, policy: ExactEntryWritePolicy = .allowed) -> IntegrationInstallationDiscovery {
        let inspection = ExactEntryEditor.inspect(at: scope.url, selector: selector, receipt: manifest?.proving(selector, at: scope.path))
        let compatibility = Self.compatibility(snapshot: snapshot, policy: policy)
        let affected = Self.affectedCapabilities(snapshot: snapshot)
        let state: IntegrationInstallationDiscoveryState = switch inspection.state {
        case .notConfigured: .notConfigured
        case .ownedIntact: .ownedIntact
        case .ownedDrifted: .ownedDrifted
        case .externalCandidate: .externalCandidate
        case .shadowedManaged: .shadowedManaged
        case .unsupported: .unsupported
        case .unavailable: .unavailable
        }
        let safe = state == .notConfigured && compatibility == .compatible && selector.isLossless && policy.allowsMutation && (snapshot == nil || Self.configurationAvailable(snapshot!))
        return IntegrationInstallationDiscovery(installationID: installationID, product: product, integrationMode: integrationMode, scope: scope, state: state, inspection: inspection, compatibility: compatibility, affectedCapabilities: affected, safeToMutate: safe)
    }

    public func makePlan(id: String, installationID: IntegrationInstanceID, action: IntegrationInstallationPlanAction = .enable, product: ProductNamespace, integrationMode: String, scope: IntegrationInstallationScope, selector: ExactEntrySelector, snapshot: NegotiationSnapshot? = nil, policy: ExactEntryWritePolicy = .allowed, now: Date = Date(), expiresIn: TimeInterval = 300) -> IntegrationInstallationPlan {
        makePlan(id: id, installationID: installationID, action: action, product: product, integrationMode: integrationMode, scope: scope, selectors: [selector], snapshot: snapshot, policy: policy, now: now, expiresIn: expiresIn)
    }

    public func makePlan(id: String, installationID: IntegrationInstanceID, action: IntegrationInstallationPlanAction = .enable, product: ProductNamespace, integrationMode: String, scope: IntegrationInstallationScope, selectors: [ExactEntrySelector], snapshot: NegotiationSnapshot? = nil, policy: ExactEntryWritePolicy = .allowed, now: Date = Date(), expiresIn: TimeInterval = 300) -> IntegrationInstallationPlan {
        let source = ExactEntryEditor.snapshot(at: scope.url)
        let compatibility = Self.compatibility(snapshot: snapshot, policy: policy)
        return IntegrationInstallationPlan(id: id, installationID: installationID, action: action, product: product, integrationMode: integrationMode, scope: scope, sourcePath: scope.path, entries: selectors, compatibility: compatibility, productVersion: snapshot?.productVersion ?? "unknown", interfaceVersion: snapshot?.interfaceVersion ?? "unknown", policyFingerprint: Self.policyFingerprint(policy), sourceFingerprint: source.fingerprint, permissionSummary: source.fingerprint.permissionBits.map { ["posix:\(String($0, radix: 8))"] } ?? [], affectedCapabilities: Self.affectedCapabilities(snapshot: snapshot), capabilityEvidence: IntegrationInstallationCapabilityEvidence(snapshot: snapshot, capabilityIDs: Self.affectedCapabilities(snapshot: snapshot), configurationAvailable: snapshot.map(Self.configurationAvailable) ?? policy.allowsMutation), createdAt: now, expiresAt: now.addingTimeInterval(expiresIn))
    }

    public func approve(_ plan: IntegrationInstallationPlan, personIdentifier: String, at date: Date = Date()) throws -> IntegrationInstallationApproval {
        guard plan.isReviewable, date >= plan.createdAt, plan.isFresh(at: date), !personIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw personIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? IntegrationInstallationPlanError.personApprovalRequired : IntegrationInstallationPlanError.invalidPlan
        }
        return IntegrationInstallationApproval(plan: plan, personIdentifier: personIdentifier, approvedAt: date)
    }

    public func apply(_ approval: IntegrationInstallationApproval, revalidation: IntegrationInstallationRevalidation, probe: (() -> Bool)? = nil, now: Date = Date()) -> IntegrationInstallationApplyResult {
        let plan = approval.plan
        guard !approval.personIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return IntegrationInstallationApplyResult(status: .unapproved, reason: .notManifestProven) }
        guard !plan.entries.isEmpty else { return IntegrationInstallationApplyResult(status: .blocked, reason: .lossy) }
        guard plan.isFresh(at: now) else { return IntegrationInstallationApplyResult(status: .stale, reason: .sourceChanged) }
        guard plan.compatibility == .compatible, revalidation.ownershipProven else { return IntegrationInstallationApplyResult(status: .blocked, reason: revalidation.ownershipProven ? .policyDenied : .notManifestProven) }
        guard revalidation.product == plan.product, revalidation.productVersion == plan.productVersion, revalidation.interfaceVersion == plan.interfaceVersion, revalidation.policyFingerprint == plan.policyFingerprint else { return IntegrationInstallationApplyResult(status: .stale, reason: .sourceChanged) }
        guard acquire(plan.installationID.rawValue) else { return IntegrationInstallationApplyResult(status: .unavailable, reason: .unavailable) }
        defer { release(plan.installationID.rawValue) }
        let current = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: plan.sourcePath))
        guard current.fingerprint == plan.sourceFingerprint, current.fingerprint == revalidation.sourceFingerprint else {
            return IntegrationInstallationApplyResult(status: .stale, reason: current.fingerprint.symlinkTarget != plan.sourceFingerprint.symlinkTarget ? .symlinkChanged : .sourceChanged)
        }
        do {
            var receipts: [ExactEntryReceipt] = []
            var expected = plan.sourceFingerprint
            for selector in plan.entries {
                let receipt = try ExactEntryEditor.add(selector: selector, at: URL(fileURLWithPath: plan.sourcePath), expected: expected, policy: .allowed, now: now)
                receipts.append(receipt)
                expected = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: plan.sourcePath)).fingerprint
            }
            let inspections = zip(plan.entries, receipts).map { ExactEntryEditor.inspect(at: URL(fileURLWithPath: plan.sourcePath), selector: $0.0, receipt: $0.1) }
            let verified = inspections[0]
            let probeSucceeded = probe?() ?? true
            let reread = inspections.allSatisfy { $0.state == .ownedIntact }
            let evidence = OwnershipManifestVerificationEvidence(verifiedAt: now, reread: reread, probeSucceeded: probeSucceeded, sourceFingerprint: verified.source.fingerprint, capabilityIDs: plan.affectedCapabilities)
            let lifecycle: OwnershipManifestLifecycle = probeSucceeded && reread ? .active : .drifted
            let manifest = OwnershipManifest(id: plan.manifestID, installationID: plan.installationID.rawValue, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, sourcePath: plan.sourcePath, entries: receipts, artifacts: plan.artifacts, productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion, policyFingerprint: plan.policyFingerprint, lifecycle: lifecycle, verification: evidence, createdAt: now, updatedAt: now)
            let installation = IntegrationInstallation(id: plan.installationID, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, manifestID: manifest.id, lifecycle: lifecycle == .active ? .enabled : .degraded, enabledIntent: lifecycle == .active, capabilities: plan.affectedCapabilities)
            return IntegrationInstallationApplyResult(status: lifecycle == .active ? .applied : .degraded, manifest: manifest, installation: installation, reason: lifecycle == .active ? nil : .verificationFailed)
        } catch let error as ExactEntryEditorError {
            let reason: ExactEntryFailureReason = switch error {
            case .invalidSelector: .lossy
            case .sourceChanged: .sourceChanged
            case .symlinkChanged: .symlinkChanged
            case .unsupported: .unsupported
            case .lossy: .lossy
            case .ambiguous: .ambiguous
            case .policyDenied: .policyDenied
            case .unavailable, .ioFailure: .unavailable
            case .interrupted: .interrupted
            case .verificationFailed: .verificationFailed
            case .notManifestProven: .notManifestProven
            }
            if error == .interrupted {
                // An interruption after replacement may have left the exact
                // line in place. Capture a minimal partial receipt so the
                // next repair/removal can be honest about what happened.
                let source = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: plan.sourcePath))
                if let data = source.content, let text = String(data: data, encoding: .utf8), text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).contains(where: { String($0) == plan.entries[0].renderedLine }) {
                    let receipt = ExactEntryReceipt(selector: plan.entries[0], path: plan.sourcePath, sourceFingerprint: source.fingerprint, createdAt: now)
                    let evidence = OwnershipManifestVerificationEvidence(verifiedAt: now, reread: true, probeSucceeded: false, sourceFingerprint: source.fingerprint, capabilityIDs: plan.affectedCapabilities)
                    let manifest = OwnershipManifest(id: plan.manifestID, installationID: plan.installationID.rawValue, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, sourcePath: plan.sourcePath, entries: [receipt], artifacts: plan.artifacts, productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion, policyFingerprint: plan.policyFingerprint, lifecycle: .partial, verification: evidence, createdAt: now, updatedAt: now)
                    let installation = IntegrationInstallation(id: plan.installationID, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, manifestID: manifest.id, lifecycle: .partial, enabledIntent: false, capabilities: plan.affectedCapabilities)
                    return IntegrationInstallationApplyResult(status: .partial, manifest: manifest, installation: installation, reason: reason)
                }
            }
            return IntegrationInstallationApplyResult(status: error == .interrupted ? .partial : .degraded, reason: reason)
        } catch {
            return IntegrationInstallationApplyResult(status: .degraded, reason: .unavailable)
        }
    }

    /// Convenience boundary for callers that have just performed the live
    /// Product/version/policy probe. It still rereads the selected source
    /// before taking the exact-entry write path.
    public func apply(_ approval: IntegrationInstallationApproval, currentSnapshot: NegotiationSnapshot, policy: ExactEntryWritePolicy = .allowed, probe: (() -> Bool)? = nil, now: Date = Date()) -> IntegrationInstallationApplyResult {
        let currentSource = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: approval.plan.sourcePath))
        let revalidation = IntegrationInstallationRevalidation(sourceFingerprint: currentSource.fingerprint, product: currentSnapshot.productNamespace, productVersion: currentSnapshot.productVersion, interfaceVersion: currentSnapshot.interfaceVersion, policyFingerprint: Self.policyFingerprint(policy), ownershipProven: currentSnapshot.grants(WellKnownCapability.configuration, direction: .configure))
        return apply(approval, revalidation: revalidation, probe: probe, now: now)
    }

    public func approveAndApply(_ plan: IntegrationInstallationPlan, personIdentifier: String, currentSnapshot: NegotiationSnapshot, policy: ExactEntryWritePolicy = .allowed, probe: (() -> Bool)? = nil, now: Date = Date()) -> IntegrationInstallationApplyResult {
        guard let approval = try? approve(plan, personIdentifier: personIdentifier, at: now) else {
            return IntegrationInstallationApplyResult(status: .unapproved, reason: .notManifestProven)
        }
        return apply(approval, currentSnapshot: currentSnapshot, policy: policy, probe: probe, now: now)
    }

    public func disable(_ installation: IntegrationInstallation) -> IntegrationInstallation { installation.disabling() }

    public func makeRemovalPlan(id: String, installationID: IntegrationInstanceID, manifest: OwnershipManifest, snapshot: NegotiationSnapshot? = nil, policy: ExactEntryWritePolicy = .allowed, now: Date = Date(), expiresIn: TimeInterval = 300) -> IntegrationInstallationPlan {
        IntegrationInstallationPlan(id: id, installationID: installationID, action: .remove, product: manifest.product, integrationMode: manifest.integrationMode, scope: manifest.scope, sourcePath: manifest.sourcePath, entries: manifest.exactSelectors, artifacts: manifest.artifacts, compatibility: Self.compatibility(snapshot: snapshot, policy: policy), productVersion: manifest.productVersion, interfaceVersion: manifest.interfaceVersion, policyFingerprint: manifest.policyFingerprint, sourceFingerprint: ExactEntryEditor.snapshot(at: URL(fileURLWithPath: manifest.sourcePath)).fingerprint, affectedCapabilities: [], capabilityEvidence: IntegrationInstallationCapabilityEvidence(snapshot: snapshot), rollback: "Restore only the manifest-proven receipt if removal was interrupted.", manualRemedy: "Remove residual exact entries manually after reviewing external changes.", createdAt: now, expiresAt: now.addingTimeInterval(expiresIn), manifestID: manifest.id)
    }

    public func remove(_ approval: IntegrationInstallationApproval, manifest: OwnershipManifest, now: Date = Date()) -> OwnershipManifestRemovalReport {
        let plan = approval.plan
        guard plan.action == .remove, plan.isFresh(at: now), plan.compatibility == .compatible else {
            return OwnershipManifestRemovalReport(outcome: .notRemoved, reason: .sourceChanged)
        }
        guard acquire(plan.installationID.rawValue) else { return OwnershipManifestRemovalReport(outcome: .notRemoved, reason: .unavailable) }
        defer { release(plan.installationID.rawValue) }
        var removed: [ExactEntrySelector] = []
        var residual: [ExactEntrySelector] = []
        var expected = plan.sourceFingerprint
        for receipt in manifest.entries {
            do {
                _ = try ExactEntryEditor.remove(receipt: receipt, at: URL(fileURLWithPath: receipt.path), expected: expected, now: now)
                removed.append(receipt.selector)
                expected = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: receipt.path)).fingerprint
            } catch {
                residual.append(receipt.selector)
            }
        }
        var removedArtifacts: [String] = []
        var notRemovedArtifacts: [String] = []
        for artifact in manifest.artifacts {
            guard artifact.kind != .directory, artifact.kind != .exactEntry, artifact.path != manifest.scope.path, artifact.path != "/" else {
                notRemovedArtifacts.append(artifact.path)
                continue
            }
            let url = URL(fileURLWithPath: artifact.path)
            let current = ExactEntryEditor.snapshot(at: url)
            guard current.fingerprint.content == artifact.fingerprint else { notRemovedArtifacts.append(artifact.path); continue }
            do {
                try FileManager.default.removeItem(at: url)
                removedArtifacts.append(artifact.path)
            } catch { notRemovedArtifacts.append(artifact.path) }
        }
        let outcome: OwnershipManifestRemovalOutcome = !residual.isEmpty || !notRemovedArtifacts.isEmpty ? (removed.isEmpty && removedArtifacts.isEmpty ? .notRemoved : .partialWithResidual) : .removed
        let updatedManifest = manifest.replacing(lifecycle: outcome == .removed ? .removed : .partial, at: now)
        return OwnershipManifestRemovalReport(outcome: outcome, removedEntries: removed, residualEntries: residual, removedArtifacts: removedArtifacts, notRemovedArtifacts: notRemovedArtifacts, reason: outcome == .removed ? nil : .sourceChanged, manifest: updatedManifest)
    }

    private func acquire(_ id: String) -> Bool {
        Self.lockState.lock.lock(); defer { Self.lockState.lock.unlock() }
        guard !Self.lockState.locked.contains(id) else { return false }
        Self.lockState.locked.insert(id)
        return true
    }

    private func release(_ id: String) {
        Self.lockState.lock.lock(); Self.lockState.locked.remove(id); Self.lockState.lock.unlock()
    }

    private static func affectedCapabilities(snapshot: NegotiationSnapshot?) -> [String] {
        guard let snapshot else { return [] }
        return snapshot.capabilities.filter { $0.availability == .available && snapshot.killSwitches.isEnabled($0.direction) }.map(\.id)
    }

    private static func configurationAvailable(_ snapshot: NegotiationSnapshot) -> Bool {
        snapshot.grants(WellKnownCapability.configuration, direction: .configure)
    }

    private static func compatibility(snapshot: NegotiationSnapshot?, policy: ExactEntryWritePolicy) -> IntegrationInstallationCompatibility {
        guard policy.allowsMutation else { return .policyBlocked }
        guard let snapshot else { return .unknown }
        if snapshot.health.loadPolicy == .denied || snapshot.health.configured == .denied { return .policyBlocked }
        if snapshot.health.loadPolicy == .unavailable { return .unknown }
        guard snapshot.killSwitches.isEnabled(.configure), configurationAvailable(snapshot) else { return .killSwitchClosed }
        switch snapshot.compatibility {
        case .compatible: return .compatible
        case .interfaceChanged: return .interfaceChanged
        case .unknown: return .unknown
        case .incompatibleMajor: return .incompatible
        }
    }

    private static func policyFingerprint(_ policy: ExactEntryWritePolicy) -> ExactEntryFingerprint? {
        guard let reason = policy.reason else { return nil }
        return ExactEntryFingerprint(ExactEntryDigest.value(Data(reason.utf8)))
    }
}
