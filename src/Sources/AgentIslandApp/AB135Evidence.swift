import Foundation
import CryptoKit
import ClaudeActionRouting
import ClaudeCodeAdapter
import SessionDomain
import SessionStore

/// Deterministic, no-network proof of the production listener composition:
/// helper request -> authenticated listener -> durable request -> one guided
/// submit -> authenticated typed reply -> helper's native stdout JSON.
enum AB135Evidence {
    static func run() async -> [(String, Bool)] {
        let now = Date()
        let installation = IntegrationInstanceID("ab135-self-check")
        let secret = ClaudeIPCAuthenticator(secret: "ab135-self-check-secret")
        let provenance = CapabilityProvenance(snapshotID: NegotiationSnapshotID("ab135-self-check-snapshot"), integrationInstanceID: installation, productNamespace: ClaudeCodeIntegration.productNamespace, integrationMode: ClaudeCodeIntegration.integrationMode)
        let capabilities = ClaudeCodeIntegration.allActionCapabilities.map { CapabilityRecord(id: $0, direction: .act, availability: .available, scope: .request, provenance: provenance, semanticVariant: $0) }
        let snapshot = NegotiationSnapshot(id: NegotiationSnapshotID("ab135-self-check-snapshot"), contractVersion: ContractVersion(major: 1, minor: 0), adapterKind: ClaudeCodeIntegration.adapterKind, adapterBuildVersion: "self-check", productNamespace: ClaudeCodeIntegration.productNamespace, integrationInstanceID: installation, integrationMode: ClaudeCodeIntegration.integrationMode, capabilities: capabilities, negotiatedAt: now)
        let listener = ClaudeActionRequestListener(configuration: .init(installationID: installation, helperID: "helper", authenticator: secret, snapshot: snapshot, maximumFutureDeadline: 2))
        let store = ActionAttemptStore(); let router = ClaudeGuidedActionRouter(store: store, dispatchPort: listener)
        await listener.attach(router: router)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab135-self-check-" + UUID().uuidString)
        let endpointURL = root.appendingPathComponent("endpoint")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: root.path)
            try Data().write(to: endpointURL)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: endpointURL.path)
            let helper = ClaudeHookHelperRuntime(installationID: installation, helperID: "helper", authenticator: secret, endpoint: ClaudeLocalEndpoint(path: endpointURL, appOwnedRoot: root), timeout: 1)
            let transport = AwaitingListenerTransport(listener: listener)
            let payload = Data("{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"self-check-session\",\"event_id\":\"self-check-event\",\"request_id\":\"self-check-request\",\"permission_mode\":\"default\"}".utf8)
            let outputTask = Task { try await helper.respondToAction(stdin: payload, deadline: now.addingTimeInterval(1), now: now, transport: transport) }
            var request: ClaudeHelperActionRequest?
            for _ in 0..<100 where request == nil { request = await transport.request; try? await Task.sleep(for: .milliseconds(2)) }
            guard let request, let nonce = UUID(uuidString: request.nonce) else { return [("ab135.helperListenerRoundTrip.request", false)] }
            let identity = ClaudeLiveCallbackIdentity(nativeSessionID: NativeSessionID("self-check-session"), promptID: nil, hook: .permissionRequest, toolUseID: nil, callbackInputFingerprint: request.callbackFingerprint, nonce: nonce)
            guard case .dispatched = await router.submit(callbackIdentity: identity, submission: .init(action: .allow, deliberateConfirmation: true), attemptID: "ab135-self-check-attempt", at: now),
                  let output = try? await outputTask.value,
                  let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
                  ((json["hookSpecificOutput"] as? [String: Any])?["permissionDecision"] as? String) == "allow"
            else { return [("ab135.helperListenerRoundTrip.reply", false)] }
            return [("ab135.helperListenerRoundTrip", (await store.requests()).count == 1)]
        } catch { return [("ab135.helperListenerRoundTrip", false)] }
    }
}

private actor AwaitingListenerTransport: ClaudeHookActionIPCTransport {
    let listener: ClaudeActionRequestListener
    private let channel = ClaudeInMemoryActionReplyChannel()
    private(set) var request: ClaudeHelperActionRequest?
    init(listener: ClaudeActionRequestListener) { self.listener = listener }
    func request(_ request: ClaudeHelperActionRequest, timeout: TimeInterval) async throws -> ClaudeHelperActionResponse {
        self.request = request
        guard await listener.receive(request, channel: channel) else { throw ClaudeHookHelperError.transportFailure }
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let response = await channel.response { return response }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw ClaudeHookHelperError.transportTimeout
    }
}
