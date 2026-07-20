import Foundation
import SessionDomain

/// A deliberately small command vocabulary for the documented Orca CLI.
/// It contains no terminal input, terminal lifecycle, pane-layout, title,
/// path-discovery, or Product-action operation.
public enum OrcaRuntimeCommand: Hashable, Sendable {
    case status
    case terminalShow(handle: String)
    case terminalSwitch(handle: String)
    case worktreeShow(id: String)
    case fileOpen(worktreeID: String, fileID: String)
    case openApplication

    fileprivate var arguments: [String] {
        switch self {
        case .status: ["status", "--json"]
        case .terminalShow(let handle): ["terminal", "show", "--terminal", handle, "--json"]
        case .terminalSwitch(let handle): ["terminal", "switch", "--terminal", handle, "--json"]
        case .worktreeShow(let id): ["worktree", "show", "--worktree", "id:\(id)", "--json"]
        case .fileOpen(let workspaceID, let fileID): ["file", "open", "--path", fileID, "--worktree", "id:\(workspaceID)", "--json"]
        case .openApplication: ["open", "--json"]
        }
    }
}

public enum OrcaRuntimeClientFailure: String, Error, Hashable, Sendable, Codable {
    case commandUnavailable
    case commandFailed
    case malformedResponse
    case runtimeUnavailable
    case runtimeContradiction
    case runtimeVersionMissing
    case handleUnavailable
    case handleContradiction
    case tabContradiction
    case workspaceUnavailable
    case selectionRejected
    case unsupportedNavigation
}

/// Injectable outer transport. Production invokes the public `orca` command;
/// fixtures can return the exact documented JSON envelope without spawning a
/// process. It has no terminal-control method outside documented selection.
public protocol OrcaRuntimeCommandTransport: Sendable {
    func run(_ command: OrcaRuntimeCommand) -> Result<Data, OrcaRuntimeClientFailure>
}

public final class OrcaCLICommandTransport: @unchecked Sendable, OrcaRuntimeCommandTransport {
    private let executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/local/bin/orca")) {
        self.executableURL = executableURL
    }

    public func run(_ command: OrcaRuntimeCommand) -> Result<Data, OrcaRuntimeClientFailure> {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = command.arguments
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return .failure(.commandFailed) }
            return .success(output.fileHandleForReading.readDataToEndOfFile())
        } catch {
            return .failure(.commandUnavailable)
        }
    }
}

/// Current evidence issued by one live Orca runtime. `runtimeID` is the
/// public status response's opaque incarnation. Current Orca status responses
/// do not expose a semantic build string, so this is also the version-matched
/// runtime discriminator stored in the existing domain locator contract.
public struct OrcaRuntimeStatus: Hashable, Sendable {
    public let runtimeID: String
    public let runtimeVersion: String
    public let appAvailable: Bool

    public init(runtimeID: String, runtimeVersion: String, appAvailable: Bool) {
        self.runtimeID = runtimeID
        self.runtimeVersion = runtimeVersion
        self.appAvailable = appAvailable
    }
}

/// This is intentionally smaller than the public terminal response. Titles,
/// paths, previews, PTY IDs, and internal leaf IDs are neither decoded nor
/// retained, so they cannot become cross-runtime selectors.
public struct OrcaTerminalEvidence: Hashable, Sendable {
    public let runtime: OrcaRuntimeStatus
    public let handle: String
    public let tabID: String
    public let connected: Bool
    public let candidateCount: Int
    /// Only a documented current runtime response may set this true. A stable
    /// pane ID or a visual-layout observation is never such proof.
    public let exactChildSurfaceSelected: Bool

    public init(
        runtime: OrcaRuntimeStatus,
        handle: String,
        tabID: String,
        connected: Bool,
        candidateCount: Int = 1,
        exactChildSurfaceSelected: Bool = false
    ) {
        self.runtime = runtime
        self.handle = handle
        self.tabID = tabID
        self.connected = connected
        self.candidateCount = max(0, candidateCount)
        self.exactChildSurfaceSelected = exactChildSurfaceSelected
    }
}

