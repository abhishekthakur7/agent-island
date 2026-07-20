import XCTest
@testable import ApplicationRuntime
@testable import SessionDomain
@testable import SessionStore

final class AB146WorkloadTests: XCTestCase {
    private func snapshot(_ runtime: ApplicationRuntime) async throws -> NegotiationSnapshot {
        let request = NegotiationRequest(
            integrationInstanceID: .init("ab146-tests"), adapterKind: "ab146-test", adapterBuildVersion: "1",
            productNamespace: .init("claude-code"), integrationMode: "workload-fixture",
            offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0),
            requestedCapabilities: [WellKnownCapability.sessionObservation]
        )
        guard case .compatible(let snapshot) = await runtime.negotiate(request) else { throw AB146Error.negotiation }
        return snapshot
    }

    private func envelope(_ snapshot: NegotiationSnapshot, session: String, event: String, activity: SessionActivityKind, cursor: Int64) -> RawEventEnvelope {
        RawEventEnvelope(
            negotiationSnapshotID: snapshot.id, integrationInstanceID: snapshot.integrationInstanceID,
            contractVersion: snapshot.contractVersion, productNamespace: snapshot.productNamespace.rawValue,
            nativeSessionID: session, eventIdentity: .stable(event), family: .sessionActivity,
            sourceVariant: "ab146.test", activityKind: activity, classification: .operationalMetadata,
            payloadByteSize: 1, sourceCursor: .init(scope: session, value: cursor)
        )
    }

    func testThirtyFirstInactiveSessionArchivesLosslesslyWithRecap() async throws {
        let store = SessionStore(); let runtime = ApplicationRuntime(store: store); let snapshot = try await snapshot(runtime)
        for index in 0..<31 {
            let session = "inactive-\(index)"
            guard case .committed = await runtime.deliver(envelope(snapshot, session: session, event: "start-\(index)", activity: .started, cursor: 1)),
                  case .committed = await runtime.deliver(envelope(snapshot, session: session, event: "done-\(index)", activity: .completed, cursor: 2))
            else { return XCTFail("fixture event must commit") }
        }
        let identity = AgentSessionIdentity(productNamespace: .init("claude-code"), nativeSessionID: .init("inactive-0"))
        let tier = await store.tier(for: identity)
        let working = await store.workingSetProjections()
        let summaries = await store.historySummaries()
        let recap = await store.recordSourcedRecap(.init(sourceEventIdentity: .stable("recap"), text: "received recap"), for: identity)
        XCTAssertEqual(tier, .history)
        XCTAssertEqual(working.count, 30)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(recap, .recapRecorded)
        let history = await store.inspectHistory(for: identity)
        XCTAssertEqual(history?.facts.count, 2)
        XCTAssertEqual(history?.record.recap?.text, "received recap")
    }

    func testAttentionAndActiveChildOverflowNeverArchives() async throws {
        let store = SessionStore(); let runtime = ApplicationRuntime(store: store); let snapshot = try await snapshot(runtime)
        for index in 0..<31 {
            let session = "protected-\(index)"
            guard case .committed = await runtime.deliver(envelope(snapshot, session: session, event: "start-\(index)", activity: .started, cursor: 1)) else { return XCTFail("start") }
            let attention = RawEventEnvelope(
                negotiationSnapshotID: snapshot.id, integrationInstanceID: snapshot.integrationInstanceID, contractVersion: snapshot.contractVersion,
                productNamespace: snapshot.productNamespace.rawValue, nativeSessionID: session, eventIdentity: .stable("attention-\(index)"),
                family: .attentionRequest, sourceVariant: "ab146.test", classification: .operationalMetadata, payloadByteSize: 1,
                sourceCursor: .init(scope: session, value: 2), ownership: .init(nativeAttentionRequestID: "request-\(index)"), attentionKind: .opened
            )
            guard case .committed = await runtime.deliver(attention) else { return XCTFail("attention") }
        }
        let working = await store.workingSetProjections()
        let history = await store.historySummaries()
        XCTAssertEqual(working.count, 31)
        XCTAssertTrue(history.isEmpty)
    }

    func testGapAndRestartRemainUnresolvedWithExactOwner() async throws {
        let store = SessionStore(); let runtime = ApplicationRuntime(store: store); let snapshot = try await snapshot(runtime)
        guard case .committed = await runtime.deliver(envelope(snapshot, session: "gap-owner", event: "start", activity: .started, cursor: 1)),
              case .committed = await runtime.deliver(envelope(snapshot, session: "gap-owner", event: "completed-after-gap", activity: .completed, cursor: 3))
        else { return XCTFail("gap events") }
        let projection = await store.workingSetProjections().values.first
        XCTAssertEqual(projection?.identity.nativeSessionID.rawValue, "gap-owner")
        XCTAssertEqual(projection?.execution, .unresolved)
        XCTAssertEqual(SessionReducer.applyRestartBoundary(projection!).execution, .unresolved)
    }

    private enum AB146Error: Error { case negotiation }
}
