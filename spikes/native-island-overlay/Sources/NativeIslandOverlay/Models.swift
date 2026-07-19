import AppKit
import SwiftUI

enum OverlayPresentation: String {
    case withdrawn
    case collapsed
    case focused
    case expanded
}

/// Pure lifecycle reducer used by the fixture and its headless checks. Product
/// actions, adapters, stored preferences, and Host focus are intentionally out of scope.
enum OverlayLifecycleEvent {
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
    case setFullscreenSuppressed(Bool)
    case sleep
    case wake(displayAvailable: Bool)
    case terminate
}

struct OverlayLifecycleState: Equatable {
    var presentation: OverlayPresentation = .withdrawn
    var keyboardEngaged = false
    var interactionGuard = false
    var selectedDisplayAvailable = false
    var fullscreenSuppressed = false
    var terminated = false

    var hasVisibleHitRegions: Bool { presentation != .withdrawn && !terminated }
    var hasVisibleAccessibilityRegions: Bool { hasVisibleHitRegions }
}

struct OverlayStateMachine {
    private(set) var state = OverlayLifecycleState()

    mutating func reduce(_ event: OverlayLifecycleEvent) {
        guard !state.terminated || { if case .terminate = event { return true }; return false }() else { return }
        switch event {
        case let .launch(available), let .wake(available):
            state.terminated = false
            state.selectedDisplayAvailable = available
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.presentation = available && !state.fullscreenSuppressed ? .collapsed : .withdrawn
        case .automaticReveal:
            guard state.selectedDisplayAvailable, !state.fullscreenSuppressed else { return }
            state.presentation = .focused
        case .hoverEntered:
            guard state.selectedDisplayAvailable, !state.fullscreenSuppressed else { return }
            state.presentation = .expanded
        case .hoverExited:
            guard !state.interactionGuard, !state.keyboardEngaged else { return }
            if state.selectedDisplayAvailable, !state.fullscreenSuppressed { state.presentation = .collapsed }
        case let .setInteractionGuard(value): state.interactionGuard = value
        case .collapse:
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.presentation = state.selectedDisplayAvailable && !state.fullscreenSuppressed ? .collapsed : .withdrawn
        case .engageKeyboard:
            guard state.selectedDisplayAvailable, !state.fullscreenSuppressed else { return }
            state.presentation = .expanded
            state.keyboardEngaged = true
        case .releaseKeyboard: state.keyboardEngaged = false
        case .displayLost, .sleep:
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.selectedDisplayAvailable = false
            state.presentation = .withdrawn
        case .displayReconnected:
            state.selectedDisplayAvailable = true
            state.keyboardEngaged = false
            state.interactionGuard = false
            state.presentation = state.fullscreenSuppressed ? .withdrawn : .collapsed
        case let .setFullscreenSuppressed(suppressed):
            state.fullscreenSuppressed = suppressed
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

enum SessionState: String, CaseIterable, Identifiable {
    case working = "Working"
    case attention = "Needs attention"
    case complete = "Completed"
    case waiting = "Waiting"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .working: .cyan
        case .attention: .orange
        case .complete: .green
        case .waiting: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .working: "sparkles"
        case .attention: "exclamationmark.circle.fill"
        case .complete: "checkmark.circle.fill"
        case .waiting: "pause.circle"
        }
    }
}

struct FixtureSession: Identifiable, Hashable {
    let id: UUID
    let title: String
    let project: String
    let product: String
    let host: String
    let state: SessionState
    let elapsed: String
    let childRuns: Int

    static let samples: [FixtureSession] = {
        let projects = ["Agent Island", "Northstar", "Paper Trail", "Horizon", "Canopy"]
        let tasks = [
            "Reconcile display placement", "Review migration plan", "Implement settings preview",
            "Trace attention routing", "Build accessibility audit", "Investigate reconnect", 
            "Prepare release notes", "Validate session reducer", "Review pull request", "Measure idle energy"
        ]
        let states: [SessionState] = [.attention, .working, .working, .complete, .waiting]
        return (0..<30).map { index in
            FixtureSession(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                title: tasks[index % tasks.count],
                project: projects[index % projects.count],
                product: index.isMultiple(of: 3) ? "Codex" : (index.isMultiple(of: 2) ? "Claude Code" : "Cursor"),
                host: index.isMultiple(of: 2) ? "iTerm" : "Cursor",
                state: states[index % states.count],
                elapsed: index < 2 ? "now" : "\(index * 3)m ago",
                childRuns: index.isMultiple(of: 4) ? (index % 3) + 1 : 0
            )
        }
    }()
}

struct DisplayOption: Identifiable, Hashable {
    /// CoreGraphics UUID is stable across screen-number/arrangement changes and
    /// can be revalidated if this selected display disconnects and returns.
    let id: String
    let displayNumber: UInt32
    let name: String
    let isBuiltIn: Bool

    init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        displayNumber = number.uint32Value
        guard let stableIdentity = Self.identity(for: CGDirectDisplayID(displayNumber)) else { return nil }
        id = stableIdentity
        isBuiltIn = CGDisplayIsBuiltin(CGDirectDisplayID(displayNumber)) != 0
        let label = screen.localizedName.isEmpty ? "Display \(id)" : screen.localizedName
        name = isBuiltIn ? "\(label) (Built-in)" : label
    }

    static func identity(for displayID: CGDirectDisplayID) -> String? {
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        let uuid = unmanagedUUID.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }
}

struct OverlayGeometry: Equatable {
    let frame: CGRect
    let hitRegions: [CGRect]
    let isBuiltIn: Bool
    let protectedGap: CGFloat

    static func make(for screen: NSScreen, presentation: OverlayPresentation) -> OverlayGeometry {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return make(usableFrame: screen.visibleFrame, isBuiltIn: CGDisplayIsBuiltin(CGDirectDisplayID(number)) != 0, presentation: presentation)
    }

    /// Frame-independent helper keeps geometry verification runnable without a display server.
    static func make(usableFrame: CGRect, isBuiltIn: Bool, presentation: OverlayPresentation) -> OverlayGeometry {
        let expanded = presentation == .expanded || presentation == .focused
        let desiredHeight: CGFloat = expanded ? 500 : 56
        let desiredWidth: CGFloat = expanded ? 820 : 350
        // visibleFrame is the usable top-edge frame. Clamp before creating either pixels or hit regions.
        let usable = usableFrame.insetBy(dx: 12, dy: 6)
        let height = min(desiredHeight, max(56, usable.height))
        let width = min(desiredWidth, max(180, usable.width))
        let frame = CGRect(
            x: usable.midX - width / 2,
            y: usable.maxY - height,
            width: width,
            height: height
        ).integral

        guard isBuiltIn else {
            return OverlayGeometry(frame: frame, hitRegions: [CGRect(origin: .zero, size: frame.size)], isBuiltIn: false, protectedGap: 0)
        }

        // The 136 point reserve is a maximum visual/notch reserve; never a transparent hit bridge.
        let gap = min(136, max(32, width - 160))
        let wingWidth = (width - gap) / 2
        let left = CGRect(x: 0, y: 0, width: wingWidth, height: height)
        let right = CGRect(x: wingWidth + gap, y: 0, width: wingWidth, height: height)
        return OverlayGeometry(frame: frame, hitRegions: [left, right], isBuiltIn: true, protectedGap: gap)
    }
}
