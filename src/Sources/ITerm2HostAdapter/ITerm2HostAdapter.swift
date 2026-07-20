import Foundation
import SessionDomain

/// The supported iTerm2 Python API is asynchronous and distributed with its
/// own Python module. This narrow bridge protocol keeps that implementation
/// outside the domain and makes every operation name an opaque API ID only.
/// It intentionally has no field for a title, CWD, PID, ordinal, geometry,
/// Space, visible text, keystroke, or terminal input.
public protocol ITerm2DocumentedAPIClient: Sendable {
    /// Explicit setup/reprobe operation. It is the only operation allowed to
    /// create or replace the persistent official API connection.
    func reprobe() -> Result<ITerm2APISnapshot, ITerm2APIClientFailure>
    func probe() -> Result<ITerm2APISnapshot, ITerm2APIClientFailure>
    func activate(sessionID: String?, tabID: String?, appOnly: Bool, expectedConnectionID: String?) -> Result<Void, ITerm2APIClientFailure>
}

public enum ITerm2APIClientFailure: String, Error, Hashable, Sendable, Codable {
    case bridgeUnavailable
    case apiDisconnected
    case unsupportedAPI
    case malformedResponse
    case targetUnavailable
    case activationRejected
    case incarnationChanged
}

/// A read-only result from one current documented API connection. `connectionID`
/// is an opaque bridge-provided API-connection incarnation, not a process ID.
/// Exact navigation is withheld when it is absent.
public struct ITerm2APISnapshot: Hashable, Sendable, Codable {
    public let hostVersion: String
    public let endpointID: String
    public let connectionID: String?
    public let apiConnected: Bool
    public let appAvailable: Bool
    public let sessionIDs: [String]
    public let tabIDs: [String]

    public init(
        hostVersion: String = "unknown",
        endpointID: String = "iterm2-python-api",
        connectionID: String?,
        apiConnected: Bool,
        appAvailable: Bool,
        sessionIDs: [String] = [],
        tabIDs: [String] = []
    ) {
        self.hostVersion = hostVersion
        self.endpointID = endpointID
        self.connectionID = connectionID
        self.apiConnected = apiConnected
        self.appAvailable = appAvailable
        self.sessionIDs = sessionIDs
        self.tabIDs = tabIDs
    }
}

/// Production client for the documented iTerm2 Python API. The bundled helper
/// imports iTerm2's official `iterm2` module and calls only its activate/list
/// APIs. A missing module, disabled API, or malformed response fails closed.
public final class ITerm2PythonAPIClient: @unchecked Sendable, ITerm2DocumentedAPIClient {
    private let helperURL: URL?
    private let lock = NSLock()
    private var helper: PersistentHelper?

    public convenience init() {
        self.init(helperURL: Bundle.module.url(forResource: "iterm2_api_bridge", withExtension: "py"))
    }

    public init(helperURL: URL?) {
        self.helperURL = helperURL
    }

    /// Starts the bundled helper only at explicit setup/reprobe time. A
    /// Jump Back calls `probe`, which fails closed if this connection ended.
    public func reprobe() -> Result<ITerm2APISnapshot, ITerm2APIClientFailure> {
        lock.lock(); defer { lock.unlock() }
        if helper?.process.isRunning != true {
            helper = nil
            guard let started = startHelperLocked() else { return .failure(.bridgeUnavailable) }
            helper = started
        }
        return decodeSnapshot(commandLocked(["operation": "probe"]))
    }

    public func probe() -> Result<ITerm2APISnapshot, ITerm2APIClientFailure> {
        lock.lock(); defer { lock.unlock() }
        guard helper?.process.isRunning == true else { return .failure(.apiDisconnected) }
        return decodeSnapshot(commandLocked(["operation": "probe"]))
    }

    public func activate(sessionID: String?, tabID: String?, appOnly: Bool, expectedConnectionID: String?) -> Result<Void, ITerm2APIClientFailure> {
        lock.lock(); defer { lock.unlock() }
        guard helper?.process.isRunning == true else { return .failure(.apiDisconnected) }
        var body: [String: String] = ["operation": "activate"]
        if let sessionID { body["sessionID"] = sessionID }
        if let tabID { body["tabID"] = tabID }
        if appOnly { body["appOnly"] = "true" }
        if let expectedConnectionID { body["expectedConnectionID"] = expectedConnectionID }
        switch commandLocked(body) {
        case .failure(let failure): return .failure(failure)
        case .success(let data):
            guard let response = try? JSONDecoder().decode(ITerm2BridgeActivationResponse.self, from: data) else {
                return .failure(.malformedResponse)
            }
            guard response.connectionID == expectedConnectionID || expectedConnectionID == nil else { return .failure(.incarnationChanged) }
            return response.activated ? .success(()) : .failure(response.failure ?? .activationRejected)
        }
    }

