import Foundation
import SessionDomain

/// Local maintenance coordinator. It tracks only selected local categories
/// and manifest IDs; it cannot infer ownership of an external file or touch a
/// Product/session. Exact setup removal remains delegated to the manifest
/// proven IntegrationInstallation coordinator.
public actor MaintenanceStore {
    private var state: MaintenanceState

    public init(state: MaintenanceState = MaintenanceState()) {
        self.state = state
    }

    public func currentState() -> MaintenanceState { state }

    public func markIntegrityFailure(_ category: MaintenanceLocalCategory) {
        state.markIntegrityFailure(category)
    }

    public func preview(_ request: MaintenanceRequest, at date: Date = Date()) -> MaintenancePreview {
        MaintenancePlanner.preview(request, state: state, at: date)
    }

    @discardableResult
    public func apply(_ preview: MaintenancePreview, confirmation: MaintenanceConfirmation) -> MaintenanceOutcome {
        MaintenancePlanner.apply(preview, confirmation: confirmation, state: &state)
    }

    /// Applies a person-confirmed scope to a supplied set of exact manifest
    /// reports. Ambiguous/drifted receipts are retained in the result rather
    /// than being represented as successful cleanup.
    @discardableResult
    public func applyManifestReports(_ reports: [OwnershipManifestRemovalReport], for preview: MaintenancePreview, confirmation: MaintenanceConfirmation) -> MaintenanceOutcome {
        let selectedIDs = Set(preview.externalManifestScopes.map(\.manifestID))
        guard reports.allSatisfy({ report in
            guard let manifest = report.manifest else { return true }
            return selectedIDs.contains(manifest.id)
        }) else { return .invalidScope }
        let initial = MaintenancePlanner.apply(preview, confirmation: confirmation, state: &state)
        guard case .applied = initial else { return initial }
        let residual = reports.compactMap(\.manifest).compactMap { manifest -> MaintenanceManifestScope? in
            guard manifest.lifecycle != .removed else { return nil }
            return MaintenanceManifestScope(manifest)
        }
        return residual.isEmpty ? initial : .partialWithResidual(manifestScopes: residual)
    }
}

public extension SessionStore {
    /// Executes only the selected inactive/active local-history flow after a
    /// maintenance preview has been confirmed. Setup, diagnostics, and other
    /// categories are intentionally not touched by this method.
    func applyHistoryMaintenance(
        _ preview: MaintenancePreview,
        confirmation: MaintenanceConfirmation
    ) -> [HistoryMutationOutcome] {
        guard confirmation.confirmed,
              confirmation.previewDigest == preview.previewDigest else { return preview.exactSessionIDs.map { _ in .confirmationRequired } }
        switch preview.request.flow {
        case .deleteInactiveSessionHistory:
            return preview.exactSessionIDs.map { identity in
                guard let historyPreview = previewHistoryDeletion(for: identity) else { return .notSafelyInactive }
                return deleteHistory(for: identity, confirmation: historyPreview.confirmation.confirming())
            }
        case .deleteActiveLocalHistory:
            return preview.exactSessionIDs.map { identity in
                guard let activePreview = beginActiveLocalHistoryDeletion(for: identity) else { return .observationStopRequired }
                return deleteActiveLocalHistory(for: identity, confirmation: activePreview.confirmation.confirming())
            }
        default:
            // A category-specific coordinator must own all other mutations;
            // returning no work prevents accidental cross-category deletion.
            return []
        }
    }
}