public struct OrcaWorkspaceEvidence: Hashable, Sendable {
    public let runtime: OrcaRuntimeStatus
    public let workspaceID: String
    public let fileID: String?

    public init(runtime: OrcaRuntimeStatus, workspaceID: String, fileID: String?) {
        self.runtime = runtime
        self.workspaceID = workspaceID
        self.fileID = fileID
    }
}

public protocol OrcaDocumentedRuntimeClient: Sendable {
    func inspectTerminal(handle: String) -> Result<OrcaTerminalEvidence, OrcaRuntimeClientFailure>
    func inspectWorkspace(workspaceID: String, fileID: String?) -> Result<OrcaWorkspaceEvidence, OrcaRuntimeClientFailure>
    func switchTerminal(
        handle: String,
        expectedRuntimeID: String,
        expectedRuntimeVersion: String,
        expectedTabID: String,
        requireExactChildSurface: Bool
    ) -> Result<Void, OrcaRuntimeClientFailure>
    func openWorkspaceFile(
        workspaceID: String,
        fileID: String,
        expectedRuntimeID: String
    ) -> Result<Void, OrcaRuntimeClientFailure>
    func activateApplication() -> Result<Void, OrcaRuntimeClientFailure>
}

/// Production implementation for Orca's documented CLI/runtime JSON API.
/// Each selection re-runs status and terminal show before terminal switch;
/// an opaque handle is therefore never reused solely because it was captured
/// earlier. The only mutating commands are documented navigation commands.
public final class OrcaCLIClient: @unchecked Sendable, OrcaDocumentedRuntimeClient {
    private let transport: any OrcaRuntimeCommandTransport

    public init(transport: any OrcaRuntimeCommandTransport = OrcaCLICommandTransport()) {
        self.transport = transport
    }

    public func inspectTerminal(handle: String) -> Result<OrcaTerminalEvidence, OrcaRuntimeClientFailure> {
        switch status() {
        case .failure(let failure): return .failure(failure)
        case .success(let runtime):
            guard runtime.appAvailable else { return .failure(.runtimeUnavailable) }
            switch decode(transport.run(.terminalShow(handle: handle)), as: OrcaTerminalShowResult.self) {
            case .failure(let failure): return .failure(failure)
            case .success(let response):
                guard response.meta.runtimeID == runtime.runtimeID else { return .failure(.runtimeContradiction) }
                guard response.value.terminal.handle == handle else { return .failure(.handleContradiction) }
                guard !response.value.terminal.tabID.isEmpty else { return .failure(.malformedResponse) }
                return .success(.init(
                    runtime: runtime,
                    handle: handle,
                    tabID: response.value.terminal.tabID,
                    connected: response.value.terminal.connected,
                    exactChildSurfaceSelected: response.value.terminal.exactChildSurfaceSelected ?? false
                ))
            }
        }
    }

    public func inspectWorkspace(workspaceID: String, fileID: String?) -> Result<OrcaWorkspaceEvidence, OrcaRuntimeClientFailure> {
        switch status() {
        case .failure(let failure): return .failure(failure)
        case .success(let runtime):
            guard runtime.appAvailable else { return .failure(.runtimeUnavailable) }
            switch decode(transport.run(.worktreeShow(id: workspaceID)), as: OrcaWorktreeShowResult.self) {
            case .failure(let failure): return .failure(failure)
            case .success(let response):
                guard response.meta.runtimeID == runtime.runtimeID else { return .failure(.runtimeContradiction) }
                guard response.value.worktree.id == workspaceID else { return .failure(.workspaceUnavailable) }
                return .success(.init(runtime: runtime, workspaceID: workspaceID, fileID: fileID))
            }
        }
    }

