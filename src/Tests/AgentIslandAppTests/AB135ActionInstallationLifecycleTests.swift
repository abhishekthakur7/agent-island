import XCTest
@testable import AgentIslandApp
@testable import ClaudeCodeAdapter
@testable import SessionDomain

@MainActor
final class AB135ActionInstallationLifecycleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 20_000)

    private func snapshot(for installationID: IntegrationInstanceID) -> NegotiationSnapshot {
        let provenance = CapabilityProvenance(
            snapshotID: NegotiationSnapshotID("ab135-installation-snapshot"),
            integrationInstanceID: installationID,
            productNamespace: ClaudeCodeIntegration.productNamespace,
            integrationMode: ClaudeCodeIntegration.integrationMode
        )
        let capabilities = ClaudeCodeIntegration.allActionCapabilities.map {
            CapabilityRecord(id: $0, direction: .act, availability: .available, scope: .request, provenance: provenance, semanticVariant: $0)
        }
        return NegotiationSnapshot(
            id: NegotiationSnapshotID("ab135-installation-snapshot"),
            contractVersion: ContractVersion(major: 1, minor: 0),
            adapterKind: ClaudeCodeIntegration.adapterKind,
            adapterBuildVersion: "test",
            productNamespace: ClaudeCodeIntegration.productNamespace,
            integrationInstanceID: installationID,
            integrationMode: ClaudeCodeIntegration.integrationMode,
            capabilities: capabilities,
            negotiatedAt: now
        )
    }

    private func installationAndManifest(for installationID: IntegrationInstanceID) -> (IntegrationInstallation, OwnershipManifest) {
        let scope = IntegrationInstallationScope(kind: .customPath, identifier: "test", path: "/tmp/ab135-installation.json")
        let installation = IntegrationInstallation(
            id: installationID,
            product: ClaudeCodeIntegration.productNamespace,
            integrationMode: ClaudeCodeIntegration.integrationMode,
            scope: scope,
            lifecycle: .enabled,
            enabledIntent: true
        )
        let manifest = OwnershipManifest(
            id: "ab135-installation-manifest",
            installationID: installationID.rawValue,
            product: ClaudeCodeIntegration.productNamespace,
            integrationMode: ClaudeCodeIntegration.integrationMode,
            scope: scope,
            sourcePath: scope.path,
            entries: [],
            lifecycle: .active,
            verification: OwnershipManifestVerificationEvidence(
                verifiedAt: now,
                reread: true,
                probeSucceeded: true,
                sourceFingerprint: ExactEntrySourceFingerprint(content: ExactEntryFingerprint("fixture")),
                capabilityIDs: [ClaudeCodeIntegration.permissionCapability]
            ),
            createdAt: now
        )
        return (installation, manifest)
    }

    func testRetainedInstallationLifecycleActivatesWithInMemoryCredentialAtInjectedEndpoint() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-island-ab135-lifecycle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeLocalEndpoint(path: root.appendingPathComponent("actions.sock"), appOwnedRoot: root)
        let composition = ClaudeActionApplicationComposition(endpointOverride: endpoint)
        let lifecycle = ClaudeActionIntegrationLifecycle(composition: composition)
        let installationID = IntegrationInstanceID("ab135-lifecycle-installation")
        let (installation, manifest) = installationAndManifest(for: installationID)
        let credentialStore = InMemoryClaudeHookCredentialStore(secret: Data("test-secret".utf8), installationID: installationID, helperID: "helper")

        XCTAssertTrue(await lifecycle.activate(installation: installation, manifest: manifest, helperID: "helper", snapshot: snapshot(for: installationID), credentialStore: credentialStore))
        XCTAssertTrue(FileManager.default.fileExists(atPath: endpoint.path), "test endpoint is app-owned temporary state, never the user's production socket")
        await lifecycle.retireCurrentInstallation()
        XCTAssertFalse(FileManager.default.fileExists(atPath: endpoint.path))
    }

    func testRetainedInstallationLifecycleFailsClosedWithoutCredentialAndDoesNotBindEndpoint() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-island-ab135-lifecycle-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeLocalEndpoint(path: root.appendingPathComponent("actions.sock"), appOwnedRoot: root)
        let composition = ClaudeActionApplicationComposition(endpointOverride: endpoint)
        let lifecycle = ClaudeActionIntegrationLifecycle(composition: composition)
        let installationID = IntegrationInstanceID("ab135-lifecycle-failure")
        let (installation, manifest) = installationAndManifest(for: installationID)

        XCTAssertFalse(await lifecycle.activate(installation: installation, manifest: manifest, helperID: "helper", snapshot: snapshot(for: installationID), credentialStore: InMemoryClaudeHookCredentialStore(secret: nil)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: endpoint.path))
    }
}
