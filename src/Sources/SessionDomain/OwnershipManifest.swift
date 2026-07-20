import Foundation

public enum OwnershipManifestLifecycle: String, Codable, Equatable, Hashable, Sendable {
    case active
    case disabled
    case drifted
    case partial
    case removed
}

public enum OwnershipManifestArtifactKind: String, Codable, Equatable, Hashable, Sendable {
    case exactEntry
    case directory
    case generatedFile
    case temporary
}

/// A receipt for an application-created artifact. The artifact is individually
/// fingerprinted; no directory or Product data root is ever owned wholesale.
public struct OwnershipManifestArtifactReceipt: Codable, Equatable, Hashable, Sendable {
    public let path: String
    public let kind: OwnershipManifestArtifactKind
    public let fingerprint: ExactEntryFingerprint
    public let createdAt: Date

    public init(path: String, kind: OwnershipManifestArtifactKind = .generatedFile, fingerprint: ExactEntryFingerprint, createdAt: Date = Date()) {
        self.path = path
        self.kind = kind
        self.fingerprint = fingerprint
        self.createdAt = createdAt
    }
}

public struct OwnershipManifestVerificationEvidence: Codable, Equatable, Hashable, Sendable {
    public let verifiedAt: Date
    public let reread: Bool
    public let probeSucceeded: Bool
    public let sourceFingerprint: ExactEntrySourceFingerprint
    public let capabilityIDs: [String]

    public init(verifiedAt: Date = Date(), reread: Bool, probeSucceeded: Bool, sourceFingerprint: ExactEntrySourceFingerprint, capabilityIDs: [String] = []) {
        self.verifiedAt = verifiedAt
        self.reread = reread
        self.probeSucceeded = probeSucceeded
        self.sourceFingerprint = sourceFingerprint
        self.capabilityIDs = capabilityIDs
    }
}

/// Minimal protected-local evidence for one Integration Installation. It
/// intentionally stores selectors and fingerprints rather than configuration
/// contents, credentials or arbitrary command lines.
public struct OwnershipManifest: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let installationID: String
    public let product: ProductNamespace
    public let integrationMode: String
    public let scope: IntegrationInstallationScope
    public let sourcePath: String
    public let entries: [ExactEntryReceipt]
    public let artifacts: [OwnershipManifestArtifactReceipt]
    public let productVersion: String
    public let interfaceVersion: String
    public let policyFingerprint: ExactEntryFingerprint?
    public var lifecycle: OwnershipManifestLifecycle
    public var verification: OwnershipManifestVerificationEvidence?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        installationID: String,
        product: ProductNamespace,
        integrationMode: String,
        scope: IntegrationInstallationScope,
        sourcePath: String,
        entries: [ExactEntryReceipt],
        artifacts: [OwnershipManifestArtifactReceipt] = [],
        productVersion: String = "unknown",
        interfaceVersion: String = "unknown",
        policyFingerprint: ExactEntryFingerprint? = nil,
        lifecycle: OwnershipManifestLifecycle = .active,
        verification: OwnershipManifestVerificationEvidence? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.installationID = installationID
        self.product = product
        self.integrationMode = integrationMode
        self.scope = scope
        self.sourcePath = sourcePath
        self.entries = entries
        self.artifacts = artifacts
        self.productVersion = productVersion
        self.interfaceVersion = interfaceVersion
        self.policyFingerprint = policyFingerprint
        self.lifecycle = lifecycle
        self.verification = verification
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var exactSelectors: [ExactEntrySelector] { entries.map(\.selector) }
    public var exactEntries: [ExactEntryReceipt] { entries }
    public var artifactReceipts: [OwnershipManifestArtifactReceipt] { artifacts }
    public var lifecycleState: OwnershipManifestLifecycle { lifecycle }

    public func proving(_ selector: ExactEntrySelector, at path: String) -> ExactEntryReceipt? {
        entries.first { $0.selector.key == selector.key && $0.selector.marker == selector.marker && $0.path == path }
    }

    public func replacing(lifecycle: OwnershipManifestLifecycle, verification: OwnershipManifestVerificationEvidence? = nil, at date: Date = Date()) -> Self {
        var copy = self
        copy.lifecycle = lifecycle
        copy.verification = verification ?? copy.verification
        copy.updatedAt = date
        return copy
    }
}

private struct OwnershipManifestPersistedEntry: Codable, Equatable, Hashable, Sendable {
    let key: String
    let marker: String
    let path: String
    let sourceFingerprint: ExactEntrySourceFingerprint
    let entryFingerprint: ExactEntryFingerprint
    let symlinkTarget: String?
    let permissionBits: UInt16?
    let createdAt: Date

