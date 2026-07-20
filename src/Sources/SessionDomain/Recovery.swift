import Foundation

/// A process/liveness boundary is deliberately narrower than Product state.
/// Crossing one expires local authority and Host evidence; it never asserts a
/// Product completion, resolves an Attention Request, or recreates a route.
public enum RecoveryBoundary: String, CaseIterable, Codable, Hashable, Sendable {
    case coldResume
    case systemWake
    case adapterDisconnected
    case hostDisconnected
    case displayRecovered
    case explicitQuit

    public var invalidatesActionAuthority: Bool {
        switch self {
        case .coldResume, .systemWake, .adapterDisconnected, .hostDisconnected, .explicitQuit: true
        case .displayRecovered: false
        }
    }

    public var requiresFreshHostProbe: Bool {
        switch self {
        case .coldResume, .systemWake, .hostDisconnected, .explicitQuit: true
        case .adapterDisconnected, .displayRecovered: false
        }
    }
}

/// Only documented, read-only reconciliation operations are permitted after
/// a boundary. The type intentionally has no private-state, transcript,
/// scrollback, title, path, or automatic-launch case.
public enum ReconciliationOperation: String, CaseIterable, Codable, Hashable, Sendable {
    case read
    case list
    case replay
    case status
    case probe
}

public enum RecoveryPresentationState: String, Codable, Hashable, Sendable {
    case readyForFreshReconciliation
    case protectedStoreUnavailable
}
