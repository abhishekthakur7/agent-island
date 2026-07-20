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
        XCTAssertTrue(ShortcutCommand.safeAction(.allow).isGloballyEligible)
        XCTAssertFalse(ShortcutCommand.safeAction("arbitrary-product-command").isGloballyEligible)
    }

    func testSafeActionChoicesMapOnlyToGuidedSemantics() {
        XCTAssertEqual(ShortcutSafeAction.allow.guidedAction, .allow)
        XCTAssertEqual(ShortcutSafeAction.persistentDeny.guidedAction, .persistentSuggestion(allow: false))
        XCTAssertEqual(ShortcutSafeAction.planAccept.guidedAction, .planReview(.accept, reason: nil))
        XCTAssertEqual(ShortcutSafeAction.planAccept.semanticKind, .planReview)
        XCTAssertEqual(Set(ShortcutSafeAction.allCases.map(\.nativeRegistrationID)).count, ShortcutSafeAction.allCases.count)
    }

    func testGuidedSafeShortcutResolvesOneLiveRequestWithoutDispatchAuthority() {
        let snapshot = NegotiationSnapshotID("snapshot")
        let instance = IntegrationInstanceID("instance")
        let product = ProductNamespace("fixture")
        let owner = GuidedAttentionOwner(
            productNamespace: product,
            nativeSessionID: NativeSessionID("session"),
            nativeAttentionRequestID: "request",
            integrationInstanceID: instance,
            negotiationSnapshotID: snapshot
        )
        let provenance = CapabilityProvenance(snapshotID: snapshot, integrationInstanceID: instance, productNamespace: product, integrationMode: "fixture")
        let capability = CapabilityRecord(id: "attention.respond", direction: .act, availability: .available, provenance: provenance)
        let request = GuidedAttentionRequest(evidence: GuidedAttentionEvidence(
            owner: owner,
            eventIdentity: .stable("event"),
            sourceVariant: "allow-deny",
            capability: capability,
            semanticShape: .allowDeny,
            constraints: GuidedAttentionConstraints(nativeFingerprint: "fp"),
            sourceObservedAt: Date(timeIntervalSince1970: 1)
        ))

        let result = ShortcutGuidedRouteResolver.resolve(command: .safeAction(.allow), requests: [request])
        guard case let .eligible(route) = result else { return XCTFail("one live request should be eligible") }
        XCTAssertEqual(route.requestID, request.id)
        XCTAssertEqual(route.owner, request.owner)
        XCTAssertEqual(route.action, .allow)
        // The route is an opening/focus instruction only; ActionLease and
        // ActionAttempt types remain outside this resolver.
    }

    func testGuidedSafeShortcutFailsClosedForMissingStaleAndAmbiguousAuthority() {
        let snapshot = NegotiationSnapshotID("snapshot")
        let instance = IntegrationInstanceID("instance")
        let product = ProductNamespace("fixture")
        func request(id: String, outcome: GuidedSourceOutcome = .pending, capability: CapabilityRecord? = nil) -> GuidedAttentionRequest {
            let owner = GuidedAttentionOwner(productNamespace: product, nativeSessionID: NativeSessionID("session-\(id)"), nativeAttentionRequestID: id, integrationInstanceID: instance, negotiationSnapshotID: snapshot)
            let provenance = CapabilityProvenance(snapshotID: snapshot, integrationInstanceID: instance, productNamespace: product, integrationMode: "fixture")
            let granted = capability ?? CapabilityRecord(id: "attention.respond", direction: .act, availability: .available, provenance: provenance)
            var value = GuidedAttentionRequest(evidence: GuidedAttentionEvidence(owner: owner, eventIdentity: .stable("event-\(id)"), sourceVariant: "allow-deny", capability: granted, semanticShape: .allowDeny, constraints: GuidedAttentionConstraints(nativeFingerprint: "fp"), sourceObservedAt: Date(timeIntervalSince1970: 1)))
            value.sourceOutcome = outcome
            return value
        }

        guard case .unavailable(.noLiveRequest) = ShortcutGuidedRouteResolver.resolve(command: .safeAction(.allow), requests: []) else { return XCTFail("missing request must be unavailable") }
        guard case .unavailable(.sourceResolved) = ShortcutGuidedRouteResolver.resolve(command: .safeAction(.allow), requests: [request(id: "resolved", outcome: .resolvedElsewhere)]) else { return XCTFail("resolved request must be unavailable") }
        let unavailable = CapabilityRecord(id: "attention.respond", direction: .observe, availability: .available, provenance: CapabilityProvenance(snapshotID: snapshot, integrationInstanceID: instance, productNamespace: product, integrationMode: "fixture"))
        guard case .unavailable(.capabilityUnavailable) = ShortcutGuidedRouteResolver.resolve(command: .safeAction(.allow), requests: [request(id: "stale", capability: unavailable)]) else { return XCTFail("observation-only request must be unavailable") }
        let staleCapability = CapabilityRecord(id: "attention.respond", direction: .act, availability: .available, freshness: .stale, provenance: CapabilityProvenance(snapshotID: snapshot, integrationInstanceID: instance, productNamespace: product, integrationMode: "fixture"))
        guard case .unavailable(.capabilityUnavailable) = ShortcutGuidedRouteResolver.resolve(command: .safeAction(.allow), requests: [request(id: "stale-freshness", capability: staleCapability)]) else { return XCTFail("stale capability must be unavailable") }
        guard case .unavailable(.ambiguousRequest) = ShortcutGuidedRouteResolver.resolve(command: .safeAction(.allow), requests: [request(id: "one"), request(id: "two")]) else { return XCTFail("ambiguous live requests must fail closed") }
        guard case .unavailable(.unknownSafeAction) = ShortcutGuidedRouteResolver.resolve(command: .safeAction("arbitrary"), requests: []) else { return XCTFail("unknown safe action must be unavailable") }
    }

    func testShortcutFailureDescriptionsAreHumanReadable() {
        XCTAssertFalse(ShortcutBindingValidationFailure.registeredCollision.humanReadableDescription.contains("registeredCollision"))
        XCTAssertTrue(ShortcutGuidedRouteFailure.capabilityUnavailable.humanReadableDescription.contains("stale or unavailable"))
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

    func testConfiguredSafeActionsRegisterAndRouteOnlyThroughTheInjectedCallback() {
        let backend = FakeBackend()
        let coordinator = ShortcutRegistrationCoordinator(backend: backend)
        var registry = ShortcutRegistry()
        XCTAssertEqual(registry.setBinding(ShortcutBinding(key: PhysicalKey(2), modifiers: [.option]), for: .safeAction(.allow)), .valid)
        XCTAssertEqual(registry.setBinding(ShortcutBinding(key: PhysicalKey(3), modifiers: [.option]), for: .safeAction(.deny)), .valid)
        var callbacks: [ShortcutCommand] = []
        XCTAssertEqual(coordinator.apply(registry, invocation: { callbacks.append($0) }), .accepted(.active))
        XCTAssertEqual(backend.registered.count, 2)
        backend.emit(.safeAction(.allow), phase: .down)
        backend.emit(.safeAction(.allow), phase: .down)
        backend.emit(.safeAction(.deny), phase: .down)
        XCTAssertEqual(callbacks, [.safeAction(.allow), .safeAction(.deny)])
        backend.emit(.safeAction(.allow), phase: .up)
        backend.emit(.safeAction(.allow), phase: .down)
        XCTAssertEqual(callbacks, [.safeAction(.allow), .safeAction(.deny), .safeAction(.allow)])
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
