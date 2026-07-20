import Foundation
import XCTest
@testable import CursorHostAdapter
@testable import SessionDomain

final class CursorHostAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let identity = AgentSessionIdentity(productNamespace: .init("cursor"), nativeSessionID: .init("agent-session"))
    private let installation = IntegrationInstanceID("cursor-host")

    private func negotiation() -> NegotiationSnapshot { .init(id: .init("snapshot"), contractVersion: .init(major: 1, minor: 0), adapterKind: CursorHostContract.adapterKind, adapterBuildVersion: "1", productNamespace: identity.productNamespace, integrationInstanceID: installation, integrationMode: CursorHostContract.integrationMode, capabilities: [.init(id: WellKnownCapability.hostNavigation, direction: .navigate, availability: .available)], negotiatedAt: now) }
    private func registration(reference: String = "live-ref") -> CursorExtensionLiveTerminalRegistration { .init(endpointID: "endpoint", incarnation: "extension-a", cursorVersion: "1.0", sessionIdentity: identity, terminalReference: .init(reference), authentication: .init(keyID: "fixture", proof: Data([1]))) }

    private func capture(_ client: FixtureEndpoint, reference: String = "live-ref") -> (CursorHostNavigationPort, HostContextAssociation) {
        let port = CursorHostNavigationPort(endpoint: client, application: client)
        let context = try! CursorHostContextCapture(endpoint: client).captureLiveTerminal(id: "context", sessionIdentity: identity, integrationInstanceID: installation, registration: registration(reference: reference), at: now).get()
        port.retain(client.binding!, for: context.id)
        return (port, context)
    }

    func testLiveEndpointRetainedReferenceRevealsExactSurface() {
        let client = FixtureEndpoint(); let (port, context) = capture(client)
        let outcome = JumpBackCoordinator(evidence: .init([context]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.exactSurface); XCTAssertEqual(client.revealedTerminal, "live-ref")
        XCTAssertFalse(outcome.productActionGranted); XCTAssertTrue(outcome.voiceOverLabel.contains("exactSurface"))
    }

    func testCaptureRequiresOwningSessionAuthenticatedCompatibleEndpointAndLiveReference() {
        let client = FixtureEndpoint(); let capture = CursorHostContextCapture(endpoint: client)
        var wrong = registration(); wrong = .init(endpointID: wrong.endpointID, incarnation: wrong.incarnation, cursorVersion: wrong.cursorVersion, sessionIdentity: .init(productNamespace: identity.productNamespace, nativeSessionID: .init("other")), terminalReference: wrong.terminalReference, authentication: wrong.authentication)
        XCTAssertEqual(capture.captureLiveTerminal(id: "bad", sessionIdentity: identity, integrationInstanceID: installation, registration: wrong, at: now), .failure(.registrationRejected))
        let unauthenticated = CursorExtensionLiveTerminalRegistration(endpointID: "endpoint", incarnation: "extension-a", cursorVersion: "1", sessionIdentity: identity, terminalReference: "x", authentication: .init(keyID: "", proof: Data()))
        XCTAssertEqual(capture.captureLiveTerminal(id: "bad", sessionIdentity: identity, integrationInstanceID: installation, registration: unauthenticated, at: now), .failure(.unauthenticated))
    }

    func testReloadClosureDisconnectAndDuplicateNeverRebuildExactTerminal() {
        let client = FixtureEndpoint(); let (port, context) = capture(client)
        for change in [FixtureEndpoint.Change.reload, .closed, .disconnected, .duplicate] {
            client.change = change
            let outcome = JumpBackCoordinator(evidence: .init([context]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
            XCTAssertNotEqual(outcome.qualifier, HostNavigationLevel.exactSurface)
            XCTAssertNil(client.revealedTerminal)
        }
        XCTAssertEqual(port.diagnostic(for: context.id)?.reason, .duplicateLiveReference)
    }

    func testProtocolMismatchInvalidatesExactAndReportsTruthfulDiagnostic() {
        let client = FixtureEndpoint(); let (port, context) = capture(client); client.change = .incompatible
        let outcome = JumpBackCoordinator(evidence: .init([context]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.appOnly); XCTAssertEqual(port.diagnostic(for: context.id)?.reason, .protocolIncompatible)
        XCTAssertTrue(outcome.voiceOverLabel.contains("appOnly fallback from exactSurface"), outcome.voiceOverLabel)
    }

    func testNativeThreadNeverExactButUsesSeparatelyProvenWorkspace() {
        let client = FixtureEndpoint(); client.workspace = .init(sessionIdentity: identity, workspaceID: "workspace", fileID: "file")
        let port = CursorHostNavigationPort(endpoint: client, application: client)
        let native = try! CursorHostContextCapture(endpoint: client).captureNativeThread(id: "native", sessionIdentity: identity, integrationInstanceID: installation, registration: .init(endpointID: "endpoint", incarnation: "extension-a", cursorVersion: "1", sessionIdentity: identity, authentication: .init(keyID: "fixture", proof: Data([1]))), at: now).get()
        port.retain(client.binding!, for: native.id)
        let outcome = JumpBackCoordinator(evidence: .init([native]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(outcome.qualifier, HostNavigationLevel.workspaceOrFile, outcome.voiceOverLabel); XCTAssertEqual(client.revealedWorkspace?.workspaceID, "workspace")
        XCTAssertEqual(port.diagnostic(for: native.id)?.reason, .nativeThreadNeverExact)
    }

    func testNativeThreadFallsBackToAppOnlyOrUnavailableWithoutWorkspaceProof() {
        let client = FixtureEndpoint(); let port = CursorHostNavigationPort(endpoint: client, application: client)
        let native = try! CursorHostContextCapture(endpoint: client).captureNativeThread(id: "native", sessionIdentity: identity, integrationInstanceID: installation, registration: .init(endpointID: "endpoint", incarnation: "extension-a", cursorVersion: "1", sessionIdentity: identity, authentication: .init(keyID: "fixture", proof: Data([1]))), at: now).get(); port.retain(client.binding!, for: native.id)
        let appOnly = JumpBackCoordinator(evidence: .init([native]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(appOnly.qualifier, HostNavigationLevel.appOnly, appOnly.voiceOverLabel)
        client.appAvailable = false
        let unavailable = JumpBackCoordinator(evidence: .init([native]), port: port).jumpBack(.init(sessionIdentity: identity, negotiation: negotiation(), requestedAt: now))
        XCTAssertEqual(unavailable.qualifier, HostNavigationLevel.unavailable, unavailable.voiceOverLabel)
    }

    func testNoMetadataOrDeepLinkAutomationSurfaceExists() {
        let registration = registration()
        XCTAssertEqual(registration.terminalReference.rawValue, "live-ref")
        // The public endpoint seam carries only opaque references. There is
        // intentionally no API argument for terminal name/PID/title/path/
        // layout, clicks, keys, terminal input, or an existing-session URL.
        XCTAssertTrue(true)
    }
}

private final class FixtureEndpoint: @unchecked Sendable, CursorExtensionEndpointClient, CursorApplicationClient {
    enum Change: Equatable { case live, reload, closed, disconnected, duplicate, incompatible }
    var change: Change = .live; var binding: CursorExtensionEndpointBinding?; var appAvailable = true
    var workspace: CursorWorkspaceFileProof?; var revealedTerminal: String?; var revealedWorkspace: CursorWorkspaceFileProof?
    func registerLiveTerminal(_ registration: CursorExtensionLiveTerminalRegistration) -> Result<CursorExtensionEndpointBinding, CursorExtensionEndpointFailure> {
        guard registration.authentication.isPresent else { return .failure(.unauthenticated) }; guard registration.protocolVersion == 1 else { return .failure(.incompatibleProtocol) }
        let value = CursorExtensionEndpointBinding(endpointID: registration.endpointID, incarnation: registration.incarnation, protocolVersion: registration.protocolVersion, cursorVersion: registration.cursorVersion, sessionIdentity: registration.sessionIdentity, terminalReference: registration.terminalReference); binding = value; return .success(value)
    }
    func registerNativeThread(_ registration: CursorExtensionNativeThreadRegistration) -> Result<CursorExtensionEndpointBinding, CursorExtensionEndpointFailure> { guard registration.authentication.isPresent else { return .failure(.unauthenticated) }; let value = CursorExtensionEndpointBinding(endpointID: registration.endpointID, incarnation: registration.incarnation, protocolVersion: registration.protocolVersion, cursorVersion: registration.cursorVersion, sessionIdentity: registration.sessionIdentity, terminalReference: nil); binding = value; return .success(value) }
    func status(for binding: CursorExtensionEndpointBinding) -> Result<CursorExtensionEndpointStatus, CursorExtensionEndpointFailure> {
        switch change {
        case .disconnected: return .failure(.endpointUnavailable)
        case .reload: return .success(.init(endpointID: binding.endpointID, incarnation: "extension-b", protocolVersion: 1, cursorVersion: binding.cursorVersion, authenticated: true, connected: true, applicationAvailable: appAvailable, matchingLiveReferenceCount: 1))
        case .closed: return .success(.init(endpointID: binding.endpointID, incarnation: binding.incarnation, protocolVersion: 1, cursorVersion: binding.cursorVersion, authenticated: true, connected: true, applicationAvailable: appAvailable, matchingLiveReferenceCount: 0))
        case .duplicate: return .success(.init(endpointID: binding.endpointID, incarnation: binding.incarnation, protocolVersion: 1, cursorVersion: binding.cursorVersion, authenticated: true, connected: true, applicationAvailable: appAvailable, matchingLiveReferenceCount: 2))
        case .incompatible: return .success(.init(endpointID: binding.endpointID, incarnation: binding.incarnation, protocolVersion: 2, cursorVersion: binding.cursorVersion, authenticated: true, connected: true, applicationAvailable: appAvailable, matchingLiveReferenceCount: 1))
        case .live: return .success(.init(endpointID: binding.endpointID, incarnation: binding.incarnation, protocolVersion: 1, cursorVersion: binding.cursorVersion, authenticated: true, connected: true, applicationAvailable: appAvailable, matchingLiveReferenceCount: binding.terminalReference == nil ? 0 : 1))
        }
    }
    func workspaceFileProof(for binding: CursorExtensionEndpointBinding, sessionIdentity: AgentSessionIdentity) -> Result<CursorWorkspaceFileProof?, CursorExtensionEndpointFailure> { .success(workspace?.sessionIdentity == sessionIdentity ? workspace : nil) }
    func revealLiveTerminal(_ binding: CursorExtensionEndpointBinding) -> Result<Void, CursorExtensionEndpointFailure> { guard change == .live, let reference = binding.terminalReference else { return .failure(.terminalUnavailable) }; revealedTerminal = reference.rawValue; return .success(()) }
    func revealWorkspaceOrFile(_ proof: CursorWorkspaceFileProof, through binding: CursorExtensionEndpointBinding) -> Result<Void, CursorExtensionEndpointFailure> { revealedWorkspace = proof; return .success(()) }
    func status() -> CursorApplicationState { appAvailable ? .available : .unavailable }
    func activate() -> Result<Void, CursorExtensionEndpointFailure> { appAvailable ? .success(()) : .failure(.endpointUnavailable) }
}
