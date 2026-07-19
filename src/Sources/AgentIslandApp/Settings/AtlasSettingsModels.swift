import Foundation

/// The ten destinations in the Atlas Settings sidebar.  The ordering is part
/// of the presentation contract: it is also the order used by the default
/// grouped navigation model.
public enum AtlasSettingsDestination: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case general
    case integrations
    case notifications
    case display
    case sound
    case usage
    case shortcuts
    case labs
    case diagnostics
    case maintenance

    public enum Group: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
        case preferences
        case advanced
    }

    public var group: Group {
        switch self {
        case .general, .integrations, .notifications, .display, .sound, .usage:
            return .preferences
        case .shortcuts, .labs, .diagnostics, .maintenance:
            return .advanced
        }
    }

    public static var grouped: [(group: Group, destinations: [Self])] {
        [
            (.preferences, [.general, .integrations, .notifications, .display, .sound, .usage]),
            (.advanced, [.shortcuts, .labs, .diagnostics, .maintenance]),
        ]
    }

    public var title: String {
        switch self {
        case .general: "General"
        case .integrations: "Integrations"
        case .notifications: "Notifications"
        case .display: "Display"
        case .sound: "Sound"
        case .usage: "Usage"
        case .shortcuts: "Shortcuts"
        case .labs: "Labs"
        case .diagnostics: "Diagnostics"
        case .maintenance: "Maintenance"
        }
    }
}

public typealias AtlasSettingsGroup = AtlasSettingsDestination.Group

/// Launch behavior is intentionally an enum rather than a loosely named
/// boolean.  `manual` is the safe default and means no launch-at-login claim.
public enum AtlasLaunchBehavior: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case manual
    case atLogin
}

/// The click action is explicit because inspect/expand must never silently
/// become an unvalidated Host navigation attempt.
public enum AtlasClickBehavior: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case inspectExpand
    case jumpBack
}

/// The nine persisted General preferences.  Keep this structure deliberately
/// flat: each property maps to one namespaced UserDefaults value.
public struct AtlasGeneralPreferences: Codable, Equatable, Hashable, Sendable {
    public var launchBehavior: AtlasLaunchBehavior
    public var expandOnHover: Bool
    public var collapseOnPointerExit: Bool
    public var suppressWhenExactHostForeground: Bool
    public var hideInFullScreen: Bool
    public var hideWhenNoActiveSession: Bool
    public var revealOnCompletion: Bool
    public var revealOnAttention: Bool
    public var clickBehavior: AtlasClickBehavior

    public init(
        launchBehavior: AtlasLaunchBehavior = .manual,
        expandOnHover: Bool = true,
        collapseOnPointerExit: Bool = true,
        suppressWhenExactHostForeground: Bool = true,
        hideInFullScreen: Bool = true,
        hideWhenNoActiveSession: Bool = true,
        revealOnCompletion: Bool = true,
        revealOnAttention: Bool = true,
        clickBehavior: AtlasClickBehavior = .inspectExpand
    ) {
        self.launchBehavior = launchBehavior
        self.expandOnHover = expandOnHover
        self.collapseOnPointerExit = collapseOnPointerExit
        self.suppressWhenExactHostForeground = suppressWhenExactHostForeground
        self.hideInFullScreen = hideInFullScreen
        self.hideWhenNoActiveSession = hideWhenNoActiveSession
        self.revealOnCompletion = revealOnCompletion
        self.revealOnAttention = revealOnAttention
        self.clickBehavior = clickBehavior
    }

    public static let `default` = AtlasGeneralPreferences()

    /// Compatibility/readability aliases for settings views that use the
    /// product language instead of the persistence language.
    public var launchAtLogin: Bool {
        get { launchBehavior == .atLogin }
        set { launchBehavior = newValue ? .atLogin : .manual }
    }

    public var hoverExpansion: Bool {
        get { expandOnHover }
        set { expandOnHover = newValue }
    }

    public var pointerExitCollapse: Bool {
        get { collapseOnPointerExit }
        set { collapseOnPointerExit = newValue }
    }

    public var suppressForExactHostForeground: Bool {
        get { suppressWhenExactHostForeground }
        set { suppressWhenExactHostForeground = newValue }
    }

    public var hideWhenFullscreen: Bool {
        get { hideInFullScreen }
        set { hideInFullScreen = newValue }
    }

    public var revealOnCompletedSession: Bool {
        get { revealOnCompletion }
        set { revealOnCompletion = newValue }
    }

    public var clickAction: AtlasClickBehavior {
        get { clickBehavior }
        set { clickBehavior = newValue }
    }
}

public typealias AtlasGeneralSettings = AtlasGeneralPreferences

/// The durable settings view plus ephemeral preview state.  Preview is kept
/// in the snapshot for SwiftUI convenience but is never written by the
/// repository.
public struct AtlasSettingsSnapshot: Equatable, Hashable, Sendable {
    public var selectedDestination: AtlasSettingsDestination
    public var general: AtlasGeneralPreferences
    public var onboarding: AtlasOnboardingState
    public var integrations: [AtlasIntegrationState]
    public var preview: AtlasPreviewState

    public init(
        selectedDestination: AtlasSettingsDestination = .general,
        general: AtlasGeneralPreferences = .default,
        onboarding: AtlasOnboardingState = .initial,
        integrations: [AtlasIntegrationState] = AtlasIntegrationState.defaults,
        preview: AtlasPreviewState? = nil
    ) {
        self.selectedDestination = selectedDestination
        self.general = general
        self.onboarding = onboarding
        self.integrations = integrations
        self.preview = preview ?? AtlasPreviewState(general: general)
    }
}
