import Foundation
import Combine
import SessionDomain
import SessionStore

/// Main-actor bridge for the durable Guided ledger.  It owns no Product
/// client; typed dispatch remains behind ActionAttemptStore's lease gates.
@MainActor
public final class GuidedSheetCoordinator: ObservableObject {
    public let model: GuidedSheetModel
    private let store: ActionAttemptStore

    public init(store: ActionAttemptStore, model: GuidedSheetModel = GuidedSheetModel()) {
        self.store = store
        self.model = model
    }

    public func reload() async {
        model.apply(requests: await store.requests())
    }

    @discardableResult
    public func ingest(_ evidence: GuidedAttentionEvidence) async -> GuidedAttentionIngestResult {
        let result = await store.ingest(evidence)
        await reload()
        return result
    }

    public func select(_ id: GuidedAttentionRequestID) { model.select(id) }

    public func updateDraft(_ draft: GuidedAttentionDraft) async {
        guard let id = model.selectedRequestID else { return }
        _ = await store.updateDraft(id, draft)
        await reload()
    }

    public func acknowledgeLocally() async {
        guard let id = model.selectedRequestID else { return }
        _ = await store.acknowledgeLocally(id)
        await reload()
    }

    public func collapse() { model.setCollapsed(true) }
    public func resume() { model.setCollapsed(false) }

    /// Focuses an exact request for a safe shortcut. This is intentionally a
    /// presentation-only operation: the route's typed action is revalidated
    /// against the live model, but no lease is issued and no Action Attempt is
    /// reserved, consumed, or dispatched here.
    @discardableResult
    public func focusSafeShortcut(_ route: ShortcutGuidedRoute) -> ShortcutGuidedRouteOutcome {
        guard let request = model.requests.first(where: { $0.id == route.requestID }) else {
            return .unavailable(.noLiveRequest)
        }
        guard request.owner == route.owner else { return .unavailable(.noLiveRequest) }
        guard request.sourceOutcome == .pending else { return .unavailable(.sourceResolved) }
        guard request.canRouteAction,
              request.capability.provenance?.productNamespace == request.owner.productNamespace,
              request.capability.provenance?.integrationInstanceID == request.owner.integrationInstanceID,
              request.capability.provenance?.snapshotID == request.owner.negotiationSnapshotID
        else { return .unavailable(.capabilityUnavailable) }
        guard route.safeAction.guidedAction == route.action else {
            return .unavailable(.semanticResponseUnavailable)
        }
        guard case .success = route.action.validating(against: request, confirmation: true) else {
            return .unavailable(.semanticResponseUnavailable)
        }
        model.select(route.requestID)
        model.setCollapsed(false)
        return .opened
    }
}
