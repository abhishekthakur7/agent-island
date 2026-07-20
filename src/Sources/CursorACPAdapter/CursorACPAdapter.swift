import Foundation
import AdapterPort
import SessionDomain

/// Version-pinned, stdio JSON-RPC boundary for ACP sessions deliberately
/// launched by Agent Island.  It neither discovers nor adopts Cursor IDE,
/// CLI, SDK, headless, or pre-existing ACP sessions.
public enum CursorACPContract {
    public static let adapterKind = "cursor.acp.v1"
    public static let adapterBuildVersion = "ab-139"
    public static let productNamespace = ProductNamespace("cursor.acp")
    public static let integrationMode = "agent-island-started-acp"
    public static let protocolVersion = "1.0"
    public static let observationCapability = "cursor.acp.session-observation"
    public static let actionCapability = "cursor.acp.guided-action"
}

public enum CursorACPFailure: String, Sendable, Equatable, Error {
    case unavailable
    case protocolDrift
    case authenticationFailed
    case disconnected
    case processExited
    case malformedJSONRPC
    case unknownMethod
    case unrecordedSession
    case sourceResolved
    case ownerMismatch
    case staleOrReusedLease
    case unsupportedAction
    case indeterminateDelivery
}

public enum CursorACPHealth: Sendable, Equatable {
    case idle
    case negotiating
    case ready
    case degraded(CursorACPFailure)
}

public enum CursorACPActionResult: Sendable, Equatable {
    case dispatched(ActionAttempt)
    case unavailable(CursorACPFailure, fallback: CapabilityFallback)
}

public protocol CursorACPTransport: Sendable {
    func start() async throws
    func write(_ bytes: Data) async throws
    func read() async throws -> Data?
    func close() async
}

/// Real stdio seam.  Production composition supplies an executable command;
/// tests use `CursorACPFixtureTransport` below.  EOF and child exit are
/// transport degradation only, never lifecycle completion evidence.
public actor CursorACPProcessTransport: CursorACPTransport {
    private let executableURL: URL
    private let arguments: [String]
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pendingLineBytes = Data()

    public init(executableURL: URL, arguments: [String] = []) {
        self.executableURL = executableURL; self.arguments = arguments
    }
    public func start() async throws {
        guard process == nil else { return }
        let child = Process(); child.executableURL = executableURL; child.arguments = arguments
        let stdin = Pipe(); let stdout = Pipe(); child.standardInput = stdin; child.standardOutput = stdout; child.standardError = Pipe()
        try child.run(); process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
    }
    public func write(_ bytes: Data) async throws {
        guard let input else { throw NSError(domain: "CursorACP", code: 1) }
        try input.write(contentsOf: bytes)
    }
    public func read() async throws -> Data? {
        guard let output else { throw NSError(domain: "CursorACP", code: 2) }
        while true {
            if let newline = pendingLineBytes.firstIndex(of: 10) {
                let line = pendingLineBytes[..<newline]
                pendingLineBytes.removeSubrange(...newline)
                return Data(line)
            }
            // `availableData` blocks only until the child supplies a stdio
            // chunk or closes stdout; unlike readToEnd it does not wait for
            // process exit and preserves JSON-RPC line boundaries.
            let next = output.availableData
            guard !next.isEmpty else { return pendingLineBytes.isEmpty ? nil : pendingLineBytes }
            pendingLineBytes.append(next)
        }
    }
    public func close() async {
        input?.closeFile(); output?.closeFile(); if let process, process.isRunning { process.terminate() }
        input = nil; output = nil; process = nil; pendingLineBytes.removeAll()
    }
}

