import Foundation
import CodexCLIAdapter
import ClaudeCodeAdapter
import SessionDomain
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Codex's helper is intentionally independent from ClaudeHookHelper: it has
/// one one-way observation transport and no callback/action runtime at all.
@main
struct CodexHookHelperMain {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard env["AGENT_ISLAND_CODEX_OBSERVATION_ONLY"] == "1",
              let installation = env["AGENT_ISLAND_INSTALLATION_ID"],
              let helper = env["AGENT_ISLAND_HELPER_ID"] else { exit(64) }
        var body = Data()
        while true {
            guard let chunk = try? FileHandle.standardInput.read(upToCount: 65_537), !chunk.isEmpty else { break }
            body.append(chunk); if body.count > SessionDomainValidator.maxPayloadBytes { exit(64) }
        }
        guard (try? CodexHookEnvelope.decode(body)) != nil else { exit(65) }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Agent Island/IPC", isDirectory: true)
        let endpoint = ClaudeLocalEndpoint(path: root.appendingPathComponent(CodexCLIIntegration.helperEndpointFileName), appOwnedRoot: root)
        #if canImport(Security) && canImport(Network)
        guard let secret = KeychainClaudeHookCredentialStore().secret(for: .init(installation), helperID: helper), !secret.isEmpty else { exit(77) }
        let authenticator = ClaudeIPCAuthenticator(secret: secret)
        guard authenticator.isUsable else { exit(77) }
        let message = ClaudeHookIPCMessage(installationID: .init(installation), helperID: helper, nonce: UUID().uuidString, payload: body, issuedAt: Date(), authenticator: authenticator)
        do { try await ClaudeUnixDomainHookIPCTransport(endpoint: endpoint).send(frame: try ClaudeHookIPCFrame.encode(message), timeout: 2); exit(0) }
        catch { exit(75) }
        #else
        exit(69)
        #endif
    }
}