    public func switchTerminal(handle: String, expectedRuntimeID: String, expectedRuntimeVersion: String, expectedTabID: String, requireExactChildSurface: Bool) -> Result<Void, OrcaRuntimeClientFailure> {
        // Revalidate the opaque handle inside the operation as well as at the
        // port boundary; this closes a restart/terminal-close race.
        switch inspectTerminal(handle: handle) {
        case .failure(let failure): return .failure(failure)
        case .success(let evidence):
            guard evidence.runtime.runtimeID == expectedRuntimeID else { return .failure(.runtimeContradiction) }
            guard evidence.runtime.runtimeVersion == expectedRuntimeVersion else { return .failure(.runtimeVersionMissing) }
            guard evidence.tabID == expectedTabID else { return .failure(.tabContradiction) }
            guard evidence.connected else { return .failure(.handleUnavailable) }
            guard !requireExactChildSurface || evidence.exactChildSurfaceSelected else { return .failure(.unsupportedNavigation) }
            switch decode(transport.run(.terminalSwitch(handle: handle)), as: OrcaEmptyResult.self) {
            case .failure(let failure): return .failure(failure)
            case .success(let response):
                guard response.meta.runtimeID == expectedRuntimeID else { return .failure(.runtimeContradiction) }
                return .success(())
            }
        }
    }

    public func openWorkspaceFile(workspaceID: String, fileID: String, expectedRuntimeID: String) -> Result<Void, OrcaRuntimeClientFailure> {
        switch inspectWorkspace(workspaceID: workspaceID, fileID: fileID) {
        case .failure(let failure): return .failure(failure)
        case .success(let evidence):
            guard evidence.runtime.runtimeID == expectedRuntimeID else { return .failure(.runtimeContradiction) }
            switch decode(transport.run(.fileOpen(worktreeID: workspaceID, fileID: fileID)), as: OrcaEmptyResult.self) {
            case .failure(let failure): return .failure(failure)
            case .success(let response):
                guard response.meta.runtimeID == expectedRuntimeID else { return .failure(.runtimeContradiction) }
                return .success(())
            }
        }
    }

    public func activateApplication() -> Result<Void, OrcaRuntimeClientFailure> {
        switch decode(transport.run(.openApplication), as: OrcaEmptyResult.self) {
        case .failure(let failure): return .failure(failure)
        case .success: return .success(())
        }
    }

    private func status() -> Result<OrcaRuntimeStatus, OrcaRuntimeClientFailure> {
        switch decode(transport.run(.status), as: OrcaStatusResult.self) {
        case .failure(let failure): return .failure(failure)
        case .success(let response):
            let runtimeID = response.value.runtime.runtimeID
            guard !runtimeID.isEmpty, response.meta.runtimeID == runtimeID, response.value.runtime.reachable, response.value.runtime.state == "ready" else {
                return .failure(.runtimeUnavailable)
            }
            // Runtime `runtimeId` is the version-matched live instance in the
            // current public CLI. A future explicit `runtimeVersion` is used
            // verbatim without changing this boundary.
            let version = response.value.runtime.runtimeVersion ?? runtimeID
            guard !version.isEmpty else { return .failure(.runtimeVersionMissing) }
            let appAvailable = response.value.app.running && response.value.app.desktopWindowStatus == "available"
            return .success(.init(runtimeID: runtimeID, runtimeVersion: version, appAvailable: appAvailable))
        }
    }

    private func decode<Value: Decodable>(_ raw: Result<Data, OrcaRuntimeClientFailure>, as: Value.Type) -> Result<OrcaEnvelope<Value>, OrcaRuntimeClientFailure> {
        switch raw {
        case .failure(let failure): return .failure(failure)
        case .success(let data):
            guard let envelope = try? JSONDecoder().decode(OrcaEnvelope<Value>.self, from: data), envelope.ok, let value = envelope.result, !envelope.meta.runtimeID.isEmpty else {
                return .failure(.malformedResponse)
            }
            return .success(envelope.with(value))
        }
    }
}

private struct OrcaEnvelope<Value: Decodable>: Decodable {
    let ok: Bool
    let result: Value?
    let meta: OrcaMeta
    enum CodingKeys: String, CodingKey { case ok, result, meta = "_meta" }
    var value: Value { result! }
    func with(_ value: Value) -> OrcaEnvelope<Value> { .init(ok: ok, result: value, meta: meta) }
}

