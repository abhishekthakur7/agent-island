import Foundation

public enum ActionLeaseRevocationReason: String, Codable, Hashable, Sendable, Equatable {
    case sourceChanged
    case capabilityChanged
    case gateClosed
    case reconnect
    case restart
    case wake
    case expired
    case consumed
}

public enum ActionLeaseState: Codable, Hashable, Sendable, Equatable {
    case live
    case consumed
    case revoked(ActionLeaseRevocationReason)

    private enum CodingKeys: String, CodingKey { case state, reason }
    private enum State: String, Codable { case live, consumed, revoked }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .live: try c.encode(State.live, forKey: .state)
        case .consumed: try c.encode(State.consumed, forKey: .state)
        case .revoked(let reason):
            try c.encode(State.revoked, forKey: .state)
            try c.encode(reason, forKey: .reason)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(State.self, forKey: .state) {
        case .live: self = .live
        case .consumed: self = .consumed
        case .revoked: self = .revoked(try c.decode(ActionLeaseRevocationReason.self, forKey: .reason))
        }
    }
}

/// Binding for one exact native route.  It intentionally contains no callback
/// or credential.  A changed Product fingerprint or capability cannot reuse a
/// previous lease, even when the visible title is identical.
public struct ActionLeaseBinding: Codable, Hashable, Sendable, Equatable {
    public let requestID: GuidedAttentionRequestID
    public let owner: GuidedAttentionOwner
    public let capabilityID: String
    public let capabilityRevision: Int
    public let negotiationSnapshotID: NegotiationSnapshotID
    public let semanticFingerprint: String
    public let nativeFingerprint: String

    public init(
        requestID: GuidedAttentionRequestID,
        owner: GuidedAttentionOwner,
        capabilityID: String,
        capabilityRevision: Int,
        negotiationSnapshotID: NegotiationSnapshotID,
        semanticFingerprint: String,
        nativeFingerprint: String
    ) {
        self.requestID = requestID
        self.owner = owner
        self.capabilityID = capabilityID
        self.capabilityRevision = capabilityRevision
        self.negotiationSnapshotID = negotiationSnapshotID
        self.semanticFingerprint = semanticFingerprint
        self.nativeFingerprint = nativeFingerprint
    }
}

public struct ActionLease: Codable, Hashable, Sendable, Equatable, Identifiable {
    public let id: String
    public let binding: ActionLeaseBinding
    public let issuedAt: Date
    public let deadline: Date
    public let generation: UInt64
    public private(set) var state: ActionLeaseState

    public init(id: String, binding: ActionLeaseBinding, issuedAt: Date, deadline: Date, generation: UInt64 = 0, state: ActionLeaseState = .live) {
        self.id = id
        self.binding = binding
        self.issuedAt = issuedAt
        self.deadline = deadline
        self.generation = generation
        self.state = state
    }

    public var isLive: Bool {
        if case .live = state { return true }
        return false
    }

    fileprivate mutating func consume() { state = .consumed }
    fileprivate mutating func revoke(_ reason: ActionLeaseRevocationReason) { state = .revoked(reason) }
}

public struct ActionLeaseValidationContext: Sendable, Equatable {
    public let binding: ActionLeaseBinding
    public let capability: CapabilityRecord
    public let currentNativeFingerprint: String
    public let sourceOutcome: GuidedSourceOutcome
    public let gateOpen: Bool
    public let now: Date

    public init(
        binding: ActionLeaseBinding,
        capability: CapabilityRecord,
        currentNativeFingerprint: String,
        sourceOutcome: GuidedSourceOutcome = .pending,
        gateOpen: Bool = true,
        now: Date
    ) {
        self.binding = binding
        self.capability = capability
        self.currentNativeFingerprint = currentNativeFingerprint
        self.sourceOutcome = sourceOutcome
        self.gateOpen = gateOpen
        self.now = now
    }
}

public enum ActionLeaseFailure: String, Codable, Hashable, Sendable, Equatable, Error {
    case unknownLease
    case expired
    case consumed
    case revoked
    case requestMismatch
    case ownerMismatch
    case capabilityMismatch
    case capabilityUnavailable
    case sourceChanged
    case sourceResolved
    case gateClosed
    case restart
    case reconnect
    case wake
    case invalidDeadline
}

public enum ActionLeaseIssueResult: Sendable, Equatable {
    case issued(ActionLease)
    case rejected(ActionLeaseFailure)
}

public enum ActionLeaseValidationResult: Sendable, Equatable {
    case valid
    case rejected(ActionLeaseFailure)
}

