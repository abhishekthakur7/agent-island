import AppKit

/// The overlay lifecycle is deliberately a small pure reducer. AppKit only
/// renders its result, so display loss, quiet scenes, sleep, and termination
/// cannot leave a panel, hit target, or keyboard lease behind by accident.
enum IslandOverlayPresentation: Equatable {
    case withdrawn
    case collapsed
    case focused
    case expanded
}

enum IslandOverlayEvent {
    case launch(displayAvailable: Bool)
    case automaticReveal
    case hoverEntered
    case hoverExited
    case setInteractionGuard(Bool)
    case collapse
    case engageKeyboard
    case releaseKeyboard
    case displayLost
    case displayReconnected
    case setQuietSceneSuppressed(Bool)
    case sleep
    case wake(displayAvailable: Bool)
    case terminate
}

struct IslandOverlayState: Equatable {
    var presentation: IslandOverlayPresentation = .withdrawn
    var keyboardEngaged = false
    var interactionGuard = false
    var selectedDisplayAvailable = false
    var quietSceneSuppressed = false
    var terminated = false

    /// The visible silhouette is the only place this state permits both input
    /// and accessibility. `withdrawn` always means neither exists.
    var hasVisibleRegions: Bool { presentation != .withdrawn && !terminated }
}

struct IslandOverlayStateMachine {
    private(set) var state = IslandOverlayState()

    mutating func reduce(_ event: IslandOverlayEvent) {
        guard !state.terminated || { if case .terminate = event { return true }; return false }() else { return }

        switch event {
        case let .launch(available), let .wake(available):
            state.terminated = false
            state.selectedDisplayAvailable = available
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.presentation = available && !state.quietSceneSuppressed ? .collapsed : .withdrawn

        case .automaticReveal:
            guard state.selectedDisplayAvailable, !state.quietSceneSuppressed else { return }
            state.presentation = .focused

        case .hoverEntered:
            guard state.selectedDisplayAvailable, !state.quietSceneSuppressed else { return }
            state.presentation = .expanded

        case .hoverExited:
            guard !state.interactionGuard, !state.keyboardEngaged else { return }
            state.presentation = state.selectedDisplayAvailable && !state.quietSceneSuppressed ? .collapsed : .withdrawn

        case let .setInteractionGuard(guarded):
            state.interactionGuard = guarded

        case .collapse:
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.presentation = state.selectedDisplayAvailable && !state.quietSceneSuppressed ? .collapsed : .withdrawn

        case .engageKeyboard:
            guard state.selectedDisplayAvailable, !state.quietSceneSuppressed else { return }
            state.presentation = .expanded
            state.keyboardEngaged = true

        case .releaseKeyboard:
            state.keyboardEngaged = false

        case .displayLost, .sleep:
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.selectedDisplayAvailable = false
            state.presentation = .withdrawn

        case .displayReconnected:
            state.selectedDisplayAvailable = true
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.presentation = state.quietSceneSuppressed ? .withdrawn : .collapsed

        case let .setQuietSceneSuppressed(suppressed):
            state.quietSceneSuppressed = suppressed
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.presentation = state.selectedDisplayAvailable && !suppressed ? .collapsed : .withdrawn

        case .terminate:
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.presentation = .withdrawn
            state.terminated = true
        }
    }
}

struct IslandDisplay: Identifiable, Hashable {
    /// A CoreGraphics UUID remains stable when macOS renumbers displays.
    let id: String
    let displayNumber: UInt32
    let name: String
    let isBuiltIn: Bool

    init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let id = Self.identity(for: CGDirectDisplayID(number.uint32Value)) else { return nil }
        self.id = id
        displayNumber = number.uint32Value
        isBuiltIn = CGDisplayIsBuiltin(CGDirectDisplayID(displayNumber)) != 0
        name = isBuiltIn ? "\(screen.localizedName) (Built-in)" : screen.localizedName
    }

    static func identity(for displayID: CGDirectDisplayID) -> String? {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        return CFUUIDCreateString(nil, unmanaged.takeRetainedValue()) as String
    }
}

struct IslandOverlayGeometry: Equatable {
    let frame: CGRect
    /// Coordinates are local to `frame`; these are also the exact permitted
    /// AppKit hit regions. The protected notch reserve is intentionally absent.
    let hitRegions: [CGRect]
    let isBuiltIn: Bool
    let protectedGap: CGFloat

    static func make(for screen: NSScreen, presentation: IslandOverlayPresentation) -> IslandOverlayGeometry {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return make(usableFrame: screen.visibleFrame, isBuiltIn: CGDisplayIsBuiltin(CGDirectDisplayID(number)) != 0, presentation: presentation)
    }

    static func make(usableFrame: CGRect, isBuiltIn: Bool, presentation: IslandOverlayPresentation) -> IslandOverlayGeometry {
        let expanded = presentation == .expanded || presentation == .focused
        let desired = CGSize(width: expanded ? 820 : 350, height: expanded ? 500 : 56)
        let safe = usableFrame.insetBy(dx: 12, dy: 6)
        let size = CGSize(width: min(desired.width, max(180, safe.width)), height: min(desired.height, max(56, safe.height)))
        let frame = CGRect(x: safe.midX - size.width / 2, y: safe.maxY - size.height, width: size.width, height: size.height).integral

        guard isBuiltIn else {
            return IslandOverlayGeometry(frame: frame, hitRegions: [CGRect(origin: .zero, size: size)], isBuiltIn: false, protectedGap: 0)
        }
        let gap = min(136, max(32, size.width - 160))
        let wingWidth = (size.width - gap) / 2
        return IslandOverlayGeometry(
            frame: frame,
            hitRegions: [CGRect(x: 0, y: 0, width: wingWidth, height: size.height), CGRect(x: wingWidth + gap, y: 0, width: wingWidth, height: size.height)],
            isBuiltIn: true,
            protectedGap: gap
        )
    }
}