private struct OrcaMeta: Decodable { let runtimeID: String; enum CodingKeys: String, CodingKey { case runtimeID = "runtimeId" } }
private struct OrcaStatusResult: Decodable {
    let app: OrcaAppStatus
    let runtime: OrcaRuntimeJSON
}
private struct OrcaAppStatus: Decodable { let running: Bool; let desktopWindowStatus: String? }
private struct OrcaRuntimeJSON: Decodable {
    let state: String
    let reachable: Bool
    let runtimeID: String
    let runtimeVersion: String?
    enum CodingKeys: String, CodingKey { case state, reachable, runtimeID = "runtimeId", runtimeVersion }
}
private struct OrcaTerminalShowResult: Decodable { let terminal: OrcaTerminalJSON }
private struct OrcaTerminalJSON: Decodable {
    let handle: String
    let tabID: String
    let connected: Bool
    let exactChildSurfaceSelected: Bool?
    enum CodingKeys: String, CodingKey { case handle, tabID = "tabId", connected, exactChildSurfaceSelected }
}
private struct OrcaWorktreeShowResult: Decodable { let worktree: OrcaWorktreeJSON }
private struct OrcaWorktreeJSON: Decodable { let id: String }
private struct OrcaEmptyResult: Decodable {}

/// Captures associations only from a current typed runtime/terminal or
/// worktree/file response. The opaque terminal handle remains in the locator,
/// independently of the Product-owned Agent Session identity.
public final class OrcaHostContextCapture: @unchecked Sendable {
    private let client: any OrcaDocumentedRuntimeClient

    public init(client: any OrcaDocumentedRuntimeClient = OrcaCLIClient()) { self.client = client }

    public func captureTerminal(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        terminalHandle: String,
        at date: Date
    ) -> Result<HostContextAssociation, OrcaRuntimeClientFailure> {
        switch client.inspectTerminal(handle: terminalHandle) {
        case .failure(let failure): return .failure(failure)
        case .success(let evidence):
            guard evidence.connected, evidence.candidateCount == 1 else { return .failure(.handleUnavailable) }
            return .success(association(
                id: id,
                sessionIdentity: sessionIdentity,
                integrationInstanceID: integrationInstanceID,
                integrationMode: integrationMode,
                incarnation: .init(evidence.runtime.runtimeID),
                hostVersion: evidence.runtime.runtimeVersion,
                locator: .orcaRuntimeTab(runtimeHandle: evidence.handle, tabID: evidence.tabID, runtimeVersion: evidence.runtime.runtimeVersion),
                at: date
            ))
        }
    }

    public func captureWorkspaceFile(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        workspaceID: String,
        fileID: String,
        at date: Date
    ) -> Result<HostContextAssociation, OrcaRuntimeClientFailure> {
        switch client.inspectWorkspace(workspaceID: workspaceID, fileID: fileID) {
        case .failure(let failure): return .failure(failure)
        case .success(let evidence):
            guard evidence.fileID == fileID, !fileID.isEmpty else { return .failure(.workspaceUnavailable) }
            return .success(association(
                id: id,
                sessionIdentity: sessionIdentity,
                integrationInstanceID: integrationInstanceID,
                integrationMode: integrationMode,
                incarnation: .init(evidence.runtime.runtimeID),
                hostVersion: evidence.runtime.runtimeVersion,
                locator: .orcaWorkspace(workspaceID: workspaceID, fileID: fileID),
                at: date
            ))
        }
    }

    private func association(id: HostContextID, sessionIdentity: AgentSessionIdentity, integrationInstanceID: IntegrationInstanceID, integrationMode: String, incarnation: HostIncarnation, hostVersion: String, locator: HostLocator, at date: Date) -> HostContextAssociation {
        .init(
            id: id,
            sessionIdentity: sessionIdentity,
            host: .orca,
            hostVersion: hostVersion,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            incarnation: incarnation,
            locator: locator,
            provenance: .init(host: .orca, hostVersion: hostVersion, endpointID: "orca-cli-runtime", evidence: .documentedRuntime, observedAt: date),
            validity: .live,
            firstObservedAt: date,
            lastValidatedAt: date
        )
    }
}

