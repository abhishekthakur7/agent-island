import Foundation
import Combine
import ApplicationRuntime
import CursorACPAdapter
import SessionDomain

/// Retained production composition for explicitly started Cursor ACP work.
/// It intentionally exposes no discovery, adoption, usage, or generic reply
/// API. The installation/settings flow supplies the executable only after a
/// person deliberately starts a new controlled Agent Session.
@MainActor
final class CursorACPApplicationComposition {
    private let runtime: ApplicationRuntime
    private let installationID: IntegrationInstanceID
    private var adapter: CursorACPAdapter?
    let settingsModel = CursorACPSettingsModel()

    init(runtime: ApplicationRuntime, installationID: IntegrationInstanceID = IntegrationInstanceID("cursor-acp-local")) {
        self.runtime = runtime; self.installationID = installationID
    }

    func start(cursorExecutable: URL, arguments: [String]) async -> Result<AgentSessionIdentity, CursorACPFailure> {
        if let adapter { await adapter.shutdown() }
        let adapter = CursorACPAdapter(port: runtime, transport: CursorACPProcessTransport(executableURL: cursorExecutable, arguments: arguments), integrationInstanceID: installationID)
        self.adapter = adapter
        guard case .compatible = await adapter.negotiate(productVersion: "unknown", interfaceVersion: CursorACPContract.protocolVersion, authenticationAvailable: true) else { return .failure(.protocolDrift) }
        return await adapter.startControlledSession()
    }

    func stop() async { guard let adapter else { return }; self.adapter = nil; await adapter.shutdown() }

    /// The Guided presentation supplies only a selected source request and a
    /// typed response.  There is deliberately no free-form ACP command path.
    func submit(requestID: GuidedAttentionRequestID, action: GuidedAction, attemptID: String, confirmed: Bool) async -> CursorACPActionResult {
        guard let adapter else { return .unavailable(.unavailable, fallback: .nativeHost) }
        return await adapter.submit(requestID: requestID, action: action, attemptID: attemptID, confirmed: confirmed)
    }

    func attentionRequests() async -> [GuidedAttentionRequest] { await runtime.cursorACPAttentionRequests() }
    func updateDraft(_ id: GuidedAttentionRequestID, draft: GuidedAttentionDraft) async -> Bool {
        await runtime.updateCursorACPAttentionDraft(id, draft: draft)
    }
}

@MainActor
final class CursorACPSettingsModel: ObservableObject {
    @Published var executablePath = "/usr/local/bin/cursor"
    @Published var status = "Choose the Cursor executable, then deliberately start a new controlled Agent Session."
    @Published var requests: [GuidedAttentionRequest] = []
    @Published var drafts: [GuidedAttentionRequestID: GuidedAttentionDraft] = [:]
    @Published var rejectReasons: [GuidedAttentionRequestID: String] = [:]
}
