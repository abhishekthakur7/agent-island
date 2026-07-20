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
        XCTAssertFalse(gate.shouldInvoke(ShortcutKeyEvent(binding: ShortcutBinding(key: deliberate.binding.key), phase: .up)))
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

@MainActor
final class ShortcutRegistrationCoordinatorTests: XCTestCase {
    private final class FakeBackend: ShortcutRegistrationBackend {
        var readiness: ShortcutRegistrationStatus = .active
        var outcomes: [ShortcutBinding: ShortcutRegistrationBackendResult] = [:]
        var handlers: [ShortcutCommand: (ShortcutKeyEvent.Phase) -> Void] = [:]
        var registered: [ShortcutCommand: ShortcutBinding] = [:]
        var unregistered: [ShortcutCommand] = []

        func register(
            command: ShortcutCommand,
            binding: ShortcutBinding,
            handler: @escaping @MainActor @Sendable (ShortcutKeyEvent.Phase) -> Void
        ) -> ShortcutRegistrationBackendResult {
            let result = outcomes[binding] ?? .registered
            if case .registered = result {
                registered[command] = binding
                handlers[command] = handler
            }
            return result
        }

        func unregister(command: ShortcutCommand) {
            registered.removeValue(forKey: command)
            handlers.removeValue(forKey: command)
            unregistered.append(command)
        }

        func emit(_ command: ShortcutCommand, phase: ShortcutKeyEvent.Phase) {
            handlers[command]?(phase)
        }
    }

    func testAtomicCollisionRollbackRetainsPriorRegistrationAndMapping() {
        let backend = FakeBackend()
        let coordinator = ShortcutRegistrationCoordinator(backend: backend)
        let oldBinding = ShortcutBinding(key: PhysicalKey(0), modifiers: [.option])
        let replacement = ShortcutBinding(key: PhysicalKey(1), modifiers: [.option])
        var oldRegistry = ShortcutRegistry()
        XCTAssertEqual(oldRegistry.setBinding(oldBinding, for: .toggleOverlay), .valid)
        XCTAssertEqual(coordinator.apply(oldRegistry, invocation: { _ in }).status, .active)

        backend.outcomes[replacement] = .collision("OS-owned collision")
        var candidate = oldRegistry
        XCTAssertEqual(candidate.setBinding(replacement, for: .toggleOverlay), .valid)
        let result = coordinator.apply(candidate, invocation: { _ in })
        XCTAssertEqual(result, .rejected(.registeredCollision, .unavailable("OS-owned collision"), replacement))
        XCTAssertEqual(coordinator.registeredBindings[.toggleOverlay], oldBinding)
        XCTAssertEqual(backend.registered[.toggleOverlay], oldBinding)
    }

    func testAtomicRollbackUnregistersEarlierCandidateRegistrations() {
        let backend = FakeBackend()
        let coordinator = ShortcutRegistrationCoordinator(backend: backend)
        let oldBinding = ShortcutBinding(key: PhysicalKey(0), modifiers: [.option])
        let nextBinding = ShortcutBinding(key: PhysicalKey(1), modifiers: [.option])
        let replacement = ShortcutBinding(key: PhysicalKey(2), modifiers: [.option])
        var oldRegistry = ShortcutRegistry()
        XCTAssertEqual(oldRegistry.setBinding(oldBinding, for: .toggleOverlay), .valid)
        XCTAssertEqual(coordinator.apply(oldRegistry, invocation: { _ in }).status, .active)

        var candidate = oldRegistry
        XCTAssertEqual(candidate.setBinding(nextBinding, for: .nextSession), .valid)
        XCTAssertEqual(candidate.setBinding(replacement, for: .toggleOverlay), .valid)
        backend.outcomes[replacement] = .collision("OS-owned collision")
        XCTAssertEqual(coordinator.apply(candidate, invocation: { _ in }).status, .unavailable("OS-owned collision"))
        XCTAssertNil(backend.registered[.nextSession])
        XCTAssertEqual(backend.registered[.toggleOverlay], oldBinding)
    }

