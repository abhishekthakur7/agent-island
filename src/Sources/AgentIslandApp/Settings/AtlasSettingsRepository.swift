import Foundation
import Combine
import SessionDomain

/// A typed, namespaced UserDefaults boundary for Atlas.  Callers never need
/// to know a raw key and an isolated suite can be injected in tests.
public struct AtlasSettingsRepository {
    public static let defaultNamespace = "com.agentisland.atlas.settings"

    public let defaults: UserDefaults
    public let namespace: String

    public init(
        defaults: UserDefaults = .standard,
        namespace: String = AtlasSettingsRepository.defaultNamespace
    ) {
        self.defaults = defaults
        self.namespace = namespace
    }

    private enum Key {
        static let selectedDestination = "selectedDestination"
        static let generalLaunchBehavior = "general.launchBehavior"
        static let generalExpandOnHover = "general.expandOnHover"
        static let generalCollapseOnPointerExit = "general.collapseOnPointerExit"
        static let generalSuppressExactHost = "general.suppressWhenExactHostForeground"
        static let generalHideFullScreen = "general.hideInFullScreen"
        static let generalHideNoActiveSession = "general.hideWhenNoActiveSession"
        static let generalRevealCompletion = "general.revealOnCompletion"
        static let generalRevealAttention = "general.revealOnAttention"
        static let generalClickBehavior = "general.clickBehavior"
        static let display = "display"
        static let shortcuts = "shortcuts"
        static let onboarding = "onboarding"
        static let integrations = "integrations"
    }

    private func key(_ value: String) -> String { "\(namespace).\(value)" }

