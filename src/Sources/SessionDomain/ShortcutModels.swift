import Foundation

/// A physical macOS key (USB/HID key code), deliberately independent of the
/// character produced by the current keyboard layout.  This keeps bindings
/// stable when a person changes input source or uses an IME.
public struct PhysicalKey: Codable, Hashable, Sendable, Equatable, RawRepresentable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(_ rawValue: UInt16) { self.init(rawValue: rawValue) }

    public static let space = Self(49)
    public static let escape = Self(53)
    public static let tab = Self(48)
    public static let leftArrow = Self(123)
    public static let rightArrow = Self(124)
    public static let downArrow = Self(125)
    public static let upArrow = Self(126)
    public static let returnKey = Self(36)

    /// A stable fallback label for layouts for which no input-source map is
    /// available.  It is intentionally a key identity, never typed text.
    public var fallbackLabel: String {
        switch rawValue {
        case 18...29: return String(rawValue - 17)
        case 0...50 where asciiKey(for: rawValue) != 63:
            return String(UnicodeScalar(asciiKey(for: rawValue)))
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 53: return "Escape"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key " + String(rawValue)
        }
    }

    private func asciiKey(for code: UInt16) -> UInt8 {
        // Physical positions for the common ANSI letter keys. Unknown values
        // intentionally remain a readable key-code label.
        let labels: [UInt16: UInt8] = [
            0: 65, 1: 83, 2: 68, 3: 70, 4: 72, 5: 71, 6: 90,
            7: 88, 8: 67, 9: 86, 11: 66, 12: 81, 13: 87, 14: 69,
            15: 82, 16: 89, 17: 84, 31: 79, 32: 85, 34: 73,
            35: 80, 37: 76, 38: 74, 40: 75, 45: 78, 46: 77
        ]
        return labels[code] ?? 63
    }
}

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)

    public static let none: Self = []

    public var isOrdinaryCharacterShortcut: Bool {
        intersection([.command, .option, .control, .function]).isEmpty
    }
}

/// The key labels supplied by the active input source. `keyCodeLabels` maps
/// physical positions to the source's displayed equivalent (for example an
/// AZERTY source maps the physical Q position to `A`).
public struct ShortcutInputSource: Codable, Hashable, Sendable, Equatable {
    public let identifier: String
    public let localizedName: String
    public let keyCodeLabels: [UInt16: String]

    public init(identifier: String = "unknown", localizedName: String = "Current keyboard", keyCodeLabels: [UInt16: String] = [:]) {
        self.identifier = identifier
        self.localizedName = localizedName
        self.keyCodeLabels = keyCodeLabels
    }

    public func label(for key: PhysicalKey) -> String {
        keyCodeLabels[key.rawValue]?.isEmpty == false ? keyCodeLabels[key.rawValue]! : key.fallbackLabel
    }
}

public struct ShortcutBinding: Codable, Hashable, Sendable, Equatable {
    public let key: PhysicalKey
    public let modifiers: ShortcutModifiers

    public init(key: PhysicalKey, modifiers: ShortcutModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public func renderedLabel(inputSource: ShortcutInputSource = .init()) -> String {
        let prefix = [
            modifiers.contains(.function) ? "fn" : nil,
            modifiers.contains(.control) ? "⌃" : nil,
            modifiers.contains(.option) ? "⌥" : nil,
            modifiers.contains(.shift) ? "⇧" : nil,
            modifiers.contains(.command) ? "⌘" : nil
        ].compactMap { $0 }.joined()
        return prefix + inputSource.label(for: key)
    }
}

/// Commands intentionally stop at local Overlay/session navigation and the
/// explicitly configured safe actions below. Product-specific action
/// integrations remain behind the Guided workflow and Action Lease ports.
public enum ShortcutCommand: Codable, Hashable, Sendable, Equatable {
    case toggleOverlay
    case nextSession
    case previousSession
    case showAll
    case collapse
    case inspect
    case safeAction(String)