/// Volatile authority for one exact typed action.  No leases are persisted by
/// design; a fresh authority after restart starts with an empty set.
public actor ActionLeaseAuthority {
    private var leases: [String: ActionLease] = [:]
    private var generation: UInt64 = 0

    public init() {}

    public func issue(
        id: String,
        binding: ActionLeaseBinding,
        capability: CapabilityRecord,
        sourceOutcome: GuidedSourceOutcome = .pending,
        gateOpen: Bool = true,
        issuedAt: Date,
        deadline: Date
    ) -> ActionLeaseIssueResult {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, deadline > issuedAt else { return .rejected(.invalidDeadline) }
        guard sourceOutcome == .pending else { return .rejected(sourceOutcome == .resolvedElsewhere ? .sourceResolved : .sourceChanged) }
        guard gateOpen else { return .rejected(.gateClosed) }
        guard capability.id == binding.capabilityID,
              capability.revision == binding.capabilityRevision,
              capability.availability == .available,
              capability.freshness == .current,
              capability.direction == .act,
              capability.provenance?.snapshotID == binding.negotiationSnapshotID,
              capability.provenance?.integrationInstanceID == binding.owner.integrationInstanceID,
              capability.provenance?.productNamespace == binding.owner.productNamespace
        else { return .rejected(.capabilityUnavailable) }
        guard leases[id] == nil else { return .rejected(.consumed) }
        let lease = ActionLease(id: id, binding: binding, issuedAt: issuedAt, deadline: deadline, generation: generation)
        leases[id] = lease
        return .issued(lease)
    }

    public func validate(_ id: String, context: ActionLeaseValidationContext) -> ActionLeaseValidationResult {
        guard var lease = leases[id] else { return .rejected(.unknownLease) }
        guard lease.state == .live else {
            if case .consumed = lease.state { return .rejected(.consumed) }
            if case .revoked(let reason) = lease.state {
                switch reason {
                case .restart: return .rejected(.restart)
                case .reconnect: return .rejected(.reconnect)
                case .wake: return .rejected(.wake)
                case .sourceChanged: return .rejected(.sourceChanged)
                case .capabilityChanged: return .rejected(.capabilityMismatch)
                case .gateClosed: return .rejected(.gateClosed)
                case .expired: return .rejected(.expired)
                case .consumed: return .rejected(.consumed)
                }
            }
            return .rejected(.revoked)
        }
        guard lease.generation == generation else { return .rejected(.restart) }
        guard context.now <= lease.deadline else {
            lease.revoke(.expired)
            leases[id] = lease
            return .rejected(.expired)
        }
        guard context.binding == lease.binding else {
            return .rejected(context.binding.requestID == lease.binding.requestID ? .ownerMismatch : .requestMismatch)
        }
        guard context.sourceOutcome == .pending else {
            return .rejected(context.sourceOutcome == .resolvedElsewhere ? .sourceResolved : .sourceChanged)
        }
        guard context.gateOpen else { return .rejected(.gateClosed) }
        guard context.currentNativeFingerprint == lease.binding.nativeFingerprint else { return .rejected(.sourceChanged) }
        guard context.capability.id == lease.binding.capabilityID,
              context.capability.revision == lease.binding.capabilityRevision,
              context.capability.availability == .available,
              context.capability.freshness == .current,
              context.capability.direction == .act,
              context.capability.provenance?.snapshotID == lease.binding.negotiationSnapshotID,
              context.capability.provenance?.integrationInstanceID == lease.binding.owner.integrationInstanceID,
              context.capability.provenance?.productNamespace == lease.binding.owner.productNamespace
        else { return .rejected(.capabilityMismatch) }
        return .valid
    }

    public func consume(_ id: String, context: ActionLeaseValidationContext) -> ActionLeaseValidationResult {
        guard case .valid = validate(id, context: context), var lease = leases[id] else {
            return validate(id, context: context)
        }
        lease.consume()
        leases[id] = lease
        return .valid
    }

    public func revokeAll(_ reason: ActionLeaseRevocationReason) {
        for id in leases.keys {
            leases[id]?.revoke(reason)
        }
        if reason == .restart { generation &+= 1 }
    }

    public func invalidateForReconnect() { revokeAll(.reconnect) }
    public func invalidateForWake() { revokeAll(.wake) }
    public func invalidateForRestart() { revokeAll(.restart) }
    public func invalidateForSourceChange() { revokeAll(.sourceChanged) }
    public func invalidateForCapabilityChange() { revokeAll(.capabilityChanged) }
    public func invalidateForGateChange() { revokeAll(.gateClosed) }

    public func restart() { invalidateForRestart() }
    public func reconnect() { invalidateForReconnect() }
    public func wake() { invalidateForWake() }

    public func liveLeaseCount() -> Int { leases.values.filter(\.isLive).count }
}
