import Foundation
import CryptoKit
import ClaudeCodeAdapter
import SessionDomain
import SessionStore

/// The app-owned half of the documented synchronous Hook protocol.  It owns
/// only volatile callback material; the durable request and attempt history
/// remain in `ActionAttemptStore` through `ClaudeGuidedActionRouter`.
public actor ClaudeActionRequestListener: ClaudeActionDispatchPort {
    public struct Configuration: Sendable {
        public let installationID: IntegrationInstanceID
        public let helperID: String
        public let authenticator: ClaudeIPCAuthenticator
        public let snapshot: NegotiationSnapshot
        public let maximumWaiters: Int
        public let maximumFutureDeadline: TimeInterval
        public let clockSkew: TimeInterval

        public init(installationID: IntegrationInstanceID, helperID: String, authenticator: ClaudeIPCAuthenticator, snapshot: NegotiationSnapshot, maximumWaiters: Int = 16, maximumFutureDeadline: TimeInterval = 5, clockSkew: TimeInterval = 120) {
            self.installationID = installationID
            self.helperID = helperID
            self.authenticator = authenticator
            self.snapshot = snapshot
            self.maximumWaiters = max(1, min(maximumWaiters, 64))
            self.maximumFutureDeadline = max(0.1, min(maximumFutureDeadline, 10))
            self.clockSkew = max(0, min(clockSkew, 120))
        }
    }

    private struct Waiter {
        let request: ClaudeHelperActionRequest
        let callback: ClaudeLiveCallback
        let channel: any ClaudeActionReplyChannel
    }

    private let configuration: Configuration
    private var router: ClaudeGuidedActionRouter?
    private var waiters: [ClaudeLiveCallbackIdentity: Waiter] = [:]
    private var seenNonces: [String: Date] = [:]

    public init(configuration: Configuration) { self.configuration = configuration }

    /// Bootstrap is deliberately explicit to avoid giving the router a
    /// store-free adapter reference.  It is called once by app composition.
    public func attach(router: ClaudeGuidedActionRouter) {
        guard self.router == nil else { return }
        self.router = router
    }

    /// Accepts one already-framed connection request.  A production socket
    /// server supplies the channel; deterministic tests use the in-memory
    /// channel below.  Invalid input never creates a durable request.
    @discardableResult
    public func receive(_ request: ClaudeHelperActionRequest, channel: any ClaudeActionReplyChannel, at now: Date = Date()) async -> Bool {
        await prune(at: now)
        guard let router,
              waiters.count < configuration.maximumWaiters,
              request.isAuthenticated(using: configuration.authenticator, expectedInstallationID: configuration.installationID, expectedHelperID: configuration.helperID, receivedAt: now, maxClockSkew: configuration.clockSkew),
              request.deadline >= now,
              request.deadline.timeIntervalSince(now) <= configuration.maximumFutureDeadline,
              !seenNonces.keys.contains(request.nonce),
              let callbackNonce = UUID(uuidString: request.nonce),
              SHA256.hash(data: request.payload).map({ String(format: "%02x", $0) }).joined() == request.callbackFingerprint,
              let hook = try? ClaudeHookEnvelope.decode(request.payload)
        else {
            await channel.close()
            return false
        }

        // Consume the nonce before any await that could make a duplicate
        // caller race the first callback.  A rejected unsupported callback is
        // still never eligible for replay during its bounded lifetime.
        seenNonces[request.nonce] = request.deadline
        guard case .success(let callback) = ClaudeLiveCallbackFactory.make(hook: hook, snapshot: configuration.snapshot, integrationInstanceID: configuration.installationID, deadline: request.deadline, nonce: callbackNonce),
              callback.identity.callbackInputFingerprint == request.callbackFingerprint,
              callback.owner.integrationInstanceID == request.installationID,
              callback.owner.negotiationSnapshotID == configuration.snapshot.id,
              callback.capability.availability == .available,
              callback.capability.freshness == .current
        else {
            await channel.close()
            return false
        }
        guard case .success = await router.open(callback, at: now) else {
            await channel.close()
            return false
        }
        // The exact nonce/fingerprint/native tuple is the sole reply key. It
        // is volatile and disappears before or during the one dispatch.
        waiters[callback.identity] = Waiter(request: request, callback: callback, channel: channel)
        return true
    }

    /// The router's only dispatch port.  It cannot reconstruct callbacks,
    /// retry writes, or report Product application without explicit evidence.
    public func dispatch(_ request: ClaudeActionDispatchRequest, at now: Date) async -> ClaudeActionDispatchOutcome {
        await prune(at: now)
        guard let waiter = waiters.removeValue(forKey: request.callback.identity),
              waiter.callback.identity == request.callback.identity,
              waiter.request.nonce == request.callback.identity.nonce.uuidString,
              waiter.request.callbackFingerprint == request.callback.identity.callbackInputFingerprint,
              waiter.request.deadline >= now,
              waiter.callback.deadline >= now
        else { return .rejectedBeforeDispatch }

        let native = nativeResponse(request.response)
        let reply = ClaudeHelperActionResponse(
            nonce: waiter.request.nonce,
            callbackFingerprint: waiter.request.callbackFingerprint,
            response: native,
            authenticator: configuration.authenticator
        )
        // A successful local socket write only proves a kernel handoff. The
        // documented Hook protocol has no Product acceptance acknowledgement,
        // so it is deliberately terminal-but-indeterminate rather than a
        // fabricated Product acceptance claim.
        _ = await waiter.channel.send(reply)
        await waiter.channel.close()
        return .indeterminate
    }

    /// A connection close, wake/reconnect, restart, source change, or timeout
    /// invalidates all volatile callbacks and leases while retaining durable
    /// requests/drafts/attempts for native Host fallback.
    public func retireAll(reason: ClaudeLiveActionRejection = .helperUnavailable) async {
        let channels = waiters.values.map(\.channel)
        waiters.removeAll(); seenNonces.removeAll()
        for channel in channels { await channel.close() }
        await router?.retireAll(reason: reason)
    }

    public func connectionLost(identity: ClaudeLiveCallbackIdentity) async {
        guard waiters[identity] != nil else { return }
        await retireAll(reason: .helperUnavailable)
    }

    public var liveWaiterCount: Int { waiters.count }

    /// Called by the socket server's bounded timer.  Expiry is a source-state
    /// change, so every live lease is invalidated rather than reconstructed.
    public func expire(at now: Date = Date()) async {
        await prune(at: now)
    }

    /// An expiry is an authority-incarnation boundary.  The router only has a
    /// retire-all operation, therefore all waiter channels are closed in the
    /// same awaited transaction before its leases/callbacks are invalidated.
    private func prune(at now: Date) async {
        let hasExpiredWaiter = waiters.values.contains { $0.request.deadline < now }
        if hasExpiredWaiter {
            let channels = waiters.values.map(\.channel)
            waiters.removeAll()
            for channel in channels { await channel.close() }
            await router?.retireAll(reason: .expired)
        }
        seenNonces = seenNonces.filter { $0.value >= now }
        if seenNonces.count > 1_024 {
            for key in seenNonces.sorted(by: { $0.value < $1.value }).prefix(seenNonces.count - 1_024).map(\.key) { seenNonces.removeValue(forKey: key) }
        }
    }

    private func nativeResponse(_ response: ClaudeTypedHookResponse) -> ClaudeHelperNativeResponse {
        switch response {
        case .permission(let decision, let suggestion): .permission(decision, suggestionJSON: suggestion)
        case .preToolAllow(let input): .preToolAllow(updatedInput: input)
        }
    }
}