    /// Constructs a command only from the closed set of safe actions exposed
    /// by Settings.  The string-backed case remains decodable so older local
    /// mappings can be retained, but unknown IDs never acquire authority.
    public static func safeAction(_ action: ShortcutSafeAction) -> Self {
        .safeAction(action.rawValue)
    }

    /// Returns the typed safe action only when this command is one of the
    /// explicitly supported Guided semantics.  Arbitrary persisted strings
    /// are intentionally not treated as Product authority.
    public var configuredSafeAction: ShortcutSafeAction? {
        guard case let .safeAction(id) = self else { return nil }
        return ShortcutSafeAction(rawValue: id)
    }

    public var identifier: String {
        switch self {
        case .toggleOverlay: "overlay.toggle"
        case .nextSession: "session.next"
        case .previousSession: "session.previous"
        case .showAll: "overlay.showAll"
        case .collapse: "overlay.collapse"
        case .inspect: "overlay.inspect"
        case let .safeAction(id): "safe." + id
        }
    }

    public var dispatchDisposition: ShortcutDispatchDisposition {
        switch self {
        case .toggleOverlay, .nextSession, .previousSession, .showAll, .collapse, .inspect:
            return .localOverlayNavigation
        case .safeAction:
            return .guidedWorkflowAction
        }
    }

    /// Only commands whose effect is local Overlay/session navigation may be
    /// installed as native global hot keys. Focused controls and safe actions
    /// stay on the engaged Overlay/Guided workflow path.
    public var isGloballyEligible: Bool {
        switch self {
        case .toggleOverlay, .nextSession, .previousSession:
            return true
        case .showAll, .collapse, .inspect:
            return false
        case .safeAction:
            // Only the closed, source-supported choices may have a native
            // callback. Unknown legacy IDs remain persisted but inert.
            return configuredSafeAction != nil
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, id }
    private enum Kind: String, Codable { case toggleOverlay, nextSession, previousSession, showAll, collapse, inspect, safeAction }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .toggleOverlay: try c.encode(Kind.toggleOverlay, forKey: .kind)
        case .nextSession: try c.encode(Kind.nextSession, forKey: .kind)
        case .previousSession: try c.encode(Kind.previousSession, forKey: .kind)
        case .showAll: try c.encode(Kind.showAll, forKey: .kind)
        case .collapse: try c.encode(Kind.collapse, forKey: .kind)
        case .inspect: try c.encode(Kind.inspect, forKey: .kind)
        case let .safeAction(id):
            try c.encode(Kind.safeAction, forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .toggleOverlay: self = .toggleOverlay
        case .nextSession: self = .nextSession
        case .previousSession: self = .previousSession
        case .showAll: self = .showAll
        case .collapse: self = .collapse
        case .inspect: self = .inspect
        case .safeAction:
            let id = try c.decode(String.self, forKey: .id)
            self = .safeAction(id)
        }
    }
}

/// Explicit safe-action choices that can be configured in Settings.  Each
/// value maps to one existing Guided semantic shape; there is deliberately no
/// generic command, terminal input, or arbitrary Product extension choice.
public enum ShortcutSafeAction: String, Codable, Hashable, Sendable, Equatable, CaseIterable, Identifiable {
    case allow
    case deny
    case persistentAllow
    case persistentDeny
    case planAccept

    public var id: String { rawValue }

    /// Stable process-local Carbon event ID. It is distinct for every
    /// supported safe action; the base range does not overlap local Overlay
    /// navigation IDs.
    public var nativeRegistrationID: UInt32 {
        1000 + UInt32(Self.allCases.firstIndex(of: self) ?? 0)
    }

    public var title: String {
        switch self {
        case .allow: "Allow response"
        case .deny: "Deny response"
        case .persistentAllow: "Allow persistent suggestion"
        case .persistentDeny: "Deny persistent suggestion"
        case .planAccept: "Accept plan review"
        }
    }

