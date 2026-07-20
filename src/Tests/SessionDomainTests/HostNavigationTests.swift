import Foundation
import XCTest
@testable import SessionDomain

final class HostNavigationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_752_000_000)
    private let identity = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("session-1"))

    private func snapshot(
        product: ProductNamespace = ProductNamespace("claude-code"),
        instance: IntegrationInstanceID = IntegrationInstanceID("instance-1"),
        mode: String = "hooks",
        navigation: Bool = true
    ) -> NegotiationSnapshot {
        NegotiationSnapshot(
            id: NegotiationSnapshotID("snapshot-1"),
            contractVersion: ContractVersion(major: 1, minor: 0),
            adapterKind: "fixture",
            adapterBuildVersion: "1",
            productNamespace: product,
            integrationInstanceID: instance,
            integrationMode: mode,
            capabilities: [
                CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available),
                CapabilityRecord(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: navigation ? .available : .unavailable)
            ],
            negotiatedAt: now
        )
    }

    private func association(
        id: String = "context-1",
        session: AgentSessionIdentity? = nil,
        host: HostKind = .iterm2,
        locator: HostLocator = .iterm2LiveSession(sessionID: "iterm-session"),
        version: String = "3",
        mode: String = "hooks",
        incarnation: HostIncarnation = HostIncarnation("incarnation-1")
    ) -> HostContextAssociation {
        HostContextAssociation(
            id: HostContextID(id),
            sessionIdentity: session ?? identity,
            host: host,
            hostVersion: version,
            integrationInstanceID: IntegrationInstanceID("instance-1"),
            integrationMode: mode,
            incarnation: incarnation,
            locator: locator,
            provenance: HostLocatorProvenance(host: host, hostVersion: version, endpointID: "endpoint-1", evidence: .documentedRuntime, observedAt: now),
            firstObservedAt: now
        )
    }

    func testLiveITermSessionReachesExactSurface() {
        let context = association()
        let port = MatrixHostNavigationPort(observation: HostRuntimeObservation(
            host: .iterm2,
            hostVersion: "3",
            integrationMode: "hooks",
            endpointID: "endpoint-1",
            incarnation: HostIncarnation("incarnation-1"),
            liveSessionConnected: true,
            liveSessionID: "iterm-session"
        ))
        let coordinator = JumpBackCoordinator(evidence: HostContextEvidenceStore([context]), port: port)

        let outcome = coordinator.jumpBack(JumpBackRequest(sessionIdentity: identity, negotiation: snapshot(), requestedAt: now))

        XCTAssertEqual(outcome.qualifier, .exactSurface)
        XCTAssertEqual(outcome.host, .iterm2)
        XCTAssertTrue(outcome.navigationPerformed)
        XCTAssertFalse(outcome.productActionGranted)
        XCTAssertFalse(outcome.actionLeaseRestored)
        XCTAssertFalse(outcome.productLifecycleChanged)
    }

    func testCursorExtensionReloadDoesNotRebindDuplicateTerminal() {
        let context = association(
            host: .cursor,
            locator: .cursorExtensionTerminal(terminalID: "terminal-1", extensionInstanceID: "extension-a")
        )
        let port = MatrixHostNavigationPort(observationProvider: { _, _ in
            HostRuntimeObservation(
                host: .cursor,
                hostVersion: "3",
                integrationMode: "hooks",
                endpointID: "endpoint-1",
                incarnation: HostIncarnation("incarnation-1"),
                extensionInstanceID: "extension-b",
                connectedExtensionTerminalID: "terminal-2",
                connectedExtensionTerminal: true,
                provenLevels: [.appOnly]
            )
        })
        let outcome = JumpBackCoordinator(evidence: HostContextEvidenceStore([context]), port: port)
            .jumpBack(JumpBackRequest(sessionIdentity: identity, negotiation: snapshot(), requestedAt: now))

        XCTAssertEqual(outcome.qualifier, .appOnly)
        XCTAssertFalse(outcome.reasonText.contains("terminal-1"))
    }

    func testNativeCursorThreadCanUseOnlyProvenWorkspaceOrAppFallback() {
        let context = association(host: .cursor, locator: .cursorNativeThread)
        let observation = HostRuntimeObservation(
            host: .cursor,
            hostVersion: "3",
            integrationMode: "hooks",
            endpointID: "endpoint-1",
            incarnation: HostIncarnation("incarnation-1"),
            workspaceOrFileProven: true
        )
        let outcome = JumpBackCoordinator(
            evidence: HostContextEvidenceStore([context]),
            port: MatrixHostNavigationPort(observation: observation)
        ).jumpBack(JumpBackRequest(sessionIdentity: identity, negotiation: snapshot(), requestedAt: now))

        XCTAssertEqual(outcome.qualifier, .workspaceOrFile)
    }

    func testWarpNeedsAccessibilityOptInAndExactlyOneCandidateForWindowBestEffort() {
        let context = association(host: .warp, locator: .warpAXWindow(candidateToken: "candidate"))
        let denied = HostRuntimeObservation(
            host: .warp,
            hostVersion: "3",
            integrationMode: "hooks",
            endpointID: "endpoint-1",
            incarnation: HostIncarnation("incarnation-1"),
            permission: .denied,
            provenLevels: [.windowBestEffort]
        )
        let deniedOutcome = JumpBackCoordinator(evidence: HostContextEvidenceStore([context]), port: MatrixHostNavigationPort(observation: denied))
            .jumpBack(JumpBackRequest(sessionIdentity: identity, negotiation: snapshot(), requestedAt: now))
        XCTAssertEqual(deniedOutcome.qualifier, .appOnly)

        let one = HostRuntimeObservation(
            host: .warp,
            hostVersion: "3",
            integrationMode: "hooks",
            endpointID: "endpoint-1",
            incarnation: HostIncarnation("incarnation-1"),
            permission: .granted,
            provenLevels: [.windowBestEffort],
            currentAXCandidateToken: "candidate",
            accessibilityOptIn: true
        )
        let oneOutcome = JumpBackCoordinator(evidence: HostContextEvidenceStore([context]), port: MatrixHostNavigationPort(observation: one))
            .jumpBack(JumpBackRequest(sessionIdentity: identity, negotiation: snapshot(), requestedAt: now))
        XCTAssertEqual(oneOutcome.qualifier, .windowBestEffort)
    }

    func testOrcaRuntimeVersionMismatchFallsBackWithoutExactTab() {
        let context = association(host: .orca, locator: .orcaRuntimeTab(runtimeHandle: "runtime-1", tabID: "tab-1", runtimeVersion: "9"))
        let observation = HostRuntimeObservation(
            host: .orca,
            hostVersion: "3",
            integrationMode: "hooks",
            endpointID: "endpoint-1",
            incarnation: HostIncarnation("incarnation-1"),
            runtimeHandle: "runtime-2",
            runtimeVersion: "10",
            workspaceOrFileProven: true
        )
        let outcome = JumpBackCoordinator(evidence: HostContextEvidenceStore([context]), port: MatrixHostNavigationPort(observation: observation))
            .jumpBack(JumpBackRequest(sessionIdentity: identity, negotiation: snapshot(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, .workspaceOrFile)
        XCTAssertNotEqual(outcome.qualifier, .exactTab)
    }

    func testWrongAgentSessionCannotUseSimilarHostEvidence() {
        let other = AgentSessionIdentity(productNamespace: ProductNamespace("claude-code"), nativeSessionID: NativeSessionID("session-2"))
        let context = association(session: other)
        let outcome = JumpBackCoordinator(
            evidence: HostContextEvidenceStore([context]),
            port: MatrixHostNavigationPort(observation: HostRuntimeObservation(
                host: .iterm2,
                hostVersion: "3",
                integrationMode: "hooks",
                endpointID: "endpoint-1",
                incarnation: HostIncarnation("incarnation-1"),
                liveSessionConnected: true,
                liveSessionID: "iterm-session"
            ))
        ).jumpBack(JumpBackRequest(sessionIdentity: identity, negotiation: snapshot(), requestedAt: now))

        XCTAssertEqual(outcome.qualifier, .unavailable)
        XCTAssertEqual(outcome.reason, .noAssociation)
    }

    func testOnlyExplicitPersonActionCanNavigate() {
        let context = association()
        let outcome = JumpBackCoordinator(
            evidence: HostContextEvidenceStore([context]),
            port: MatrixHostNavigationPort(observation: HostRuntimeObservation(
                host: .iterm2,
                hostVersion: "3",
                integrationMode: "hooks",
                endpointID: "endpoint-1",
                incarnation: HostIncarnation("incarnation-1"),
                liveSessionConnected: true
            ))
        ).jumpBack(JumpBackRequest(sessionIdentity: identity, trigger: .automaticReveal, negotiation: snapshot(), requestedAt: now))

        XCTAssertEqual(outcome.qualifier, .unavailable)
        XCTAssertEqual(outcome.reason, .notExplicitPersonAction)
    }

    func testRestartedIncarnationCannotUseExactLocatorButCanUseAppFallback() {
        let context = association()
        let observation = HostRuntimeObservation(
            host: .iterm2,
            hostVersion: "3",
            integrationMode: "hooks",
            endpointID: "endpoint-1",
            incarnation: HostIncarnation("incarnation-2"),
            applicationState: .available,
            liveSessionConnected: true,
            liveSessionID: "iterm-session"
        )
        let outcome = JumpBackCoordinator(evidence: HostContextEvidenceStore([context]), port: MatrixHostNavigationPort(observation: observation))
            .jumpBack(JumpBackRequest(sessionIdentity: identity, negotiation: snapshot(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, .appOnly)
        XCTAssertFalse(outcome.qualifier.isExact)
    }
}