    public var selectedDestination: AtlasSettingsDestination {
        get {
            guard let raw = defaults.string(forKey: key(Key.selectedDestination)),
                  let destination = AtlasSettingsDestination(rawValue: raw) else { return .general }
            return destination
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key(Key.selectedDestination)) }
    }

    public func loadGeneral() -> AtlasGeneralPreferences {
        func bool(_ name: String, default fallback: Bool) -> Bool {
            (defaults.object(forKey: key(name)) as? NSNumber)?.boolValue ?? fallback
        }

        let launch = defaults.string(forKey: key(Key.generalLaunchBehavior)).flatMap(AtlasLaunchBehavior.init(rawValue:)) ?? .manual
        let click = defaults.string(forKey: key(Key.generalClickBehavior)).flatMap(AtlasClickBehavior.init(rawValue:)) ?? .inspectExpand
        return AtlasGeneralPreferences(
            launchBehavior: launch,
            expandOnHover: bool(Key.generalExpandOnHover, default: true),
            collapseOnPointerExit: bool(Key.generalCollapseOnPointerExit, default: true),
            suppressWhenExactHostForeground: bool(Key.generalSuppressExactHost, default: true),
            hideInFullScreen: bool(Key.generalHideFullScreen, default: true),
            hideWhenNoActiveSession: bool(Key.generalHideNoActiveSession, default: true),
            revealOnCompletion: bool(Key.generalRevealCompletion, default: true),
            revealOnAttention: bool(Key.generalRevealAttention, default: true),
            clickBehavior: click
        )
    }

    public func saveGeneral(_ general: AtlasGeneralPreferences) {
        defaults.set(general.launchBehavior.rawValue, forKey: key(Key.generalLaunchBehavior))
        defaults.set(general.expandOnHover, forKey: key(Key.generalExpandOnHover))
        defaults.set(general.collapseOnPointerExit, forKey: key(Key.generalCollapseOnPointerExit))
        defaults.set(general.suppressWhenExactHostForeground, forKey: key(Key.generalSuppressExactHost))
        defaults.set(general.hideInFullScreen, forKey: key(Key.generalHideFullScreen))
        defaults.set(general.hideWhenNoActiveSession, forKey: key(Key.generalHideNoActiveSession))
        defaults.set(general.revealOnCompletion, forKey: key(Key.generalRevealCompletion))
        defaults.set(general.revealOnAttention, forKey: key(Key.generalRevealAttention))
        defaults.set(general.clickBehavior.rawValue, forKey: key(Key.generalClickBehavior))
    }

    public var general: AtlasGeneralPreferences {
        get { loadGeneral() }
        nonmutating set { saveGeneral(newValue) }
    }

    public func loadDisplay() -> AtlasDisplayPreferences {
        guard let data = defaults.data(forKey: key(Key.display)),
              let decoded = try? JSONDecoder().decode(AtlasDisplayPreferences.self, from: data)
        else { return .default }
        let normalized = decoded.normalized()
        if normalized != decoded { saveDisplay(normalized) }
        return normalized
    }

    public func saveDisplay(_ display: AtlasDisplayPreferences) {
        let normalized = display.normalized()
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: key(Key.display))
        }
    }

    public var display: AtlasDisplayPreferences {
        get { loadDisplay() }
        nonmutating set { saveDisplay(newValue) }
    }

    public func loadShortcuts() -> AtlasShortcutPreferences {
        guard let data = defaults.data(forKey: key(Key.shortcuts)),
              let decoded = try? JSONDecoder().decode(AtlasShortcutPreferences.self, from: data)
        else { return .default }
        return decoded
    }

    public func saveShortcuts(_ shortcuts: AtlasShortcutPreferences) {
        if let data = try? JSONEncoder().encode(shortcuts) {
            defaults.set(data, forKey: key(Key.shortcuts))
        }
    }

    public var shortcuts: AtlasShortcutPreferences {
        get { loadShortcuts() }
        nonmutating set { saveShortcuts(newValue) }
    }

    public func loadOnboarding() -> AtlasOnboardingState {
        guard let data = defaults.data(forKey: key(Key.onboarding)) else { return .initial }
        do {
            let decoded = try JSONDecoder().decode(AtlasOnboardingState.self, from: data)
            let normalized = decoded.normalized()
            if decoded != normalized { saveOnboarding(normalized) }
            return normalized
        } catch {
            // Corrupt onboarding bytes are isolated to onboarding.  General,
            // destination, and integration intent remain untouched.
            let reset = AtlasOnboardingState.resetForUnknownSchema()
            saveOnboarding(reset)
            return reset
        }
    }

    public func saveOnboarding(_ state: AtlasOnboardingState) {
        let normalized = state.normalized()
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: key(Key.onboarding))
        }
    }

    public func loadIntegrations() -> [AtlasIntegrationState] {
        guard let data = defaults.data(forKey: key(Key.integrations)),
              let decoded = try? JSONDecoder().decode([AtlasIntegrationState].self, from: data) else {
            return AtlasIntegrationState.defaults
        }
        return AtlasIntegrationState.normalizedCollection(decoded)
    }

    public func saveIntegrations(_ states: [AtlasIntegrationState]) {
        let normalized = AtlasIntegrationState.normalizedCollection(states)
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: key(Key.integrations))
        }
    }

    public func loadSnapshot() -> AtlasSettingsSnapshot {
        let general = loadGeneral()
        let display = loadDisplay()
        let shortcuts = loadShortcuts()
        let preview = AtlasPreviewState(
            general: general,
            display: display,
            selectedDisplayAvailable: display.selectedDisplayID != nil,
            unavailableDisplayLabel: display.selectedDisplayID == nil ? "No display selected" : nil
        )
        return AtlasSettingsSnapshot(
            selectedDestination: selectedDestination,
            general: general,
            display: display,
            shortcuts: shortcuts,
            onboarding: loadOnboarding(),
            integrations: loadIntegrations(),
            preview: preview
        )
    }

    public func save(_ snapshot: AtlasSettingsSnapshot) {
        selectedDestination = snapshot.selectedDestination
        saveGeneral(snapshot.general)
        saveDisplay(snapshot.display)
        saveShortcuts(snapshot.shortcuts)
        saveOnboarding(snapshot.onboarding)
        saveIntegrations(snapshot.integrations)
    }
}

/// Main-actor view model used by the SwiftUI Settings shell.  Every durable
/// mutation has an explicit method; the preview action path remains local and
/// ephemeral.
@MainActor
public final class AtlasSettingsModel: ObservableObject, AtlasPreviewDisplayAvailabilitySink {
    public typealias ShortcutRegistrationHandler = (AtlasShortcutPreferences) -> ShortcutRegistrationApplyResult
    public typealias ShortcutInputSourceResolver = () -> ShortcutInputSource

    private let repository: AtlasSettingsRepository
    private let shortcutInputSourceResolver: ShortcutInputSourceResolver
    private var shortcutRegistrationHandler: ShortcutRegistrationHandler?

    @Published public private(set) var snapshot: AtlasSettingsSnapshot
    @Published public private(set) var selectedDestination: AtlasSettingsDestination
    @Published public private(set) var general: AtlasGeneralPreferences
    @Published public private(set) var launchAtLoginState: AtlasLaunchAtLoginState = .unknown
    @Published public private(set) var display: AtlasDisplayPreferences
    @Published public private(set) var shortcuts: AtlasShortcutPreferences
    @Published public private(set) var shortcutCaptureCommand: ShortcutCommand?
    @Published public private(set) var shortcutFeedback: String?
    @Published public private(set) var shortcutRegistrationStatus: ShortcutRegistrationStatus
    @Published public private(set) var shortcutInputSource: ShortcutInputSource
    @Published public private(set) var onboarding: AtlasOnboardingState
    @Published public private(set) var integrations: [AtlasIntegrationState]
    @Published public private(set) var preview: AtlasPreviewState