/// The real Orca HostNavigationPort. It observes only documented runtime
/// responses and dispatches only `terminal switch`, `file open`, or `open`.
/// In particular it never sends, stops, creates, splits, closes, or renames a
/// terminal, and it never performs Product actions.
public final class OrcaHostNavigationPort: @unchecked Sendable, HostNavigationPort {
    private let client: any OrcaDocumentedRuntimeClient
    private let lock = NSLock()
    private var verifiedTerminals: [HostContextID: OrcaTerminalEvidence] = [:]
    private var verifiedWorkspaces: [HostContextID: OrcaWorkspaceEvidence] = [:]

    public init(client: any OrcaDocumentedRuntimeClient = OrcaCLIClient()) { self.client = client }

    public func invalidateLiveReferences() {
        lock.lock()
        verifiedTerminals.removeAll()
        verifiedWorkspaces.removeAll()
        lock.unlock()
    }

    public func revalidate(_ association: HostContextAssociation, for sessionIdentity: AgentSessionIdentity, negotiation: NegotiationSnapshot?, at date: Date) -> HostNavigationRevalidation {
        guard association.host == .orca else { return unavailable(association, sessionIdentity, negotiation, date, .unsupportedHost) }
        switch association.locator {
        case .orcaRuntimeTab(let recordedHandle, let recordedTabID, _):
            switch client.inspectTerminal(handle: recordedHandle) {
            case .failure(let failure):
                clear(association.id)
                return unavailable(association, sessionIdentity, negotiation, date, revalidationReason(for: failure))
            case .success(let evidence):
                let exact = evidence.handle == recordedHandle && evidence.tabID == recordedTabID && evidence.connected && evidence.candidateCount == 1
                let levels: Set<HostNavigationLevel> = exact ? (evidence.exactChildSurfaceSelected ? [.exactSurface, .exactTab] : [.exactTab]) : []
                let observation = HostRuntimeObservation(
                    host: .orca,
                    hostVersion: evidence.runtime.runtimeVersion,
                    integrationMode: association.integrationMode,
                    endpointID: "orca-cli-runtime",
                    incarnation: .init(evidence.runtime.runtimeID),
                    applicationState: evidence.runtime.appAvailable ? .available : .absent,
                    locatorState: exact ? .live : (evidence.connected ? .recreated : .closed),
                    provenLevels: levels,
                    candidateCount: exact ? 1 : 0,
                    runtimeHandle: exact ? evidence.handle : nil,
                    runtimeVersion: evidence.runtime.runtimeVersion,
                    childSurfaceFocusProven: evidence.exactChildSurfaceSelected
                )
                if exact { store(evidence, for: association.id) } else { clear(association.id) }
                return HostNavigationPolicy.revalidate(association: association, sessionIdentity: sessionIdentity, negotiation: negotiation, observation: observation, at: date)
            }
        case .orcaWorkspace(let workspaceID, let fileID):
            switch client.inspectWorkspace(workspaceID: workspaceID, fileID: fileID) {
            case .failure(let failure):
                clear(association.id)
                return unavailable(association, sessionIdentity, negotiation, date, revalidationReason(for: failure))
            case .success(let evidence):
                let independentlyProven = evidence.workspaceID == workspaceID && evidence.fileID == fileID && fileID?.isEmpty == false
                let observation = HostRuntimeObservation(
                    host: .orca,
                    hostVersion: evidence.runtime.runtimeVersion,
                    integrationMode: association.integrationMode,
                    endpointID: "orca-cli-runtime",
                    incarnation: .init(evidence.runtime.runtimeID),
                    applicationState: evidence.runtime.appAvailable ? .available : .absent,
                    locatorState: independentlyProven ? .live : .recreated,
                    provenLevels: independentlyProven ? [.workspaceOrFile] : [],
                    candidateCount: independentlyProven ? 1 : 0,
                    runtimeVersion: evidence.runtime.runtimeVersion,
                    workspaceOrFileProven: independentlyProven,
                    provenWorkspaceID: independentlyProven ? workspaceID : nil,
                    provenFileID: independentlyProven ? fileID : nil
                )
                if independentlyProven { store(evidence, for: association.id) } else { clear(association.id) }
                return HostNavigationPolicy.revalidate(association: association, sessionIdentity: sessionIdentity, negotiation: negotiation, observation: observation, at: date)
            }
        default:
            return unavailable(association, sessionIdentity, negotiation, date, .unsupportedHost)
        }
    }

