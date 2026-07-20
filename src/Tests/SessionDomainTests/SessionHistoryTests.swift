import XCTest
import Foundation
@testable import SessionDomain

final class SessionHistoryTests: XCTestCase {
    private let identity = AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("s"))

    private func projection(_ execution: ExecutionState = .terminalCompleted, attention: AttentionState = .none, children: [SubagentRunProjection] = []) -> SessionProjection {
        SessionProjection(identity: identity, execution: execution, observation: .fresh, displayTitle: "same title", hostLabel: "same host", sourceLastUpdated: nil, ledgerRevision: 1, attention: attention, subagentRuns: children)
    }

    private func fact(_ ordinal: Int64, family: EventFamily = .sessionActivity, event: String, occurrence: Date? = nil, receipt: Date) -> NormalizedEventFact {
        NormalizedEventFact(receiptOrdinal: ordinal, identity: identity, integrationInstanceID: IntegrationInstanceID("i"), negotiationSnapshotID: NegotiationSnapshotID("n"), eventIdentity: .stable(event), family: family, sourceVariant: "fixture", activityKind: family == .sessionActivity ? .completed : nil, boundaryReason: nil, classification: .operationalMetadata, occurrenceTime: occurrence, receiptTime: receipt, displayTitle: "same title", hostLabel: "same host")
    }

    func testSafelyInactiveRejectsUnresolvedAttentionAndChildActivity() {
        XCTAssertTrue(SessionHistoryPolicy.isSafelyInactive(projection()))
        XCTAssertFalse(SessionHistoryPolicy.isSafelyInactive(projection(.unresolved)))
        XCTAssertFalse(SessionHistoryPolicy.isSafelyInactive(projection(attention: .pending)))
        XCTAssertFalse(SessionHistoryPolicy.isSafelyInactive(projection(children: [SubagentRunProjection(nativeSubagentRunID: "child", ownerNativeTurnID: nil, execution: .waiting)])))
    }

    func testProductCreationOrdersBeforeLocalFallbackAndIdentityBreaksTies() {
        let now = Date(timeIntervalSince1970: 100)
        let olderProduct = SessionHistoryRecord(identity: identity, facts: [fact(1, family: .sessionDeclared, event: "p", occurrence: Date(timeIntervalSince1970: 1_000), receipt: now)], projection: projection(), productCreationTime: Date(timeIntervalSince1970: 1), firstObservedTime: now)
        let fallback = SessionHistoryRecord(identity: AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("a")), facts: [fact(2, event: "f", receipt: Date(timeIntervalSince1970: 0))], projection: projection(), firstObservedTime: Date(timeIntervalSince1970: 0))
        let ordered = SessionHistoryPolicy.ordered([olderProduct, fallback])
        XCTAssertEqual(ordered.first?.identity.nativeSessionID.rawValue, "a")
        XCTAssertEqual(ordered.first?.orderingSource, .localFirstObservedTime)
    }

    func testBoundedInspectionIsExplicitlyTruncated() {
        let facts = (1...4).map { fact(Int64($0), event: "e\($0)", receipt: Date(timeIntervalSince1970: Double($0))) }
        let content = (1...3).map { SessionHistoryContent(contentID: "c\($0)", bytes: Data(repeating: 1, count: 3)) }
        let record = SessionHistoryRecord(identity: identity, facts: facts, projection: projection(), firstObservedTime: Date())
        let withContent = SessionHistoryRecord(identity: identity, facts: record.facts, projection: record.projection, firstObservedTime: record.firstObservedTime, receivedContent: content)
        let inspection = withContent.inspect(maxFacts: 2, maxContentItems: 3, maxContentBytes: 4)
        XCTAssertEqual(inspection.facts.count, 2)
        XCTAssertEqual(inspection.receivedContent.count, 1)
        XCTAssertTrue(inspection.factsTruncated)
        XCTAssertTrue(inspection.contentTruncated)
    }
}

