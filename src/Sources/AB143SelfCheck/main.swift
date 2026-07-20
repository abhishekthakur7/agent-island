import Foundation
import OrcaHostAdapter
import SessionDomain

@main
struct AB143SelfCheck {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("fixture-session"))
        let installation = IntegrationInstanceID("orca-fixture")
        let client = FixtureClient()
        let capture = OrcaHostContextCapture(client: client)
        guard case .success(let association) = capture.captureTerminal(id: "fixture-context", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "orca-cli-runtime", terminalHandle: "term-fixture", at: now) else {
            fail("capture")
        }
        let negotiation = NegotiationSnapshot(id: NegotiationSnapshotID("orca-fixture-snapshot"), contractVersion: .init(major: 1, minor: 0), adapterKind: "orca-host", adapterBuildVersion: "1", productNamespace: identity.productNamespace, integrationInstanceID: installation, integrationMode: "orca-cli-runtime", capabilities: [.init(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: .available)], negotiatedAt: now)
        let outcome = JumpBackCoordinator(evidence: .init([association]), port: OrcaHostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: now))
        guard outcome.qualifier == .exactTab, client.switchCount == 1, client.requireChild == false, !outcome.productActionGranted, !outcome.productLifecycleChanged else {
            fail("exact-tab-only")
        }
        print("AB143SelfCheck PASS version-matched-handle exactTab no-terminal-controls no-product-actions")
    }

    private static func fail(_ stage: String) -> Never {
        FileHandle.standardError.write(Data("AB143SelfCheck failed: \(stage)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

private final class FixtureClient: @unchecked Sendable, OrcaDocumentedRuntimeClient {
    private let runtime = OrcaRuntimeStatus(runtimeID: "runtime-fixture", runtimeVersion: "2026.07", appAvailable: true)
    var switchCount = 0
    var requireChild = false

    func inspectTerminal(handle: String) -> Result<OrcaTerminalEvidence, OrcaRuntimeClientFailure> {
        .success(.init(runtime: runtime, handle: handle, tabID: "tab-fixture", connected: true))
    }
    func inspectWorkspace(workspaceID: String, fileID: String?) -> Result<OrcaWorkspaceEvidence, OrcaRuntimeClientFailure> { .failure(.workspaceUnavailable) }
    func switchTerminal(handle: String, expectedRuntimeID: String, expectedRuntimeVersion: String, expectedTabID: String, requireExactChildSurface: Bool) -> Result<Void, OrcaRuntimeClientFailure> {
        guard expectedRuntimeID == runtime.runtimeID, expectedRuntimeVersion == runtime.runtimeVersion, expectedTabID == "tab-fixture", !requireExactChildSurface else { return .failure(.unsupportedNavigation) }
        switchCount += 1; requireChild = requireExactChildSurface; return .success(())
    }
    func openWorkspaceFile(workspaceID: String, fileID: String, expectedRuntimeID: String) -> Result<Void, OrcaRuntimeClientFailure> { .failure(.workspaceUnavailable) }
    func activateApplication() -> Result<Void, OrcaRuntimeClientFailure> { .success(()) }
}
