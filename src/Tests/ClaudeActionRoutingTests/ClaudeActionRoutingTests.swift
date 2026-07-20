import XCTest
import CryptoKit
@testable import ClaudeActionRouting
@testable import ClaudeCodeAdapter
@testable import SessionDomain
@testable import SessionStore

final class ClaudeActionRoutingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 20_000)
    private let instance = IntegrationInstanceID("claude-installation")

    private actor DispatchFixture: ClaudeActionDispatchPort {
        var outcome: ClaudeActionDispatchOutcome
        var requests: [ClaudeActionDispatchRequest] = []
        init(_ outcome: ClaudeActionDispatchOutcome = .acceptedByProduct) { self.outcome = outcome }
        func dispatch(_ request: ClaudeActionDispatchRequest, at: Date) async -> ClaudeActionDispatchOutcome { requests.append(request); return outcome }
        func count() -> Int { requests.count }
    }

    private func snapshot() -> NegotiationSnapshot {
        let provenance = CapabilityProvenance(snapshotID: NegotiationSnapshotID("claude-snapshot"), integrationInstanceID: instance, productNamespace: ClaudeCodeIntegration.productNamespace, integrationMode: ClaudeCodeIntegration.integrationMode)
        let records = ClaudeCodeIntegration.allActionCapabilities.map { CapabilityRecord(id: $0, direction: .act, availability: .available, scope: .request, provenance: provenance, semanticVariant: $0) }
        return NegotiationSnapshot(id: NegotiationSnapshotID("claude-snapshot"), contractVersion: ContractVersion(major: 1, minor: 0), adapterKind: ClaudeCodeIntegration.adapterKind, adapterBuildVersion: "test", productNamespace: ClaudeCodeIntegration.productNamespace, integrationInstanceID: instance, integrationMode: ClaudeCodeIntegration.integrationMode, capabilities: records, negotiatedAt: now)
    }

    private func callback(semantic: ClaudeLiveActionSemantic, hook: ClaudeHookName, request: String, toolUse: String? = nil, groups: [ClaudeQuestionGroup] = [], suggestion: ClaudeOfferedPermissionSuggestion? = nil, deadline: Date? = nil) -> ClaudeLiveCallback {
        let capabilityID: String = switch semantic {
        case .permission: ClaudeCodeIntegration.permissionCapability
        case .permissionSuggestion: ClaudeCodeIntegration.permissionSuggestionCapability
        case .questionAnswers: ClaudeCodeIntegration.questionActionCapability
        case .planApproval: ClaudeCodeIntegration.planApprovalCapability
        }
        let capability = snapshot().capabilities.first { $0.id == capabilityID }!
        let owner = GuidedAttentionOwner(productNamespace: ClaudeCodeIntegration.productNamespace, nativeSessionID: NativeSessionID("session-a"), nativeAttentionRequestID: request, integrationInstanceID: instance, negotiationSnapshotID: snapshot().id)
        let shape: GuidedSemanticShape = switch semantic {
        case .permission: .allowDeny
        case .permissionSuggestion: .persistentSuggestion
        case .questionAnswers: .structuredChoice(groups.flatMap(\.choiceIDs).map { GuidedChoice(id: $0, label: "Option") }, allowsMultipleSelection: true, minimumSelections: groups.count, maximumSelections: groups.flatMap(\.choiceIDs).count)
        case .planApproval: GuidedSemanticShape(kind: .planReview)
        }
        let input: [String: Any] = semantic == .questionAnswers ? ["tool_name": "AskUserQuestion", "tool_input": ["questions": groups.map { group in ["options": group.choiceIDs.map { ["label": $0] }] }]] : ["tool_name": "ExitPlanMode", "tool_input": ["plan": "documented"]]
        let native = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])) ?? Data()
        return ClaudeLiveCallback(identity: ClaudeLiveCallbackIdentity(nativeSessionID: NativeSessionID("session-a"), promptID: "prompt-a", hook: hook, toolUseID: toolUse, callbackInputFingerprint: "fingerprint-\(request)"), owner: owner, capability: capability, semantic: semantic, semanticShape: shape, deadline: deadline ?? now.addingTimeInterval(30), nativeInput: native, offeredSuggestion: suggestion, questionGroups: groups)
    }

    func testPermissionCallbackIsBoundToOneExactIdentityAndOneDispatch() async {
        let store = ActionAttemptStore(); let dispatch = DispatchFixture(); let router = ClaudeGuidedActionRouter(store: store, dispatchPort: dispatch)
        let live = callback(semantic: .permission, hook: .permissionRequest, request: "permission-1")
        guard case .success = await router.open(live, at: now) else { return XCTFail("open") }
        guard case .dispatched(let response, let attempt) = await router.submit(callbackIdentity: live.identity, submission: ClaudeActionSubmission(action: .allow, deliberateConfirmation: true), attemptID: "allow-1", at: now) else { return XCTFail("allow should dispatch") }
        XCTAssertEqual(response, .permission(.allow, suggestionJSON: nil))
        XCTAssertEqual(attempt.outcome, .acceptedByProduct)
        XCTAssertEqual(attempt.dispatchCount, 1)
        guard case .rejected(_, .staleCallback) = await router.submit(callbackIdentity: live.identity, submission: ClaudeActionSubmission(action: .allow, deliberateConfirmation: true), attemptID: "allow-repeat", at: now) else { return XCTFail("repeat must not dispatch") }
        XCTAssertEqual((await store.attempts()).count, 1)
        XCTAssertEqual(await dispatch.count(), 1)
    }

    func testPersistentSuggestionRequiresExactSecondScopeConfirmationAndEchoesOnlyOffer() async {
        let store = ActionAttemptStore(); let dispatch = DispatchFixture(); let router = ClaudeGuidedActionRouter(store: store, dispatchPort: dispatch)
        let offer = ClaudeOfferedPermissionSuggestion(id: "offer", persistenceScope: "project", canonicalNativeJSON: Data("{\"rule\":\"offered\"}".utf8))
        let live = callback(semantic: .permissionSuggestion, hook: .permissionRequest, request: "permission-2", suggestion: offer)
        _ = await router.open(live, at: now)
        guard case .rejected(_, .invalidAnswer) = await router.submit(callbackIdentity: live.identity, submission: ClaudeActionSubmission(action: .persistentSuggestion(allow: true), deliberateConfirmation: true), attemptID: "missing-second-confirm", at: now) else { return XCTFail("scope must be explicitly repeated") }
        guard case .dispatched(.permission(.allow, let echoed?), _) = await router.submit(callbackIdentity: live.identity, submission: ClaudeActionSubmission(action: .persistentSuggestion(allow: true), deliberateConfirmation: true, persistentScopeConfirmation: "project"), attemptID: "confirmed-offer", at: now) else { return XCTFail("exact offer should dispatch") }
        XCTAssertEqual(echoed, offer.canonicalNativeJSON)
    }

    func testQuestionAndPlanRequireCompleteDocumentedInput() async {
        let groups = [ClaudeQuestionGroup(questionIndex: 0, choiceIDs: ["q0-o0", "q0-o1"], allowsMultiple: false), ClaudeQuestionGroup(questionIndex: 1, choiceIDs: ["q1-o0", "q1-o1"], allowsMultiple: true)]
        let questionStore = ActionAttemptStore(); let questionRouter = ClaudeGuidedActionRouter(store: questionStore, dispatchPort: DispatchFixture())
        let question = callback(semantic: .questionAnswers, hook: .preToolUse, request: "tool-question", toolUse: "tool-question", groups: groups)
        _ = await questionRouter.open(question, at: now)
        let incomplete = GuidedAction.structuredResponse(GuidedStructuredResponse(selectedChoiceIDs: ["q0-o0"]))
        guard case .rejected(_, .invalidAnswer) = await questionRouter.submit(callbackIdentity: question.identity, submission: ClaudeActionSubmission(action: incomplete, deliberateConfirmation: true), attemptID: "incomplete", at: now) else { return XCTFail("all questions must be answered") }
        let complete = GuidedAction.structuredResponse(GuidedStructuredResponse(selectedChoiceIDs: ["q0-o0", "q1-o0", "q1-o1"]))
        guard case .dispatched(.preToolAllow(let input), _) = await questionRouter.submit(callbackIdentity: question.identity, submission: ClaudeActionSubmission(action: complete, deliberateConfirmation: true), attemptID: "complete", at: now) else { return XCTFail("documented answer map should dispatch") }
        let decoded = try? JSONSerialization.jsonObject(with: input) as? [String: Any]
        let questionInput = decoded?["tool_input"] as? [String: Any]
        let questions = questionInput?["questions"] as? [[String: Any]]
        XCTAssertEqual(questions?[0]["answers"] as? [String], ["q0-o0"])
        XCTAssertEqual(questions?[1]["answers"] as? [String], ["q1-o0", "q1-o1"])

        let planStore = ActionAttemptStore(); let planRouter = ClaudeGuidedActionRouter(store: planStore, dispatchPort: DispatchFixture())
        let plan = callback(semantic: .planApproval, hook: .preToolUse, request: "tool-plan", toolUse: "tool-plan")
        _ = await planRouter.open(plan, at: now)
        guard case .rejected(_, .invalidAnswer) = await planRouter.submit(callbackIdentity: plan.identity, submission: ClaudeActionSubmission(action: .planReview(.reject, reason: "revise"), deliberateConfirmation: true), attemptID: "revision", at: now) else { return XCTFail("revision is Host-native") }
        guard case .dispatched(.preToolAllow(_), _) = await planRouter.submit(callbackIdentity: plan.identity, submission: ClaudeActionSubmission(action: .planReview(.accept, reason: nil), deliberateConfirmation: true), attemptID: "approve", at: now) else { return XCTFail("only plan approval is supported") }
    }

    func testFactoryUsesToolUseNotTextAndRejectsManagedAndUnsupportedPaths() throws {
        let question = try ClaudeHookEnvelope.decode(Data("{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"s\",\"event_id\":\"e\",\"tool_use_id\":\"tool-1\",\"tool_name\":\"AskUserQuestion\",\"tool_input\":{\"questions\":[{\"options\":[{},{}]},{\"multi_select\":true,\"options\":[{},{}]}]}}".utf8))
        guard case .success(let callback) = ClaudeLiveCallbackFactory.make(hook: question, snapshot: snapshot(), integrationInstanceID: instance, deadline: now.addingTimeInterval(30)) else { return XCTFail("documented question fixture") }
        XCTAssertEqual(callback.requestID.nativeAttentionRequestID, "tool-1")
        let managed = try ClaudeHookEnvelope.decode(Data("{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"s\",\"event_id\":\"p\",\"request_id\":\"request\",\"permission_mode\":\"bypassPermissions\"}".utf8))
        guard case .failure(.managedPolicy) = ClaudeLiveCallbackFactory.make(hook: managed, snapshot: snapshot(), integrationInstanceID: instance, deadline: now.addingTimeInterval(30)) else { return XCTFail("managed policy must not route") }
    }

    func testResolvedElsewhereAndAcknowledgementOutcomesNeverClaimLifecycleCompletion() async {
        let store = ActionAttemptStore(); let router = ClaudeGuidedActionRouter(store: store, dispatchPort: DispatchFixture())
        let live = callback(semantic: .permission, hook: .permissionRequest, request: "permission-3")
        _ = await router.open(live, at: now)
        await router.resolvedElsewhere(live.identity)
        guard case .rejected(_, .staleCallback) = await router.submit(callbackIdentity: live.identity, submission: ClaudeActionSubmission(action: .deny, deliberateConfirmation: true), attemptID: "after-terminal", at: now) else { return XCTFail("resolved request must have zero dispatch") }
        let attempts = await store.attempts()
        XCTAssertTrue(attempts.isEmpty)
    }

    func testDeliveryOutcomesNeverOverclaimAndAreSingleUse() async {
        for (outcome, expected) in [(ClaudeActionDispatchOutcome.acceptedByProduct, ActionAttemptOutcome.acceptedByProduct), (.applied, .applied), (.superseded, .superseded), (.indeterminate, .indeterminate)] {
            let store = ActionAttemptStore(); let dispatch = DispatchFixture(outcome); let router = ClaudeGuidedActionRouter(store: store, dispatchPort: dispatch)
            let live = callback(semantic: .permission, hook: .permissionRequest, request: "outcome-\(expected.rawValue)")
            _ = await router.open(live, at: now)
            guard case .dispatched(_, let attempt) = await router.submit(callbackIdentity: live.identity, submission: ClaudeActionSubmission(action: .allow, deliberateConfirmation: true), attemptID: "attempt-\(expected.rawValue)", at: now) else { return XCTFail("dispatch") }
            XCTAssertEqual(attempt.outcome, expected); XCTAssertEqual(await dispatch.count(), 1)
        }
        let store = ActionAttemptStore(); let dispatch = DispatchFixture(.rejectedBeforeDispatch); let router = ClaudeGuidedActionRouter(store: store, dispatchPort: dispatch)
        let live = callback(semantic: .permission, hook: .permissionRequest, request: "helper-refusal")
        _ = await router.open(live, at: now)
        guard case .rejected(let attempt?, .helperUnavailable) = await router.submit(callbackIdentity: live.identity, submission: ClaudeActionSubmission(action: .allow, deliberateConfirmation: true), attemptID: "helper-refusal", at: now) else { return XCTFail("explicit helper refusal") }
        XCTAssertEqual(attempt.outcome, .rejected); XCTAssertEqual(attempt.dispatchCount, 0); XCTAssertEqual(await dispatch.count(), 1)
    }

    func testAuthenticatedActionListenerCreatesOneDurableRequestAndReturnsOneTypedReply() async throws {
        let secret = ClaudeIPCAuthenticator(secret: "listener-secret")
        let configuration = ClaudeActionRequestListener.Configuration(installationID: instance, helperID: "helper", authenticator: secret, snapshot: snapshot(), maximumFutureDeadline: 2)
        let listener = ClaudeActionRequestListener(configuration: configuration)
        let store = ActionAttemptStore()
        let router = ClaudeGuidedActionRouter(store: store, dispatchPort: listener)
        await listener.attach(router: router)
        let payload = Data("{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"session-a\",\"event_id\":\"event-a\",\"request_id\":\"request-a\",\"permission_mode\":\"default\"}".utf8)
        let fingerprint = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let nonce = UUID().uuidString
        let request = ClaudeHelperActionRequest(installationID: instance, helperID: "helper", nonce: nonce, callbackFingerprint: fingerprint, payload: payload, issuedAt: now, deadline: now.addingTimeInterval(1), authenticator: secret)
        let channel = ClaudeInMemoryActionReplyChannel()
        XCTAssertTrue(await listener.receive(request, channel: channel, at: now))
        XCTAssertEqual((await store.requests()).count, 1)

        let identity = ClaudeLiveCallbackIdentity(nativeSessionID: NativeSessionID("session-a"), promptID: nil, hook: .permissionRequest, toolUseID: nil, callbackInputFingerprint: fingerprint, nonce: try XCTUnwrap(UUID(uuidString: nonce)))
        guard case .dispatched = await router.submit(callbackIdentity: identity, submission: ClaudeActionSubmission(action: .allow, deliberateConfirmation: true), attemptID: "listener-allow", at: now) else { return XCTFail("one live callback should dispatch") }
        let reply = try XCTUnwrap(await channel.response)
        XCTAssertEqual(reply.response, .permission(.allow, suggestionJSON: nil))
        XCTAssertTrue(reply.isAuthenticated(using: secret))
        XCTAssertEqual(await listener.liveWaiterCount, 0)
        guard case .rejected(_, .staleCallback) = await router.submit(callbackIdentity: identity, submission: ClaudeActionSubmission(action: .allow, deliberateConfirmation: true), attemptID: "listener-repeat", at: now) else { return XCTFail("responder is single use") }
    }

    func testListenerRejectsReplayCrossOwnerMismatchAndExpiredBeforeCreatingRequest() async {
        let secret = ClaudeIPCAuthenticator(secret: "listener-secret")
        let configuration = ClaudeActionRequestListener.Configuration(installationID: instance, helperID: "helper", authenticator: secret, snapshot: snapshot(), maximumFutureDeadline: 2)
        let listener = ClaudeActionRequestListener(configuration: configuration)
        let store = ActionAttemptStore(); let router = ClaudeGuidedActionRouter(store: store, dispatchPort: listener)
        await listener.attach(router: router)
        let payload = Data("{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"session-a\",\"event_id\":\"event-a\",\"request_id\":\"request-a\"}".utf8)
        let fingerprint = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let request = ClaudeHelperActionRequest(installationID: instance, helperID: "helper", nonce: UUID().uuidString, callbackFingerprint: fingerprint, payload: payload, issuedAt: now, deadline: now.addingTimeInterval(1), authenticator: secret)
        XCTAssertTrue(await listener.receive(request, channel: ClaudeInMemoryActionReplyChannel(), at: now))
        XCTAssertFalse(await listener.receive(request, channel: ClaudeInMemoryActionReplyChannel(), at: now))
        let crossOwner = ClaudeHelperActionRequest(installationID: IntegrationInstanceID("other"), helperID: "helper", nonce: UUID().uuidString, callbackFingerprint: fingerprint, payload: payload, issuedAt: now, deadline: now.addingTimeInterval(1), authenticator: secret)
        XCTAssertFalse(await listener.receive(crossOwner, channel: ClaudeInMemoryActionReplyChannel(), at: now))
        let expired = ClaudeHelperActionRequest(installationID: instance, helperID: "helper", nonce: UUID().uuidString, callbackFingerprint: fingerprint, payload: payload, issuedAt: now, deadline: now.addingTimeInterval(-1), authenticator: secret)
        XCTAssertFalse(await listener.receive(expired, channel: ClaudeInMemoryActionReplyChannel(), at: now))
        XCTAssertEqual((await store.requests()).count, 1)
    }
}
