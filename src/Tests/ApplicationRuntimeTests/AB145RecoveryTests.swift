import XCTest
@testable import ApplicationRuntime
@testable import SessionDomain
@testable import SessionStore

final class AB145RecoveryTests: XCTestCase {
    func testWakeBoundaryIsTypedAndDoesNotCreateProductFacts() async {
        let store = SessionStore()
        let runtime = ApplicationRuntime(store: store)
        let coordinator = RecoveryCoordinator(runtime: runtime)

        _ = await coordinator.cross(.systemWake)

        let lastBoundary = await coordinator.lastBoundary
        XCTAssertEqual(lastBoundary, .systemWake)
        XCTAssertTrue(RecoveryBoundary.systemWake.invalidatesActionAuthority)
        XCTAssertTrue(RecoveryBoundary.systemWake.requiresFreshHostProbe)
        let working = await store.workingSetProjections()
        XCTAssertTrue(working.isEmpty, "a wake boundary must not manufacture Product state")
    }

    func testWakeInvalidatesOnlyHostEvidence() {
        let now = Date(timeIntervalSince1970: 1)
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("session"))
        let association = HostContextAssociation(
            id: "association", sessionIdentity: identity, host: .cursor,
            integrationInstanceID: .init("integration"), integrationMode: "fixture", incarnation: .init("extension"),
            locator: .cursorExtensionTerminal(terminalID: "opaque", extensionInstanceID: "extension"),
            provenance: .init(host: .cursor, evidence: .connectedExtension, observedAt: now),
            validity: .live, firstObservedAt: now, lastValidatedAt: now
        )
        var evidence = HostContextEvidenceStore([association])
        evidence.markSystemWake(at: now)
        XCTAssertTrue(evidence.association("association")?.isInvalidated == true)
        XCTAssertEqual(evidence.associations(for: identity).count, 1, "historical association stays inspectable")
    }
}
