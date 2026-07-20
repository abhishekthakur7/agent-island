import Foundation
import ClaudeActionRouting
import ClaudeCodeAdapter
import SessionDomain

/// App-lifetime owner for the local Claude synchronous-action endpoint.  The
/// integration setup flow supplies the current negotiated configuration; an
/// absent or failed configuration stays fail-closed and is intentionally not
/// surfaced through diagnostics (it can contain endpoint and credential
/// metadata).  This object is retained by `AgentIslandApp`, not a test.
@MainActor
final class ClaudeActionApplicationComposition {
    private var production: ClaudeActionProductionComposition?

    @discardableResult
    func install(configuration: ClaudeActionRequestListener.Configuration) async -> Bool {
        await retire()
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Agent Island/IPC", isDirectory: true)
        let endpoint = ClaudeLocalEndpoint(path: root.appendingPathComponent("claude-actions.sock"), appOwnedRoot: root)
        let production = await ClaudeActionProductionComposition(endpoint: endpoint, configuration: configuration)
        guard production.start() else { return false }
        self.production = production
        return true
    }

    func retire() async {
        guard let production else { return }
        self.production = nil
        await production.stop()
    }
}

/// The only GUI-facing action endpoint lifecycle.  Integration installation
/// code calls this after it has proved an enabled owned manifest and supplied
/// a current action-capability snapshot plus the Keychain-backed credential.
/// Any later disable, helper loss, removal, or capability change calls
/// `retire`; absence never starts a listener.
@MainActor
final class ClaudeActionIntegrationLifecycle {
    private let composition: ClaudeActionApplicationComposition

    init(composition: ClaudeActionApplicationComposition) { self.composition = composition }

    /// Concrete installation-flow hook.  It accepts only the current enabled
    /// installation and its reread/probed active manifest, then obtains the
    /// same per-helper secret that the generated helper reads from Keychain.
    /// The secret is used only to build the in-memory authenticator and is
    /// never written to preferences, diagnostics, or the hook command.
    @discardableResult
    func activate(
        installation: IntegrationInstallation,
        manifest: OwnershipManifest,
        helperID: String,
        snapshot: NegotiationSnapshot,
        credentialStore: any ClaudeHookCredentialStore = KeychainClaudeHookCredentialStore()
    ) async -> Bool {
        guard installation.lifecycle == .enabled,
              installation.enabledIntent,
              installation.id.rawValue == manifest.installationID,
              installation.product == ClaudeCodeIntegration.productNamespace,
              installation.integrationMode == ClaudeCodeIntegration.integrationMode,
              manifest.lifecycle == .active,
              manifest.verification?.reread == true,
              manifest.verification?.probeSucceeded == true,
              snapshot.integrationInstanceID == installation.id,
              manifest.verification?.capabilityIDs.contains(where: ClaudeCodeIntegration.allActionCapabilities.contains) == true,
              let secret = credentialStore.secret(for: installation.id, helperID: helperID), !secret.isEmpty
        else {
            await composition.retire()
            return false
        }
        let configuration = ClaudeActionRequestListener.Configuration(
            installationID: installation.id,
            helperID: helperID,
            authenticator: ClaudeIPCAuthenticator(secret: secret),
            snapshot: snapshot
        )
        return await activateCurrentInstallation(configuration)
    }

    @discardableResult
    func activateCurrentInstallation(_ configuration: ClaudeActionRequestListener.Configuration) async -> Bool {
        guard configuration.snapshot.integrationInstanceID == configuration.installationID,
              configuration.snapshot.capabilities.contains(where: { $0.direction == .act && $0.availability == .available && $0.freshness == .current })
        else {
            await composition.retire()
            return false
        }
        return await composition.install(configuration: configuration)
    }

    func retireCurrentInstallation() async { await composition.retire() }
}