    public var guidedAction: GuidedAction {
        switch self {
        case .allow: .allow
        case .deny: .deny
        case .persistentAllow: .persistentSuggestion(allow: true)
        case .persistentDeny: .persistentSuggestion(allow: false)
        case .planAccept: .planReview(.accept, reason: nil)
        }
    }

    public var semanticKind: GuidedSemanticKind { guidedAction.semanticKind }
}

/// A resolved route is only a request-opening instruction.  It contains the
/// exact owner and typed Guided action so an injected coordinator can focus the
/// request, but it is not a lease and cannot dispatch by itself.
public struct ShortcutGuidedRoute: Codable, Hashable, Sendable, Equatable {
    public let safeAction: ShortcutSafeAction
    public let requestID: GuidedAttentionRequestID
    public let owner: GuidedAttentionOwner
    public let action: GuidedAction

    public init(safeAction: ShortcutSafeAction, requestID: GuidedAttentionRequestID, owner: GuidedAttentionOwner, action: GuidedAction) {
        self.safeAction = safeAction
        self.requestID = requestID
        self.owner = owner
        self.action = action
    }
}

public enum ShortcutGuidedRouteFailure: String, Codable, Hashable, Sendable, Equatable, Error {
    case unknownSafeAction
    case noLiveRequest
    case ambiguousRequest
    case sourceResolved
    case capabilityUnavailable
    case semanticResponseUnavailable
    case guidedWorkflowUnavailable

    public var humanReadableDescription: String {
        switch self {
        case .unknownSafeAction:
            "This safe action is not configured; no Product action was sent."
        case .noLiveRequest:
            "No live Attention Request is eligible for this safe action; continue in the native Host."
        case .ambiguousRequest:
            "More than one live Attention Request matches this safe action; select one in Guided workflow first."
        case .sourceResolved:
            "The matching Attention Request is already resolved or superseded; no Product action was sent."
        case .capabilityUnavailable:
            "The matching Action capability is stale or unavailable; continue in the native Host."
        case .semanticResponseUnavailable:
            "The safe action does not match the live Guided response shape; no Product action was sent."
        case .guidedWorkflowUnavailable:
            "The Guided workflow is unavailable; continue in the native Host."
        }
    }
}

public enum ShortcutGuidedRouteResolution: Sendable, Equatable {
    case eligible(ShortcutGuidedRoute)
    case unavailable(ShortcutGuidedRouteFailure)
}

/// Result returned by an injected live Guided coordinator. `opened` means
/// only that the exact request was focused/presented; it does not mean an
/// Action Attempt was reserved or that a Product accepted anything.
public enum ShortcutGuidedRouteOutcome: Sendable, Equatable {
    case opened
    case unavailable(ShortcutGuidedRouteFailure)
}

/// Pure, deterministic lookup used by a live Guided coordinator seam.  It
/// validates exact request identity, source liveness, capability provenance,
/// and typed semantic compatibility before opening a request.  It never
/// issues a lease, reserves an Action Attempt, or dispatches a Product action.
public enum ShortcutGuidedRouteResolver {
    public static func resolve(command: ShortcutCommand, requests: [GuidedAttentionRequest]) -> ShortcutGuidedRouteResolution {
        guard let safeAction = command.configuredSafeAction else {
            return .unavailable(.unknownSafeAction)
        }

        let matching = requests.filter { $0.semanticShape.kind == safeAction.semanticKind }
        guard !matching.isEmpty else { return .unavailable(.noLiveRequest) }

        let pending = matching.filter { $0.sourceOutcome == .pending }
        guard !pending.isEmpty else { return .unavailable(.sourceResolved) }
        guard pending.count == 1 else { return .unavailable(.ambiguousRequest) }
        let capable = pending.filter { request in
            guard request.canRouteAction else { return false }
            // Reassert the exact owner/capability provenance at the route
            // boundary even when a caller supplies a reconstructed snapshot.
            return request.capability.provenance?.productNamespace == request.owner.productNamespace
                && request.capability.provenance?.integrationInstanceID == request.owner.integrationInstanceID
                && request.capability.provenance?.snapshotID == request.owner.negotiationSnapshotID
        }
        guard !capable.isEmpty else { return .unavailable(.capabilityUnavailable) }

        let action = safeAction.guidedAction
        guard let request = capable.sorted(by: Self.requestOrder).first else {
            return .unavailable(.noLiveRequest)
        }
        guard case .success = action.validating(against: request, confirmation: true) else {
            return .unavailable(.semanticResponseUnavailable)
        }
        return .eligible(ShortcutGuidedRoute(safeAction: safeAction, requestID: request.id, owner: request.owner, action: action))
    }