    /// Stops only Agent Island's bundled Python bridge. It never terminates,
    /// quits, or sends input to iTerm2 itself.
    public func shutdownOwnedHelper() {
        lock.lock(); defer { lock.unlock() }
        guard let helper else { return }
        self.helper = nil
        try? helper.input.close()
        if helper.process.isRunning {
            helper.process.terminate()
            helper.process.waitUntilExit()
        }
        try? helper.output.close()
    }

    private func decodeSnapshot(_ result: Result<Data, ITerm2APIClientFailure>) -> Result<ITerm2APISnapshot, ITerm2APIClientFailure> {
        switch result {
        case .failure(let failure): return .failure(failure)
        case .success(let data):
            if let failure = try? JSONDecoder().decode(ITerm2BridgeFailure.self, from: data).failure { return .failure(failure) }
            do { return .success(try JSONDecoder().decode(ITerm2APISnapshot.self, from: data)) }
            catch { return .failure(.malformedResponse) }
        }
    }

    private func startHelperLocked() -> PersistentHelper? {
        guard let helperURL else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", helperURL.path, "--serve"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            return PersistentHelper(process: process, input: stdin.fileHandleForWriting, output: stdout.fileHandleForReading)
        } catch {
            return nil
        }
    }

    private func commandLocked(_ body: [String: String]) -> Result<Data, ITerm2APIClientFailure> {
        guard let helper, helper.process.isRunning, var data = try? JSONEncoder().encode(body) else { return .failure(.apiDisconnected) }
        data.append(0x0A)
        helper.input.write(data)
        while true {
            if let newline = helper.buffer.firstIndex(of: 0x0A) {
                let line = helper.buffer[..<newline]
                helper.buffer.removeSubrange(...newline)
                return .success(Data(line))
            }
            let next = helper.output.availableData
            guard !next.isEmpty else { self.helper = nil; return .failure(.apiDisconnected) }
            helper.buffer.append(next)
        }
    }

    private final class PersistentHelper {
        let process: Process
        let input: FileHandle
        let output: FileHandle
        var buffer = Data()
        init(process: Process, input: FileHandle, output: FileHandle) {
            self.process = process; self.input = input; self.output = output
        }
    }
}

private struct ITerm2BridgeActivationResponse: Decodable {
    let activated: Bool
    let connectionID: String?
    let failure: ITerm2APIClientFailure?
}

private struct ITerm2BridgeFailure: Decodable { let failure: ITerm2APIClientFailure }

/// Real iTerm2 Host port. It probes the current documented API connection on
/// *every* revalidation and lets the helper re-resolve the exact ID again at
/// activation time. It never substitutes similar presentation metadata.
public final class ITerm2HostNavigationPort: @unchecked Sendable, HostNavigationPort {
    private let client: any ITerm2DocumentedAPIClient
    private let verificationLock = NSLock()
    private var verifiedIncarnations: [HostContextID: String] = [:]

    public init(client: any ITerm2DocumentedAPIClient = ITerm2PythonAPIClient()) {
        self.client = client
    }

    /// Connection IDs are live helper/API evidence. Do not carry an exact
    /// proof across wake, helper loss, or application termination.
    public func invalidateLiveReferences() {
        verificationLock.lock()
        verifiedIncarnations.removeAll()
        verificationLock.unlock()
    }

    /// Explicit application-termination cleanup for the bundled bridge. Test
    /// clients and externally owned documented API clients are never stopped.
    public func shutdownOwnedHelper() async {
        guard let client = client as? ITerm2PythonAPIClient else { return }
        await Task.detached(priority: .utility) {
            client.shutdownOwnedHelper()
        }.value
    }