/// A bounded, one-shot action reply channel.  It intentionally retains no
/// native data after `response` is observed and is useful for deterministic
/// helper-to-listener fixtures without a socket server.
public actor ClaudeInMemoryActionReplyChannel: ClaudeActionReplyChannel {
    public private(set) var response: ClaudeHelperActionResponse?
    public private(set) var isClosed = false
    public var acceptsReply = true
    public init(acceptsReply: Bool = true) { self.acceptsReply = acceptsReply }
    public func send(_ response: ClaudeHelperActionResponse) async -> Bool {
        guard !isClosed, self.response == nil, acceptsReply else { return false }
        self.response = response
        return true
    }
    public func close() async { isClosed = true }
}

public protocol ClaudeActionReplyChannel: Sendable {
    func send(_ response: ClaudeHelperActionResponse) async -> Bool
    func close() async
}

/// Production composition owns this object.  It keeps the action-side store,
/// listener and router together, while the Claude adapter remains store-free.
public actor ClaudeGuidedActionService {
    public let store: ActionAttemptStore
    public let listener: ClaudeActionRequestListener
    public let router: ClaudeGuidedActionRouter

    public init(configuration: ClaudeActionRequestListener.Configuration, store: ActionAttemptStore = ActionAttemptStore()) async {
        self.store = store
        let listener = ClaudeActionRequestListener(configuration: configuration)
        self.listener = listener
        self.router = ClaudeGuidedActionRouter(store: store, dispatchPort: listener, validationPort: ClaudeStaticLiveActionValidationPort())
        await listener.attach(router: self.router)
    }
}
