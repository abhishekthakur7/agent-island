import XCTest
@testable import AgentIslandApp
import SessionDomain

@MainActor
final class UsagePresentationTests: XCTestCase {
    func testFollowSelectedSessionNeverSubstitutesAnotherProviderAndRendersStale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selected = AgentSessionIdentity(productNamespace: "claude-code", nativeSessionID: "selected")
        let other = AgentSessionIdentity(productNamespace: "codex", nativeSessionID: "other")
        let model = UsagePresentationModel(preferences: .init(isVisible: true, valueKind: .remaining, providerSelection: .followSelectedActiveSession), staleAfter: 60)
        model.receive(.init(snapshot: UsageSnapshot(sourceID: "other", provider: "Codex", observedAt: now, remainingPercent: 70), negotiation: negotiation(provider: other.productNamespace, installation: "other"), sessionIdentity: other, receivedAt: now), now: now)
        model.selectActiveSession(selected, now: now)
        XCTAssertEqual(model.rendered.state, .unavailable)
        model.receive(.init(snapshot: UsageSnapshot(sourceID: "selected", provider: "Claude", observedAt: now.addingTimeInterval(-61), remainingPercent: 20), negotiation: negotiation(provider: selected.productNamespace, installation: "selected"), sessionIdentity: selected, receivedAt: now), now: now)
        XCTAssertEqual(model.rendered.state, .stale)
        XCTAssertEqual(model.rendered.snapshot?.provider, "Claude")
    }

    func testDisabledAndMissingRemainExplicit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let identity = AgentSessionIdentity(productNamespace: "claude-code", nativeSessionID: "s")
        let model = UsagePresentationModel(preferences: .init(isVisible: true, valueKind: .used, providerSelection: .followSelectedActiveSession))
        model.receive(.init(snapshot: UsageSnapshot(sourceID: "s", provider: "Claude", observedAt: now), negotiation: negotiation(provider: identity.productNamespace, installation: "s"), sessionIdentity: identity, receivedAt: now), now: now)
        model.selectActiveSession(identity, now: now)
        XCTAssertEqual(model.rendered.state, .missing)
        model.updatePreferences(.init(isVisible: false, valueKind: .used, providerSelection: .followSelectedActiveSession), now: now)
        XCTAssertEqual(model.rendered.state, .disabled)
    }

    private func negotiation(provider: ProductNamespace, installation: String) -> NegotiationSnapshot {
        let id = IntegrationInstanceID(installation)
        return NegotiationSnapshot(id: NegotiationSnapshotID("n-\(installation)"), contractVersion: .init(major: 1, minor: 0), adapterKind: "fixture", adapterBuildVersion: "1", productNamespace: provider, integrationInstanceID: id, integrationMode: "fixture", capabilities: [.init(id: WellKnownCapability.usageObservation, direction: .observe, availability: .available)], negotiatedAt: Date(timeIntervalSince1970: 0))
    }
}