    public func revalidate(_ association: HostContextAssociation, for sessionIdentity: AgentSessionIdentity, negotiation: NegotiationSnapshot?, at date: Date) -> HostNavigationRevalidation {
        guard association.host == .iterm2 else {
            return unavailable(association, sessionIdentity: sessionIdentity, negotiation: negotiation, at: date, reason: .unsupportedHost)
        }
        let snapshot: ITerm2APISnapshot
        switch client.probe() {
        case .success(let value): snapshot = value
        case .failure(let failure):
            return unavailable(association, sessionIdentity: sessionIdentity, negotiation: negotiation, at: date, reason: failure == .targetUnavailable ? .locatorClosed : .hostUnavailable)
        }
        let incarnation = snapshot.connectionID.map { HostIncarnation($0) }
        let exactSession: Bool
        let exactTab: Bool
        let count: Int
        switch association.locator {
        case .iterm2LiveSession(let sessionID):
            count = snapshot.sessionIDs.filter { $0 == sessionID }.count
            exactSession = snapshot.apiConnected && snapshot.connectionID != nil && count == 1
            exactTab = false
        case .iterm2Tab(let tabID):
            count = snapshot.tabIDs.filter { $0 == tabID }.count
            exactSession = false
            exactTab = snapshot.apiConnected && snapshot.connectionID != nil && count == 1
        default:
            return unavailable(association, sessionIdentity: sessionIdentity, negotiation: negotiation, at: date, reason: .unsupportedHost)
        }
        var levels: Set<HostNavigationLevel> = []
        if exactSession { levels.insert(.exactSurface) }
        if exactTab { levels.insert(.exactTab) }
        if snapshot.appAvailable { levels.insert(.appOnly) }
        let state: HostLocatorState = (exactSession || exactTab) ? .live : (snapshot.apiConnected ? .closed : .unavailable)
        let observation = HostRuntimeObservation(
            host: .iterm2,
            hostVersion: snapshot.hostVersion,
            integrationMode: association.integrationMode,
            endpointID: snapshot.endpointID,
            incarnation: incarnation,
            applicationState: snapshot.appAvailable ? .available : .endpointLost,
            locatorState: state,
            provenLevels: levels,
            candidateCount: count,
            liveSessionConnected: exactSession,
            liveSessionID: exactSession ? snapshot.sessionIDs.first(where: { if case .iterm2LiveSession(let id) = association.locator { return $0 == id }; return false }) : nil,
            currentTabID: exactTab ? snapshot.tabIDs.first(where: { if case .iterm2Tab(let id) = association.locator { return $0 == id }; return false }) : nil
        )
        let value = HostNavigationPolicy.revalidate(association: association, sessionIdentity: sessionIdentity, negotiation: negotiation, observation: observation, at: date)
        verificationLock.lock()
        if (value.provenLevels.contains(.exactSurface) || value.provenLevels.contains(.exactTab)), let connectionID = snapshot.connectionID {
            verifiedIncarnations[association.id] = connectionID
        } else {
            verifiedIncarnations.removeValue(forKey: association.id)
        }
        verificationLock.unlock()
        return value
    }

    public func navigate(_ target: HostNavigationTarget, at date: Date) -> HostNavigationDispatch {
        guard target.host == .iterm2 else { return .rejected(.unsupportedHost) }
        verificationLock.lock()
        let expectedConnectionID = verifiedIncarnations[target.associationID]
        verificationLock.unlock()
        let requiresExactIncarnation = target.level == .exactSurface || target.level == .exactTab
        guard !requiresExactIncarnation || expectedConnectionID != nil else { return .rejected(.incarnationChanged) }
        let invocation: Result<Void, ITerm2APIClientFailure>
        switch (target.level, target.locator) {
        case (.exactSurface, .iterm2LiveSession(let sessionID)):
            invocation = client.activate(sessionID: sessionID, tabID: nil, appOnly: false, expectedConnectionID: expectedConnectionID)
        case (.exactTab, .iterm2Tab(let tabID)):
            invocation = client.activate(sessionID: nil, tabID: tabID, appOnly: false, expectedConnectionID: expectedConnectionID)
        case (.appOnly, _):
            invocation = client.activate(sessionID: nil, tabID: nil, appOnly: true, expectedConnectionID: nil)
        default:
            return .rejected(.noSeparatelyProvenFallback)
        }
        switch invocation {
        case .success: return .reached
        case .failure(let failure):
            let reason: HostNavigationRevalidationReason
            switch failure {
            case .targetUnavailable: reason = .locatorClosed
            case .incarnationChanged: reason = .incarnationChanged
            default: reason = .dispatchFailed
            }
            return .rejected(reason)
        }
    }

