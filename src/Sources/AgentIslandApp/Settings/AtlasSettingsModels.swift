import Foundation
import SessionDomain

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

public enum AtlasLaunchAtLoginState: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case unknown
    case enabled
    case disabled
    case unavailable
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

/// Durable shortcut intent. The registry stores physical keys and modifiers;
/// the AppKit Carbon registrar applies eligible bindings transactionally and
/// publishes active/disabled/unavailable status without pretending to own
/// global input when the OS rejects registration.
public struct AtlasShortcutPreferences: Codable, Equatable, Hashable, Sendable {
    public var registry: ShortcutRegistry

    public init(registry: ShortcutRegistry = ShortcutRegistry()) {
        self.registry = registry
    }

    public static let `default` = Self()
}

/// The collapsed surface deliberately has two named forms.  `clean` keeps
/// the aggregate calm; `detailed` adds only sourced metadata and never
/// invents project, worktree, model, or activity values.
public enum AtlasCollapsedLayout: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case clean
    case detailed
}

public typealias AtlasDisplayLayout = AtlasCollapsedLayout

public enum AtlasDisplayContentSize: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case small
    case medium
    case large

    public var scale: Double {
        switch self {
        case .small: 0.9
        case .medium: 1.0
        case .large: 1.15
        }
    }
}

/// Display preferences are value data only.  A display identity is an
/// opaque, stable CoreGraphics UUID; it is not a screen index or a Space.
public struct AtlasDisplayPreferences: Codable, Equatable, Hashable, Sendable {
    public var selectedDisplayID: String?
    public var collapsedLayout: AtlasCollapsedLayout
    public var contentSize: AtlasDisplayContentSize
    public var maximumPanelWidth: Double
    public var maximumPanelHeight: Double
    public var completionCardHeight: Double
    public var showProjectMetadata: Bool
    public var showWorktreeMetadata: Bool
    public var showModelMetadata: Bool
    public var showSubagentRunMetadata: Bool
    public var showActivityMetadata: Bool

    public init(
        selectedDisplayID: String? = nil,
        collapsedLayout: AtlasCollapsedLayout = .clean,
        contentSize: AtlasDisplayContentSize = .medium,
        maximumPanelWidth: Double = 820,
        maximumPanelHeight: Double = 500,
        completionCardHeight: Double = 220,
        showProjectMetadata: Bool = false,
        showWorktreeMetadata: Bool = false,
        showModelMetadata: Bool = false,
        showSubagentRunMetadata: Bool = false,
        showActivityMetadata: Bool = false
    ) {
        self.selectedDisplayID = selectedDisplayID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.collapsedLayout = collapsedLayout
        self.contentSize = contentSize
        self.maximumPanelWidth = maximumPanelWidth
        self.maximumPanelHeight = maximumPanelHeight
        self.completionCardHeight = completionCardHeight
        self.showProjectMetadata = showProjectMetadata
        self.showWorktreeMetadata = showWorktreeMetadata
        self.showModelMetadata = showModelMetadata
        self.showSubagentRunMetadata = showSubagentRunMetadata
        self.showActivityMetadata = showActivityMetadata
        self = normalized()
    }

    public static let `default` = AtlasDisplayPreferences()

