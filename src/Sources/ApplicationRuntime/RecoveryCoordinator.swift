import Foundation
import SessionDomain

public struct RecoveryCrossingOutcome: Sendable, Equatable {
    public let occurredAt: Date
    public let state: RecoveryPresentationState
    public let storageReason: StorageFailureReason?

    public init(occurredAt: Date, state: RecoveryPresentationState, storageReason: StorageFailureReason?) {
        self.occurredAt = occurredAt
        self.state = state
        self.storageReason = storageReason
    }
}

/// The one typed lifecycle seam for volatile Action Lease authority. Host and
/// AppKit composition perform their own capability-local invalidation beside
/// this call; no boundary dispatches a Product action or initiates a Host.
public actor RecoveryCoordinator {
    private let runtime: ApplicationRuntime
    private let clock: @Sendable () -> Date
    private(set) public var lastBoundary: RecoveryBoundary?

    public init(runtime: ApplicationRuntime, clock: @escaping @Sendable () -> Date = Date.init) {
        self.runtime = runtime
        self.clock = clock
    }

    @discardableResult
    public func cross(_ boundary: RecoveryBoundary) async -> RecoveryCrossingOutcome {
        let occurredAt = clock()
        if boundary.invalidatesActionAuthority {
            await runtime.expireVolatileActionAuthority(for: boundary)
        }
        lastBoundary = boundary
        let storageReason: StorageFailureReason?
        switch boundary {
        case .coldResume, .systemWake:
            storageReason = await runtime.verifyProtectedStateForRecovery()
        case .adapterDisconnected, .hostDisconnected, .displayRecovered, .explicitQuit:
            storageReason = nil
        }
        return RecoveryCrossingOutcome(
            occurredAt: occurredAt,
            state: storageReason == nil ? .readyForFreshReconciliation : .protectedStoreUnavailable,
            storageReason: storageReason
        )
    }
}