    private func unavailable(_ association: HostContextAssociation, sessionIdentity: AgentSessionIdentity, negotiation: NegotiationSnapshot?, at date: Date, reason: HostNavigationRevalidationReason) -> HostNavigationRevalidation {
        let policy = HostRuntimeObservation(host: .iterm2, integrationMode: association.integrationMode, applicationState: .endpointLost, locatorState: .unavailable, candidateCount: 0)
        var value = HostNavigationPolicy.revalidate(association: association, sessionIdentity: sessionIdentity, negotiation: negotiation, observation: policy, at: date)
        // The policy's capability gate may be more informative, but a failed
        // documented API probe must never report a live exact route.
        if value.provenLevels.isEmpty {
            value = HostNavigationRevalidation(associationID: value.associationID, sessionIdentity: value.sessionIdentity, host: value.host, integrationMode: value.integrationMode, capabilityID: value.capabilityID, capabilityRevision: value.capabilityRevision, permission: value.permission, locatorState: value.locatorState, incarnation: value.incarnation, provenLevels: [], candidateCount: 0, evaluatedAt: value.evaluatedAt, ownershipMatches: value.ownershipMatches, hostMatches: value.hostMatches, modeMatches: value.modeMatches, capabilityGranted: value.capabilityGranted, permissionGranted: value.permissionGranted, locatorMatches: value.locatorMatches, incarnationMatches: value.incarnationMatches, reason: reason)
        }
        return value
    }
}

/// Captures only a locator that the current documented API has already
/// resolved. Product integrations pass their exact Agent Session identity;
/// this capture never creates an association from presentation metadata.
public final class ITerm2HostContextCapture: @unchecked Sendable {
    private let client: any ITerm2DocumentedAPIClient

    public init(client: any ITerm2DocumentedAPIClient = ITerm2PythonAPIClient()) {
        self.client = client
    }

    public func captureSession(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        sessionID: String,
        at date: Date
    ) -> Result<HostContextAssociation, ITerm2APIClientFailure> {
        capture(id: id, sessionIdentity: sessionIdentity, integrationInstanceID: integrationInstanceID, integrationMode: integrationMode, locator: .iterm2LiveSession(sessionID: sessionID), at: date)
    }

    public func captureTab(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        tabID: String,
        at date: Date
    ) -> Result<HostContextAssociation, ITerm2APIClientFailure> {
        capture(id: id, sessionIdentity: sessionIdentity, integrationInstanceID: integrationInstanceID, integrationMode: integrationMode, locator: .iterm2Tab(tabID: tabID), at: date)
    }

    private func capture(
        id: HostContextID,
        sessionIdentity: AgentSessionIdentity,
        integrationInstanceID: IntegrationInstanceID,
        integrationMode: String,
        locator: HostLocator,
        at date: Date
    ) -> Result<HostContextAssociation, ITerm2APIClientFailure> {
        // Capture is explicit setup/person assertion, so it may establish one
        // new persistent API connection. Revalidation/navigation never does.
        guard case .success(let snapshot) = client.reprobe(), snapshot.apiConnected,
              let connectionID = snapshot.connectionID else { return .failure(.apiDisconnected) }
        let resolved: Bool
        switch locator {
        case .iterm2LiveSession(let sessionID): resolved = snapshot.sessionIDs.filter { $0 == sessionID }.count == 1
        case .iterm2Tab(let tabID): resolved = snapshot.tabIDs.filter { $0 == tabID }.count == 1
        default: resolved = false
        }
        guard resolved else { return .failure(.targetUnavailable) }
        return .success(HostContextAssociation(
            id: id,
            sessionIdentity: sessionIdentity,
            host: .iterm2,
            hostVersion: snapshot.hostVersion,
            integrationInstanceID: integrationInstanceID,
            integrationMode: integrationMode,
            incarnation: HostIncarnation(connectionID),
            locator: locator,
            provenance: HostLocatorProvenance(host: .iterm2, hostVersion: snapshot.hostVersion, endpointID: snapshot.endpointID, evidence: .liveSessionAPI, observedAt: date, sourceID: "iterm2-python-api"),
            validity: .live,
            firstObservedAt: date,
            lastValidatedAt: date
        ))
    }
}

/// Production composition/registry. Associations remain source-proven inputs
/// from a Host-aware observation integration; this registry never discovers a
/// pane from a card title or any other presentation field.
@MainActor
public final class ITerm2HostNavigationComposition {
    private var evidence = HostContextEvidenceStore()
    private var negotiations: [IntegrationInstanceID: NegotiationSnapshot] = [:]
    private let port: any HostNavigationPort
    public private(set) var attempts: [JumpBackAttemptRecord] = []