    private let previewRouter: AtlasPreviewRouter

    public init(
        repository: AtlasSettingsRepository = AtlasSettingsRepository(),
        shortcutInputSourceResolver: @escaping ShortcutInputSourceResolver = { ShortcutInputSource() }
    ) {
        self.repository = repository
        self.shortcutInputSourceResolver = shortcutInputSourceResolver
        let loaded = repository.loadSnapshot()
        self.snapshot = loaded
        self.selectedDestination = loaded.selectedDestination
        self.general = loaded.general
        self.display = loaded.display
        self.shortcuts = loaded.shortcuts
        self.shortcutCaptureCommand = nil
        self.shortcutFeedback = nil
        self.shortcutRegistrationStatus = loaded.shortcuts.registry.masterEnabled
            ? .unavailable("Native global registration is not configured.")
            : .disabled
        self.shortcutInputSource = shortcutInputSourceResolver()
        self.onboarding = loaded.onboarding
        self.integrations = loaded.integrations
        self.previewRouter = AtlasPreviewRouter(initialState: loaded.preview)
        self.preview = loaded.preview
    }

    public func select(_ destination: AtlasSettingsDestination) {
        guard selectedDestination != destination else { return }
        selectedDestination = destination
        repository.selectedDestination = destination
        publishSnapshot()
    }

    public func setSelectedDestination(_ destination: AtlasSettingsDestination) { select(destination) }

    public func setGeneral(_ value: AtlasGeneralPreferences) {
        guard general != value else { return }
        general = value
        repository.saveGeneral(value)
        previewRouter.send(.setGeneral(value))
        preview = previewRouter.state
        publishSnapshot()
    }

    public func updateGeneral(_ update: (inout AtlasGeneralPreferences) -> Void) {
        var value = general
        update(&value)
        setGeneral(value)
    }

    public func recordLaunchAtLoginState(_ state: AtlasLaunchAtLoginState) {
        launchAtLoginState = state
    }

    public func setDisplay(_ value: AtlasDisplayPreferences) {
        let normalized = value.normalized()
        guard display != normalized else { return }
        display = normalized
        repository.saveDisplay(normalized)
        previewRouter.send(.setDisplay(normalized))
        preview = previewRouter.state
        publishSnapshot()
    }

    public func updateDisplay(_ update: (inout AtlasDisplayPreferences) -> Void) {
        var value = display
        update(&value)
        setDisplay(value)
    }

    public func setShortcuts(_ value: AtlasShortcutPreferences) {
        guard shortcuts != value else { return }
        _ = commitShortcuts(value)
    }

    /// Installs the AppKit/Carbon transaction seam after composition-root
    /// construction. Existing persisted mappings are not rewritten here; the
    /// Overlay performs one bootstrap attempt and reports its status.
    public func setShortcutRegistrationHandler(_ handler: @escaping ShortcutRegistrationHandler) {
        shortcutRegistrationHandler = handler
    }

    public func updateShortcutRegistrationStatus(_ status: ShortcutRegistrationStatus) {
        shortcutRegistrationStatus = status
    }

    public func refreshShortcutInputSource() {
        shortcutInputSource = shortcutInputSourceResolver()
    }

    @discardableResult
    public func setShortcut(_ binding: ShortcutBinding, for command: ShortcutCommand) -> ShortcutBindingValidation {
        var value = shortcuts
        let result = value.registry.setBinding(binding, for: command)
        guard case .valid = result else { return result }
        return commitShortcuts(value)
    }

    public func removeShortcut(for command: ShortcutCommand) {
        var value = shortcuts
        value.registry.removeBinding(for: command)
        setShortcuts(value)
    }

    public func setShortcutsEnabled(_ enabled: Bool) {
        var value = shortcuts
        value.registry.setMasterEnabled(enabled)
        setShortcuts(value)
    }

    public func beginShortcutCapture(_ command: ShortcutCommand) {
        shortcutFeedback = nil
        shortcutCaptureCommand = command
    }

    public func cancelShortcutCapture() { shortcutCaptureCommand = nil }

    public func captureShortcut(_ binding: ShortcutBinding, for command: ShortcutCommand) {
        refreshShortcutInputSource()
        let result = setShortcut(binding, for: command)
        switch result {
        case .valid: shortcutFeedback = "Saved."
        case let .rejected(reason): shortcutFeedback = "Not saved: \(reason.rawValue)."
        }
        shortcutCaptureCommand = nil
    }