    private static func requestOrder(_ lhs: GuidedAttentionRequest, _ rhs: GuidedAttentionRequest) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        if lhs.sourceObservedAt != rhs.sourceObservedAt { return lhs.sourceObservedAt < rhs.sourceObservedAt }
        return lhs.id.id < rhs.id.id
    }
}

/// A safe-action shortcut is only a discovery/configuration record here. Its
/// invocation must enter the canonical Guided workflow and Action Lease gate;
/// this module intentionally provides no alternate Product dispatch callback.
public enum ShortcutDispatchDisposition: String, Codable, Hashable, Sendable, Equatable {
    case localOverlayNavigation
    case guidedWorkflowAction
}

public enum ShortcutBindingValidationFailure: String, Codable, Hashable, Sendable, Equatable, Error {
    case duplicateBinding
    case reservedSystemShortcut
    case registeredCollision
    case emptySafeAction
    case invalidKey
    case requiresModifier
    case registrationUnavailable
    case registrationFailed

    public var humanReadableDescription: String {
        switch self {
        case .duplicateBinding: "another configured command already uses that physical shortcut"
        case .reservedSystemShortcut: "that physical shortcut is reserved by macOS"
        case .registeredCollision: "another registered shortcut owns that physical shortcut"
        case .emptySafeAction: "the safe action choice is empty"
        case .invalidKey: "the physical key is invalid"
        case .requiresModifier: "global shortcuts need Command, Option, Control, or Function"
        case .registrationUnavailable: "native global shortcut registration is unavailable"
        case .registrationFailed: "native global shortcut registration failed"
        }
    }
}

public enum ShortcutBindingValidation: Equatable, Sendable {
    case valid
    case rejected(ShortcutBindingValidationFailure)
}

/// Pure registry and collision validator. Failed updates never mutate the
/// existing mapping, which makes Settings rebinds recoverable and deterministic.
public struct ShortcutRegistry: Codable, Hashable, Sendable, Equatable {
    public private(set) var bindings: [ShortcutCommand: ShortcutBinding]
    public private(set) var masterEnabled: Bool
    public var registeredCollisions: Set<ShortcutBinding>

    public init(bindings: [ShortcutCommand: ShortcutBinding] = [:], masterEnabled: Bool = true, registeredCollisions: Set<ShortcutBinding> = []) {
        self.bindings = bindings
        self.masterEnabled = masterEnabled
        self.registeredCollisions = registeredCollisions
    }

    public var activeBindings: [ShortcutCommand: ShortcutBinding] { masterEnabled ? bindings : [:] }

    public mutating func setMasterEnabled(_ enabled: Bool) { masterEnabled = enabled }