    public init(port: any HostNavigationPort = ITerm2HostNavigationPort()) {
        self.port = port
    }

    public func record(association: HostContextAssociation) {
        guard association.host == .iterm2 else { return }
        evidence.record(association)
    }

    public func register(navigationNegotiation snapshot: NegotiationSnapshot) {
        negotiations[snapshot.integrationInstanceID] = snapshot
    }

    public func associations(for identity: AgentSessionIdentity) -> [HostContextAssociation] {
        evidence.associations(for: identity)
    }

    /// Capability-local recovery: retains historical associations but makes
    /// every locator unusable until a new documented API probe proves it.
    public func invalidateAllLocators(reason: HostContextInvalidationReason, at date: Date = Date()) {
        (port as? ITerm2HostNavigationPort)?.invalidateLiveReferences()
        evidence.invalidateAll(reason: reason, at: date)
    }


    /// Explicit Quit cleanup. Locator invalidation remains a separate step so
    /// wake/reconnect boundaries never stop or relaunch the bridge implicitly.
    public func stopOwnedHelper() async {
        await (port as? ITerm2HostNavigationPort)?.shutdownOwnedHelper()
    }

    public func jumpBack(for identity: AgentSessionIdentity, at date: Date = Date()) -> JumpBackOutcome {
        let candidates = evidence.associations(for: identity).filter { negotiations[$0.integrationInstanceID] != nil }
        let instances = Set(candidates.map(\.integrationInstanceID))
        guard instances.count == 1, let instance = instances.first, let negotiation = negotiations[instance] else {
            let outcome = JumpBackOutcome(sessionIdentity: identity, host: candidates.first?.host, qualifier: .unavailable, occurredAt: date, reason: candidates.isEmpty ? .noAssociation : .ambiguous(level: .exactSurface))
            attempts.append(JumpBackAttemptRecord(attemptID: "", sessionIdentity: identity, trigger: .explicitPersonAction, candidateAssociationID: nil, candidateLocator: nil, outcome: outcome))
            return outcome
        }
        let selected = candidates.filter { $0.integrationInstanceID == instance }.map(\.id)
        let coordinator = JumpBackCoordinator(evidence: HostContextEvidenceStore(candidates.filter { selected.contains($0.id) }), port: port)
        let attempt = coordinator.attempt(JumpBackRequest(sessionIdentity: identity, negotiation: negotiation, requestedAt: date))
        attempts.append(attempt)
        reconcileRecordedLocator(after: attempt, negotiation: negotiation, at: date)
        return attempt.outcome
    }

    /// A live revalidation failure ends the exact locator's validity but not
    /// its historical association or earlier navigation attempts. Lower-level
    /// app navigation remains a separate current capability, never a rebinding.
    private func reconcileRecordedLocator(after attempt: JumpBackAttemptRecord, negotiation: NegotiationSnapshot, at date: Date) {
        guard let id = attempt.candidateAssociationID, let association = evidence.association(id) else { return }
        let revalidation = port.revalidate(association, for: attempt.sessionIdentity, negotiation: negotiation, at: date)
        if revalidation.provenLevels.contains(.exactSurface) || revalidation.provenLevels.contains(.exactTab) {
            evidence.record(association.validated(at: date))
            return
        }
        guard let reason = invalidationReason(for: revalidation.reason) else { return }
        evidence.invalidate(id, reason: reason, at: date)
    }

    private func invalidationReason(for reason: HostNavigationRevalidationReason) -> HostContextInvalidationReason? {
        switch reason {
        case .locatorClosed: .locatorClosed
        case .locatorRecreated: .locatorRecreated
        case .locatorInvalidated: .runtimeChanged
        case .incarnationChanged: .hostRestarted
        case .endpointChanged: .endpointLost
        case .hostVersionChanged: .runtimeChanged
        case .hostUnavailable, .hostAbsent: .hostUnavailable
        case .navigationCapabilityMissing, .navigationCapabilityUnavailable, .staleCapability: .capabilityChanged
        case .navigationPermissionDenied, .accessibilityPermissionDenied: .permissionRevoked
        case .ambiguousCandidates: .locatorRecreated
        case .noSeparatelyProvenFallback: .locatorClosed
        default: nil
        }
    }
}
