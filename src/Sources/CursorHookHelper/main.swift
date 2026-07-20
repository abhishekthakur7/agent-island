import Foundation
import CursorHooksAdapter
import ClaudeCodeAdapter
import SessionDomain
import Darwin

/// One bounded, authenticated, one-way observation envelope.  Cursor command
/// hooks are fail-open by default; every local failure intentionally exits 0
/// with no stdout/stderr and never spools or replays a payload.
@main
struct CursorHookHelperMain {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        let isProbe = env["AGENT_ISLAND_HELPER_PROBE"] == "1"
        guard env["AGENT_ISLAND_CURSOR_OBSERVATION_ONLY"] == "1",
              let installation = env["AGENT_ISLAND_INSTALLATION_ID"],
              let helper = env["AGENT_ISLAND_HELPER_ID"] else { return }
        var body = Data()
        while let chunk = try? FileHandle.standardInput.read(upToCount: 8_193), !chunk.isEmpty {
            body.append(chunk)
            if body.count > CursorHookEnvelope.maximumBytes { return }
        }
        // Decode locally only to reject malformed/oversize input before it
        // crosses IPC.  It is neither logged nor retained by this process.
        guard CursorHookEnvelope.isValid(body) else { return }
        #if canImport(Security) && canImport(Network)
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Agent Island/IPC", isDirectory: true)
        let endpoint = ClaudeLocalEndpoint(path: root.appendingPathComponent("cursor-hooks.sock"), appOwnedRoot: root)
        let installationID = IntegrationInstanceID(installation)
        guard let secret = KeychainClaudeHookCredentialStore().secret(for: installationID, helperID: helper), !secret.isEmpty else {
            if isProbe { exit(77) }
            return
        }
        let authenticator = ClaudeIPCAuthenticator(secret: secret)
        guard authenticator.isUsable else { return }
        let message = ClaudeHookIPCMessage(installationID: installationID, helperID: helper, nonce: UUID().uuidString, payload: body, issuedAt: Date(), authenticator: authenticator)
        guard let frame = try? ClaudeHookIPCFrame.encode(message) else {
            if isProbe { exit(65) }
            return
        }
        do {
            try await ClaudeUnixDomainHookIPCTransport(endpoint: endpoint).send(frame: frame, timeout: 2)
            if isProbe { exit(0) }
        } catch {
            if isProbe { exit(75) }
        }
        #endif
    }
}
