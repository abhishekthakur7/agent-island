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

enum IslandDisplayAvailability: String, Codable, Equatable {
    case available
    case selectionUnavailable
    case needsRevalidation
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
    case displayRevalidated(available: Bool)
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
    var displayAvailability: IslandDisplayAvailability = .selectionUnavailable
    var transitionRevision: UInt64 = 0

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
            state.displayAvailability = available ? .available : .selectionUnavailable
            state.transitionRevision &+= 1

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
            state.displayAvailability = .selectionUnavailable
            state.transitionRevision &+= 1

        case .displayReconnected:
            state.selectedDisplayAvailable = true
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.presentation = state.quietSceneSuppressed ? .withdrawn : .collapsed
            state.displayAvailability = .available
            state.transitionRevision &+= 1

        case let .displayRevalidated(available):
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.selectedDisplayAvailable = available
            state.displayAvailability = available ? .available : .needsRevalidation
            state.presentation = available && !state.quietSceneSuppressed ? .collapsed : .withdrawn
            state.transitionRevision &+= 1

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
            state.displayAvailability = .selectionUnavailable
            state.transitionRevision &+= 1
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

    /// Physical-notch geometry for a built-in display, in global screen
    /// coordinates. `gap` is the real notch width (the span between the two
    /// auxiliary menu-bar areas that flank it); `physicalFrame` is
    /// `NSScreen.frame` — the whole display including the menu-bar band that
    /// `visibleFrame` excludes. Only the collapsed pill uses this: it must sit
    /// at the physical top and straddle the notch, not float below the menu
    /// bar where a `visibleFrame` anchor puts it.
    struct NotchMetrics: Equatable {
        let physicalFrame: CGRect
        let gap: CGFloat
    }

    static func make(for screen: NSScreen, presentation: IslandOverlayPresentation, settings: AtlasDisplayPreferences = .default, shortcutAnnouncement: String? = nil) -> IslandOverlayGeometry {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let isBuiltIn = CGDisplayIsBuiltin(CGDirectDisplayID(number)) != 0
        return make(
            usableFrame: screen.visibleFrame,
            isBuiltIn: isBuiltIn,
            presentation: presentation,
            settings: settings,
            shortcutAnnouncement: shortcutAnnouncement,
            notch: notchMetrics(for: screen, isBuiltIn: isBuiltIn)
        )
    }