    public func navigate(_ target: HostNavigationTarget, at date: Date) -> HostNavigationDispatch {
        guard target.host == .orca else { return .rejected(.unsupportedHost) }
        switch (target.level, target.locator) {
        case (.exactTab, .orcaRuntimeTab(let handle, let tabID, let version)), (.exactSurface, .orcaRuntimeTab(let handle, let tabID, let version)):
            guard let evidence = terminal(for: target.associationID), evidence.handle == handle, evidence.tabID == tabID, evidence.runtime.runtimeVersion == version else {
                return .rejected(.locatorInvalidated)
            }
            let requireChild = target.level == .exactSurface
            switch client.switchTerminal(handle: handle, expectedRuntimeID: evidence.runtime.runtimeID, expectedRuntimeVersion: version, expectedTabID: tabID, requireExactChildSurface: requireChild) {
            case .success: return .reached
            case .failure(let failure): clear(target.associationID); return .rejected(revalidationReason(for: failure))
            }
        case (.workspaceOrFile, .orcaWorkspace(let workspaceID, let fileID)):
            guard let fileID, let evidence = workspace(for: target.associationID), evidence.workspaceID == workspaceID, evidence.fileID == fileID else {
                return .rejected(.locatorInvalidated)
            }
            switch client.openWorkspaceFile(workspaceID: workspaceID, fileID: fileID, expectedRuntimeID: evidence.runtime.runtimeID) {
            case .success: return .reached
            case .failure(let failure): clear(target.associationID); return .rejected(revalidationReason(for: failure))
            }
        case (.appOnly, _):
            switch client.activateApplication() {
            case .success: return .reached
            case .failure(let failure): return .rejected(revalidationReason(for: failure))
            }
        default:
            return .rejected(.unsupportedHost)
        }
    }

    private func unavailable(_ association: HostContextAssociation, _ identity: AgentSessionIdentity, _ negotiation: NegotiationSnapshot?, _ date: Date, _ reason: HostNavigationRevalidationReason) -> HostNavigationRevalidation {
        HostNavigationRevalidation(associationID: association.id, sessionIdentity: identity, host: association.host, integrationMode: association.integrationMode, permission: .notRequired, locatorState: .unavailable, evaluatedAt: date, capabilityGranted: negotiation?.grants(WellKnownCapability.hostNavigation, direction: .navigate) == true, locatorMatches: false, incarnationMatches: false, reason: reason)
    }

    private func revalidationReason(for failure: OrcaRuntimeClientFailure) -> HostNavigationRevalidationReason {
        switch failure {
        case .handleUnavailable: .locatorClosed
        case .handleContradiction, .tabContradiction: .locatorRecreated
        case .runtimeContradiction: .incarnationChanged
        case .runtimeVersionMissing: .runtimeVersionChanged
        case .workspaceUnavailable: .locatorClosed
        case .runtimeUnavailable: .hostUnavailable
        case .selectionRejected, .unsupportedNavigation: .dispatchFailed
        case .commandUnavailable, .commandFailed, .malformedResponse: .hostUnavailable
        }
    }

    private func store(_ evidence: OrcaTerminalEvidence, for id: HostContextID) { lock.lock(); verifiedTerminals[id] = evidence; verifiedWorkspaces.removeValue(forKey: id); lock.unlock() }
    private func store(_ evidence: OrcaWorkspaceEvidence, for id: HostContextID) { lock.lock(); verifiedWorkspaces[id] = evidence; verifiedTerminals.removeValue(forKey: id); lock.unlock() }
    private func terminal(for id: HostContextID) -> OrcaTerminalEvidence? { lock.lock(); defer { lock.unlock() }; return verifiedTerminals[id] }
    private func workspace(for id: HostContextID) -> OrcaWorkspaceEvidence? { lock.lock(); defer { lock.unlock() }; return verifiedWorkspaces[id] }
    private func clear(_ id: HostContextID) { lock.lock(); verifiedTerminals.removeValue(forKey: id); verifiedWorkspaces.removeValue(forKey: id); lock.unlock() }
}