    public func validate(_ binding: ShortcutBinding, for command: ShortcutCommand, reserved: Set<ShortcutBinding> = Self.reservedSystemShortcuts) -> ShortcutBindingValidation {
        guard binding.key.rawValue <= 255 else { return .rejected(.invalidKey) }
        if case let .safeAction(id) = command, id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .rejected(.emptySafeAction) }
        if command.isGloballyEligible,
           binding.modifiers.intersection([.command, .option, .control, .function]).isEmpty {
            return .rejected(.requiresModifier)
        }
        if reserved.contains(binding) { return .rejected(.reservedSystemShortcut) }
        if registeredCollisions.contains(binding) { return .rejected(.registeredCollision) }
        if bindings.contains(where: { $0.key != command && $0.value == binding }) { return .rejected(.duplicateBinding) }
        return .valid
    }

    @discardableResult
    public mutating func setBinding(_ binding: ShortcutBinding, for command: ShortcutCommand, reserved: Set<ShortcutBinding> = Self.reservedSystemShortcuts) -> ShortcutBindingValidation {
        let result = validate(binding, for: command, reserved: reserved)
        guard case .valid = result else { return result }
        bindings[command] = binding
        return .valid
    }

    public mutating func removeBinding(for command: ShortcutCommand) { bindings.removeValue(forKey: command) }

    public static let reservedSystemShortcuts: Set<ShortcutBinding> = [
        ShortcutBinding(key: PhysicalKey.escape),
        ShortcutBinding(key: PhysicalKey.tab),
        ShortcutBinding(key: PhysicalKey(12), modifiers: [.command]), // Command-Q
        ShortcutBinding(key: PhysicalKey(13), modifiers: [.command]), // Command-W
        ShortcutBinding(key: PhysicalKey.tab, modifiers: [.command]),
        ShortcutBinding(key: PhysicalKey(48), modifiers: [.control]), // Control-Tab
        ShortcutBinding(key: PhysicalKey.space, modifiers: [.command]),
        ShortcutBinding(key: PhysicalKey.space, modifiers: [.control]),
        ShortcutBinding(key: PhysicalKey(53), modifiers: [.command, .option])
    ]
}

public struct ShortcutKeyEvent: Hashable, Sendable, Equatable {
    public enum Phase: String, Hashable, Sendable { case down, up }
    public let binding: ShortcutBinding
    public let phase: Phase
    public let isRepeat: Bool
    public let hasMarkedText: Bool

    public init(binding: ShortcutBinding, phase: Phase = .down, isRepeat: Bool = false, hasMarkedText: Bool = false) {
        self.binding = binding
        self.phase = phase
        self.isRepeat = isRepeat
        self.hasMarkedText = hasMarkedText
    }
}

/// Composition and repeat safety gate. Ordinary character shortcuts are not
/// consumed while marked text is active; a physical command/option shortcut
/// remains available for deliberate navigation. Key-down dispatch is one-shot
/// until a matching key-up, even when AppKit reports repeats.
public struct ShortcutInvocationGate: Sendable, Equatable {
    private var held: Set<ShortcutBinding> = []

    public init() {}

    public mutating func shouldInvoke(_ event: ShortcutKeyEvent) -> Bool {
        switch event.phase {
        case .up:
            // AppKit may omit a modifier from key-up after the modifier was
            // released first. Clear by physical key so a stale held binding
            // cannot suppress the next deliberate press.
            held = held.filter { $0.key != event.binding.key }
            return false
        case .down:
            guard !(event.hasMarkedText && event.binding.modifiers.isOrdinaryCharacterShortcut) else { return false }
            guard !event.isRepeat, !held.contains(event.binding) else { return false }
            held.insert(event.binding)
            return true
        }
    }

    public mutating func reset() { held.removeAll() }
}

public enum KeyboardFocusTarget: String, Codable, Hashable, Sendable, CaseIterable {
    case summary
    case session
    case inspect
    case showAll
    case collapse
    case settings
}

/// Bounded focus traversal over currently visible controls. Hidden rows are
/// omitted before traversal; reverse traversal follows the same visible list.
public struct KeyboardEngagementState: Codable, Hashable, Sendable, Equatable {
    public private(set) var engaged = false
    public private(set) var visibleTargets: [KeyboardFocusTarget] = []
    public private(set) var focusedTarget: KeyboardFocusTarget?

