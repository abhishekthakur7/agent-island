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
}
