import XCTest
@testable import SessionDomain

final class NotificationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)
    private let product = ProductNamespace("fixture")
    private let session = NativeSessionID("session-1")
    private let integration = IntegrationInstanceID("integration-1")
    private let snapshot = NegotiationSnapshotID("snapshot-1")

    private func fact(
        revision: Int64 = 1,
        event: String = "event-1",
        family: EventFamily = .sessionActivity,
        kind: SessionActivityKind? = .completed,
        ownership: LifecycleOwnership? = nil,
        sourceVariant: String = "fixture.completed"
    ) -> NormalizedEventFact {
        NormalizedEventFact(
            receiptOrdinal: revision,
            identity: AgentSessionIdentity(productNamespace: product, nativeSessionID: session),
            integrationInstanceID: integration,
            negotiationSnapshotID: snapshot,
            eventIdentity: .stable(event),
            family: family,
            sourceVariant: sourceVariant,
            activityKind: kind,
            boundaryReason: nil,
            classification: .operationalMetadata,
            occurrenceTime: now,
            receiptTime: now,
            displayTitle: "sensitive Product title must not be an identity",
            hostLabel: "Terminal",
            ownership: ownership,
            attentionKind: family == .attentionRequest ? .opened : nil
        )
    }

    private func projection(
        revision: Int64 = 1,
        execution: ExecutionState = .terminalCompleted,
        attention: AttentionState = .none,
        children: [SubagentRunProjection] = []
    ) -> SessionProjection {
        SessionProjection(
            identity: AgentSessionIdentity(productNamespace: product, nativeSessionID: session),
            execution: execution,
            observation: .fresh,
            displayTitle: "ignored",
            hostLabel: "ignored",
            sourceLastUpdated: now,
            ledgerRevision: revision,
            attention: attention,
            turns: [],
            subagentRuns: children
        )
    }

    private func candidate(
        semanticClass: AlertCandidateClass = .completion,
        revision: Int64 = 1,
        event: String = "event-1"
    ) -> AlertCandidate {
        let evidence = AlertCandidateEvidence(
            fact: fact(revision: revision, event: event),
            projection: projection(revision: revision),
            semanticClass: semanticClass,
            configuredLabel: "Configured recap"
        )
        guard case .success(let value) = AlertCandidate.make(from: evidence) else { fatalError("valid fixture candidate") }
        return value
    }

    func testFactoryUsesOwnerAndEventOnlyAndCoalescesRevisions() {
        var ledger = AlertCandidateLedger()
        let first = candidate()
        XCTAssertEqual(ledger.ingest(AlertCandidateEvidence(fact: fact(), projection: projection(), semanticClass: .completion, configuredLabel: "one")), .accepted(first))

        let replay = ledger.ingest(AlertCandidateEvidence(fact: fact(), projection: projection(), semanticClass: .completion, configuredLabel: "two"))
        if case .duplicate = replay {} else { XCTFail("same source revision must not deliver again") }

        let updatedFact = fact(revision: 2, event: "event-1")
        let updatedProjection = projection(revision: 2)
        let update = ledger.ingest(AlertCandidateEvidence(fact: updatedFact, projection: updatedProjection, semanticClass: .completion, configuredLabel: "updated"))
        if case .updated(let value) = update { XCTAssertEqual(value.id, first.id); XCTAssertEqual(value.sourceRevision, 2) } else { XCTFail("later source revision should update one candidate") }
        XCTAssertEqual(first.id.owner.nativeSessionID, session)
        XCTAssertFalse(first.id.description.contains("sensitive Product title"))
    }

    func testWeakAndNonReducerEvidenceCreateNoCandidate() {
        let weak = NormalizedEventFact(
            receiptOrdinal: 1,
            identity: AgentSessionIdentity(productNamespace: product, nativeSessionID: session),
            integrationInstanceID: integration,
            negotiationSnapshotID: snapshot,
            eventIdentity: .weak("ambiguous"),
            family: .sessionActivity,
            sourceVariant: "fixture.completed",
            activityKind: .completed,
            boundaryReason: nil,
            classification: .operationalMetadata,
            occurrenceTime: now,
            receiptTime: now,
            displayTitle: nil,
            hostLabel: nil
        )
        let result = AlertCandidate.make(from: AlertCandidateEvidence(fact: weak, projection: projection(), semanticClass: .completion))
        XCTAssertEqual(result, .failure(.weakKeyAmbiguous))
        let rejected = AlertCandidate.make(from: AlertCandidateEvidence(fact: fact(), projection: projection(), semanticClass: .completion, reducerAccepted: false))
        XCTAssertEqual(rejected, .failure(.notReducerAccepted))
    }

    func testEvaluationOrderQuietForegroundPreferencePermissionAndSound() {
        var sound = SoundPolicy.default
        sound.register(LocalSoundAsset(id: "ding", displayName: "Ding", byteCount: 10))
        sound.selectionByClass[.completion] = .local("ding")
        var policy = NotificationPolicy.default
        policy.sound = sound
        policy.permission = NotificationPermissionPolicy(system: .granted)
        let value = candidate()

        let quiet = NotificationPolicyEvaluator.evaluate(value, context: AlertEvaluationContext(policy: policy, quietScene: QuietScene(focusMode: true), now: now))
        XCTAssertEqual(quiet.reason, .quietScene)
        XCTAssertNil(quiet.banner)
        XCTAssertNil(quiet.sound)
        XCTAssertEqual(quiet.steps, [.deduplicationAndCurrentness, .hardFilter, .quietScene])

        let exact = NotificationPolicyEvaluator.evaluate(value, context: AlertEvaluationContext(policy: policy, exactForeground: ExactForegroundRelevance(sessionIdentity: value.owner.sessionIdentity, revalidated: true, directInspection: true), now: now))
        XCTAssertEqual(exact.reason, .exactForeground)
        XCTAssertEqual(exact.primary.presentation, .inlineOnly)

        let denied = NotificationPolicyEvaluator.evaluate(value, context: AlertEvaluationContext(policy: NotificationPolicy(masterEnabled: true, permission: NotificationPermissionPolicy(system: .denied), sound: sound), now: now))
        XCTAssertEqual(denied.reason, .eligible)
        XCTAssertNil(denied.banner)
        XCTAssertNotNil(denied.sound)

        let restored = NotificationPolicyEvaluator.evaluate(value, context: AlertEvaluationContext(policy: policy, restoredFromRestart: true, now: now))
        XCTAssertEqual(restored.reason, .restartRestored)
        XCTAssertFalse(restored.hasAutomaticFacet)
    }

    func testQuietHoursMutesSoundOnlyAndForegroundIsSessionScoped() {
        var sound = SoundPolicy.default
        sound.register(LocalSoundAsset(id: "ding", displayName: "Ding", byteCount: 10))
        sound.selectionByClass[.completion] = .local("ding")
        let policy = NotificationPolicy(permission: NotificationPermissionPolicy(system: .granted), sound: sound)
        let value = candidate()
        let inQuietHours = NotificationPolicyEvaluator.evaluate(value, context: AlertEvaluationContext(policy: policy, now: now, currentRevision: 1))
        // The default quiet-hours switch is off; enabling it demonstrates that
        // the primary/banner remain while only sound is removed.
        var quietPolicy = policy
        quietPolicy.sound.quietHoursEnabled = true
        quietPolicy.sound.quietHours = QuietHours(startMinute: 0, endMinute: 23 * 60 + 59)
        let muted = NotificationPolicyEvaluator.evaluate(value, context: AlertEvaluationContext(policy: quietPolicy, now: now))
        XCTAssertEqual(muted.reason, .eligible)
        if case .suppressed(_, .quietHours) = muted.sound {} else { XCTFail("quiet hours suppress sound only") }
        XCTAssertNotNil(muted.banner)
        XCTAssertEqual(inQuietHours.candidateID, value.id)

        let otherSession = ExactForegroundRelevance(sessionIdentity: AgentSessionIdentity(productNamespace: product, nativeSessionID: NativeSessionID("other")), revalidated: true, directInspection: true)
        let sameTitle = NotificationPolicyEvaluator.evaluate(value, context: AlertEvaluationContext(policy: policy, exactForeground: otherSession, now: now))
        XCTAssertNotEqual(sameTitle.reason, .exactForeground)
    }
}