    public init() {}

    public mutating func engage(visibleTargets: [KeyboardFocusTarget]) {
        let visible = Self.unique(visibleTargets)
        self.visibleTargets = visible
        engaged = !visible.isEmpty
        focusedTarget = visible.first
    }

    public mutating func updateVisibleTargets(_ targets: [KeyboardFocusTarget]) {
        visibleTargets = Self.unique(targets)
        guard engaged else { return }
        if let focusedTarget, visibleTargets.contains(focusedTarget) { return }
        focusedTarget = visibleTargets.first
        if visibleTargets.isEmpty { engaged = false }
    }

    public mutating func moveForward() {
        move(offset: 1)
    }

    public mutating func moveBackward() {
        move(offset: -1)
    }

    public mutating func end() {
        engaged = false
        visibleTargets = []
        focusedTarget = nil
    }

    @discardableResult
    public mutating func handleEscape(localEditActive: Bool) -> Bool {
        guard !localEditActive else { return false }
        end()
        return true
    }

    private mutating func move(offset: Int) {
        guard engaged, !visibleTargets.isEmpty,
              let focusedTarget,
              let index = visibleTargets.firstIndex(of: focusedTarget)
        else { return }
        let next = index + offset
        guard visibleTargets.indices.contains(next) else { return }
        self.focusedTarget = visibleTargets[next]
    }

    private static func unique(_ targets: [KeyboardFocusTarget]) -> [KeyboardFocusTarget] {
        var seen: Set<KeyboardFocusTarget> = []
        return targets.filter { seen.insert($0).inserted }
    }
}

public struct AccessibilityAdaptation: Codable, Hashable, Sendable, Equatable {
    public let crossFadeDuration: TimeInterval
    public let usesOpaqueSurface: Bool
    public let usesStrongBoundaries: Bool
    public let compactOptionalMetadata: Bool

    public init(reduceMotion: Bool = false, reduceTransparency: Bool = false, increasedContrast: Bool = false, textScale: Double = 1) {
        crossFadeDuration = reduceMotion ? 0.15 : 0.36
        usesOpaqueSurface = reduceTransparency
        usesStrongBoundaries = increasedContrast
        compactOptionalMetadata = textScale > 1.15
    }
}

public enum ShortcutRegistrationStatus: Codable, Hashable, Sendable, Equatable {
    case disabled
    case active
    case unavailable(String)
}

/// Result returned by a native or fake registration backend. A backend must
/// distinguish an OS-owned collision from an unavailable/failed capability so
/// Settings can report the actual reason without fabricating active status.
public enum ShortcutRegistrationBackendResult: Codable, Hashable, Sendable, Equatable {
    case registered
    case collision(String)
    case unavailable(String)
    case failed(String)
}

/// The backend is deliberately tiny: Carbon owns registration and callback
/// delivery in the AppKit shell; tests can supply a deterministic fake without
/// requiring a login session, Accessibility permission, or Host input.
@MainActor
public protocol ShortcutRegistrationBackend: AnyObject {
    /// Readiness is observable even when the registry has no eligible global
    /// bindings, so Settings does not claim active capability on a failed OS
    /// event-handler installation.
    var readiness: ShortcutRegistrationStatus { get }

    func register(
        command: ShortcutCommand,
        binding: ShortcutBinding,
        handler: @escaping @MainActor @Sendable (ShortcutKeyEvent.Phase) -> Void
    ) -> ShortcutRegistrationBackendResult
    func unregister(command: ShortcutCommand)
}

public enum ShortcutRegistrationApplyResult: Codable, Hashable, Sendable, Equatable {
    case accepted(ShortcutRegistrationStatus)
    case rejected(ShortcutBindingValidationFailure, ShortcutRegistrationStatus, ShortcutBinding?)

    public var status: ShortcutRegistrationStatus {
        switch self {
        case let .accepted(status), let .rejected(_, status, _): status
        }
    }
}

