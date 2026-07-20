import Foundation
import XCTest
@testable import OrcaHostAdapter
@testable import SessionDomain

final class OrcaHostAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("agent-session"))
    private let installation = IntegrationInstanceID("orca-installation")

    private func negotiation(available: CapabilityAvailability = .available) -> NegotiationSnapshot {
        .init(id: NegotiationSnapshotID("orca-snapshot"), contractVersion: .init(major: 1, minor: 0), adapterKind: "orca-host", adapterBuildVersion: "1", productNamespace: ProductNamespace("claude-code"), integrationInstanceID: installation, integrationMode: "orca-cli-runtime", capabilities: [.init(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: available)], negotiatedAt: now)
    }

    private func terminal(runtimeID: String = "runtime-a", version: String = "runtime-a", connected: Bool = true, candidates: Int = 1, child: Bool = false) -> OrcaTerminalEvidence {
        .init(runtime: .init(runtimeID: runtimeID, runtimeVersion: version, appAvailable: true), handle: "term-opaque", tabID: "tab-opaque", connected: connected, candidateCount: candidates, exactChildSurfaceSelected: child)
    }

    func testDocumentedTerminalSwitchAchievesExactTabWithoutChildSurfaceClaim() throws {
        let client = FixtureClient(terminal: terminal())
        let association = try capture(client).captureTerminal(id: "terminal", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "orca-cli-runtime", terminalHandle: "term-opaque", at: now).get()
        let outcome = JumpBackCoordinator(evidence: .init([association]), port: OrcaHostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))

        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.exactTab)
        XCTAssertEqual(client.switches.count, 1)
        XCTAssertEqual(client.switches.first?.0, "term-opaque")
        XCTAssertEqual(client.switches.first?.1, "tab-opaque")
        XCTAssertEqual(client.switches.first?.2, false)
        XCTAssertEqual(client.workspaceOpens.count, 0)
        XCTAssertEqual(client.applicationActivations, 0)
        XCTAssertFalse(outcome.productActionGranted)
    }

    func testExactSurfaceNeedsExplicitCurrentRuntimeChildProof() throws {
        let client = FixtureClient(terminal: terminal(child: true))
        let association = try capture(client).captureTerminal(id: "terminal", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "orca-cli-runtime", terminalHandle: "term-opaque", at: now).get()
        let outcome = JumpBackCoordinator(evidence: .init([association]), port: OrcaHostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))

        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.exactSurface)
        XCTAssertEqual(client.switches.last?.2, true)
    }

    func testRestartCannotReviveSameLookingHandleOrTab() throws {
        let client = FixtureClient(terminal: terminal(runtimeID: "runtime-a", version: "runtime-a"))
        let association = try capture(client).captureTerminal(id: "terminal", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "orca-cli-runtime", terminalHandle: "term-opaque", at: now).get()
        client.terminal = terminal(runtimeID: "runtime-b", version: "runtime-b")

        let outcome = JumpBackCoordinator(evidence: .init([association]), port: OrcaHostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.appOnly)
        XCTAssertTrue(client.switches.isEmpty)
        XCTAssertEqual(client.applicationActivations, 1)
    }

    func testDisconnectedOrDuplicateHandleIsNeverSelected() throws {
        let client = FixtureClient(terminal: terminal())
        let association = try capture(client).captureTerminal(id: "terminal", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "orca-cli-runtime", terminalHandle: "term-opaque", at: now).get()
        client.terminal = terminal(connected: false)
        var outcome = JumpBackCoordinator(evidence: .init([association]), port: OrcaHostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.appOnly)
        XCTAssertTrue(client.switches.isEmpty)

        client.terminal = terminal(candidates: 2)
        outcome = JumpBackCoordinator(evidence: .init([association]), port: OrcaHostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.appOnly)
        XCTAssertTrue(client.switches.isEmpty)
    }

    func testIndependentlyReprovenWorktreeFileUsesWorkspaceFallback() throws {
        let client = FixtureClient(terminal: terminal(), workspace: .init(runtime: .init(runtimeID: "runtime-a", runtimeVersion: "runtime-a", appAvailable: true), workspaceID: "worktree-opaque", fileID: "Sources/App.swift"))
        let association = try capture(client).captureWorkspaceFile(id: "workspace", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "orca-cli-runtime", workspaceID: "worktree-opaque", fileID: "Sources/App.swift", at: now).get()
        // A new runtime is acceptable only because the worktree/file is
        // separately reproven through `worktree show` before `file open`.
        client.workspace = .init(runtime: .init(runtimeID: "runtime-b", runtimeVersion: "runtime-b", appAvailable: true), workspaceID: "worktree-opaque", fileID: "Sources/App.swift")

        let outcome = JumpBackCoordinator(evidence: .init([association]), port: OrcaHostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.workspaceOrFile)
        XCTAssertEqual(client.workspaceOpens.count, 1)
        XCTAssertEqual(client.workspaceOpens.first?.0, "worktree-opaque")
        XCTAssertEqual(client.workspaceOpens.first?.1, "Sources/App.swift")
        XCTAssertTrue(client.switches.isEmpty)
    }

    func testIncompatibleNegotiationAndRuntimeLossAreUnavailable() throws {
        let client = FixtureClient(terminal: terminal())
        let association = try capture(client).captureTerminal(id: "terminal", sessionIdentity: identity, integrationInstanceID: installation, integrationMode: "orca-cli-runtime", terminalHandle: "term-opaque", at: now).get()
        var outcome = JumpBackCoordinator(evidence: .init([association]), port: OrcaHostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(available: .unavailable), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.unavailable)
        XCTAssertTrue(client.switches.isEmpty)
        XCTAssertEqual(client.applicationActivations, 0)

        client.terminalFailure = .runtimeUnavailable
        outcome = JumpBackCoordinator(evidence: .init([association]), port: OrcaHostNavigationPort(client: client)).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.unavailable)
        XCTAssertEqual(client.applicationActivations, 0)
    }

    private func capture(_ client: FixtureClient) -> OrcaHostContextCapture { .init(client: client) }
}