    func testMasterDisableUnregistersOnlyNativeSetAndCallbackIsAtMostOnce() {
        let backend = FakeBackend()
        let coordinator = ShortcutRegistrationCoordinator(backend: backend)
        let binding = ShortcutBinding(key: PhysicalKey(0), modifiers: [.option])
        var registry = ShortcutRegistry()
        XCTAssertEqual(registry.setBinding(binding, for: .toggleOverlay), .valid)
        var invocations = 0
        XCTAssertEqual(coordinator.apply(registry, invocation: { _ in invocations += 1 }), .accepted(.active))
        backend.emit(.toggleOverlay, phase: .down)
        backend.emit(.toggleOverlay, phase: .down)
        XCTAssertEqual(invocations, 1)
        backend.emit(.toggleOverlay, phase: .up)
        backend.emit(.toggleOverlay, phase: .down)
        XCTAssertEqual(invocations, 2)

        registry.setMasterEnabled(false)
        XCTAssertEqual(coordinator.apply(registry, invocation: { _ in }), .accepted(.disabled))
        XCTAssertTrue(coordinator.registeredBindings.isEmpty)
        XCTAssertEqual(registry.bindings[.toggleOverlay], binding)
    }

    func testFocusedAndSafeActionCommandsNeverReachGlobalBackend() {
        let backend = FakeBackend()
        let coordinator = ShortcutRegistrationCoordinator(backend: backend)
        var registry = ShortcutRegistry()
        XCTAssertEqual(registry.setBinding(ShortcutBinding(key: PhysicalKey(2)), for: .safeAction("answer")), .valid)
        XCTAssertEqual(registry.setBinding(ShortcutBinding(key: PhysicalKey(3)), for: .showAll), .valid)
        XCTAssertEqual(coordinator.apply(registry, invocation: { _ in }), .accepted(.active))
        XCTAssertTrue(backend.registered.isEmpty)
    }

    func testRemovingLastGlobalBindingUnregistersItWhileFocusedMappingCanPersist() {
        let backend = FakeBackend()
        let coordinator = ShortcutRegistrationCoordinator(backend: backend)
        let binding = ShortcutBinding(key: PhysicalKey(0), modifiers: [.option])
        var registry = ShortcutRegistry()
        XCTAssertEqual(registry.setBinding(binding, for: .toggleOverlay), .valid)
        XCTAssertEqual(coordinator.apply(registry, invocation: { _ in }), .accepted(.active))
        registry.removeBinding(for: .toggleOverlay)
        XCTAssertEqual(registry.setBinding(ShortcutBinding(key: PhysicalKey(1)), for: .showAll), .valid)
        XCTAssertEqual(coordinator.apply(registry, invocation: { _ in }), .accepted(.active))
        XCTAssertTrue(backend.registered.isEmpty)
        XCTAssertEqual(registry.bindings[.showAll], ShortcutBinding(key: PhysicalKey(1)))
    }

    func testProductionEventMapperPreservesMarkedTextGateAndPhysicalFallback() {
        let ordinary = ShortcutKeyEventMapper.make(
            keyCode: 0,
            modifiers: [],
            phase: .down,
            isRepeat: false,
            hasMarkedText: true
        )
        var gate = ShortcutInvocationGate()
        XCTAssertFalse(gate.shouldInvoke(ordinary))
        let deliberate = ShortcutKeyEventMapper.make(
            keyCode: 0,
            modifiers: [.option],
            phase: .down,
            isRepeat: false,
            hasMarkedText: true
        )
        XCTAssertTrue(gate.shouldInvoke(deliberate))
        XCTAssertEqual(ShortcutInputSource(identifier: "ime", localizedName: "Japanese").label(for: PhysicalKey(0)), "A")
    }
}
