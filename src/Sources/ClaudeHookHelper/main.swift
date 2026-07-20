import Foundation
import ClaudeCodeAdapter
import SessionDomain
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct ClaudeHookHelperMain {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        guard let installation = env["AGENT_ISLAND_INSTALLATION_ID"],
              let helper = env["AGENT_ISLAND_HELPER_ID"] else { exit(64) }
        // Hook environments are Product-controlled. The endpoint location is
        // application-owned and intentionally has no environment override.
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Agent Island/IPC", isDirectory: true)
        let endpoint = ClaudeLocalEndpoint(path: root.appendingPathComponent("claude-hooks.sock"), appOwnedRoot: root)
        #if canImport(Security)
        guard let runtime = try? ClaudeHookHelperRuntime(installationID: IntegrationInstanceID(installation), helperID: helper, credentialStore: KeychainClaudeHookCredentialStore(), endpoint: endpoint) else { exit(77) }
        #else
        exit(69)
        #endif
        var body = Data(); let input = FileHandle.standardInput
        while true {
            guard let chunk = try? input.read(upToCount: 65_537), !chunk.isEmpty else { break }
            body.append(chunk)
            if body.count > SessionDomainValidator.maxPayloadBytes { exit(64) }
        }
        #if canImport(Network)
        let transport = ClaudeUnixDomainHookIPCTransport(endpoint: endpoint)
        do {
            _ = try await runtime.forward(stdin: body, transport: transport)
            exit(0)
        } catch let error as ClaudeHookHelperError {
            switch error {
            case .oversizedStdin, .malformedJSON, .frameTooLarge:
                exit(65)
            case .endpointUnavailable, .transportTimeout, .transportFailure:
                exit(75)
            case .endpointUntrusted, .emptyAuthenticator, .credentialMissing, .credentialInvalid:
                exit(77)
            }
        } catch {
            exit(70)
        }
        #else
        exit(69)
        #endif
    }
}