    public func onboarding(_ action: AtlasOnboardingAction) {
        var value = onboarding
        value.reduce(action)
        guard value != onboarding else { return }
        onboarding = value
        repository.saveOnboarding(value)
        publishSnapshot()
    }

    public func startOnboarding() { onboarding(.start) }
    public func backOnboarding() { onboarding(.back) }
    public func nextOnboarding() { onboarding(.next) }
    public func skipOnboarding() { onboarding(.skip) }
    public func resumeOnboarding() { onboarding(.resume) }
    public func completeOnboarding() { onboarding(.complete) }

    public func setIntegrationIntent(_ kind: AtlasIntegrationKind, enabled: Bool) {
        updateIntegration(kind) { $0.enabledIntent = enabled }
    }

    public func updateIntegrationEvidence(_ kind: AtlasIntegrationKind, evidence: AtlasIntegrationEvidence, capabilities: Set<AtlasIntegrationCapability>? = nil, affectedCapability: AtlasIntegrationCapability? = nil) {
        updateIntegration(kind) { state in
            state.apply(evidence: evidence, capabilities: capabilities, affectedCapability: affectedCapability)
        }
    }

    public func updateIntegration(_ kind: AtlasIntegrationKind, update: (inout AtlasIntegrationState) -> Void) {
        var value = integrations.first(where: { $0.kind == kind }) ?? AtlasIntegrationState(kind: kind)
        update(&value)
        value = value.normalized()
        if let index = integrations.firstIndex(where: { $0.kind == kind }) {
            integrations[index] = value
        } else {
            integrations.append(value)
        }
        integrations = AtlasIntegrationState.normalizedCollection(integrations)
        repository.saveIntegrations(integrations)
        publishSnapshot()
    }

    public func sendPreview(_ action: AtlasPreviewAction) {
        previewRouter.send(action)
        preview = previewRouter.state
        publishSnapshot()
    }

    /// AppKit forwards only the current selected-display availability and a
    /// human-readable label. This updates the ephemeral read-only preview and
    /// never writes Atlas preferences or moves the live Overlay.
    public func updatePreviewDisplayAvailability(available: Bool, label: String?) {
        previewRouter.send(.setSelectedDisplayAvailability(available: available, label: label))
        preview = previewRouter.state
        publishSnapshot()
    }

    public var previewTrace: [AtlasPreviewTrace] { previewRouter.trace }

    private func publishSnapshot() {
        snapshot = AtlasSettingsSnapshot(
            selectedDestination: selectedDestination,
            general: general,
            display: display,
            shortcuts: shortcuts,
            onboarding: onboarding,
            integrations: integrations,
            preview: preview
        )
    }

    @discardableResult
    private func commitShortcuts(_ value: AtlasShortcutPreferences) -> ShortcutBindingValidation {
        if let handler = shortcutRegistrationHandler {
            switch handler(value) {
            case let .accepted(status):
                var committed = value
                if case .active = status {
                    let activeGlobalBindings = Set(value.registry.activeBindings.compactMap { command, binding in
                        command.isGloballyEligible ? binding : nil
                    })
                    committed.registry.registeredCollisions.subtract(activeGlobalBindings)
                }
                shortcuts = committed
                shortcutRegistrationStatus = status
                repository.saveShortcuts(committed)
                publishSnapshot()
                return .valid
            case let .rejected(reason, status, collisionBinding):
                shortcutRegistrationStatus = status
                shortcutFeedback = "Not saved: \(reason.rawValue)."
                // A native collision is retained as model evidence without
                // replacing the prior valid command mapping. Unavailable and
                // generic failures remain transient status only.
                if reason == .registeredCollision {
                    var evidence = shortcuts
                    evidence.registry.registeredCollisions.formUnion(value.registry.registeredCollisions)
                    if let collisionBinding {
                        evidence.registry.registeredCollisions.insert(collisionBinding)
                    } else if let command = value.registry.bindings.first(where: { old in
                        shortcuts.registry.bindings[old.key] != old.value
                    })?.key,
                       let binding = value.registry.bindings[command] {
                        evidence.registry.registeredCollisions.insert(binding)
                    }
                    shortcuts = evidence
                    repository.saveShortcuts(evidence)
                    publishSnapshot()
                }
                return .rejected(reason)
            }
        } else {
            shortcuts = value
            repository.saveShortcuts(value)
            publishSnapshot()
            return .valid
        }
    }
}