/// Deterministic, faithful line-oriented JSON-RPC fixture seam.  Writes are
/// retained as bytes so tests prove exact one-dispatch behavior without a
/// Cursor installation.
public actor CursorACPFixtureTransport: CursorACPTransport {
    private var inbound: [Data]
    private(set) public var writes: [Data] = []
    private var started = false
    private var eof = false
    private var readers: [CheckedContinuation<Data?, Never>] = []
    public var failWrites = false
    public init(inbound: [Data] = []) { self.inbound = inbound }
    public func setFailWrites(_ value: Bool) { failWrites = value }
    public func enqueue(_ object: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        if !readers.isEmpty { readers.removeFirst().resume(returning: data) }
        else { inbound.append(data) }
    }
    public func start() async throws { started = true; eof = false }
    public func write(_ bytes: Data) async throws { guard started, !failWrites else { throw NSError(domain: "CursorACP", code: 3) }; writes.append(bytes) }
    /// Empty inbound data is a live idle stdio stream, not EOF. Tests must
    /// explicitly call `finish()` to model process EOF and release a reader.
    public func read() async throws -> Data? {
        guard started else { throw NSError(domain: "CursorACP", code: 4) }
        if !inbound.isEmpty { return inbound.removeFirst() }
        if eof { return nil }
        return await withCheckedContinuation { readers.append($0) }
    }
    public func finish() { eof = true; let pending = readers; readers.removeAll(); pending.forEach { $0.resume(returning: nil) } }
    public func close() async { started = false; finish() }
}

private struct CursorACPRoute: Sendable {
    let requestID: GuidedAttentionRequestID
    let owner: GuidedAttentionOwner
    let capability: CapabilityRecord
    let fingerprint: String
    let method: String
    let allowed: Set<String>
    let deadline: Date
}

private struct CursorACPChild: Hashable, Sendable { let sessionID: String; let turnID: String; let childID: String }

