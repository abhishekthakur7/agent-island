import Foundation
import SessionDomain
import SessionStore

/// Headless AB-130 evidence used by the repository self-check. It exercises
/// only local, typed boundaries and deliberately does not open or upload any
/// generated artifact.
enum AB130Evidence {
    static func run() async -> [(String, Bool)] {
        var results: [(String, Bool)] = []
        let fixed = Date(timeIntervalSince1970: 1_752_000_000)

        let diagnostics = DiagnosticEvidenceStore()
        let outcomes: [DiagnosticOutcome] = [.accepted, .filtered, .deduplicated, .quarantined, .downgraded, .rejected, .unavailable, .degraded, .failed]
        for outcome in outcomes {
            _ = await diagnostics.append(DiagnosticEvidence(operation: .inspect, outcome: outcome, scope: DiagnosticScope(component: .integration, owner: .integration, capability: .observation), reason: .unknown, occurredAt: fixed, correlationID: .generated(), safeNextStep: .inspect))
        }
        let records = await diagnostics.all()
        results.append(("ab130.diagnosticOutcomesAllowlisted", records.map(\.outcome) == outcomes))
        if let bundle = try? await diagnostics.previewBundle(at: fixed) {
            let safe = !bundle.humanReadable.contains("prompt") && !bundle.humanReadable.contains("/private") && !bundle.humanReadable.contains("token")
            results.append(("ab130.bundleRedacted", safe && bundle.machineReadable.count > 0))
        } else {
            results.append(("ab130.bundleRedacted", false))
        }

        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("session"))
        let content = SessionHistoryContent(contentID: "content", bytes: Data("selected interaction content".utf8))
        let exportRecord = VerifiedUserDataRecord(identity: identity, interactionContent: [content])
        let selection = UserDataExportSelection(sessions: [identity], dataClasses: [.interactionContent], includeInteractionContent: true)
        do {
            let preview = try UserDataExportWriter.preview(selection: selection, verifiedRecords: [exportRecord], at: fixed)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab130-self-check-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = try UserDataExportDestination(file: root.appendingPathComponent("selected.json"))
            let unconfirmed = (try? UserDataExportWriter.write(selection: selection, verifiedRecords: [exportRecord], confirmation: preview.confirmation.confirming(), destination: destination, at: fixed)) == nil
            results.append(("ab130.exportSeparateConfirmation", unconfirmed))
            let artifacts = try UserDataExportWriter.write(selection: selection, verifiedRecords: [exportRecord], confirmation: preview.confirmation.confirmingInteractionContent(), destination: destination, at: fixed)
            let bytes = try Data(contentsOf: artifacts.data)
            results.append(("ab130.exportIntegrityManifest", FileManager.default.fileExists(atPath: artifacts.integrityManifest.path) && bytes.count > 0))
        } catch {
            results.append(("ab130.exportSeparateConfirmation", false))
            results.append(("ab130.exportIntegrityManifest", false))
        }

        let maintenance = MaintenanceStore()
        let request = MaintenanceRequest(flow: .removeManifestProvenSetup, manifestScopes: [MaintenanceManifestScope(manifestID: "manifest", exactEntryCount: 1, ownedArtifactCount: 0, lifecycle: .drifted, residualKnown: true)])
        let preview = await maintenance.preview(request, at: fixed)
        let outcome = await maintenance.apply(preview, confirmation: preview.confirmation.confirming())
        if case .partialWithResidual = outcome {
            results.append(("ab130.maintenanceResidualHonesty", true))
        } else {
            results.append(("ab130.maintenanceResidualHonesty", false))
        }
        return results
    }
}
