import Foundation

/// Discovery compatibility is evidence, not an inferred Product status.  A
/// candidate can be selectable even when a fresh probe is required; activation
/// must then produce a narrowed NegotiationSnapshot.
public enum DiscoveryCompatibility: String, Hashable, Sendable, Codable {
    case compatible
    case interfaceChanged
    case unknown
    case incompatibleMajor
}

public typealias ProbeCompatibility = DiscoveryCompatibility
public typealias AdapterCompatibility = DiscoveryCompatibility

public enum DiscoveryProbeState: String, Hashable, Sendable, Codable {
    case notRun
    case planned
    case verified
    case interfaceChanged
    case unknown
    case incompatibleMajor
    case failed
}

public enum DiscoverySetupState: String, Hashable, Sendable, Codable {
    case unknown
    case notInstalled
    case installed
    case manifestLoaded
    case permissionDenied
    case manualRepairRequired
}

public struct DiscoveryPermission: Hashable, Sendable, Codable {
    public let identifier: String
    public let granted: Bool
    public let required: Bool

    public init(identifier: String, granted: Bool = false, required: Bool = true) {
        self.identifier = identifier
        self.granted = granted
        self.required = required
    }
}

/// A probe plan names documented/selectable surfaces only.  `mutatesExternal`
/// is a stored invariant so a caller cannot accidentally turn discovery into
/// setup or configuration.
public struct NonMutatingProbePlan: Hashable, Sendable, Codable {
    public let surfaces: [String]
    public let mutatesExternal: Bool
    public let readsPrivateTranscripts: Bool
    public let scansArbitraryHome: Bool
    public let startsCompetingResumeProcess: Bool

    public init(
        surfaces: [String] = [],
        mutatesExternal: Bool = false,
        readsPrivateTranscripts: Bool = false,
        scansArbitraryHome: Bool = false,
        startsCompetingResumeProcess: Bool = false
    ) {
        self.surfaces = surfaces
        self.mutatesExternal = mutatesExternal
        self.readsPrivateTranscripts = readsPrivateTranscripts
        self.scansArbitraryHome = scansArbitraryHome
        self.startsCompetingResumeProcess = startsCompetingResumeProcess
    }

    public var isSafe: Bool {
        !mutatesExternal && !readsPrivateTranscripts && !scansArbitraryHome && !startsCompetingResumeProcess
    }

    public static let empty = Self()
}

public struct DiscoveryVersionEvidence: Hashable, Sendable, Codable {
    public let productVersion: String
    public let interfaceVersion: String
    public let adapterVersion: String
    public let observedAt: Date?

    public init(
        productVersion: String = "unknown",
        interfaceVersion: String = "unknown",
        adapterVersion: String = "unknown",
        observedAt: Date? = nil
    ) {
        self.productVersion = productVersion
        self.interfaceVersion = interfaceVersion
        self.adapterVersion = adapterVersion
        self.observedAt = observedAt
    }
}

/// Read-only evidence for one explicitly selectable Integration Installation.
public struct IntegrationDiscoveryCandidate: Hashable, Sendable, Codable {
    public let id: String
    public let product: ProductNamespace
    public let versionEvidence: DiscoveryVersionEvidence
    public let availableModes: [String]
    public let compatibility: DiscoveryCompatibility
    public let probeState: DiscoveryProbeState
    public let setup: DiscoverySetupState
    public let requiredPermissions: [DiscoveryPermission]
    public let probePlan: NonMutatingProbePlan
    public let selectable: Bool

    public var productVersion: String { versionEvidence.productVersion }
    public var interfaceVersion: String { versionEvidence.interfaceVersion }
    public var adapterVersion: String { versionEvidence.adapterVersion }
    public var modes: [String] { availableModes }
    public var setupEvidence: DiscoverySetupState { setup }
    public var permissions: [DiscoveryPermission] { requiredPermissions }
    public var nonMutatingProbe: NonMutatingProbePlan { probePlan }

    public init(
        id: String,
        product: ProductNamespace,
        versionEvidence: DiscoveryVersionEvidence = DiscoveryVersionEvidence(),
        availableModes: [String] = [],
        compatibility: DiscoveryCompatibility = .unknown,
        probeState: DiscoveryProbeState = .notRun,
        setup: DiscoverySetupState = .unknown,
        requiredPermissions: [DiscoveryPermission] = [],
        probePlan: NonMutatingProbePlan = .empty,
        selectable: Bool = true
    ) {
        self.id = id
        self.product = product
        self.versionEvidence = versionEvidence
        self.availableModes = availableModes
        self.compatibility = compatibility
        self.probeState = probeState
        self.setup = setup
        self.requiredPermissions = requiredPermissions
        self.probePlan = probePlan
        self.selectable = selectable && !availableModes.isEmpty && probePlan.isSafe
    }