public actor CursorACPAdapter {
    private let port: any CursorACPControlPort
    private let transport: any CursorACPTransport
    private let integrationInstanceID: IntegrationInstanceID
    private let clock: @Sendable () -> Date
    private var snapshot: NegotiationSnapshot?
    private var health: CursorACPHealth = .idle
    private var nextRequest = 0
    private var transportReady = false
    private var reader: Task<Void, Never>?
    private var attentionWaiters: [GuidedAttentionRequestID: [CheckedContinuation<Bool, Never>]] = [:]
    private var controlled: Set<AgentSessionIdentity> = []
    private var routes: [GuidedAttentionRequestID: CursorACPRoute] = [:]
    private var children: Set<CursorACPChild> = []

    public init(port: any CursorACPControlPort, transport: any CursorACPTransport, integrationInstanceID: IntegrationInstanceID, clock: @escaping @Sendable () -> Date = Date.init) {
        self.port = port; self.transport = transport; self.integrationInstanceID = integrationInstanceID; self.clock = clock
    }

    public func negotiationRequest(productVersion: String = "unknown", interfaceVersion: String = CursorACPContract.protocolVersion, authenticationAvailable: Bool = true) -> NegotiationRequest {
        let availability: CapabilityRecord.Availability = authenticationAvailable && interfaceVersion == CursorACPContract.protocolVersion ? .available : .incompatible
        let provenance = CapabilityProvenance(integrationInstanceID: integrationInstanceID, productNamespace: CursorACPContract.productNamespace, integrationMode: CursorACPContract.integrationMode)
        let observation = CapabilityRecord(id: CursorACPContract.observationCapability, direction: .observe, availability: availability, scope: .session, constraints: .init(values: ["acpVersion": CursorACPContract.protocolVersion, "startedBy": "agent-island"], requiresLiveEvidence: true), provenance: provenance, fallback: .retryProbe, semanticVariant: "controlled-only")
        let action = CapabilityRecord(id: CursorACPContract.actionCapability, direction: .act, availability: availability, scope: .request, constraints: .init(values: ["acpVersion": CursorACPContract.protocolVersion, "responses": "permissions,questions,plans"], requiresLiveEvidence: true), provenance: provenance, fallback: .nativeHost, semanticVariant: "guided-only")
        return .init(integrationInstanceID: integrationInstanceID, adapterKind: CursorACPContract.adapterKind, adapterBuildVersion: CursorACPContract.adapterBuildVersion, productNamespace: CursorACPContract.productNamespace, integrationMode: CursorACPContract.integrationMode, offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0), requestedCapabilities: [observation.id, action.id], catalogRevision: "cursor-acp-v1", productVersion: productVersion, interfaceVersion: interfaceVersion, probeEvidence: .init(compatibility: availability == .available ? .compatible : .interfaceChanged, productVersion: productVersion, interfaceVersion: interfaceVersion, setup: authenticationAvailable ? .loaded : .permissionDenied, requiredPermissions: authenticationAvailable ? [] : ["acp-auth"], observedAt: clock()), requestedCapabilityRecords: [observation, action], compatibility: availability == .available ? .compatible : .interfaceChanged)
    }

    @discardableResult public func negotiate(productVersion: String = "unknown", interfaceVersion: String = CursorACPContract.protocolVersion, authenticationAvailable: Bool = true) async -> NegotiationOutcome {
        health = .negotiating
        let result = await port.negotiate(negotiationRequest(productVersion: productVersion, interfaceVersion: interfaceVersion, authenticationAvailable: authenticationAvailable))
        guard case .compatible(let snapshot) = result,
              snapshot.grants(CursorACPContract.observationCapability, direction: .observe),
              snapshot.grants(CursorACPContract.actionCapability, direction: .act)
        else { health = .degraded(.protocolDrift); self.snapshot = nil; return result }
        self.snapshot = snapshot; health = .ready; return result
    }

    /// Starts a fresh child and requests a source-created ACP session. There
    /// is no discovery/list/load path for external Cursor work.
    public func startControlledSession() async -> Result<AgentSessionIdentity, CursorACPFailure> {
        guard snapshot != nil else { return .failure(.unavailable) }
        guard await ensureTransportReady() else { return .failure(.disconnected) }
        guard let id = await send(method: "session/new", params: [:]), let result = await receiveOne(), responseID(result) == id, let native = string(result["result"], key: "sessionId") else { await degrade(.malformedJSONRPC); return .failure(.malformedJSONRPC) }
        let identity = AgentSessionIdentity(productNamespace: CursorACPContract.productNamespace, nativeSessionID: .init(native))
        guard let snapshot else { return .failure(.unavailable) }
        switch await port.recordCursorACPControlledSession(.init(integrationInstanceID: integrationInstanceID, negotiationSnapshotID: snapshot.id, identity: identity)) {
        case .recorded, .alreadyRecorded:
            controlled.insert(identity); _ = await deliverSession(identity, event: "session-new", family: .sessionDeclared, activity: nil, sourceID: native + ":created")
            _ = await deliverSession(identity, event: "session-new", family: .sessionActivity, activity: .started, sourceID: native + ":started")
            startReadLoop()
            return .success(identity)
        case .rejected: return .failure(.unrecordedSession)
        }
    }

    /// ACP load is admitted only after this runtime-owned adapter-specific
    /// allowlist check; a similar native ID from another Cursor path fails.
    public func loadControlledSession(_ identity: AgentSessionIdentity) async -> Bool {
        guard let snapshot, identity.productNamespace == CursorACPContract.productNamespace,
              await port.mayLoadCursorACPControlledSession(.init(integrationInstanceID: integrationInstanceID, negotiationSnapshotID: snapshot.id, identity: identity))
        else { return false }
        guard await ensureTransportReady() else { return false }
        guard await send(method: "session/load", params: ["sessionId": identity.nativeSessionID.rawValue]) != nil else { return false }
        startReadLoop()
        return true
    }

    /// Drives one source JSON-RPC notification or response. Unknown methods,
    /// malformed payloads, EOF, and protocol errors degrade without asserting
    /// Product completion.
    @discardableResult private func receiveOne() async -> [String: Any]? {
        do {
            guard let bytes = try await transport.read() else { await degrade(.processExited); return nil }
            guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { await degrade(.malformedJSONRPC); return nil }
            if let error = value["error"] { _ = error; await degrade(.authenticationFailed); return value }
            if let method = value["method"] as? String { await ingest(method: method, params: value["params"] as? [String: Any] ?? [:]); return value }
            return value
        } catch { await degrade(.disconnected); return nil }
    }

    /// Test-only deterministic ingress. Production starts exactly one reader
    /// after a successful creation/load, so UI code never manually pumps.
    public func pump() async { guard reader == nil else { return }; _ = await receiveOne() }

    private func startReadLoop() {
        reader?.cancel()
        reader = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard await self.readForLifecycle() else { return }
            }
        }
    }

    private func readForLifecycle() async -> Bool {
        guard await receiveOne() != nil else { reader = nil; return false }
        if case .degraded = health { reader = nil; return false }
        return true
    }

    public func shutdown() async {
        let activeReader = reader
        reader?.cancel(); reader = nil; transportReady = false
        await port.invalidateCursorACPActionsForDisconnect()
        await transport.close()
        await activeReader?.value
    }

    /// Deterministic fixture/evidence synchronization. Production UI reads
    /// its persisted queue; it never waits on this test seam.
    public func waitForAttention(_ id: GuidedAttentionRequestID) async -> Bool {
        if routes[id] != nil { return true }
        return await withCheckedContinuation { attentionWaiters[id, default: []].append($0) }
    }

    public func waitForReaderTermination() async {
        let activeReader = reader
        await activeReader?.value
    }

    public func currentHealth() -> CursorACPHealth { health }

    public func submit(requestID: GuidedAttentionRequestID, action: GuidedAction, attemptID: String, confirmed: Bool = true) async -> CursorACPActionResult {
        guard health == .ready, let route = routes[requestID] else { return .unavailable(.sourceResolved, fallback: .nativeHost) }
        guard route.owner == (await requestOwner(requestID)), clock() <= route.deadline else { return .unavailable(.staleOrReusedLease, fallback: .nativeHost) }
        guard allowed(action, route: route) else { return .unavailable(.unsupportedAction, fallback: .nativeHost) }
        let semantic = "\(route.method):\(action.semanticKind)"
        switch await port.beginCursorACPAction(attemptID: attemptID, requestID: requestID, owner: route.owner, action: action, capability: route.capability, semanticFingerprint: semantic, nativeFingerprint: route.fingerprint, confirmed: confirmed, deadline: route.deadline) {
        case .unavailable(let reason): return .unavailable(map(reason), fallback: .nativeHost)
        case .dispatch(let attempt):
            let params = responseParameters(for: action, route: route)
            guard await send(method: route.method, params: params) != nil else {
                _ = await port.finishCursorACPAction(attemptID: attemptID, outcome: .indeterminate, evidence: "stdio-write-failed")
                routes.removeValue(forKey: requestID); await degrade(.indeterminateDelivery)
                return .unavailable(.indeterminateDelivery, fallback: .nativeHost)
            }
            // A successful local stdio write proves only a handoff attempt.
            // ACP has not sent documented source acknowledgement yet, so do
            // not manufacture acceptance or application from delivery.
            _ = await port.finishCursorACPAction(attemptID: attemptID, outcome: .indeterminate, evidence: "json-rpc-handoff-without-source-ack")
            routes.removeValue(forKey: requestID)
            return .dispatched(attempt)
        }
    }

    private func validateInitialize(_ message: [String: Any]?) -> Bool {
        guard let message, let result = message["result"] as? [String: Any], result["protocolVersion"] as? String == CursorACPContract.protocolVersion,
              result["authenticated"] as? Bool == true else { return false }
        return true
    }
    private func ensureTransportReady() async -> Bool {
        if transportReady { return true }
        do { try await transport.start() } catch { await degrade(.disconnected); return false }
        guard await send(method: "initialize", params: ["protocolVersion": CursorACPContract.protocolVersion, "client": "Agent Island"]) != nil else { await degrade(.indeterminateDelivery); return false }
        guard let initialize = await receiveOne(), validateInitialize(initialize) else { await degrade(.protocolDrift); return false }
        transportReady = true
        return true
    }
    private func ingest(method: String, params: [String: Any]) async {
        guard let sessionID = params["sessionId"] as? String,
              let identity = controlled.first(where: { $0.nativeSessionID.rawValue == sessionID })
        else { await degrade(.unrecordedSession); return }
        let sourceID = (params["eventId"] as? String) ?? ""
        guard !sourceID.isEmpty else { await degrade(.malformedJSONRPC); return }
        switch method {
        case "session/update":
            let state = (params["status"] as? String) ?? "working"
            let terminal: SessionActivityKind? = state == "completed" ? .completed : (state == "failed" ? .failed : nil)
            _ = await deliverSession(identity, event: method, family: .sessionActivity, activity: terminal ?? .working, sourceID: sourceID)
        case "session/prompt/stopped":
            // Prompt-stop is a source fact, but no terminal state follows
            // from it; it may merely mean that Cursor awaits a response.
            _ = await deliverSession(identity, event: method, family: .sessionActivity, activity: .waiting, sourceID: sourceID)
        case "todo/updated":
            _ = await deliverSession(identity, event: method, family: .sessionActivity, activity: .working, sourceID: sourceID)
        case "child/started":
            guard let turn = params["turnId"] as? String, let child = params["childSessionId"] as? String else { await degrade(.malformedJSONRPC); return }
            children.insert(.init(sessionID: sessionID, turnID: turn, childID: child))
            _ = await deliverSession(identity, event: method, family: .subagentRunDeclared, activity: nil, sourceID: sourceID, ownership: .init(nativeTurnID: turn, nativeSubagentRunID: child))
        case "child/completed":
            guard let turn = params["turnId"] as? String, let child = params["childSessionId"] as? String, children.remove(.init(sessionID: sessionID, turnID: turn, childID: child)) != nil else { await degrade(.ownerMismatch); return }
            _ = await deliverSession(identity, event: method, family: .sessionActivity, activity: .completed, sourceID: sourceID, ownership: .init(nativeTurnID: turn, nativeSubagentRunID: child))
        case "permission/request", "question/request", "plan/request":
            await ingestAttention(method: method, params: params, identity: identity, sourceID: sourceID)
        case "request/resolved":
            guard let request = params["requestId"] as? String else { await degrade(.malformedJSONRPC); return }
            let id = GuidedAttentionRequestID(productNamespace: CursorACPContract.productNamespace, nativeSessionID: identity.nativeSessionID, nativeAttentionRequestID: request)
            _ = await port.resolveCursorACPAttention(id, outcome: .resolvedElsewhere, fingerprint: sourceID); routes.removeValue(forKey: id)
        default: await degrade(.unknownMethod)
        }
    }

    private func ingestAttention(method: String, params: [String: Any], identity: AgentSessionIdentity, sourceID: String) async {
        guard let snapshot, let nativeRequest = params["requestId"] as? String, !nativeRequest.isEmpty else { await degrade(.malformedJSONRPC); return }
        let choices = (params["choices"] as? [[String: Any]] ?? []).compactMap { item -> GuidedChoice? in guard let id = item["id"] as? String, let label = item["label"] as? String else { return nil }; return GuidedChoice(id: id, label: label) }
        let shape: GuidedSemanticShape; let allowed: Set<String>
        switch method {
        case "permission/request":
            // Cursor documents only these three offered decisions.  No
            // generic approval or unoffered persistent denial is synthesized.
            let offered = Set((params["permissions"] as? [String] ?? []).filter(["allow-once", "allow-always", "reject-once"].contains))
            guard !offered.isEmpty else { await degrade(.unsupportedAction); return }
            shape = .allowDeny; allowed = offered
        case "question/request":
            let multiple = params["multiSelect"] as? Bool ?? false
            guard !choices.isEmpty else { await degrade(.malformedJSONRPC); return }
            shape = .init(kind: .structuredChoice, choices: choices, allowsMultipleSelection: multiple, minimumSelections: 1, maximumSelections: multiple ? choices.count : 1)
            allowed = ["answer"]
        default:
            shape = .init(kind: .planReview); allowed = ["accept", "reject", "cancel"]
        }
        let capability = CapabilityRecord(id: CursorACPContract.actionCapability, direction: .act, availability: .available, scope: .request, constraints: .init(values: ["offeredResponses": allowed.sorted().joined(separator: ",")], requiresLiveEvidence: true), provenance: .init(snapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, productNamespace: CursorACPContract.productNamespace, integrationMode: CursorACPContract.integrationMode), fallback: .nativeHost, semanticVariant: method)
        let owner = GuidedAttentionOwner(productNamespace: CursorACPContract.productNamespace, nativeSessionID: identity.nativeSessionID, nativeAttentionRequestID: nativeRequest, nativeTurnID: params["turnId"] as? String, integrationInstanceID: integrationInstanceID, negotiationSnapshotID: snapshot.id)
        let evidence = GuidedAttentionEvidence(owner: owner, eventIdentity: .stable(sourceID), sourceVariant: "cursor.acp.\(method)", capability: capability, semanticShape: shape, constraints: .init(requiresConfirmation: true, nativeFingerprint: sourceID), sourceObservedAt: clock())
        switch await port.ingestCursorACPAttention(evidence) { case .accepted, .duplicate:
            routes[evidence.requestID] = .init(requestID: evidence.requestID, owner: owner, capability: capability, fingerprint: sourceID, method: method.replacingOccurrences(of: "/request", with: "/respond"), allowed: allowed, deadline: clock().addingTimeInterval(60))
            let waiters = attentionWaiters.removeValue(forKey: evidence.requestID) ?? []
            waiters.forEach { $0.resume(returning: true) }
        case .rejected: await degrade(.ownerMismatch) }
    }

    private func allowed(_ action: GuidedAction, route: CursorACPRoute) -> Bool {
        switch action {
        case .allow: return route.allowed.contains("allow-once")
        case .persistentSuggestion(let allow): return allow && route.allowed.contains("allow-always")
        case .deny: return route.allowed.contains("reject-once")
        case .structuredResponse: return route.allowed.contains("answer")
        case .planReview(let decision, _): return route.allowed.contains(decision.rawValue)
        default: return false
        }
    }
    private func responseParameters(for action: GuidedAction, route: CursorACPRoute) -> [String: Any] {
        var values: [String: Any] = ["requestId": route.owner.nativeAttentionRequestID, "sessionId": route.owner.nativeSessionID.rawValue]
        switch action {
        case .allow: values["decision"] = "allow-once"
        case .persistentSuggestion: values["decision"] = "allow-always"
        case .deny: values["decision"] = "reject-once"
        case .structuredResponse(let response): values["choiceIds"] = response.selectedChoiceIDs; if let text = response.freeText { values["text"] = text }
        case .planReview(let decision, let reason): values["decision"] = decision.rawValue; if let reason { values["reason"] = reason }
        default: break
        }
        return values
    }
    private func requestOwner(_ id: GuidedAttentionRequestID) async -> GuidedAttentionOwner? { routes[id]?.owner }
    private func send(method: String, params: [String: Any]) async -> String? {
        nextRequest += 1; let id = "cursor-acp-\(nextRequest)"
        guard JSONSerialization.isValidJSONObject(params), let data = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params]) else { return nil }
        do { try await transport.write(data + Data([10])); return id } catch { return nil }
    }
    private func responseID(_ message: [String: Any]?) -> String? { message?["id"] as? String }
    private func string(_ value: Any?, key: String) -> String? { (value as? [String: Any])?[key] as? String }
    private func deliverSession(_ identity: AgentSessionIdentity, event: String, family: EventFamily, activity: SessionActivityKind?, sourceID: String, ownership: LifecycleOwnership? = nil) async -> IntakeOutcome? {
        guard let snapshot else { return nil }
        return await port.deliver(.init(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, contractVersion: snapshot.contractVersion, productNamespace: identity.productNamespace.rawValue, nativeSessionID: identity.nativeSessionID.rawValue, eventIdentity: .stable(sourceID), family: family, sourceVariant: "cursor.acp.\(event)", activityKind: activity, classification: .operationalMetadata, payloadByteSize: 0, ownership: ownership, integrationMode: CursorACPContract.integrationMode, capabilityID: CursorACPContract.observationCapability, capabilityDirection: .observe, capabilityRevision: 1))
    }
    private func map(_ reason: ActionAttemptRejectionReason) -> CursorACPFailure { switch reason { case .sourceResolved: .sourceResolved; case .ownerMismatch: .ownerMismatch; case .staleLease, .expiredLease, .alreadyDispatched: .staleOrReusedLease; case .capabilityUnavailable, .capabilityMismatch, .invalidSemanticResponse: .unsupportedAction; default: .unavailable } }
    private func degrade(_ failure: CursorACPFailure) async {
        health = .degraded(failure)
        if let snapshot { for identity in controlled { _ = await port.reportObservationBoundary(.init(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, identity: identity, reason: .transportLost)) } }
        reader?.cancel(); reader = nil
        let waiters = attentionWaiters.values.flatMap { $0 }; attentionWaiters.removeAll()
        waiters.forEach { $0.resume(returning: false) }
        await port.invalidateCursorACPActionsForDisconnect(); routes.removeAll(); children.removeAll(); transportReady = false; await transport.close()
    }
}
