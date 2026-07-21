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
        let observationEndpoint = ClaudeLocalEndpoint(path: root.appendingPathComponent("claude-hooks.sock"), appOwnedRoot: root)
        let actionEndpoint = ClaudeLocalEndpoint(path: root.appendingPathComponent("claude-actions.sock"), appOwnedRoot: root)
        #if canImport(Network)
        guard let runtime = try? ClaudeHookHelperRuntime(installationID: IntegrationInstanceID(installation), helperID: helper, credentialStore: DerivedClaudeHookCredentialStore(), endpoint: observationEndpoint),
              let actionRuntime = try? ClaudeHookHelperRuntime(installationID: IntegrationInstanceID(installation), helperID: helper, credentialStore: DerivedClaudeHookCredentialStore(), endpoint: actionEndpoint) else { exit(77) }
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
        do {
            if isDocumentedSynchronousAction(body) {
                // The Product-controlled environment supplies neither endpoint
                // nor timeout. Bound waiting by the helper's provisioned safe
                // timeout and write one native response only on exact success.
                let transport = ClaudeUnixDomainActionIPCTransport(endpoint: actionEndpoint)
                let response = try await actionRuntime.respondToAction(stdin: body, deadline: Date().addingTimeInterval(actionRuntime.timeout), transport: transport)
                try FileHandle.standardOutput.write(contentsOf: response)
            } else {
                let transport = ClaudeUnixDomainHookIPCTransport(endpoint: observationEndpoint)
                _ = try await runtime.forward(stdin: body, transport: transport)
            }
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

    private static func isDocumentedSynchronousAction(_ body: Data) -> Bool {
        guard let hook = try? ClaudeHookEnvelope.decode(body) else { return false }
        if hook.name == .permissionRequest { return hook.nativeAttentionRequestID?.isEmpty == false && hook.nativeToolUseID == nil }
        guard hook.name == .preToolUse, hook.nativeToolUseID?.isEmpty == false,
              let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        let name = root["tool_name"] as? String ?? root["toolName"] as? String
        return name == "AskUserQuestion" || name == "ExitPlanMode"
    }
}