    public init(
        id: String,
        product: ProductNamespace,
        productVersion: String,
        interfaceVersion: String,
        adapterVersion: String = "unknown",
        availableModes: [String],
        compatibility: DiscoveryCompatibility = .unknown,
        probeState: DiscoveryProbeState = .notRun,
        setup: DiscoverySetupState = .unknown,
        requiredPermissions: [DiscoveryPermission] = [],
        probePlan: NonMutatingProbePlan = .empty,
        selectable: Bool = true,
        observedAt: Date? = nil
    ) {
        self.init(
            id: id,
            product: product,
            versionEvidence: DiscoveryVersionEvidence(productVersion: productVersion, interfaceVersion: interfaceVersion, adapterVersion: adapterVersion, observedAt: observedAt),
            availableModes: availableModes,
            compatibility: compatibility,
            probeState: probeState,
            setup: setup,
            requiredPermissions: requiredPermissions,
            probePlan: probePlan,
            selectable: selectable
        )
    }

    public init(
        id: String,
        product: String,
        productVersion: String,
        interfaceVersion: String,
        adapterVersion: String = "unknown",
        availableModes: [String],
        compatibility: DiscoveryCompatibility = .unknown,
        probeState: DiscoveryProbeState = .notRun,
        setup: DiscoverySetupState = .unknown,
        requiredPermissions: [DiscoveryPermission] = [],
        probePlan: NonMutatingProbePlan = .empty,
        selectable: Bool = true,
        observedAt: Date? = nil
    ) {
        self.init(id: id, product: ProductNamespace(product), productVersion: productVersion, interfaceVersion: interfaceVersion, adapterVersion: adapterVersion, availableModes: availableModes, compatibility: compatibility, probeState: probeState, setup: setup, requiredPermissions: requiredPermissions, probePlan: probePlan, selectable: selectable, observedAt: observedAt)
    }

    public init(
        id: String,
        product: ProductNamespace,
        versionEvidence: DiscoveryVersionEvidence = DiscoveryVersionEvidence(),
        availableModes: [String] = [],
        compatibility: DiscoveryCompatibility = .unknown,
        probeState: DiscoveryProbeState = .notRun,
        setup: DiscoverySetupState = .unknown,
        requiredPermissions: [String],
        probePlan: NonMutatingProbePlan = .empty,
        selectable: Bool = true
    ) {
        self.init(id: id, product: product, versionEvidence: versionEvidence, availableModes: availableModes, compatibility: compatibility, probeState: probeState, setup: setup, requiredPermissions: requiredPermissions.map { DiscoveryPermission(identifier: $0) }, probePlan: probePlan, selectable: selectable)
    }

    public var hasRequiredPermission: Bool {
        requiredPermissions.filter(\.required).allSatisfy(\.granted)
    }
}

public typealias AdapterDiscoveryCandidate = IntegrationDiscoveryCandidate
public typealias DiscoveryCandidate = IntegrationDiscoveryCandidate

public struct DiscoveryRequest: Hashable, Sendable, Codable {
    public let candidates: [IntegrationDiscoveryCandidate]
    public let observedAt: Date?

    public init(candidates: [IntegrationDiscoveryCandidate], observedAt: Date? = nil) {
        self.candidates = candidates
        self.observedAt = observedAt
    }
}

public enum DiscoveryValidationError: String, Hashable, Sendable, Codable {
    case malformedCandidate
    case oversizedCandidateSet
    case mutatingProbePlan
}

public enum DiscoveryResult: Sendable {
    case candidates([IntegrationDiscoveryCandidate])
    case rejected(DiscoveryValidationError)
}

/// Pure discovery boundary.  The function accepts already documented probe
/// results and returns a value; it performs no filesystem scan, configuration
/// write, enabled-intent change, or Product process launch.
public enum ReadOnlyAdapterDiscovery {
    public static let maxCandidates = 128

    public static func discover(_ request: DiscoveryRequest) -> DiscoveryResult {
        guard request.candidates.count <= maxCandidates else {
            return .rejected(.oversizedCandidateSet)
        }
        guard request.candidates.allSatisfy({ candidate in
            !candidate.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !candidate.product.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return .rejected(.malformedCandidate)
        }
        guard request.candidates.allSatisfy({ $0.probePlan.isSafe }) else {
            return .rejected(.mutatingProbePlan)
        }
        return .candidates(request.candidates.filter(\.selectable))
    }
}

public typealias AdapterDiscovery = ReadOnlyAdapterDiscovery
