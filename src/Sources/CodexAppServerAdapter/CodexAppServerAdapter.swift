import Foundation
import AdapterPort
import SessionDomain
import SessionStore

/// AB-137's product boundary. This is not the Codex Hooks integration: it is
/// usable only for a child process Agent Island starts, or a child it explicitly
/// resumes through this same local stdio actor.
public enum CodexAppServerContract {
    public static let productNamespace = ProductNamespace("codex-app-server")
    public static let integrationMode = "codex.appServer.childProcessStdio"
    public static let adapterKind = "codex-app-server-stdio"
    /// Generated locally with `codex app-server generate-json-schema --out`;
    /// the command is labelled experimental by Codex, so this evidence is
    /// version-pinned and never treated as a general compatibility promise.
    public static let interfaceVersion = "codex-cli-0.144.6-app-server-v2"
    public static let schemaDigest = "5ff91672223f52bdaa35d882db98e7b6a6fccb6add36c96107e64f5fc03fed97"
    public static let initializeMethod = "initialize"
    public static let initializedMethod = "initialized"
    public static let observationCapability = "codex.appServer.threadObservation"
    public static let approvalCapability = "codex.appServer.approvalResponse"
    public static let turnInputCapability = "codex.appServer.turnInput"
    public static let turnControlCapability = "codex.appServer.turnControl"
    public static let threadControlCapability = "codex.appServer.threadControl"
    public static let schemaResource = "Fixtures/CodexAppServerAdapter/stable-schema.json"
}