    /// The physical notch, or `nil` when the display has none (external, or a
    /// built-in without a notch). `safeAreaInsets.top > 0` detects a notch;
    /// the auxiliary top areas measure its width. Both are macOS 12+.
    static func notchMetrics(for screen: NSScreen, isBuiltIn: Bool) -> NotchMetrics? {
        guard isBuiltIn, screen.safeAreaInsets.top > 0 else { return nil }
        let gap: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            gap = max(0, right.minX - left.maxX)
        } else {
            // A notch is present (safe-area inset > 0) but the auxiliary areas
            // are unavailable — fall back to a typical MacBook notch width
            // rather than dropping the notch layout entirely.
            gap = 200
        }
        guard gap > 0 else { return nil }
        return NotchMetrics(physicalFrame: screen.frame, gap: gap)
    }

    static func make(usableFrame: CGRect, isBuiltIn: Bool, presentation: IslandOverlayPresentation, settings: AtlasDisplayPreferences = .default, shortcutAnnouncement: String? = nil, notch: NotchMetrics? = nil) -> IslandOverlayGeometry {
        let expanded = presentation == .expanded || presentation == .focused
        let normalized = settings.normalized()
        let scale = normalized.contentSize.scale

        // Built-in NOTCHED display: anchor to the physical screen top so the
        // wings flank the real notch instead of floating below the menu bar
        // (which a `visibleFrame` anchor causes). BOTH collapsed and expanded
        // share this physical-top anchor + notch center, so a hover-expand
        // grows the panel *in place* rather than jumping to a different
        // position — a mismatch would move the panel out from under the cursor
        // and cause an expand/collapse flicker. `notch` is only ever non-nil
        // from `make(for:)` on a real notched screen, so every existing
        // caller/test that omits it keeps the exact prior behavior.
        if let notch, isBuiltIn {
            return expanded
                ? makeExpandedNotch(notch: notch, scale: scale, settings: normalized)
                : makeCollapsedNotch(notch: notch, scale: scale, settings: normalized, shortcutAnnouncement: shortcutAnnouncement)
        }

        // Expanded presentation reserves deterministic room for a sourced
        // completion card while still respecting the user's maximum panel
        // height. The card height therefore changes real live geometry.
        let completionDrivenHeight = normalized.completionCardHeight + (120 * scale)
        let announcementHeight = shortcutAnnouncement == nil ? 0 : 42 * scale
        let desired = CGSize(
            width: expanded ? normalized.maximumPanelWidth : min(normalized.maximumPanelWidth, 350 * scale),
            height: expanded
                ? min(normalized.maximumPanelHeight, max(320 * scale, completionDrivenHeight))
                : min(normalized.maximumPanelHeight, max(56 * scale, 56 * scale + announcementHeight))
        )
        let safe = usableFrame.insetBy(dx: 12, dy: 6)
        // Even unusually small visible frames win over readability minima:
        // the Overlay must never cross the current safe bounds.
        let size = CGSize(width: min(desired.width, max(1, safe.width)), height: min(desired.height, max(1, safe.height)))
        let frame = CGRect(x: safe.midX - size.width / 2, y: safe.maxY - size.height, width: size.width, height: size.height).integral

        guard isBuiltIn else {
            return IslandOverlayGeometry(frame: frame, hitRegions: [CGRect(origin: .zero, size: size)], isBuiltIn: false, protectedGap: 0)
        }
        let gap = min(size.width, min(136, max(32, size.width - 160)))
        let wingWidth = (size.width - gap) / 2
        return IslandOverlayGeometry(
            frame: frame,
            hitRegions: [CGRect(x: 0, y: 0, width: wingWidth, height: size.height), CGRect(x: wingWidth + gap, y: 0, width: wingWidth, height: size.height)],
            isBuiltIn: true,
            protectedGap: gap
        )
    }

    /// Collapsed notch layout: a pill pinned to the physical top, split into
    /// two content wings that flank the notch `gap` (which aligns with the
    /// horizontally-centered physical notch). The collapsed view's flaps fill
    /// each wing (`maxWidth: .infinity`), so a generous wing width is what
    /// stops the agent name / "N Sessions" from truncating.
    private static func makeCollapsedNotch(notch: NotchMetrics, scale: CGFloat, settings: AtlasDisplayPreferences, shortcutAnnouncement: String?) -> IslandOverlayGeometry {
        let announcementHeight = shortcutAnnouncement == nil ? 0 : 42 * scale
        let height = min(settings.maximumPanelHeight, max(56 * scale, 56 * scale + announcementHeight))
        let desiredWing = 200 * scale
        return notchFrame(notch: notch, height: height, minWing: desiredWing, maxWing: desiredWing)
    }

    /// Expanded notch layout: shares the collapsed pill's physical-top anchor
    /// and notch center so a hover-expand grows in place (no jump → no
    /// flicker), unfolding out of the notch. The two content panels (session
    /// surface + header) flank the notch gap, which aligns with the physical
    /// notch — so nothing renders behind it. Wings get real room for the
    /// session list; total width still never exceeds the display.
    private static func makeExpandedNotch(notch: NotchMetrics, scale: CGFloat, settings: AtlasDisplayPreferences) -> IslandOverlayGeometry {
        let completionDrivenHeight = settings.completionCardHeight + (120 * scale)
        let height = min(settings.maximumPanelHeight, max(320 * scale, completionDrivenHeight))
        // Each wing wants at least the session list's readable width; honor the
        // person's maximum-panel-width preference as a floor for the total too.
        let minWing = max(300 * scale, (settings.maximumPanelWidth - notch.gap) / 2)
        return notchFrame(notch: notch, height: height, minWing: minWing, maxWing: minWing)
    }

    /// Shared physical-top, notch-centered frame + two flanking wing hit
    /// regions. `minWing`/`maxWing` bound each wing's width; the whole pill is
    /// `gap + 2 * wing`, clamped to the display (small side margins) and
    /// centered on the notch.
    private static func notchFrame(notch: NotchMetrics, height: CGFloat, minWing: CGFloat, maxWing: CGFloat) -> IslandOverlayGeometry {
        let gap = notch.gap
        let maxTotal = max(gap + 2, notch.physicalFrame.width - 24)
        let wing = min(maxWing, max(minWing, (maxTotal - gap) / 2))
        let width = min(maxTotal, gap + 2 * wing)
        let x = notch.physicalFrame.midX - width / 2
        let y = notch.physicalFrame.maxY - height
        let frame = CGRect(x: x, y: y, width: width, height: height).integral
        let wingWidth = max(1, (frame.width - gap) / 2)
        return IslandOverlayGeometry(
            frame: frame,
            hitRegions: [
                CGRect(x: 0, y: 0, width: wingWidth, height: frame.height),
                CGRect(x: wingWidth + gap, y: 0, width: wingWidth, height: frame.height)
            ],
            isBuiltIn: true,
            protectedGap: gap
        )
    }
}
