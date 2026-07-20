import XCTest
@testable import SessionDomain

final class ShortcutModelsTests: XCTestCase {
    func testPhysicalBindingRendersCurrentInputSourceEquivalent() {
        let binding = ShortcutBinding(key: PhysicalKey(12), modifiers: [.command, .option])
        let source = ShortcutInputSource(identifier: "azerty", localizedName: "French", keyCodeLabels: [12: "A"])
        XCTAssertEqual(binding.renderedLabel(inputSource: source), "⌥⌘A")
    }

    func testRegistryRejectsDuplicatesReservedAndRegisteredCollisionsWithoutReplacingPriorBinding() {
        let first = ShortcutBinding(key: PhysicalKey(0), modifiers: [.option])
        let duplicate = ShortcutBinding(key: PhysicalKey(1), modifiers: [.option])
        let reserved = ShortcutBinding(key: PhysicalKey.space, modifiers: [.command])
        let collision = ShortcutBinding(key: PhysicalKey(2), modifiers: [.option])
        var registry = ShortcutRegistry(registeredCollisions: [collision])

        XCTAssertEqual(registry.setBinding(first, for: .toggleOverlay), .valid)
        XCTAssertEqual(registry.setBinding(first, for: .nextSession), .rejected(.duplicateBinding))
        XCTAssertEqual(registry.setBinding(reserved, for: .showAll), .rejected(.reservedSystemShortcut))
        XCTAssertEqual(registry.setBinding(collision, for: .inspect), .rejected(.registeredCollision))
        XCTAssertEqual(registry.bindings[.toggleOverlay], first)
        XCTAssertNil(registry.bindings[.showAll])
    }

    func testMasterDisableRemovesActiveRegistrationsButPreservesMappings() {
        let binding = ShortcutBinding(key: PhysicalKey(0), modifiers: [.option])
        var registry = ShortcutRegistry()
        XCTAssertEqual(registry.setBinding(binding, for: .toggleOverlay), .valid)
        registry.setMasterEnabled(false)
        XCTAssertTrue(registry.activeBindings.isEmpty)
        XCTAssertEqual(registry.bindings[.toggleOverlay], binding)
        registry.setMasterEnabled(true)
        XCTAssertEqual(registry.activeBindings[.toggleOverlay], binding)
    }

    func testSafeActionShortcutCannotCreateParallelProductDispatchPath() {
        XCTAssertEqual(ShortcutCommand.inspect.dispatchDisposition, .localOverlayNavigation)
        XCTAssertEqual(ShortcutCommand.safeAction("answer").dispatchDisposition, .guidedWorkflowAction)
    }

    func testMarkedCompositionBlocksOrdinaryCharactersAndRepeatDispatchesOnce() {
        let ordinary = ShortcutKeyEvent(binding: ShortcutBinding(key: PhysicalKey(0)), hasMarkedText: true)
        var gate = ShortcutInvocationGate()
        XCTAssertFalse(gate.shouldInvoke(ordinary))

        let deliberate = ShortcutKeyEvent(binding: ShortcutBinding(key: PhysicalKey(0), modifiers: [.option]), hasMarkedText: true)
        XCTAssertTrue(gate.shouldInvoke(deliberate))
        XCTAssertFalse(gate.shouldInvoke(ShortcutKeyEvent(binding: deliberate.binding, isRepeat: true)))
        XCTAssertFalse(gate.shouldInvoke(ShortcutKeyEvent(binding: deliberate.binding, phase: .up)))
        XCTAssertTrue(gate.shouldInvoke(deliberate))
    }

    func testBoundedFocusExcludesHiddenTargetsAndEscapeCancelsEditBeforeEnding() {
        var focus = KeyboardEngagementState()
        focus.engage(visibleTargets: [.summary, .session, .collapse])
        XCTAssertEqual(focus.focusedTarget, .summary)
        focus.moveForward()
        XCTAssertEqual(focus.focusedTarget, .session)
        focus.moveBackward()
        XCTAssertEqual(focus.focusedTarget, .summary)
        XCTAssertFalse(focus.handleEscape(localEditActive: true))
        XCTAssertTrue(focus.engaged)
        XCTAssertTrue(focus.handleEscape(localEditActive: false))
        XCTAssertFalse(focus.engaged)
    }

    func testAdaptationsAndOneShotAttentionAnnouncements() {
        let adaptation = AccessibilityAdaptation(reduceMotion: true, reduceTransparency: true, increasedContrast: true, textScale: 1.3)
        XCTAssertEqual(adaptation.crossFadeDuration, 0.15)
        XCTAssertTrue(adaptation.usesOpaqueSurface)
        XCTAssertTrue(adaptation.usesStrongBoundaries)
        XCTAssertTrue(adaptation.compactOptionalMetadata)

        var ledger = AccessibilityAnnouncementLedger()
        XCTAssertNotNil(ledger.announce(requestID: "request-1", priority: 2, owner: "Claude Code / Session 1"))
        XCTAssertNil(ledger.announce(requestID: "request-1", priority: 2, owner: "Claude Code / Session 1"))
        XCTAssertNotNil(ledger.announce(requestID: "request-1", priority: 3, owner: "Claude Code / Session 1"))
    }
}