    private enum CodingKeys: String, CodingKey {
        case selectedDisplayID, collapsedLayout, contentSize, maximumPanelWidth,
             maximumPanelHeight, completionCardHeight, showProjectMetadata,
             showWorktreeMetadata, showModelMetadata, showSubagentRunMetadata,
             showActivityMetadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectedDisplayID: try c.decodeIfPresent(String.self, forKey: .selectedDisplayID) ?? nil,
            collapsedLayout: try c.decodeIfPresent(AtlasCollapsedLayout.self, forKey: .collapsedLayout) ?? .clean,
            contentSize: try c.decodeIfPresent(AtlasDisplayContentSize.self, forKey: .contentSize) ?? .medium,
            maximumPanelWidth: try c.decodeIfPresent(Double.self, forKey: .maximumPanelWidth) ?? 820,
            maximumPanelHeight: try c.decodeIfPresent(Double.self, forKey: .maximumPanelHeight) ?? 500,
            completionCardHeight: try c.decodeIfPresent(Double.self, forKey: .completionCardHeight) ?? 220,
            showProjectMetadata: try c.decodeIfPresent(Bool.self, forKey: .showProjectMetadata) ?? false,
            showWorktreeMetadata: try c.decodeIfPresent(Bool.self, forKey: .showWorktreeMetadata) ?? false,
            showModelMetadata: try c.decodeIfPresent(Bool.self, forKey: .showModelMetadata) ?? false,
            showSubagentRunMetadata: try c.decodeIfPresent(Bool.self, forKey: .showSubagentRunMetadata) ?? false,
            showActivityMetadata: try c.decodeIfPresent(Bool.self, forKey: .showActivityMetadata) ?? false
        )
    }

    public var maxPanelWidth: Double {
        get { maximumPanelWidth }
        set { maximumPanelWidth = newValue }
    }

    public var maxPanelHeight: Double {
        get { maximumPanelHeight }
        set { maximumPanelHeight = newValue }
    }

    public var contentScale: Double { contentSize.scale }

    /// Values written by older builds or hand-edited defaults fail closed to
    /// a readable, finite range rather than producing an off-screen panel.
    public func normalized() -> Self {
        var value = self
        if let selectedDisplayID, selectedDisplayID.isEmpty { value.selectedDisplayID = nil }
        value.maximumPanelWidth = Self.clampFinite(maximumPanelWidth, lower: 240, upper: 2400, fallback: 820)
        value.maximumPanelHeight = Self.clampFinite(maximumPanelHeight, lower: 80, upper: 1600, fallback: 500)
        value.completionCardHeight = Self.clampFinite(completionCardHeight, lower: 80, upper: 900, fallback: 220)
        return value
    }

    public func clamped(to visibleBounds: AtlasVisibleBounds, isBuiltIn: Bool) -> AtlasClampedDisplayGeometry {
        let bounds = visibleBounds.normalized
        let safeInset: Double = isBuiltIn ? 12 : 8
        let safeWidth = max(1, bounds.width - safeInset * 2)
        let safeHeight = max(1, bounds.height - safeInset * 2)
        let width = min(maximumPanelWidth, safeWidth)
        let height = min(maximumPanelHeight, safeHeight)
        let x = bounds.minX + (bounds.width - width) / 2
        let y = bounds.maxY - safeInset - height
        let gap = isBuiltIn ? min(136, max(32, width - 160)) : 0
        return AtlasClampedDisplayGeometry(x: x, y: y, width: width, height: height, protectedGap: gap, isBuiltIn: isBuiltIn)
    }

    private static func clampFinite(_ value: Double, lower: Double, upper: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(upper, max(lower, value))
    }
}

public typealias AtlasDisplaySettings = AtlasDisplayPreferences

public struct AtlasVisibleBounds: Codable, Equatable, Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var width: Double
    public var height: Double

    public init(minX: Double = 0, minY: Double = 0, width: Double = 1_920, height: Double = 1_080) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }
    public var normalized: Self {
        Self(minX: minX.isFinite ? minX : 0, minY: minY.isFinite ? minY : 0, width: width.isFinite ? max(1, width) : 1, height: height.isFinite ? max(1, height) : 1)
    }
}

public struct AtlasClampedDisplayGeometry: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let protectedGap: Double
    public let isBuiltIn: Bool

    public init(x: Double, y: Double, width: Double, height: Double, protectedGap: Double, isBuiltIn: Bool) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.protectedGap = protectedGap
        self.isBuiltIn = isBuiltIn
    }
}

/// The durable settings view plus ephemeral preview state.  Preview is kept
/// in the snapshot for SwiftUI convenience but is never written by the
/// repository.
public struct AtlasSettingsSnapshot: Equatable, Hashable, Sendable {
    public var selectedDestination: AtlasSettingsDestination
    public var general: AtlasGeneralPreferences
    public var display: AtlasDisplayPreferences
    public var shortcuts: AtlasShortcutPreferences
    public var onboarding: AtlasOnboardingState
    public var integrations: [AtlasIntegrationState]
    public var preview: AtlasPreviewState

    public init(
        selectedDestination: AtlasSettingsDestination = .general,
        general: AtlasGeneralPreferences = .default,
        display: AtlasDisplayPreferences = .default,
        shortcuts: AtlasShortcutPreferences = .default,
        onboarding: AtlasOnboardingState = .initial,
        integrations: [AtlasIntegrationState] = AtlasIntegrationState.defaults,
        preview: AtlasPreviewState? = nil
    ) {
        self.selectedDestination = selectedDestination
        self.general = general
        self.display = display
        self.shortcuts = shortcuts
        self.onboarding = onboarding
        self.integrations = integrations
        self.preview = preview ?? AtlasPreviewState(general: general, display: display)
    }

    /// Source-compatible overload for callers written before Display became
    /// durable. It intentionally supplies the safe Display defaults.
    public init(
        selectedDestination: AtlasSettingsDestination,
        general: AtlasGeneralPreferences,
        shortcuts: AtlasShortcutPreferences = .default,
        onboarding: AtlasOnboardingState,
        integrations: [AtlasIntegrationState],
        preview: AtlasPreviewState? = nil
    ) {
        self.init(
            selectedDestination: selectedDestination,
            general: general,
            display: .default,
            shortcuts: shortcuts,
            onboarding: onboarding,
            integrations: integrations,
            preview: preview
        )
    }
}
