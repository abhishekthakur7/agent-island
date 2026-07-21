import AppKit
import SwiftUI

@MainActor
final class IslandOverlayPanel: NSPanel {
    var keyboardEngaged = false

    override var canBecomeKey: Bool { keyboardEngaged }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        // AC-1.1-d: lock the panel to dark regardless of the system
        // appearance, so Light Mode / increased contrast can never invert
        // the opaque near-black surface into a system gray. Mirrors
        // agent-notch's window setup
        // (`/Users/abhishekthakur/Developer/agent-notch/main.swift:742`).
        appearance = NSAppearance(named: .darkAqua)
        // A panel belongs to the current Space only. In particular, do not add
        // canJoinAllSpaces/fullScreenAuxiliary: an Island Overlay never tracks
        // or crosses Spaces as though they were a durable Host identity.
        collectionBehavior = [.ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
    }
}

@MainActor
class IslandVisibleRegionView: NSView {
    var regions: [CGRect] = [] { didSet { updateTrackingAreas() } }
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var pointerIsVisible = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsVisibleShape(point) ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) { updatePointer(for: event) }
    override func mouseMoved(with event: NSEvent) { updatePointer(for: event) }
    override func mouseExited(with event: NSEvent) {
        if pointerIsVisible { exited?() }
        pointerIsVisible = false
    }

    private func updatePointer(for event: NSEvent) {
        let visible = containsVisibleShape(event.locationInWindow)
        guard visible != pointerIsVisible else { return }
        pointerIsVisible = visible
        visible ? entered?() : exited?()
    }

    nonisolated override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        // AppKit invokes this synchronous accessibility override on its main
        // thread. State is main-actor-owned everywhere else in this view.
        let result: UnsafeAccessibilityResult = MainActor.assumeIsolated {
            // Accessibility uses screen coordinates; its target must agree
            // with normal hit testing, including the protected notch gap.
            let localPoint = self.convert(point, from: nil)
            guard self.containsVisibleShape(localPoint) else { return UnsafeAccessibilityResult(nil) }
            return UnsafeAccessibilityResult(super.accessibilityHitTest(point))
        }
        return result.value
    }

    func containsVisibleShape(_ point: NSPoint) -> Bool {
        regions.contains { NSBezierPath(roundedRect: $0, xRadius: 18, yRadius: 18).contains(point) }
    }
}

/// AppKit's Objective-C accessibility result is intentionally untyped; this
/// box only bridges that result through a synchronous main-actor assertion.
private final class UnsafeAccessibilityResult: @unchecked Sendable {
    let value: Any?
    init(_ value: Any?) { self.value = value }
}

@MainActor
final class IslandOverlayContainerView: IslandVisibleRegionView {
    private let hostingView: NSHostingView<IslandOverlayView>

    init(rootView: IslandOverlayView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        addSubview(hostingView)
        // The hosted visible controls are the AX elements. Do not add an
        // aggregate container whose frame would span a built-in notch gap.
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    func replace(rootView: IslandOverlayView) { hostingView.rootView = rootView }
    override func layout() { super.layout(); hostingView.frame = bounds }
}