/// Main-thread-owned transaction coordinator for native global bindings.
/// Registration is all-or-nothing: the old native set remains the durable
/// source of truth until every candidate registration succeeds. A failed
/// replacement is rolled back to the previous native set and never reaches
/// the settings repository.
@MainActor
public final class ShortcutRegistrationCoordinator {
    public typealias Invocation = @MainActor @Sendable (ShortcutCommand) -> Void

    private let backend: ShortcutRegistrationBackend
    private var callback: Invocation?
    private var gate = ShortcutInvocationGate()
    private(set) public var registeredBindings: [ShortcutCommand: ShortcutBinding] = [:]
    private(set) public var status: ShortcutRegistrationStatus = .unavailable("Native global registration has not been configured.")
    private(set) public var lastCollisionBinding: ShortcutBinding?

    public init(backend: ShortcutRegistrationBackend) {
        self.backend = backend
    }

    /// Applies one complete registry snapshot. Focused controls are omitted;
    /// explicitly configured safe actions may be registered, but their
    /// callback can only open the Guided workflow through the injected local
    /// route and never dispatches a Product action.
    public func apply(
        _ registry: ShortcutRegistry,
        invocation: @escaping Invocation
    ) -> ShortcutRegistrationApplyResult {
        callback = invocation
        lastCollisionBinding = nil
        let previous = registeredBindings

        if !registry.masterEnabled {
            unregisterAll()
            status = .disabled
            return .accepted(.disabled)
        }

        let candidates = registry.activeBindings
            .filter { $0.key.isGloballyEligible }
            .sorted { $0.key.identifier < $1.key.identifier }

        if candidates.isEmpty {
            unregisterAll()
            status = backend.readiness
            return .accepted(status)
        }
        if case let .unavailable(reason) = backend.readiness {
            status = .unavailable(reason)
            return .rejected(.registrationUnavailable, status, nil)
        }

        // A registry loaded from older data may contain an invalid global
        // binding. Reject before touching the currently active native set.
        var seenBindings: Set<ShortcutBinding> = []
        for (command, binding) in candidates {
            guard !ShortcutRegistry.reservedSystemShortcuts.contains(binding) else {
                status = .unavailable("\(binding.renderedLabel()) is reserved by macOS.")
                return .rejected(.reservedSystemShortcut, status, nil)
            }
            guard seenBindings.insert(binding).inserted else {
                status = .unavailable("Two global commands use \(binding.renderedLabel()).")
                return .rejected(.duplicateBinding, status, nil)
            }
            guard binding.modifiers.intersection([.command, .option, .control, .function]).isEmpty == false else {
                status = .unavailable("Global shortcut \(command.identifier) needs a deliberate modifier.")
                return .rejected(.requiresModifier, status, nil)
            }
        }

        unregisterAll()
        var registered: [ShortcutCommand: ShortcutBinding] = [:]
        for (command, binding) in candidates {
            let result = backend.register(command: command, binding: binding) { [weak self] phase in
                self?.receive(command: command, binding: binding, phase: phase)
            }
            switch result {
            case .registered:
                registered[command] = binding
            case let .collision(reason):
                registeredBindings = registered
                rollback(to: previous)
                lastCollisionBinding = binding
                status = .unavailable(reason.isEmpty ? "Another application owns \(binding.renderedLabel())." : reason)
                return .rejected(.registeredCollision, status, binding)
            case let .unavailable(reason):
                registeredBindings = registered
                rollback(to: previous)
                status = .unavailable(reason.isEmpty ? "Global registration is unavailable." : reason)
                return .rejected(.registrationUnavailable, status, nil)
            case let .failed(reason):
                registeredBindings = registered
                rollback(to: previous)
                status = .unavailable(reason.isEmpty ? "Global registration failed." : reason)
                return .rejected(.registrationFailed, status, nil)
            }
        }

        registeredBindings = registered
        gate.reset()
        status = .active
        return .accepted(.active)
    }