private final class FixtureClient: @unchecked Sendable, OrcaDocumentedRuntimeClient {
    var terminal: OrcaTerminalEvidence
    var workspace: OrcaWorkspaceEvidence?
    var terminalFailure: OrcaRuntimeClientFailure?
    var switches: [(String, String, Bool)] = []
    var workspaceOpens: [(String, String)] = []
    var applicationActivations = 0

    init(terminal: OrcaTerminalEvidence, workspace: OrcaWorkspaceEvidence? = nil) { self.terminal = terminal; self.workspace = workspace }
    func inspectTerminal(handle: String) -> Result<OrcaTerminalEvidence, OrcaRuntimeClientFailure> { terminalFailure.map(Result.failure) ?? .success(terminal) }
    func inspectWorkspace(workspaceID: String, fileID: String?) -> Result<OrcaWorkspaceEvidence, OrcaRuntimeClientFailure> { workspace.map(Result.success) ?? .failure(.workspaceUnavailable) }
    func switchTerminal(handle: String, expectedRuntimeID: String, expectedRuntimeVersion: String, expectedTabID: String, requireExactChildSurface: Bool) -> Result<Void, OrcaRuntimeClientFailure> {
        guard terminal.runtime.runtimeID == expectedRuntimeID, terminal.runtime.runtimeVersion == expectedRuntimeVersion, terminal.handle == handle, terminal.tabID == expectedTabID, terminal.connected else { return .failure(.handleUnavailable) }
        guard !requireExactChildSurface || terminal.exactChildSurfaceSelected else { return .failure(.unsupportedNavigation) }
        switches.append((handle, expectedTabID, requireExactChildSurface)); return .success(())
    }
    func openWorkspaceFile(workspaceID: String, fileID: String, expectedRuntimeID: String) -> Result<Void, OrcaRuntimeClientFailure> {
        guard let workspace, workspace.runtime.runtimeID == expectedRuntimeID, workspace.workspaceID == workspaceID, workspace.fileID == fileID else { return .failure(.workspaceUnavailable) }
        workspaceOpens.append((workspaceID, fileID)); return .success(())
    }
    func activateApplication() -> Result<Void, OrcaRuntimeClientFailure> { applicationActivations += 1; return .success(()) }
}
