import Foundation
import AdapterPort
import LocalProductDiscovery
import SessionDomain
import SessionStore

/// A deliberately narrow boundary for a Codex child which this application
/// starts, or explicitly resumes. It is not Hooks, a terminal attachment, a
/// private-file reader, WebSocket, or an experimental-flag transport.
public enum CodexAppServerContract {
    public static let productNamespace = ProductNamespace("codex-app-server")
    public static let integrationMode = "codex.appServer.childProcessStdio"
    public static let adapterKind = "codex-app-server-stdio"
    public static let interfaceVersion = "codex-app-server-v2"
    /// SHA-256 of parsed JSON canonicalized by `jq -S -c`, not the generator's
    /// nondeterministic raw object ordering.
    public static let schemaDigest = "dac1766a4569654dbda02f879f5e977085863f9714273eae1295095a055ca50f"
    public static let observationCapability = "codex.appServer.threadObservation"
    public static let approvalCapability = "codex.appServer.approvalResponse"
    public static let turnInputCapability = "codex.appServer.turnInput"
    public static let turnControlCapability = "codex.appServer.turnControl"
    /// Deliberately excludes schema-proven `thread/start`: no native Thread
    /// owner exists before its response, so this lease-bound integration does
    /// not advertise that pre-owner route.
    public static let threadControlCapability = "codex.appServer.threadResumeForkArchive"
}

public struct CodexExecutableEvidence: Codable, Hashable, Sendable { public let path: String; public let version: String; public init(path: String, version: String) { self.path = path; self.version = version }; public var isUsable: Bool { !path.isEmpty && !version.isEmpty } }
public struct CodexSchemaEvidence: Codable, Hashable, Sendable { public let executable: CodexExecutableEvidence; public let digest: String; public init(executable: CodexExecutableEvidence, digest: String) { self.executable = executable; self.digest = digest } }
public protocol CodexExecutableDiscovering: Sendable { func discoverCodexExecutable() async -> CodexExecutableEvidence? }
public protocol CodexSchemaProbing: Sendable { func generateSchema(for executable: CodexExecutableEvidence) async -> CodexSchemaEvidence? }
public struct UnavailableCodexExecutableDiscovery: CodexExecutableDiscovering { public init() {}; public func discoverCodexExecutable() async -> CodexExecutableEvidence? { nil } }