public struct CodexExecutableEvidence: Codable, Hashable, Sendable {
    public let path: String
    public let version: String
    public init(path: String, version: String) { self.path = path; self.version = version }
    public var isUsable: Bool { !path.isEmpty && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public protocol CodexExecutableDiscovering: Sendable {
    func discoverCodexExecutable() async -> CodexExecutableEvidence?
}

/// Explicit test/fail-closed discovery. Unlike local discovery, this cannot
/// turn fixtures or an ambient executable into a live connection.
public struct UnavailableCodexExecutableDiscovery: CodexExecutableDiscovering {
    public init() {}
    public func discoverCodexExecutable() async -> CodexExecutableEvidence? { nil }
}

/// Read-only executable discovery for the documented local child process. It
/// does not inspect Codex configuration, databases, transcripts, terminals,
/// or running processes. The result is merely probe evidence; schema and
/// handshake validation still decide whether a connection may become ready.
public struct LocalCodexExecutableDiscovery: CodexExecutableDiscovering {
    public init() {}
    public func discoverCodexExecutable() async -> CodexExecutableEvidence? {
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"] + environmentPaths.map { "\($0)/codex" }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            let process = Process(); let output = Pipe(); process.executableURL = URL(fileURLWithPath: path); process.arguments = ["--version"]; process.standardOutput = output; process.standardError = Pipe()
            do {
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0 else { continue }
                let version = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !version.isEmpty { return .init(path: path, version: version) }
            } catch { continue }
        }
        return nil
    }
}

public enum CodexAppServerState: String, Codable, Hashable, Sendable {
    case idle, probing, schemaValidated, launching, initializing, ready, disconnected, failed
}

public enum CodexAppServerFailure: String, Codable, Hashable, Sendable, Error {
    case executableUnavailable, schemaUnavailable, schemaMismatch, spawnFailed, malformedJSONRPC, oversizedFrame, oversizedBuffer, excessiveNesting, wrongHandshake, duplicateHandshake, prematureMessage, handshakeTimeout, eof, unsupportedMethod, pendingLimit, disconnected
}

public struct CodexAppServerLimits: Hashable, Sendable {
    public let maxFrameBytes: Int
    public let maxBufferBytes: Int
    public let maxNesting: Int
    public let maxPendingRequests: Int
    public init(maxFrameBytes: Int = 64 * 1024, maxBufferBytes: Int = 128 * 1024, maxNesting: Int = 32, maxPendingRequests: Int = 32) {
        self.maxFrameBytes = maxFrameBytes; self.maxBufferBytes = maxBufferBytes; self.maxNesting = maxNesting; self.maxPendingRequests = maxPendingRequests
    }
}

public struct CodexSchemaManifest: Codable, Hashable, Sendable {
    public let interfaceVersion: String
    public let digest: String
    public let stableMethods: Set<String>
    public let stableNotificationMethods: Set<String>
    public init(interfaceVersion: String = CodexAppServerContract.interfaceVersion, digest: String = CodexAppServerContract.schemaDigest, stableMethods: Set<String> = ["initialize", "thread/list", "thread/resume", "thread/fork", "thread/archive", "turn/start", "turn/steer", "turn/interrupt"], stableNotificationMethods: Set<String> = ["thread/started", "thread/status/changed", "turn/started", "turn/completed", "turn/diff/updated", "turn/plan/updated", "item/started", "item/completed", "item/agentMessage/delta", "item/commandExecution/outputDelta", "item/fileChange/outputDelta", "item/fileChange/patchUpdated"]) {
        self.interfaceVersion = interfaceVersion; self.digest = digest; self.stableMethods = stableMethods; self.stableNotificationMethods = stableNotificationMethods
    }
}

/// The generated-manifest validator is deliberately exact: a fixture is only
/// documentation evidence. Live enablement also requires a matching executable
/// and schema digest from the launched child.
public enum CodexSchemaValidation {
    public static func validate(manifest: CodexSchemaManifest, liveDigest: String?) -> Bool {
        manifest.interfaceVersion == CodexAppServerContract.interfaceVersion &&
        manifest.digest == CodexAppServerContract.schemaDigest &&
        liveDigest == CodexAppServerContract.schemaDigest
    }
}

public protocol CodexAppServerTransport: Sendable {
    func write(_ bytes: Data) async throws
    func close() async
}

public enum CodexChildOwnership: String, Codable, Hashable, Sendable {
    case startedByAgentIsland, explicitlyResumedByAgentIsland
}

public struct CodexConnectionProvenance: Codable, Hashable, Sendable {
    public let executable: CodexExecutableEvidence
    public let schemaDigest: String
    public let epoch: Int64
    public let transport: String
    public let initializationResult: String
    public init(executable: CodexExecutableEvidence, schemaDigest: String, epoch: Int64, transport: String = "child-process-stdio", initializationResult: String) {
        self.executable = executable; self.schemaDigest = schemaDigest; self.epoch = epoch; self.transport = transport; self.initializationResult = initializationResult
    }
}

public struct CodexAppServerHealth: Codable, Hashable, Sendable {
    public let state: CodexAppServerState
    public let epoch: Int64
    public let provenance: CodexConnectionProvenance?
    public let failure: CodexAppServerFailure?
    public let unresolvedGap: Bool
    public init(state: CodexAppServerState, epoch: Int64, provenance: CodexConnectionProvenance?, failure: CodexAppServerFailure?, unresolvedGap: Bool) {
        self.state = state; self.epoch = epoch; self.provenance = provenance; self.failure = failure; self.unresolvedGap = unresolvedGap
    }
}

public enum CodexAppServerActionResult: Sendable, Equatable {
    case rejected(ActionAttempt?)
    case dispatched(ActionAttempt)
}

/// Single actor that owns one bounded stdio incarnation. Calls to `receive` are
/// injected by a process supervisor; stdout is framed JSON-RPC only and stderr
/// never enters this actor (a supervisor may retain a separately redacted code).
public actor CodexAppServerAdapter {
    private let intake: any AdapterIntakePort
    private let attempts: ActionAttemptStore
    private let discovery: any CodexExecutableDiscovering
    private let integrationInstanceID: IntegrationInstanceID
    private let limits: CodexAppServerLimits
    private let clock: @Sendable () -> Date
    private var state: CodexAppServerState = .idle
    private var epoch: Int64 = 0
    private var executable: CodexExecutableEvidence?
    private var snapshot: NegotiationSnapshot?
    private var schemaValidated = false
    private var transport: (any CodexAppServerTransport)?
    private var buffer = Data()
    private var pending: Set<String> = []
    private var initializeID: String?
    private var initializedSent = false
    private var provenance: CodexConnectionProvenance?
    private var failure: CodexAppServerFailure?
    private var unresolvedGap = false
    private var routes: [String: ApprovalRoute] = [:]

    private struct ApprovalRoute: Sendable {
        let requestID: GuidedAttentionRequestID
        let owner: GuidedAttentionOwner
        let nativeRequestID: String
        let opaqueApprovalID: String?
        let fingerprint: String
        let deadline: Date
        let capability: CapabilityRecord
    }

    public init(intake: any AdapterIntakePort, attempts: ActionAttemptStore, integrationInstanceID: IntegrationInstanceID = .init("codex-app-server"), discovery: any CodexExecutableDiscovering = LocalCodexExecutableDiscovery(), limits: CodexAppServerLimits = .init(), clock: @escaping @Sendable () -> Date = Date.init) {
        self.intake = intake; self.attempts = attempts; self.integrationInstanceID = integrationInstanceID; self.discovery = discovery; self.limits = limits; self.clock = clock
    }

    public func health() -> CodexAppServerHealth { .init(state: state, epoch: epoch, provenance: provenance, failure: failure, unresolvedGap: unresolvedGap) }

    /// Explicitly starts/resumes only an application-owned child. An arbitrary
    /// terminal process has no API path into this adapter.
    public func connect(ownership: CodexChildOwnership, transport: any CodexAppServerTransport, liveSchemaDigest: String?) async -> Result<Int64, CodexAppServerFailure> {
        guard state == .idle || state == .disconnected || state == .failed else { return .failure(.prematureMessage) }
        state = .probing; failure = nil; unresolvedGap = false
        guard let executable = await discovery.discoverCodexExecutable(), executable.isUsable else { failState(.executableUnavailable); return .failure(.executableUnavailable) }
        self.executable = executable
        guard CodexSchemaValidation.validate(manifest: .init(), liveDigest: liveSchemaDigest) else { let cause: CodexAppServerFailure = liveSchemaDigest == nil ? .schemaUnavailable : .schemaMismatch; failState(cause); return .failure(cause) }
        let request = NegotiationRequest(
            integrationInstanceID: integrationInstanceID,
            adapterKind: CodexAppServerContract.adapterKind,
            adapterBuildVersion: "ab-137",
            productNamespace: CodexAppServerContract.productNamespace,
            integrationMode: CodexAppServerContract.integrationMode,
            offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0),
            requestedCapabilities: [CodexAppServerContract.observationCapability, CodexAppServerContract.approvalCapability],
            catalogRevision: CodexAppServerContract.schemaDigest,
            productVersion: executable.version,
            interfaceVersion: CodexAppServerContract.interfaceVersion,
            requestedCapabilityRecords: [
                .init(id: CodexAppServerContract.observationCapability, direction: .observe, availability: .available, scope: .session),
                .init(id: CodexAppServerContract.approvalCapability, direction: .act, availability: .available, scope: .request)
            ]
        )
        guard case .compatible(let accepted) = await intake.negotiate(request), accepted.productNamespace == CodexAppServerContract.productNamespace, accepted.integrationInstanceID == integrationInstanceID, accepted.grants(CodexAppServerContract.observationCapability, direction: .observe) else { failState(.schemaMismatch); return .failure(.schemaMismatch) }
        snapshot = accepted
        schemaValidated = true; state = .schemaValidated
        epoch &+= 1; self.transport = transport; state = .launching
        state = .initializing; let id = "initialize:\(epoch)"; initializeID = id; pending = [id]
        guard await writeRPC(["jsonrpc": "2.0", "id": id, "method": CodexAppServerContract.initializeMethod, "params": ["client": "agent-island", "transport": "stdio"]]) else { failState(.spawnFailed); return .failure(.spawnFailed) }
        return .success(epoch)
    }

