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

/// Commands intentionally stop at local Overlay/session navigation and
/// explicitly configured safe actions. Product-specific action integrations
/// remain behind Guided workflow and Action Lease ports in later tickets.
public enum ShortcutCommand: Codable, Hashable, Sendable, Equatable {
    case toggleOverlay
    case nextSession
    case previousSession
    case showAll
    case collapse
    case inspect
    case safeAction(String)

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
            held.remove(event.binding)
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