    public func unregisterAll() {
        Array(registeredBindings.keys).forEach { backend.unregister(command: $0) }
        registeredBindings.removeAll()
        gate.reset()
    }

    /// Withdraw one native binding while preserving every other successfully
    /// registered command. This is used when a capability-scoped source (such
    /// as Guided workflow) disconnects after local navigation remains live.
    public func unregister(command: ShortcutCommand) {
        guard registeredBindings.removeValue(forKey: command) != nil else { return }
        backend.unregister(command: command)
        gate.reset()
    }

    /// Carbon reports both pressed and released events. The shared gate makes
    /// held/repeated global events one-shot while still allowing the next
    /// physical press after key-up.
    private func receive(command: ShortcutCommand, binding: ShortcutBinding, phase: ShortcutKeyEvent.Phase) {
        guard registeredBindings[command] == binding else { return }
        let event = ShortcutKeyEvent(binding: binding, phase: phase)
        guard gate.shouldInvoke(event), phase == .down else { return }
        // The configured local Overlay callback receives both local
        // navigation and typed safe-action IDs. The callback owns the
        // Guided/lease boundary; this coordinator never dispatches a Product
        // action itself.
        callback?(command)
    }

    private func rollback(to previous: [ShortcutCommand: ShortcutBinding]) {
        registeredBindings.keys.forEach { backend.unregister(command: $0) }
        registeredBindings.removeAll()
        for (command, binding) in previous.sorted(by: { $0.key.identifier < $1.key.identifier }) {
            guard command.isGloballyEligible else { continue }
            let result = backend.register(command: command, binding: binding) { [weak self] phase in
                self?.receive(command: command, binding: binding, phase: phase)
            }
            if case .registered = result { registeredBindings[command] = binding }
        }
        gate.reset()
    }
}

/// Platform-neutral conversion used by the AppKit monitor and production
/// tests. `hasMarkedText` is supplied by the active NSTextInputClient rather
/// than inferred from characters, so ordinary composition is never consumed.
public enum ShortcutKeyEventMapper {
    public static func make(
        keyCode: UInt16,
        modifiers: ShortcutModifiers,
        phase: ShortcutKeyEvent.Phase,
        isRepeat: Bool,
        hasMarkedText: Bool
    ) -> ShortcutKeyEvent {
        ShortcutKeyEvent(
            binding: ShortcutBinding(key: PhysicalKey(keyCode), modifiers: modifiers),
            phase: phase,
            isRepeat: isRepeat,
            hasMarkedText: hasMarkedText
        )
    }
}

/// Keeps dynamic Attention announcements concise and one-shot. A higher
/// priority update may be announced once; ordinary redraws never repeat it.
public struct AccessibilityAnnouncementLedger: Codable, Hashable, Sendable, Equatable {
    private var announcedPriorityByID: [String: Int] = [:]

    public init() {}

    public mutating func announce(requestID: String, priority: Int, owner: String) -> String? {
        guard !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let previous = announcedPriorityByID[requestID], previous >= priority { return nil }
        announcedPriorityByID[requestID] = priority
        return "Attention Request from \(owner); priority \(priority)"
    }

    public mutating func reset() { announcedPriorityByID.removeAll() }
}

/// Keeps shortcut invocation feedback one-shot while the same result remains
/// visible in the Overlay. A new result can be announced immediately; clearing
/// on withdrawal prevents a stale accessibility element from reappearing when
/// a later Overlay surface is created.
public struct ShortcutInvocationAnnouncementLedger: Codable, Hashable, Sendable, Equatable {
    private var lastMessage: String?

    public init() {}

    public mutating func publish(_ message: String) -> String? {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != lastMessage else { return nil }
        lastMessage = normalized
        return normalized
    }

    public mutating func clear() { lastMessage = nil }
}
