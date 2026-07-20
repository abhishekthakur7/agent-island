import Foundation
import Combine
import SessionDomain

/// Settings-facing model for AB-128. It owns only local Notification Policy
/// values; preview methods never create a candidate, banner, sound lease, or
/// Product action.
@MainActor
public final class NotificationPolicySettingsModel: ObservableObject {
    @Published public private(set) var policy: NotificationPolicy
    @Published public private(set) var lastSoundPreview: SoundPreview?

    public init(policy: NotificationPolicy = .default) {
        self.policy = policy
    }

    public var masterEnabled: Bool {
        get { policy.masterEnabled }
        set { policy.masterEnabled = newValue }
    }

    public var volume: Double {
        get { policy.sound.volume }
        set { policy.sound.volume = min(max(0, newValue), 1) }
    }

    public var immediateMute: Bool {
        get { policy.sound.immediateMute }
        set { policy.sound.immediateMute = newValue }
    }

    public var quietHoursEnabled: Bool {
        get { policy.sound.quietHoursEnabled }
        set { policy.sound.quietHoursEnabled = newValue }
    }

    public func preference(for semanticClass: AlertCandidateClass) -> AlertEventPreference {
        policy.preference(for: semanticClass)
    }

    public func setPreference(_ preference: AlertEventPreference, for semanticClass: AlertCandidateClass) {
        policy.preferences[semanticClass] = preference
        objectWillChange.send()
    }

    public func setPermission(_ state: NotificationPermissionState, for semanticClass: AlertCandidateClass? = nil) {
        if let semanticClass { policy.permission.byClass[semanticClass] = state }
        else { policy.permission.system = state }
        objectWillChange.send()
    }

    public func setFilter(_ enabled: Bool, for origin: AlertCandidateOrigin) {
        switch origin {
        case .normal: break
        case .launcher: policy.filters.showLauncher = enabled
        case .probe: policy.filters.showProbe = enabled
        case .builtInInternalWork: policy.filters.showBuiltInInternalWork = enabled
        case .directory: policy.filters.showDirectory = enabled
        case .firstPrompt: policy.filters.showFirstPrompt = enabled
        case .sourcedChildRun: policy.filters.showSourcedChildCompletion = enabled
        }
        objectWillChange.send()
    }

    public func registerSound(_ asset: LocalSoundAsset) {
        policy.sound.register(asset)
        objectWillChange.send()
    }

    public func selectSound(_ selection: SoundSelection, for semanticClass: AlertCandidateClass) {
        policy.sound.selectionByClass[semanticClass] = selection
        objectWillChange.send()
    }

    /// A local, read-only sound preview. The model returns a value for an
    /// AppKit adapter to play; it cannot reach NotificationPresentationCoordinator.
    @discardableResult
    public func previewSound(_ assetID: LocalSoundID) -> SoundPreview {
        let preview = policy.sound.preview(assetID)
        lastSoundPreview = preview
        return preview
    }

    public func clearPreview() {
        lastSoundPreview = nil
    }

    public func snapshot() -> NotificationPolicy { policy }
}

public typealias NotificationSettingsModel = NotificationPolicySettingsModel

