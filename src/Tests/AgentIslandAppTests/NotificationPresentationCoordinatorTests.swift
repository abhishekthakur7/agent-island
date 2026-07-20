import XCTest
@testable import AgentIslandApp
@testable import SessionDomain

@MainActor
final class NotificationPresentationCoordinatorTests: XCTestCase {
    private final class BannerSpy: NotificationBannerPort {
        var posted: [NotificationBannerFacet] = []
        func post(_ facet: NotificationBannerFacet) async -> Bool {
            posted.append(facet)
            return true
        }
    }

    private func candidate(_ kind: AlertCandidateClass, event: String) -> AlertCandidate {
        let owner = AlertCandidateOwner(
            productNamespace: ProductNamespace("fixture"),
            nativeSessionID: NativeSessionID("session"),
            integrationInstanceID: IntegrationInstanceID("integration"),
            negotiationSnapshotID: NegotiationSnapshotID("snapshot")
        )
        return AlertCandidate(
            id: AlertCandidateID(owner: owner, semanticClass: kind, sourceEventIdentity: .stable(event)),
            owner: owner,
            semanticClass: kind,
            origin: .normal,
            sourceEventIdentity: .stable(event),
            sourceVariant: "fixture",
            sourceRevision: 1,
            sourceObservedAt: Date(timeIntervalSince1970: 1),
            payload: AlertCandidatePayload(label: "Configured", state: kind == .attention ? .needsAttention : .completed),
            dwell: kind == .completion ? .completion : nil
        )
    }

    func testDuplicateReplayIsOneBannerAndOneCurrentPresentation() async {
        let spy = BannerSpy()
        let policy = NotificationPolicy(permission: NotificationPermissionPolicy(system: .granted))
        let coordinator = NotificationPresentationCoordinator(policy: policy, bannerPort: spy)
        let value = candidate(.completion, event: "completion")
        let first = await coordinator.submit(value)
        let replay = await coordinator.submit(value)
        XCTAssertTrue(first.bannerPosted)
        XCTAssertFalse(replay.bannerPosted)
        XCTAssertEqual(spy.posted.count, 1)
        XCTAssertEqual(coordinator.currentCandidate?.id, value.id)
    }

    func testGuardedAttentionIsNotDisplacedByCompletionAndRestartDoesNotReplay() async {
        let spy = BannerSpy()
        let policy = NotificationPolicy(permission: NotificationPermissionPolicy(system: .granted))
        let coordinator = NotificationPresentationCoordinator(policy: policy, bannerPort: spy)
        let attention = candidate(.attention, event: "attention")
        let completion = candidate(.completion, event: "completion")
        _ = await coordinator.submit(attention)
        coordinator.beginInteraction(for: attention.id)
        let guarded = await coordinator.submit(completion)
        XCTAssertEqual(guarded.decision.reason, .guardedPresentation)
        XCTAssertEqual(coordinator.currentCandidate?.id, attention.id)

        coordinator.dismissCurrent()
        coordinator.restore([completion])
        let restored = await coordinator.submit(completion)
        XCTAssertEqual(restored.decision.reason, .restartRestored)
        XCTAssertTrue(spy.posted.count <= 1)
    }
}