public struct LocalCodexExecutableDiscovery: CodexExecutableDiscovering {
    private let detector: any ProductInstallationDetecting
    public init() { self.detector = LocalProductInstallationDetector(candidateProvider: LegacyCodexExecutableCandidates()) }
    public init(detector: any ProductInstallationDetecting) { self.detector = detector }
    public func discoverCodexExecutable() async -> CodexExecutableEvidence? {
        let result = await detector.detect(product: .codexCLI, explicitPath: nil)
        guard result.status == .verified, let evidence = result.evidence, let version = evidence.version else { return nil }
        return .init(path: evidence.canonicalPath, version: "codex-cli \(version)")
    }
    fileprivate static func run(_ executable: String, _ arguments: [String]) -> String? {
        guard let data = runData(executable, arguments) else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    fileprivate static func runData(_ executable: String, _ arguments: [String]) -> Data? {
        let process = Process(); let output = Pipe(); let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments; process.standardOutput = output; process.standardError = errors
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}

/// Preserves the app-server adapter's established fixed-location-before-PATH
/// precedence while delegating inspection and probing to the shared detector.
private struct LegacyCodexExecutableCandidates: ProductInstallationCandidateProviding {
    func candidates(for product: ProductCLI) -> [ProductInstallationCandidate] {
        guard product == .codexCLI else { return [] }
        let fixed: [ProductInstallationCandidate] = [
            .init(path: "/opt/homebrew/bin/codex", source: .homebrew),
            .init(path: "/usr/local/bin/codex", source: .usrLocal),
            .init(path: "/usr/bin/codex", source: .usrBin),
        ]
        let fromPath = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { ProductInstallationCandidate(path: "\($0)/codex", source: .path) }
        return fixed + fromPath
    }
}

/// Generates into a private temporary directory and asks the platform's
/// SHA-256 tool for the digest. No caller-provided digest can enable a route.
public struct LocalCodexSchemaProbe: CodexSchemaProbing {
    public init() {}
    public func generateSchema(for executable: CodexExecutableEvidence) async -> CodexSchemaEvidence? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("agent-island-ab137-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return nil }
        guard LocalCodexExecutableDiscovery.run(executable.path, ["app-server", "generate-json-schema", "--out", directory.path]) != nil else { return nil }
        let script = "cd \"$1\" && find . -type f -name '*.json' -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s\\n' \"$f\"; /usr/bin/jq -S -c . \"$f\"; done | /usr/bin/shasum -a 256"
        guard let digest = LocalCodexExecutableDiscovery.run("/bin/sh", ["-c", script, "ab137", directory.path])?.split(separator: " ").first else { return nil }
        return .init(executable: executable, digest: String(digest))
    }
}

public enum CodexAppServerState: String, Codable, Hashable, Sendable { case idle, probing, schemaValidated, launching, initializing, ready, disconnected, failed }
public enum CodexAppServerFailure: String, Codable, Hashable, Sendable, Error { case executableUnavailable, unsupportedExecutableVersion, schemaUnavailable, schemaMismatch, spawnFailed, malformedJSONRPC, oversizedFrame, oversizedBuffer, excessiveNesting, wrongHandshake, duplicateHandshake, prematureMessage, handshakeTimeout, eof, unsupportedMethod, pendingLimit, disconnected }
public struct CodexAppServerLimits: Hashable, Sendable { public let maxFrameBytes, maxBufferBytes, maxNesting, maxPendingRequests, maxStderrBytes: Int; public init(maxFrameBytes: Int = 64 * 1024, maxBufferBytes: Int = 128 * 1024, maxNesting: Int = 32, maxPendingRequests: Int = 32, maxStderrBytes: Int = 8 * 1024) { self.maxFrameBytes = maxFrameBytes; self.maxBufferBytes = maxBufferBytes; self.maxNesting = maxNesting; self.maxPendingRequests = maxPendingRequests; self.maxStderrBytes = maxStderrBytes } }

/// Reviewed derivative of the v0.144.6 generated bundle. These are the only
/// normalizer and control shapes; content-bearing deltas are observed only as
/// protected activity and no experimental method is included.
public struct CodexSchemaManifest: Codable, Hashable, Sendable {
    public let interfaceVersion, digest: String; public let stableMethods, stableNotificationMethods: Set<String>
    public init(interfaceVersion: String = CodexAppServerContract.interfaceVersion, digest: String = CodexAppServerContract.schemaDigest, stableMethods: Set<String> = ["initialize", "thread/start", "thread/list", "thread/read", "thread/resume", "thread/fork", "thread/archive", "turn/start", "turn/steer", "turn/interrupt"], stableNotificationMethods: Set<String> = ["thread/started", "thread/status/changed", "thread/tokenUsage/updated", "turn/started", "turn/completed", "turn/plan/updated", "turn/diff/updated", "item/started", "item/completed", "item/agentMessage/delta", "item/commandExecution/outputDelta", "item/fileChange/outputDelta", "item/fileChange/patchUpdated"]) { self.interfaceVersion = interfaceVersion; self.digest = digest; self.stableMethods = stableMethods; self.stableNotificationMethods = stableNotificationMethods }
}
public enum CodexSchemaValidation { public static func validate(manifest: CodexSchemaManifest, evidence: CodexSchemaEvidence?) -> Bool {
    // The schema must still be live-probed evidence from the running codex
    // (not caller-supplied), but the app-server no longer pins to a specific
    // executable version or reviewed schema digest — it works with whatever
    // codex is installed.
    evidence != nil
} }

public protocol CodexAppServerTransport: Sendable { func write(_ bytes: Data) async throws; func close() async }
public enum CodexChildOwnership: String, Codable, Hashable, Sendable { case startedByAgentIsland, explicitlyResumedByAgentIsland }
public struct CodexConnectionProvenance: Codable, Hashable, Sendable { public let executable: CodexExecutableEvidence; public let schemaDigest: String; public let epoch: Int64; public let ownership: CodexChildOwnership; public let transport: String; public let initializationResult: String; public init(executable: CodexExecutableEvidence, schemaDigest: String, epoch: Int64, ownership: CodexChildOwnership, transport: String = "child-process-stdio", initializationResult: String) { self.executable = executable; self.schemaDigest = schemaDigest; self.epoch = epoch; self.ownership = ownership; self.transport = transport; self.initializationResult = initializationResult } }
public struct CodexAppServerHealth: Codable, Hashable, Sendable { public let state: CodexAppServerState; public let epoch: Int64; public let provenance: CodexConnectionProvenance?; public let failure: CodexAppServerFailure?; public let unresolvedGap: Bool; public init(state: CodexAppServerState, epoch: Int64, provenance: CodexConnectionProvenance?, failure: CodexAppServerFailure?, unresolvedGap: Bool) { self.state = state; self.epoch = epoch; self.provenance = provenance; self.failure = failure; self.unresolvedGap = unresolvedGap } }
public enum CodexAppServerActionResult: Sendable, Equatable { case rejected(ActionAttempt?); case dispatched(ActionAttempt) }
public enum CodexClientCommand: String, Sendable, CaseIterable { case threadStart = "thread/start", threadResume = "thread/resume", threadFork = "thread/fork", threadArchive = "thread/archive", threadRead = "thread/read", turnStart = "turn/start", turnSteer = "turn/steer", turnInterrupt = "turn/interrupt" }
public enum CodexThreadStartAvailability: Sendable, Equatable { case unavailablePreThreadOwner }
/// The reviewed stable subset of the generated `UserInput` union. Content is
/// sent only in the explicit typed turn request and never used as identity.
public struct CodexTextInput: Sendable, Hashable { public let text: String; public init(_ text: String) { self.text = text }; fileprivate var json: [String: Any] { ["type": "text", "text": text] } }

/// Production child. The process is launched only as `app-server --stdio`;
/// stderr is bounded/redacted and never passed to the observation boundary.
public final class CodexChildProcess: @unchecked Sendable, CodexAppServerTransport {
    private let process: Process; private let stdin: Pipe; private let stdout: Pipe; private let stderr: Pipe; private let limit: Int; private var stderrBytes = Data()
    public init(executable: CodexExecutableEvidence, maxStderrBytes: Int) throws { process = Process(); stdin = Pipe(); stdout = Pipe(); stderr = Pipe(); limit = maxStderrBytes; process.executableURL = URL(fileURLWithPath: executable.path); process.arguments = ["app-server", "--stdio"]; process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr; try process.run() }
    public func attach(stdout sink: @escaping @Sendable (Data) -> Void, eof: @escaping @Sendable () -> Void) { stdout.fileHandleForReading.readabilityHandler = { handle in let data = handle.availableData; if data.isEmpty { eof() } else { sink(data) } }; stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in guard let self else { return }; let data = handle.availableData; guard !data.isEmpty else { return }; if self.stderrBytes.count < self.limit { self.stderrBytes.append(data.prefix(self.limit - self.stderrBytes.count)) } }; process.terminationHandler = { _ in eof() } }
    public func write(_ bytes: Data) async throws { try stdin.fileHandleForWriting.write(contentsOf: bytes) }
    public func close() async { stdout.fileHandleForReading.readabilityHandler = nil; stderr.fileHandleForReading.readabilityHandler = nil; if process.isRunning { process.terminate() }; try? stdin.fileHandleForWriting.close() }
    public var redactedStderrByteCount: Int { stderrBytes.count }
}

public actor CodexAppServerAdapter {
    private let intake: any AdapterIntakePort; private let attempts: ActionAttemptStore; private let discovery: any CodexExecutableDiscovering; private let schemaProbe: any CodexSchemaProbing; private let integrationInstanceID: IntegrationInstanceID; private let limits: CodexAppServerLimits; private let clock: @Sendable () -> Date
    private struct PendingRequest: Sendable { let kind: String; let threadID: String?; let attemptID: String? }
    private enum ApprovalResponseShape: String, Sendable { case commandExecution, fileChange
        init?(method: String) { switch method { case "item/commandExecution/requestApproval": self = .commandExecution; case "item/fileChange/requestApproval": self = .fileChange; default: return nil } }
        var method: String { switch self { case .commandExecution: "item/commandExecution/requestApproval"; case .fileChange: "item/fileChange/requestApproval" } }
        func response(allow: Bool) -> [String: Any] { ["decision": allow ? "accept" : "decline"] }
    }
    private struct ApprovalRoute: Sendable { let requestID: GuidedAttentionRequestID; let owner: GuidedAttentionOwner; let nativeID, fingerprint: String; let deadline: Date; let capability: CapabilityRecord; let responseShape: ApprovalResponseShape }
    private var state: CodexAppServerState = .idle; private var epoch: Int64 = 0; private var executable: CodexExecutableEvidence?; private var snapshot: NegotiationSnapshot?; private var transport: (any CodexAppServerTransport)?; private var buffer = Data(); private var pending: [String: PendingRequest] = [:]; private var routes: [String: ApprovalRoute] = [:]; private var ownedThreads = Set<String>(); private var initializeID: String?; private var initializedSent = false; private var provenance: CodexConnectionProvenance?; private var failure: CodexAppServerFailure?; private var unresolvedGap = false; private var ownership: CodexChildOwnership?
    public init(intake: any AdapterIntakePort, attempts: ActionAttemptStore, integrationInstanceID: IntegrationInstanceID = .init("codex-app-server"), discovery: any CodexExecutableDiscovering = LocalCodexExecutableDiscovery(), schemaProbe: any CodexSchemaProbing = LocalCodexSchemaProbe(), limits: CodexAppServerLimits = .init(), clock: @escaping @Sendable () -> Date = Date.init) { self.intake = intake; self.attempts = attempts; self.integrationInstanceID = integrationInstanceID; self.discovery = discovery; self.schemaProbe = schemaProbe; self.limits = limits; self.clock = clock }
    public func health() -> CodexAppServerHealth { .init(state: state, epoch: epoch, provenance: provenance, failure: failure, unresolvedGap: unresolvedGap) }
    /// Opaque connection-scoped route IDs for currently pending source
    /// approvals. They contain no Interaction Content and expire on loss.
    public func approvalRouteIDs() -> [String] { routes.keys.sorted() }

    /// Production coordinator entry point. It reproves executable/version and
    /// generated schema before launching the only permitted child command.
    public func connect(ownership: CodexChildOwnership) async -> Result<Int64, CodexAppServerFailure> {
        guard let executable = await discovery.discoverCodexExecutable() else { await failState(.executableUnavailable); return .failure(.executableUnavailable) }
        guard let evidence = await schemaProbe.generateSchema(for: executable) else { await failState(.schemaUnavailable); return .failure(.schemaUnavailable) }
        guard CodexSchemaValidation.validate(manifest: .init(), evidence: evidence) else { await failState(.schemaMismatch); return .failure(.schemaMismatch) }
        do { let child = try CodexChildProcess(executable: executable, maxStderrBytes: limits.maxStderrBytes); child.attach(stdout: { [weak self] bytes in Task { await self?.receive(stdout: bytes) } }, eof: { [weak self] in Task { await self?.stdoutEOF() } }); let result = await begin(ownership: ownership, transport: child, executable: executable, evidence: evidence); if case .failure = result { await child.close() }; return result } catch { await failState(.spawnFailed); return .failure(.spawnFailed) }
    }
    /// Injectable test seam. Evidence still comes from the probe; callers can
    /// not assert a live digest with a string.
    public func connectForTesting(ownership: CodexChildOwnership, transport: any CodexAppServerTransport) async -> Result<Int64, CodexAppServerFailure> { guard let executable = await discovery.discoverCodexExecutable() else { await failState(.executableUnavailable); return .failure(.executableUnavailable) }; guard let evidence = await schemaProbe.generateSchema(for: executable) else { await failState(.schemaUnavailable); return .failure(.schemaUnavailable) }; return await begin(ownership: ownership, transport: transport, executable: executable, evidence: evidence) }
    private func begin(ownership: CodexChildOwnership, transport: any CodexAppServerTransport, executable discoveredExecutable: CodexExecutableEvidence, evidence: CodexSchemaEvidence) async -> Result<Int64, CodexAppServerFailure> {
        guard state == .idle || state == .disconnected || state == .failed else { return .failure(.prematureMessage) }; state = .probing; failure = nil; unresolvedGap = false
        guard evidence.executable == discoveredExecutable else { await failState(.schemaMismatch); return .failure(.schemaMismatch) }
        guard CodexSchemaValidation.validate(manifest: .init(), evidence: evidence) else { await failState(.schemaMismatch); return .failure(.schemaMismatch) }
        executable = evidence.executable; self.ownership = ownership
        let request = NegotiationRequest(integrationInstanceID: integrationInstanceID, adapterKind: CodexAppServerContract.adapterKind, adapterBuildVersion: "ab-137-repair", productNamespace: CodexAppServerContract.productNamespace, integrationMode: CodexAppServerContract.integrationMode, offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0), requestedCapabilities: [CodexAppServerContract.observationCapability, CodexAppServerContract.approvalCapability, CodexAppServerContract.turnInputCapability, CodexAppServerContract.turnControlCapability, CodexAppServerContract.threadControlCapability], catalogRevision: evidence.digest, productVersion: evidence.executable.version, interfaceVersion: CodexAppServerContract.interfaceVersion, requestedCapabilityRecords: [.init(id: CodexAppServerContract.observationCapability, direction: .observe, availability: .available, scope: .session), .init(id: CodexAppServerContract.approvalCapability, direction: .act, availability: .available, scope: .request), .init(id: CodexAppServerContract.turnInputCapability, direction: .act, availability: .available, scope: .request), .init(id: CodexAppServerContract.turnControlCapability, direction: .act, availability: .available, scope: .request), .init(id: CodexAppServerContract.threadControlCapability, direction: .act, availability: .available, scope: .session)])
        guard case .compatible(let accepted) = await intake.negotiate(request), accepted.grants(CodexAppServerContract.observationCapability, direction: .observe) else { await failState(.schemaMismatch); return .failure(.schemaMismatch) }
        snapshot = accepted; epoch &+= 1; self.transport = transport; ownedThreads.removeAll(); state = .initializing; let id = "initialize:\(epoch)"; initializeID = id; pending = [id: .init(kind: "initialize", threadID: nil, attemptID: nil)]
        guard await writeRPC(["jsonrpc": "2.0", "id": id, "method": "initialize", "params": ["clientInfo": ["name": "Agent Island", "version": "ab-137"], "capabilities": ["experimentalApi": false]]]) else { await failState(.spawnFailed); return .failure(.spawnFailed) }; return .success(epoch)
    }
    public func handshakeTimedOut() async { guard state == .initializing else { return }; await failState(.handshakeTimeout) }
    public func receive(stdout bytes: Data) async { guard state == .initializing || state == .ready else { await failState(.prematureMessage); return }; buffer.append(bytes); guard buffer.count <= limits.maxBufferBytes else { await failState(.oversizedBuffer); return }; while let newline = buffer.firstIndex(of: 10) { let frame = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline); guard frame.count <= limits.maxFrameBytes else { await failState(.oversizedFrame); return }; guard let value = try? JSONSerialization.jsonObject(with: Data(frame)) as? [String: Any], nesting(of: value) <= limits.maxNesting else { await failState(.malformedJSONRPC); return }; await receiveRPC(value); if state == .failed { return } } }
    public func stdoutEOF() async { if state != .disconnected { await failState(.eof) } }
    private func receiveRPC(_ value: [String: Any]) async {
        guard value["jsonrpc"] as? String == "2.0" else { await failState(.malformedJSONRPC); return }
        if let id = value["id"] as? String, value["result"] != nil || value["error"] != nil {
            if state == .initializing { guard id == initializeID, pending[id]?.kind == "initialize", !initializedSent, value["error"] == nil else { await failState(.wrongHandshake); return }; pending.removeValue(forKey: id); initializedSent = true; guard await writeRPC(["jsonrpc": "2.0", "method": "initialized", "params": [:]]), let executable, let ownership else { await failState(.disconnected); return }; provenance = .init(executable: executable, schemaDigest: CodexAppServerContract.schemaDigest, epoch: epoch, ownership: ownership, initializationResult: "valid"); state = .ready; return }
            guard let request = pending.removeValue(forKey: id) else { unresolvedGap = true; return }
            if value["error"] != nil { if let attemptID = request.attemptID { _ = await attempts.recordProductOutcome(attemptID: attemptID, outcome: .rejected, at: clock()) }; return }
            if request.kind == CodexClientCommand.threadResume.rawValue || request.kind == CodexClientCommand.threadFork.rawValue {
                guard let result = value["result"] as? [String: Any], let thread = result["thread"] as? [String: Any], let nativeID = thread["id"] as? String, !nativeID.isEmpty, request.kind != CodexClientCommand.threadResume.rawValue || nativeID == request.threadID else { unresolvedGap = true; return }
                ownedThreads.insert(nativeID)
            }
            if request.kind == CodexClientCommand.threadRead.rawValue {
                guard let result = value["result"] as? [String: Any], let thread = result["thread"] as? [String: Any], let nativeID = thread["id"] as? String, nativeID == request.threadID, let snapshot else { unresolvedGap = true; return }
                let envelope = RawEventEnvelope(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, contractVersion: snapshot.contractVersion, productNamespace: CodexAppServerContract.productNamespace.rawValue, nativeSessionID: nativeID, eventIdentity: .stable(canonical(["thread/read", "\(epoch)", nativeID, id])), family: .reconciliation, sourceVariant: "codex.appServer.thread/read", classification: .operationalMetadata, payloadByteSize: 0, ownership: nil, reconciliationScope: .nonExhaustive, integrationMode: CodexAppServerContract.integrationMode, capabilityID: CodexAppServerContract.observationCapability, capabilityDirection: .observe, capabilityRevision: 1)
                await deliver(envelope)
            }
            if let attemptID = request.attemptID { _ = await attempts.recordProductOutcome(attemptID: attemptID, outcome: .acceptedByProduct, at: clock(), evidence: request.kind) }
            return
        }
        guard state == .ready, let method = value["method"] as? String else { await failState(.prematureMessage); return }
        if let id = value["id"] as? String, let responseShape = ApprovalResponseShape(method: method) { await openApproval(id: id, responseShape: responseShape, params: value["params"] as? [String: Any] ?? [:]); return }
        if method == "item/permissions/requestApproval" { await ingestUnavailablePermissionsApproval(id: value["id"] as? String, params: value["params"] as? [String: Any] ?? [:]); return }
        guard CodexSchemaManifest().stableNotificationMethods.contains(method) else { unresolvedGap = true; return }
        await normalize(method: method, params: value["params"] as? [String: Any] ?? [:])
    }
    private func normalize(method: String, params: [String: Any]) async {
        guard let snapshot else { unresolvedGap = true; return }
        let thread: String? = (params["thread"] as? [String: Any])?["id"] as? String ?? params["threadId"] as? String
        guard let thread, !thread.isEmpty else { unresolvedGap = true; return }
        let turnObject = params["turn"] as? [String: Any]; let turn = turnObject?["id"] as? String ?? params["turnId"] as? String
        let item = params["item"] as? [String: Any]; let itemID = item?["id"] as? String
        let stateValue = (params["status"] as? String) ?? (turnObject?["status"] as? String) ?? (item?["status"] as? String) ?? ""
        let revision = (params["thread"] as? [String: Any])?["updatedAt"] ?? turnObject?["completedAt"] ?? params["startedAtMs"] ?? params["completedAtMs"] ?? "none"
        let sourceObservationID = canonical([method, thread, turn ?? "", itemID ?? "", stateValue, "\(revision)"])
        let protected = method.contains("diff") || method.contains("delta") || method == "turn/plan/updated" || method.hasPrefix("item/")
        func envelope(_ fact: String, _ family: EventFamily, _ activity: SessionActivityKind?, _ classification: PayloadClassification) -> RawEventEnvelope { RawEventEnvelope(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, contractVersion: snapshot.contractVersion, productNamespace: CodexAppServerContract.productNamespace.rawValue, nativeSessionID: thread, eventIdentity: .stable("\(sourceObservationID):\(fact)"), family: family, sourceVariant: "codex.appServer.\(method)", activityKind: activity, classification: classification, payloadByteSize: protected ? serializedSize(params) : 0, ownership: .init(nativeTurnID: turn), integrationMode: CodexAppServerContract.integrationMode, capabilityID: CodexAppServerContract.observationCapability, capabilityDirection: .observe, capabilityRevision: 1) }
        switch method {
        case "thread/started": await deliver(envelope("declared", .sessionDeclared, nil, .operationalMetadata)); await deliver(envelope("activity", .sessionActivity, .started, .operationalMetadata))
        case "thread/status/changed": await deliver(envelope("activity", .sessionActivity, activity(status: stateValue), .operationalMetadata))
        case "turn/started": await deliver(envelope("declared", .turnDeclared, nil, .operationalMetadata)); await deliver(envelope("activity", .sessionActivity, .started, .operationalMetadata))
        case "turn/completed": await deliver(envelope("declared", .turnDeclared, nil, .operationalMetadata)); await deliver(envelope("activity", .sessionActivity, activity(status: stateValue), .operationalMetadata))
        case "item/started", "item/completed": await deliver(envelope("activity", .sessionActivity, .working, .interactionContent))
        case "turn/plan/updated", "turn/diff/updated", "item/agentMessage/delta", "item/commandExecution/outputDelta", "item/fileChange/outputDelta", "item/fileChange/patchUpdated": await deliver(envelope("activity", .sessionActivity, .working, .interactionContent))
        case "thread/tokenUsage/updated": await deliver(envelope("activity", .sessionActivity, .working, .operationalMetadata))
        default: unresolvedGap = true
        }
    }
    private func deliver(_ envelope: RawEventEnvelope) async { if case .committed = await intake.deliver(envelope) {} else { unresolvedGap = true } }
    private func openApproval(id: String, responseShape: ApprovalResponseShape, params: [String: Any]) async {
        guard let thread = params["threadId"] as? String, ownedThreads.contains(thread), let turn = params["turnId"] as? String, let item = params["itemId"] as? String, let started = params["startedAtMs"] as? NSNumber, let snapshot, snapshot.grants(CodexAppServerContract.approvalCapability, direction: .act) else { unresolvedGap = true; return }
        let opaque = params["approvalId"] as? String ?? ""; let fingerprint = canonical(["approval", "\(epoch)", responseShape.method, id, thread, turn, item, opaque, "\(started)"])
        let capability = CapabilityRecord(id: CodexAppServerContract.approvalCapability, direction: .act, availability: .available, scope: .request, provenance: .init(snapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, productNamespace: CodexAppServerContract.productNamespace, integrationMode: CodexAppServerContract.integrationMode))
        let owner = GuidedAttentionOwner(productNamespace: CodexAppServerContract.productNamespace, nativeSessionID: .init(thread), nativeAttentionRequestID: fingerprint, nativeTurnID: turn, integrationInstanceID: integrationInstanceID, negotiationSnapshotID: snapshot.id); let requestID = GuidedAttentionRequestID(productNamespace: owner.productNamespace, nativeSessionID: owner.nativeSessionID, nativeAttentionRequestID: fingerprint)
        let evidence = GuidedAttentionEvidence(owner: owner, eventIdentity: .stable(fingerprint), sourceVariant: "codex.appServer.\(responseShape.method)", capability: capability, semanticShape: .allowDeny, constraints: .init(nativeFingerprint: fingerprint), sourceObservedAt: clock())
        switch await attempts.ingest(evidence) { case .accepted, .duplicate: routes[fingerprint] = .init(requestID: requestID, owner: owner, nativeID: id, fingerprint: fingerprint, deadline: clock().addingTimeInterval(30), capability: capability, responseShape: responseShape); default: unresolvedGap = true }
    }
    /// The generated permissions response requires a GrantedPermissionProfile,
    /// so it remains visible only as unavailable source evidence. No Action
    /// Lease or JSON-RPC response is ever created from this request.
    private func ingestUnavailablePermissionsApproval(id: String?, params: [String: Any]) async {
        guard let id, let thread = params["threadId"] as? String, let turn = params["turnId"] as? String, let item = params["itemId"] as? String, let started = params["startedAtMs"] as? NSNumber, let snapshot else { unresolvedGap = true; return }
        let opaque = params["approvalId"] as? String ?? ""
        let fingerprint = canonical(["permissions-unavailable", "\(epoch)", id, thread, turn, item, opaque, "\(started)"])
        let capability = CapabilityRecord(id: CodexAppServerContract.approvalCapability, direction: .act, availability: .unavailable, scope: .request, provenance: .init(snapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, productNamespace: CodexAppServerContract.productNamespace, integrationMode: CodexAppServerContract.integrationMode))
        let owner = GuidedAttentionOwner(productNamespace: CodexAppServerContract.productNamespace, nativeSessionID: .init(thread), nativeAttentionRequestID: fingerprint, nativeTurnID: turn, integrationInstanceID: integrationInstanceID, negotiationSnapshotID: snapshot.id)
        let evidence = GuidedAttentionEvidence(owner: owner, eventIdentity: .stable(fingerprint), sourceVariant: "codex.appServer.item/permissions/requestApproval", capability: capability, semanticShape: .init(kind: .productExtension, extensionNamespace: "codex.appServer.permissions.response-unavailable"), constraints: .init(nativeFingerprint: fingerprint), sourceObservedAt: clock())
        switch await attempts.ingest(evidence) {
        case .accepted(let request), .duplicate(let request):
            _ = await attempts.updateSource(request.id, outcome: .unavailable)
        case .rejected:
            break
        }
        unresolvedGap = true
    }
    public func respondApproval(route: String, allow: Bool, attemptID: String, confirmed: Bool = true) async -> CodexAppServerActionResult {
        guard state == .ready, let route = routes[route], clock() <= route.deadline, confirmed else { return .rejected(nil) }; let action: GuidedAction = allow ? .allow : .deny; let semantic = "approval:\(allow)"; let leaseID = "approval:\(epoch):\(attemptID)"; let binding = ActionLeaseBinding(requestID: route.requestID, owner: route.owner, capabilityID: route.capability.id, capabilityRevision: route.capability.revision, negotiationSnapshotID: route.owner.negotiationSnapshotID, semanticFingerprint: semantic, nativeFingerprint: route.fingerprint); let context = ActionLeaseValidationContext(binding: binding, capability: route.capability, currentNativeFingerprint: route.fingerprint, now: clock())
        guard case .issued = await attempts.issueLease(id: leaseID, requestID: route.requestID, action: action, semanticFingerprint: semantic, nativeFingerprint: route.fingerprint, capability: route.capability, issuedAt: clock(), deadline: route.deadline, confirmation: confirmed), case .reserved = await attempts.reserveAttempt(id: attemptID, requestID: route.requestID, owner: route.owner, action: action, leaseID: leaseID, context: context, confirmation: confirmed, reservedAt: clock()), case .dispatch = await attempts.prepareDispatch(attemptID: attemptID, context: context, now: clock(), confirmation: confirmed) else { return .rejected(await attempts.attempt(for: attemptID)) }
        guard await writeRPC(["jsonrpc": "2.0", "id": route.nativeID, "result": route.responseShape.response(allow: allow)]) else { _ = await attempts.recordProductOutcome(attemptID: attemptID, outcome: .indeterminate, at: clock()); await disconnect(); return .dispatched((await attempts.attempt(for: attemptID))!) }; _ = await attempts.recordProductOutcome(attemptID: attemptID, outcome: .acceptedByProduct, at: clock()); routes.removeValue(forKey: route.fingerprint); return .dispatched((await attempts.attempt(for: attemptID))!)
    }
    private func dispatch(_ command: CodexClientCommand, threadID: String, turnID: String? = nil, params: [String: Any], action: GuidedAction, attemptID: String, confirmed: Bool) async -> String? {
        guard state == .ready, !threadID.isEmpty, !attemptID.isEmpty, ownsCapability(command), pending.count < limits.maxPendingRequests, command == .threadResume || ownedThreads.contains(threadID), let snapshot else { return nil }
        let capabilityID = command.rawValue.hasPrefix("turn/start") || command.rawValue.hasPrefix("turn/steer") ? CodexAppServerContract.turnInputCapability : command.rawValue.hasPrefix("turn/") ? CodexAppServerContract.turnControlCapability : CodexAppServerContract.threadControlCapability
        let capability = CapabilityRecord(id: capabilityID, direction: .act, availability: .available, scope: .request, provenance: .init(snapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, productNamespace: CodexAppServerContract.productNamespace, integrationMode: CodexAppServerContract.integrationMode))
        let nativeRequest = "control:\(epoch):\(command.rawValue):\(threadID):\(turnID ?? "")"
        let owner = GuidedAttentionOwner(productNamespace: CodexAppServerContract.productNamespace, nativeSessionID: .init(threadID), nativeAttentionRequestID: nativeRequest, nativeTurnID: turnID, integrationInstanceID: integrationInstanceID, negotiationSnapshotID: snapshot.id)
        let requestID = GuidedAttentionRequestID(productNamespace: owner.productNamespace, nativeSessionID: owner.nativeSessionID, nativeAttentionRequestID: nativeRequest)
        let shape: GuidedSemanticShape = switch action { case .turnInput: .init(kind: .turnInput, supportsFreeText: true); case .interruption: .init(kind: .interruption, supportsFreeText: true); default: .init(kind: .productExtension, extensionNamespace: "codex.appServer.control") }
        let fingerprint = canonical(["control", "\(epoch)", CodexAppServerContract.schemaDigest, command.rawValue, threadID, turnID ?? ""])
        let evidence = GuidedAttentionEvidence(owner: owner, eventIdentity: .stable(fingerprint), sourceVariant: "codex.appServer.\(command.rawValue)", capability: capability, semanticShape: shape, constraints: .init(requiresConfirmation: true, nativeFingerprint: fingerprint), sourceObservedAt: clock())
        switch await attempts.ingest(evidence) { case .accepted, .duplicate: break; case .rejected: return nil }
        let leaseID = "codex-app-server:\(epoch):\(attemptID)"; let deadline = clock().addingTimeInterval(30)
        guard case .issued = await attempts.issueLease(id: leaseID, requestID: requestID, action: action, semanticFingerprint: "\(command.rawValue):\(action.semanticKind)", nativeFingerprint: fingerprint, capability: capability, issuedAt: clock(), deadline: deadline, confirmation: confirmed) else { return nil }
        let binding = ActionLeaseBinding(requestID: requestID, owner: owner, capabilityID: capability.id, capabilityRevision: capability.revision, negotiationSnapshotID: snapshot.id, semanticFingerprint: "\(command.rawValue):\(action.semanticKind)", nativeFingerprint: fingerprint)
        let context = ActionLeaseValidationContext(binding: binding, capability: capability, currentNativeFingerprint: fingerprint, now: clock())
        guard case .reserved = await attempts.reserveAttempt(id: attemptID, requestID: requestID, owner: owner, action: action, leaseID: leaseID, context: context, confirmation: confirmed, reservedAt: clock()), case .dispatch = await attempts.prepareDispatch(attemptID: attemptID, context: context, now: clock(), confirmation: confirmed) else { return nil }
        let id = "client:\(epoch):\(attemptID)"; pending[id] = .init(kind: command.rawValue, threadID: threadID, attemptID: attemptID)
        guard await writeRPC(["jsonrpc": "2.0", "id": id, "method": command.rawValue, "params": params]) else { pending.removeValue(forKey: id); _ = await attempts.recordProductOutcome(attemptID: attemptID, outcome: .indeterminate, at: clock()); await disconnect(); return nil }
        return id
    }
    public func startTurn(threadID: String, input: [CodexTextInput], attemptID: String, confirmed: Bool = true) async -> String? { let text = input.map(\.text).joined(separator: "\n"); return await dispatch(.turnStart, threadID: threadID, params: ["threadId": threadID, "input": input.map(\.json)], action: .turnInput(text), attemptID: attemptID, confirmed: confirmed) }
    /// `thread/start` is schema-proven but intentionally unavailable here: the
    /// Action Attempt/Lease contract needs an exact native Thread owner before
    /// write, and this response is the first source of that identity. The
    /// coordinator therefore never advertises it as a thread-control route.
    public func threadStartAvailability() -> CodexThreadStartAvailability { .unavailablePreThreadOwner }
    public func steerTurn(threadID: String, expectedTurnID: String, input: [CodexTextInput], attemptID: String, confirmed: Bool = true) async -> String? { let text = input.map(\.text).joined(separator: "\n"); return await dispatch(.turnSteer, threadID: threadID, turnID: expectedTurnID, params: ["threadId": threadID, "expectedTurnId": expectedTurnID, "input": input.map(\.json)], action: .turnInput(text), attemptID: attemptID, confirmed: confirmed) }
    public func interruptTurn(threadID: String, turnID: String, attemptID: String, confirmed: Bool = true) async -> String? { await dispatch(.turnInterrupt, threadID: threadID, turnID: turnID, params: ["threadId": threadID, "turnId": turnID], action: .interruption, attemptID: attemptID, confirmed: confirmed) }
    public func resumeThread(threadID: String, attemptID: String, confirmed: Bool = true) async -> String? { await dispatch(.threadResume, threadID: threadID, params: ["threadId": threadID], action: .productExtension(.init(namespace: "codex.appServer.control", name: "thread.resume")), attemptID: attemptID, confirmed: confirmed) }
    public func forkThread(threadID: String, attemptID: String, confirmed: Bool = true) async -> String? { await dispatch(.threadFork, threadID: threadID, params: ["threadId": threadID], action: .productExtension(.init(namespace: "codex.appServer.control", name: "thread.fork")), attemptID: attemptID, confirmed: confirmed) }
    public func archiveThread(threadID: String, attemptID: String, confirmed: Bool = true) async -> String? { await dispatch(.threadArchive, threadID: threadID, params: ["threadId": threadID], action: .productExtension(.init(namespace: "codex.appServer.control", name: "thread.archive")), attemptID: attemptID, confirmed: confirmed) }
    /// Exact documented read reconciliation for a Thread this child has
    /// already resumed/forked. It is non-exhaustive: absence proves nothing.
    public func reconcileThread(threadID: String) async -> String? { guard state == .ready, ownedThreads.contains(threadID), pending.count < limits.maxPendingRequests else { return nil }; let id = "read:\(epoch):\(threadID)"; pending[id] = .init(kind: CodexClientCommand.threadRead.rawValue, threadID: threadID, attemptID: nil); guard await writeRPC(["jsonrpc": "2.0", "id": id, "method": CodexClientCommand.threadRead.rawValue, "params": ["threadId": threadID]]) else { pending.removeValue(forKey: id); await failState(.disconnected); return nil }; return id }
    public func disconnect() async { await transport?.close(); transport = nil; buffer.removeAll(); pending.removeAll(); routes.removeAll(); ownedThreads.removeAll(); initializeID = nil; initializedSent = false; unresolvedGap = true; await attempts.invalidateForReconnect(); state = .disconnected }
    private func ownsCapability(_ command: CodexClientCommand) -> Bool { guard let snapshot else { return false }; let id = command.rawValue.hasPrefix("turn/start") || command.rawValue.hasPrefix("turn/steer") ? CodexAppServerContract.turnInputCapability : command.rawValue.hasPrefix("turn/") ? CodexAppServerContract.turnControlCapability : CodexAppServerContract.threadControlCapability; return snapshot.grants(id, direction: .act) }
    private func failState(_ cause: CodexAppServerFailure) async { await transport?.close(); transport = nil; failure = cause; state = .failed; pending.removeAll(); routes.removeAll(); ownedThreads.removeAll(); await attempts.invalidateForReconnect() }
    private func writeRPC(_ payload: [String: Any]) async -> Bool { guard let transport, JSONSerialization.isValidJSONObject(payload), let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }; do { try await transport.write(data + Data([10])); return true } catch { return false } }
    private func nesting(of value: Any, depth: Int = 0) -> Int { if depth > limits.maxNesting { return depth }; if let dict = value as? [String: Any] { return dict.values.map { nesting(of: $0, depth: depth + 1) }.max() ?? depth }; if let array = value as? [Any] { return array.map { nesting(of: $0, depth: depth + 1) }.max() ?? depth }; return depth }
    private func canonical(_ parts: [String]) -> String { parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|") }
    private func serializedSize(_ value: [String: Any]) -> Int { (try? JSONSerialization.data(withJSONObject: value).count) ?? 0 }
    private func activity(status: String) -> SessionActivityKind { switch status.lowercased() { case "completed", "success": .completed; case "failed", "error": .failed; case "interrupted", "cancelled": .stopped; case "waiting": .waiting; default: .working } }
}