/// Adapter-local composition storage mirrors the existing Host boundary: it
/// retains Host evidence and negotiated capability snapshots, never Product
/// lifecycle/action state. Application registration may use this object
/// without giving the adapter a store, overlay, or settings dependency.
public final class OrcaHostNavigationComposition: @unchecked Sendable {
    private let port: any HostNavigationPort
    private var evidence = HostContextEvidenceStore()
    private var negotiations: [IntegrationInstanceID: NegotiationSnapshot] = [:]
    public private(set) var attempts: [JumpBackAttemptRecord] = []

    public init(port: any HostNavigationPort = OrcaHostNavigationPort()) { self.port = port }

    public func record(association: HostContextAssociation) {
        guard association.host == .orca else { return }
        evidence.record(association)
    }

    public func register(navigationNegotiation snapshot: NegotiationSnapshot) {
        negotiations[snapshot.integrationInstanceID] = snapshot
    }

    public func associations(for identity: AgentSessionIdentity) -> [HostContextAssociation] {
        evidence.associations(for: identity)
    }

    public func invalidateAllLocators(reason: HostContextInvalidationReason, at date: Date = Date()) {
        if let port = port as? OrcaHostNavigationPort { port.invalidateLiveReferences() }
        evidence.invalidateAll(reason: reason, at: date)
    }

    public func jumpBack(for identity: AgentSessionIdentity, at date: Date = Date()) -> JumpBackOutcome {
        let candidates = evidence.associations(for: identity).filter { negotiations[$0.integrationInstanceID] != nil }
        let instances = Set(candidates.map(\.integrationInstanceID))
        guard instances.count == 1, let instance = instances.first, let negotiation = negotiations[instance] else {
            let outcome = JumpBackOutcome(sessionIdentity: identity, host: candidates.first?.host, qualifier: .unavailable, occurredAt: date, reason: candidates.isEmpty ? .noAssociation : .ambiguous(level: .exactSurface))
            attempts.append(.init(attemptID: "", sessionIdentity: identity, trigger: .explicitPersonAction, candidateAssociationID: nil, candidateLocator: nil, outcome: outcome))
            return outcome
        }
        let scoped = candidates.filter { $0.integrationInstanceID == instance }
        let attempt = JumpBackCoordinator(evidence: .init(scoped), port: port).attempt(.init(sessionIdentity: identity, negotiation: negotiation, requestedAt: date))
        attempts.append(attempt)
        reconcile(after: attempt, negotiation: negotiation, at: date)
        return attempt.outcome
    }

    private func reconcile(after attempt: JumpBackAttemptRecord, negotiation: NegotiationSnapshot, at date: Date) {
        guard let id = attempt.candidateAssociationID, let association = evidence.association(id) else { return }
        let revalidation = port.revalidate(association, for: attempt.sessionIdentity, negotiation: negotiation, at: date)
        let retainsLiveEvidence = revalidation.provenLevels.contains(.exactSurface) ||
            revalidation.provenLevels.contains(.exactTab) ||
            (revalidation.provenLevels.contains(.workspaceOrFile) && {
                if case .orcaWorkspace = association.locator { return true }
                return false
            }())
        if retainsLiveEvidence {
            evidence.record(association.validated(at: date)); return
        }
        guard let reason = invalidationReason(for: revalidation.reason) else { return }
        evidence.invalidate(id, reason: reason, at: date)
    }

    private func invalidationReason(for reason: HostNavigationRevalidationReason) -> HostContextInvalidationReason? {
        switch reason {
        case .locatorClosed: .locatorClosed
        case .locatorRecreated, .ambiguousCandidates: .locatorRecreated
        case .locatorInvalidated, .runtimeVersionChanged, .hostVersionChanged: .runtimeChanged
        case .incarnationChanged: .hostRestarted
        case .endpointChanged: .endpointLost
        case .hostUnavailable, .hostAbsent: .hostUnavailable
        case .navigationCapabilityMissing, .navigationCapabilityUnavailable, .staleCapability: .capabilityChanged
        case .navigationPermissionDenied, .accessibilityPermissionDenied: .permissionRevoked
        case .noSeparatelyProvenFallback: .locatorClosed
        default: nil
        }
    }
}