    public func handshakeTimedOut() async { guard state == .initializing else { return }; failState(.handshakeTimeout) }

    public func receive(stdout bytes: Data) async {
        guard state == .initializing || state == .ready else { failState(.prematureMessage); return }
        buffer.append(bytes)
        guard buffer.count <= limits.maxBufferBytes else { failState(.oversizedBuffer); return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let frame = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard frame.count <= limits.maxFrameBytes else { failState(.oversizedFrame); return }
            guard let value = try? JSONSerialization.jsonObject(with: Data(frame)) as? [String: Any], nesting(of: value) <= limits.maxNesting else { failState(.malformedJSONRPC); return }
            await receiveRPC(value)
            if state == .failed { return }
        }
    }

    public func stdoutEOF() async { failState(.eof) }

    private func receiveRPC(_ value: [String: Any]) async {
        guard value["jsonrpc"] as? String == "2.0" else { failState(.malformedJSONRPC); return }
        if let id = value["id"] as? String, value["result"] != nil || value["error"] != nil {
            guard state == .initializing, id == initializeID, pending.contains(id), !initializedSent, value["error"] == nil else { failState(.wrongHandshake); return }
            pending.remove(id); initializedSent = true
            guard await writeRPC(["jsonrpc": "2.0", "method": CodexAppServerContract.initializedMethod, "params": [:]]) else { failState(.disconnected); return }
            guard let executable else { failState(.executableUnavailable); return }
            provenance = .init(executable: executable, schemaDigest: CodexAppServerContract.schemaDigest, epoch: epoch, initializationResult: "valid")
            state = .ready
            return
        }
        guard let method = value["method"] as? String else { failState(.malformedJSONRPC); return }
        guard state == .ready else { failState(.prematureMessage); return }
        if let id = value["id"] as? String, ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval"].contains(method) {
            await openApproval(jsonRequestID: id, method: method, params: value["params"] as? [String: Any] ?? [:])
            return
        }
        guard CodexSchemaManifest().stableNotificationMethods.contains(method) else { failState(.unsupportedMethod); return }
        await normalize(method: method, params: value["params"] as? [String: Any] ?? [:])
    }

    private func normalize(method: String, params: [String: Any]) async {
        guard let thread = params["threadId"] as? String, !thread.isEmpty else { unresolvedGap = true; return }
        let turn = params["turnId"] as? String
        guard let sourceID = params["eventId"] as? String, !sourceID.isEmpty else { unresolvedGap = true; return }
        let family: EventFamily = method.hasPrefix("item/") ? .turnDeclared : (method == "thread/started" ? .sessionActivity : .turnDeclared)
        let activity: SessionActivityKind? = method.hasSuffix("/completed") ? .completed : (method.hasSuffix("/started") ? .working : .working)
        let cursor = (params["sequence"] as? NSNumber).map { SourceCursor(scope: "codex-app-server:\(epoch):\(thread)", value: $0.int64Value) }
        guard let snapshot else { unresolvedGap = true; return }
        let envelope = RawEventEnvelope(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, contractVersion: snapshot.contractVersion, productNamespace: CodexAppServerContract.productNamespace.rawValue, nativeSessionID: thread, eventIdentity: .stable(sourceID), family: family, sourceVariant: "codex.appServer.\(method)", activityKind: activity, classification: .operationalMetadata, payloadByteSize: 0, sourceCursor: cursor, ownership: .init(nativeTurnID: turn), integrationMode: CodexAppServerContract.integrationMode, capabilityID: CodexAppServerContract.observationCapability, capabilityDirection: .observe, capabilityRevision: 1)
        _ = await intake.deliver(envelope)
    }

    private func openApproval(jsonRequestID: String, method: String, params: [String: Any]) async {
        guard let thread = params["threadId"] as? String, let turn = params["turnId"] as? String, let item = params["itemId"] as? String,
              let startedAtMilliseconds = (params["startedAtMs"] as? NSNumber)?.doubleValue else { unresolvedGap = true; return }
        let opaque = params["approvalId"] as? String
        let kind = method
        // The v0.144.6 schema does not supply a deadline. A request without a
        // documented deadline deliberately receives no live Action Lease.
        guard let deadlineSeconds = (params["deadline"] as? NSNumber)?.doubleValue else { unresolvedGap = true; return }
        let tuple = "\(epoch):\(jsonRequestID):\(thread):\(turn):\(item):\(opaque ?? "none"):\(kind)"
        guard let snapshot, snapshot.grants(CodexAppServerContract.approvalCapability, direction: .act) else { unresolvedGap = true; return }
        let owner = GuidedAttentionOwner(productNamespace: CodexAppServerContract.productNamespace, nativeSessionID: .init(thread), nativeAttentionRequestID: tuple, nativeTurnID: turn, integrationInstanceID: integrationInstanceID, negotiationSnapshotID: snapshot.id)
        let requestID = GuidedAttentionRequestID(productNamespace: owner.productNamespace, nativeSessionID: owner.nativeSessionID, nativeAttentionRequestID: tuple)
        let capability = CapabilityRecord(id: CodexAppServerContract.approvalCapability, direction: .act, availability: .available, scope: .request, maturity: .stable, freshness: .current)
        let fingerprint = "\(tuple):\(startedAtMilliseconds):\(deadlineSeconds)"
        let evidence = GuidedAttentionEvidence(owner: owner, eventIdentity: .stable("approval:\(tuple)"), sourceVariant: "codex.appServer.approval.request", capability: capability, semanticShape: .allowDeny, constraints: .init(nativeFingerprint: fingerprint), sourceObservedAt: clock())
        switch await attempts.ingest(evidence) { case .accepted, .duplicate: routes[tuple] = .init(requestID: requestID, owner: owner, nativeRequestID: jsonRequestID, opaqueApprovalID: opaque, fingerprint: fingerprint, deadline: Date(timeIntervalSince1970: deadlineSeconds), capability: capability); default: unresolvedGap = true }
    }

    /// Approval is the only routed action in this first stable schema. Other
    /// action capabilities remain unavailable until their exact response fields
    /// are proven in a generated schema and live initialization evidence.
    public func respondApproval(tuple: String, allow: Bool, attemptID: String, confirmed: Bool = true) async -> CodexAppServerActionResult {
        guard state == .ready, let route = routes[tuple], transport != nil, clock() <= route.deadline, confirmed else {
            return .rejected(nil)
        }
        let action: GuidedAction = allow ? .allow : .deny
        let binding = ActionLeaseBinding(requestID: route.requestID, owner: route.owner, capabilityID: route.capability.id, capabilityRevision: route.capability.revision, negotiationSnapshotID: route.owner.negotiationSnapshotID, semanticFingerprint: "approval:\(allow)", nativeFingerprint: route.fingerprint)
        let context = ActionLeaseValidationContext(binding: binding, capability: route.capability, currentNativeFingerprint: route.fingerprint, now: clock())
        let leaseID = "codex-app-server:\(epoch):\(attemptID)"
        guard case .issued = await attempts.issueLease(id: leaseID, requestID: route.requestID, action: action, semanticFingerprint: binding.semanticFingerprint, nativeFingerprint: binding.nativeFingerprint, capability: route.capability, issuedAt: clock(), deadline: route.deadline, confirmation: true),
              case .reserved = await attempts.reserveAttempt(id: attemptID, requestID: route.requestID, owner: route.owner, action: action, leaseID: leaseID, context: context, confirmation: true, reservedAt: clock()),
              case .dispatch = await attempts.prepareDispatch(attemptID: attemptID, context: context, now: clock(), confirmation: true) else { return .rejected(await attempts.attempt(for: attemptID)) }
        // A server-initiated approval is answered with the same JSON-RPC id,
        // not by an invented `approval/respond` client method. The v0.144.6
        // schema exposes no deadline, so this path remains normally disabled;
        // it exists only for a future schema that proves that field.
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": route.nativeRequestID, "result": ["decision": allow ? "accept" : "decline"]]
        guard await writeRPC(payload) else { _ = await attempts.recordProductOutcome(attemptID: attemptID, outcome: .indeterminate, at: clock()); await disconnect(); return .dispatched((await attempts.attempt(for: attemptID))!) }
        _ = await attempts.recordProductOutcome(attemptID: attemptID, outcome: .acceptedByProduct, at: clock())
        routes.removeValue(forKey: tuple)
        return .dispatched((await attempts.attempt(for: attemptID))!)
    }

    public func disconnect() async {
        await transport?.close(); transport = nil; buffer.removeAll(); pending.removeAll(); initializeID = nil; initializedSent = false; routes.removeAll(); unresolvedGap = true
        await attempts.invalidateForReconnect(); state = .disconnected
    }

    private func failState(_ cause: CodexAppServerFailure) { failure = cause; state = .failed; routes.removeAll(); Task { await attempts.invalidateForReconnect() } }
    private func writeRPC(_ payload: [String: Any]) async -> Bool {
        guard let transport, pending.count <= limits.maxPendingRequests, JSONSerialization.isValidJSONObject(payload), let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        do { try await transport.write(data + Data([0x0A])); return true } catch { return false }
    }
    private func nesting(of value: Any, depth: Int = 0) -> Int { if depth > limits.maxNesting { return depth }; if let dict = value as? [String: Any] { return dict.values.map { nesting(of: $0, depth: depth + 1) }.max() ?? depth }; if let list = value as? [Any] { return list.map { nesting(of: $0, depth: depth + 1) }.max() ?? depth }; return depth }
}
