import AppKit
import SwiftUI

@MainActor
final class OverlayPanel: NSPanel {
    var keyboardEngaged = false

    override var canBecomeKey: Bool { keyboardEngaged }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
}

@MainActor
class VisibleHitRegionView: NSView {
    var regions: [CGRect] = [] {
        didSet { updateTrackingAreas() }
    }
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var pointerIsInVisibleRegion = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsVisibleShape(point) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateVisiblePointerState(for: event)
    }

    override func mouseMoved(with event: NSEvent) { updateVisiblePointerState(for: event) }

    override func mouseExited(with event: NSEvent) {
        if pointerIsInVisibleRegion { exited?() }
        pointerIsInVisibleRegion = false
    }

    private func updateVisiblePointerState(for event: NSEvent) {
        let visible = containsVisibleShape(event.locationInWindow)
        guard visible != pointerIsInVisibleRegion else { return }
        pointerIsInVisibleRegion = visible
        visible ? entered?() : exited?()
    }

    private func containsVisibleShape(_ point: NSPoint) -> Bool {
        regions.contains {
            NSBezierPath(roundedRect: $0, xRadius: 22, yRadius: 22).contains(point)
        }
    }
}

@MainActor
final class OverlayContainerView: VisibleHitRegionView {
    private let hostingView: NSHostingView<OverlayContentView>

    init(rootView: OverlayContentView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        addSubview(hostingView)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { nil }

    func replace(rootView: OverlayContentView) {
        hostingView.rootView = rootView
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }
}
