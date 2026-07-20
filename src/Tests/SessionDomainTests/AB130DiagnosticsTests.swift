import XCTest
import Foundation
@testable import SessionDomain

final class AB130DiagnosticsTests: XCTestCase {
    private let fixed = Date(timeIntervalSince1970: 1_752_000_000)

    private func evidence(_ outcome: DiagnosticOutcome = .degraded) -> DiagnosticEvidence {
        DiagnosticEvidence(
            operation: .degrade,
            outcome: outcome,
            scope: DiagnosticScope(component: .integration, owner: .integration, capability: .observation),
            reason: .transportUnavailable,
            occurredAt: fixed,
            correlationID: DiagnosticCorrelationID("seeded-prompt /private/worktree --token=secret"),
            health: DiagnosticHealthDimensions(transport: .unavailable, eventFreshness: .stale, summary: .degraded, safeNextStep: .retry),
            safeNextStep: .retry
        )
    }

    func testDiagnosticEvidenceIsClosedAndCorrelationIsRedacted() throws {
        let record = evidence()
        XCTAssertTrue(record.correlationID.value.hasPrefix("corr-"))
        XCTAssertFalse(record.correlationID.value.contains("seeded"))
        let mirrorLabels = Mirror(reflecting: record).children.compactMap(\.label)
        XCTAssertFalse(mirrorLabels.contains("payload"))
        XCTAssertFalse(mirrorLabels.contains("path"))
        XCTAssertFalse(mirrorLabels.contains("token"))
    }

    func testBundleHumanAndMachineArtifactsExcludeSeededSensitiveStrings() throws {
        let bundle = try DiagnosticBundle(records: [evidence(.accepted)], generatedAt: fixed)
        XCTAssertFalse(bundle.humanReadable.contains("seeded-prompt"))
        XCTAssertFalse(bundle.humanReadable.contains("worktree"))
        XCTAssertFalse(bundle.humanReadable.contains("secret"))
        let json = String(data: bundle.machineReadable, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("seeded-prompt"))
        XCTAssertFalse(json.contains("/private"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab130-bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try DiagnosticBundleDestination(directory: root)
        let artifacts = try DiagnosticBundleWriter.write(bundle, to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.markdown.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.machineReadableJSON.path))
        XCTAssertNil(FileManager.default.contents(atPath: root.appendingPathComponent("agent-island-diagnostic-bundle.zip").path))
    }

    func testUserDataExportIsSeparateAndRequiresContentConfirmation() throws {
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("session"))
        let record = VerifiedUserDataRecord(identity: identity, interactionContent: [
            SessionHistoryContent(contentID: "content", bytes: Data("private response".utf8)),
            SessionHistoryContent(contentID: "credential", bytes: Data("api_key=do-not-export".utf8))
        ])
        let selection = UserDataExportSelection(sessions: [identity], dataClasses: [.interactionContent], includeInteractionContent: true)
        let preview = try UserDataExportWriter.preview(selection: selection, verifiedRecords: [record], at: fixed)
        XCTAssertTrue(preview.interactionContentConfirmationRequired)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab130-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try UserDataExportDestination(file: root.appendingPathComponent("selected.json"))
        XCTAssertThrowsError(try UserDataExportWriter.write(selection: selection, verifiedRecords: [record], confirmation: preview.confirmation.confirming(), destination: destination, at: fixed)) { error in
            XCTAssertEqual(error as? UserDataExportError, .confirmationRequired)
        }
        let artifacts = try UserDataExportWriter.write(selection: selection, verifiedRecords: [record], confirmation: preview.confirmation.confirmingInteractionContent(), destination: destination, at: fixed)
        let output = String(data: try Data(contentsOf: artifacts.data), encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("private response"))
        XCTAssertFalse(output.contains("do-not-export"))
        XCTAssertFalse(output.contains("api_key"))
        XCTAssertFalse(output.contains("ActionLease"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.integrityManifest.path))
    }

    func testMaintenanceScopeConfirmationStalePreviewAndResidualHonesty() {
        let manifest = MaintenanceManifestScope(manifestID: "manifest", exactEntryCount: 1, ownedArtifactCount: 1, lifecycle: .drifted, residualKnown: true)
        var state = MaintenanceState()
        let request = MaintenanceRequest(flow: .removeManifestProvenSetup, manifestScopes: [manifest])
        let preview = MaintenancePlanner.preview(request, state: state, at: fixed)
        XCTAssertEqual(preview.tone, .destructive)
        XCTAssertTrue(preview.residualAmbiguity)
        XCTAssertEqual(MaintenancePlanner.apply(preview, confirmation: preview.confirmation, state: &state), .partialWithResidual(manifestScopes: [manifest]))

        let staleRequest = MaintenanceRequest.resetPresentationPreferences()
        let stale = MaintenancePlanner.preview(staleRequest, state: state)
        state.markIntegrityFailure(.presentationPreferences)
        XCTAssertEqual(MaintenancePlanner.apply(stale, confirmation: stale.confirmation, state: &state), .stalePreview)
        let failed = MaintenancePlanner.preview(staleRequest, state: state)
        XCTAssertEqual(MaintenancePlanner.apply(failed, confirmation: failed.confirmation, state: &state), .blockedByIntegrity(category: .presentationPreferences))
        XCTAssertEqual(MaintenancePlanner.apply(failed, confirmation: MaintenanceConfirmation(previewDigest: failed.previewDigest, stateRevision: failed.stateRevision), state: &state), .confirmationRequired)
    }
}
