import XCTest
import Foundation
@testable import SessionDomain
@testable import SessionStore

final class AB130BoundaryTests: XCTestCase {
    func testAllBoundaryOutcomesRemainAllowlistedEvidence() async throws {
        let store = DiagnosticEvidenceStore()
        let outcomes: [DiagnosticOutcome] = [.accepted, .filtered, .deduplicated, .quarantined, .downgraded, .rejected, .unavailable, .degraded, .failed]
        for outcome in outcomes {
            _ = await store.append(DiagnosticEvidence(operation: .inspect, outcome: outcome, scope: DiagnosticScope(component: .integration, owner: .integration, capability: .observation), reason: .unknown, occurredAt: Date(), correlationID: .generated(), safeNextStep: .inspect))
        }
        let records = await store.all()
        XCTAssertEqual(records.map(\.outcome), outcomes)
        XCTAssertTrue(records.allSatisfy { $0.correlationID.value.hasPrefix("corr-") })
        let bundle = try await store.previewBundle()
        XCTAssertEqual(bundle.records.count, outcomes.count)
    }

    func testIntakeOutcomeProjectionNeverCopiesEnvelopeContent() async {
        let store = DiagnosticEvidenceStore()
        let outcome = IntakeOutcome.rejected(.interactionContentUnsupported)
        _ = await store.appendIntakeOutcome(outcome, at: Date(timeIntervalSince1970: 20))
        let record = await store.all().first
        XCTAssertEqual(record?.outcome, .rejected)
        XCTAssertEqual(record?.reason, .interactionContentUnsupported)
        let text = String(describing: record)
        XCTAssertFalse(text.contains("prompt"))
        XCTAssertFalse(text.contains("token"))
    }

    func testUserDataStoreSeparatesDestinationAndContentConfirmation() async throws {
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("s"))
        let record = VerifiedUserDataRecord(identity: identity, interactionContent: [SessionHistoryContent(contentID: "x", bytes: Data("selected content".utf8))])
        let store = UserDataExportStore(verifiedRecords: [record])
        let selection = UserDataExportSelection(sessions: [identity], dataClasses: [.sessionHistory])
        let preview = try await store.preview(selection: selection)
        XCTAssertFalse(preview.interactionContentConfirmationRequired)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab130-store-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try UserDataExportDestination(file: root.appendingPathComponent("selected.json"))
        let artifacts = try await store.write(selection: selection, confirmation: preview.confirmation.confirming(), destination: destination)
        let text = String(data: try Data(contentsOf: artifacts.data), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("selected content"))
        XCTAssertFalse(text.contains("callback"))
    }

    func testMaintenanceStoreRejectsUnconfirmedAndStaleScopes() async {
        let store = MaintenanceStore()
        let preview = await store.preview(.deleteDiagnostics())
        let unconfirmed = await store.apply(preview, confirmation: preview.confirmation)
        XCTAssertEqual(unconfirmed, .confirmationRequired)
        _ = await store.apply(preview, confirmation: preview.confirmation.confirming())
        let stale = await store.apply(preview, confirmation: preview.confirmation.confirming())
        XCTAssertEqual(stale, .stalePreview)
    }
}

private extension MaintenanceRequest {
    static func deleteDiagnostics() -> Self { Self(flow: .deleteDiagnostics, localCategories: [.diagnostics]) }
}