    init(_ receipt: ExactEntryReceipt) {
        key = receipt.selector.key
        marker = receipt.selector.marker
        path = receipt.path
        sourceFingerprint = receipt.sourceFingerprint
        entryFingerprint = receipt.entryFingerprint
        symlinkTarget = receipt.symlinkTarget
        permissionBits = receipt.permissionBits
        createdAt = receipt.createdAt
    }

    func receipt() -> ExactEntryReceipt {
        // Deliberately omit the rendered line. The marker + fingerprint proves
        // the exact entry while keeping command/value text (and credentials)
        // out of protected manifest serialization.
        let selector = ExactEntrySelector(key: key, renderedLine: marker, marker: marker)
        return ExactEntryReceipt(selector: selector, path: path, sourceFingerprint: sourceFingerprint, entryFingerprint: entryFingerprint, symlinkTarget: symlinkTarget, permissionBits: permissionBits, createdAt: createdAt)
    }
}

extension OwnershipManifest {
    private enum CodingKeys: String, CodingKey {
        case id, installationID, product, integrationMode, scope, sourcePath, entries, artifacts, productVersion, interfaceVersion, policyFingerprint, lifecycle, verification, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        installationID = try c.decode(String.self, forKey: .installationID)
        product = try c.decode(ProductNamespace.self, forKey: .product)
        integrationMode = try c.decode(String.self, forKey: .integrationMode)
        scope = try c.decode(IntegrationInstallationScope.self, forKey: .scope)
        sourcePath = try c.decode(String.self, forKey: .sourcePath)
        entries = try c.decode([OwnershipManifestPersistedEntry].self, forKey: .entries).map { $0.receipt() }
        artifacts = try c.decodeIfPresent([OwnershipManifestArtifactReceipt].self, forKey: .artifacts) ?? []
        productVersion = try c.decodeIfPresent(String.self, forKey: .productVersion) ?? "unknown"
        interfaceVersion = try c.decodeIfPresent(String.self, forKey: .interfaceVersion) ?? "unknown"
        policyFingerprint = try c.decodeIfPresent(ExactEntryFingerprint.self, forKey: .policyFingerprint)
        lifecycle = try c.decodeIfPresent(OwnershipManifestLifecycle.self, forKey: .lifecycle) ?? .active
        verification = try c.decodeIfPresent(OwnershipManifestVerificationEvidence.self, forKey: .verification)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(installationID, forKey: .installationID)
        try c.encode(product, forKey: .product)
        try c.encode(integrationMode, forKey: .integrationMode)
        try c.encode(scope, forKey: .scope)
        try c.encode(sourcePath, forKey: .sourcePath)
        try c.encode(entries.map(OwnershipManifestPersistedEntry.init), forKey: .entries)
        try c.encode(artifacts, forKey: .artifacts)
        try c.encode(productVersion, forKey: .productVersion)
        try c.encode(interfaceVersion, forKey: .interfaceVersion)
        try c.encodeIfPresent(policyFingerprint, forKey: .policyFingerprint)
        try c.encode(lifecycle, forKey: .lifecycle)
        try c.encodeIfPresent(verification, forKey: .verification)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum OwnershipManifestRemovalOutcome: String, Codable, Equatable, Hashable, Sendable {
    case removed
    case partialWithResidual
    case notRemoved
}

public struct OwnershipManifestRemovalReport: Codable, Equatable, Hashable, Sendable {
    public let outcome: OwnershipManifestRemovalOutcome
    public let removedEntries: [ExactEntrySelector]
    public let residualEntries: [ExactEntrySelector]
    public let removedArtifacts: [String]
    public let notRemovedArtifacts: [String]
    public let reason: ExactEntryFailureReason?
    public let manifest: OwnershipManifest?

    public var status: OwnershipManifestRemovalOutcome { outcome }

    public init(outcome: OwnershipManifestRemovalOutcome, removedEntries: [ExactEntrySelector] = [], residualEntries: [ExactEntrySelector] = [], removedArtifacts: [String] = [], notRemovedArtifacts: [String] = [], reason: ExactEntryFailureReason? = nil, manifest: OwnershipManifest? = nil) {
        self.outcome = outcome
        self.removedEntries = removedEntries
        self.residualEntries = residualEntries
        self.removedArtifacts = removedArtifacts
        self.notRemovedArtifacts = notRemovedArtifacts
        self.reason = reason
        self.manifest = manifest
    }
}
