import Foundation
import SessionDomain
import AdapterPort
import ClaudeCodeAdapter

/// Opt-in, documented-hook observation for independently launched Codex CLI
/// terminal sessions. This is not an app-server, terminal, or action bridge.
public enum CodexCLIIntegration {
    public static let productNamespace = ProductNamespace("codex-cli")
    public static let integrationMode = "codexCLI.documentedHooksObservation"
    public static let adapterKind = "codex-cli.documented-hooks"
    public static let adapterBuildVersion = "1.0.0"
    public static let interfaceVersion = "hooks-v1"
    public static let catalogRevision = "codex-hooks.catalog.v1"
    public static let observationCapability = "codex.hooks.sessionObservation"
    public static let permissionCueCapability = "codex.hooks.permissionCueObservation"
    public static let configurationCapability = WellKnownCapability.configuration
    public static let allObservationCapabilities = [observationCapability, permissionCueCapability]
    /// There are deliberately no action capabilities in this catalog.
    public static let allActionCapabilities: [String] = []
}

public struct CodexHooksVersionEvidence: Codable, Hashable, Sendable {
    public let productVersion: String
    public let interfaceVersion: String
    public let documentedHooksAvailable: Bool
    public let observedAt: Date
    public init(productVersion: String, interfaceVersion: String = CodexCLIIntegration.interfaceVersion, documentedHooksAvailable: Bool, observedAt: Date = Date()) {
        self.productVersion = productVersion; self.interfaceVersion = interfaceVersion; self.documentedHooksAvailable = documentedHooksAvailable; self.observedAt = observedAt
    }
    public var supported: Bool { documentedHooksAvailable && interfaceVersion == CodexCLIIntegration.interfaceVersion && !productVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public enum CodexHookName: String, Codable, CaseIterable, Sendable {
    case sessionStart = "SessionStart", userPromptSubmit = "UserPromptSubmit", preToolUse = "PreToolUse", postToolUse = "PostToolUse", preCompact = "PreCompact", postCompact = "PostCompact", stop = "Stop", subagentStart = "SubagentStart", subagentStop = "SubagentStop", permissionRequest = "PermissionRequest", activity = "Activity"
    init?(documentedName: String) {
        let value = documentedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let found = Self.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }) else { return nil }
        self = found
    }
}

public enum CodexHookRejection: String, Error, Codable, Hashable, Sendable {
    case disabled, unauthenticated, untrustedHelper, oversizedEnvelope, malformedEnvelope, unsupportedHook, unsupportedVersion, missingNativeSessionIdentity, missingEventIdentity, crossOwner, duplicateEvent, replayedNonce, invalidParentage, unprovenChildStop, missingStopEvidence, capabilityUnavailable, transportUnavailable
}

/// This receives only opaque JSON from an installed documented hook. It has
/// no `CODEX_HOME`, transcript, SQLite, stdout, terminal, callback, or action
/// field, and intentionally has no route for reading any of those sources.
public struct CodexHookEnvelope: Sendable {
    public let name: CodexHookName
    public let eventIdentity: EventIdentity
    public let nativeSessionID: String
    public let nativeTurnID: String?
    public let nativeChildID: String?
    public let parentTurnID: String?
    public let sourceSequence: Int64?
    public let occurrenceTime: Date?
    public let payload: Data
    public let terminalOutcome: SessionActivityKind?

    public static func decode(_ data: Data, maxBytes: Int = SessionDomainValidator.maxPayloadBytes) throws -> Self {
        guard data.count <= maxBytes else { throw CodexHookRejection.oversizedEnvelope }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CodexHookRejection.malformedEnvelope }
        func text(_ keys: [String]) -> String? { keys.lazy.compactMap { root[$0] as? String }.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= SessionDomainValidator.maxMetadataStringBytes }) }
        guard let rawName = text(["hook_event_name", "event", "event_name"]), let name = CodexHookName(documentedName: rawName) else { throw CodexHookRejection.unsupportedHook }
        guard let session = text(["session_id", "sessionId", "thread_id"]), !session.isEmpty else { throw CodexHookRejection.missingNativeSessionIdentity }
        guard let event = text(["event_id", "eventId", "id"]), !event.isEmpty else { throw CodexHookRejection.missingEventIdentity }
        if let namespace = text(["product_namespace", "productNamespace"]), namespace != CodexCLIIntegration.productNamespace.rawValue { throw CodexHookRejection.crossOwner }
        let sequence = (root["sequence"] as? NSNumber)?.int64Value ?? (root["sequence_number"] as? NSNumber)?.int64Value
        let occurrence = (root["timestamp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let rawOutcome = text(["stop_reason", "status", "result_status"]) ?? ((root["result"] as? [String: Any])?["status"] as? String)
        let outcome: SessionActivityKind? = switch rawOutcome?.lowercased() {
        case "completed", "complete", "success", "done", "ok": .completed
        case "failed", "failure", "error": .failed
        case "stopped", "cancelled", "canceled", "interrupted": .stopped
        default: nil
        }
        return Self(name: name, eventIdentity: .stable(event), nativeSessionID: session, nativeTurnID: text(["turn_id", "turnId"]), nativeChildID: text(["subagent_run_id", "child_id", "subagent_id"]), parentTurnID: text(["parent_turn_id", "parentTurnId"]), sourceSequence: sequence, occurrenceTime: occurrence, payload: data, terminalOutcome: outcome)
    }
}

public struct CodexPermissionCue: Codable, Hashable, Sendable {
    public let eventIdentity: EventIdentity
    public let sessionIdentity: AgentSessionIdentity
    public let sourceObservedAt: Date?
    /// Guided response is unavailable: there is intentionally no Action Lease.
    public let guidedResponseAvailable: Bool
    public init(eventIdentity: EventIdentity, sessionIdentity: AgentSessionIdentity, sourceObservedAt: Date?) { self.eventIdentity = eventIdentity; self.sessionIdentity = sessionIdentity; self.sourceObservedAt = sourceObservedAt; self.guidedResponseAvailable = false }
}

/// Interaction Content is never part of a fact, notification, diagnostic, or
/// export. A caller must explicitly opt in before it may retain this local
/// presentation payload through the protected-content boundary.
public struct CodexProtectedObservationContent: Codable, Hashable, Sendable {
    public let bytes: Data
    public let classification: PayloadClassification
    public let sessionIdentity: AgentSessionIdentity
    public let nativeTurnID: String?
    public init(bytes: Data, sessionIdentity: AgentSessionIdentity, nativeTurnID: String?) { self.bytes = bytes; self.classification = .interactionContent; self.sessionIdentity = sessionIdentity; self.nativeTurnID = nativeTurnID }
}

public struct CodexContentConsent: Hashable, Sendable {
    public let localPresentationEnabled: Bool
    public init(localPresentationEnabled: Bool = false) { self.localPresentationEnabled = localPresentationEnabled }
    public static let none = Self()
}

public struct CodexNormalizedObservation: Sendable {
    public let events: [RawEventEnvelope]
    public let permissionCue: CodexPermissionCue?
    public let protectedContent: CodexProtectedObservationContent?
    public init(events: [RawEventEnvelope], permissionCue: CodexPermissionCue? = nil, protectedContent: CodexProtectedObservationContent? = nil) { self.events = events; self.permissionCue = permissionCue; self.protectedContent = protectedContent }
}

public enum CodexHookNormalizer {
    public static func normalize(_ hook: CodexHookEnvelope, snapshot: NegotiationSnapshot, installationID: IntegrationInstanceID, contentConsent: CodexContentConsent = .none) -> Result<CodexNormalizedObservation, CodexHookRejection> {
        guard snapshot.productNamespace == CodexCLIIntegration.productNamespace, snapshot.integrationInstanceID == installationID, snapshot.grants(CodexCLIIntegration.observationCapability, direction: .observe) else { return .failure(.capabilityUnavailable) }
        let identity = AgentSessionIdentity(productNamespace: CodexCLIIntegration.productNamespace, nativeSessionID: NativeSessionID(hook.nativeSessionID))
        let content = contentConsent.localPresentationEnabled ? CodexProtectedObservationContent(bytes: hook.payload, sessionIdentity: identity, nativeTurnID: hook.nativeTurnID) : nil
        let cursor = hook.sourceSequence.map { SourceCursor(scope: "codex-session:\(hook.nativeSessionID)", value: $0) }
        func id(_ suffix: String) -> EventIdentity { switch hook.eventIdentity { case .stable(let value): .stable(value + ":" + suffix); case .weak(let value): .weak(value + ":" + suffix) } }
        func event(_ family: EventFamily, _ suffix: String, activity: SessionActivityKind? = nil, ownership: LifecycleOwnership? = nil, attention: AttentionRequestKind? = nil, cursorIncluded: Bool = true) -> RawEventEnvelope {
            RawEventEnvelope(negotiationSnapshotID: snapshot.id, integrationInstanceID: installationID, contractVersion: snapshot.contractVersion, productNamespace: CodexCLIIntegration.productNamespace.rawValue, nativeSessionID: hook.nativeSessionID, eventIdentity: id(suffix), family: family, sourceVariant: "codex.hook." + hook.name.rawValue, activityKind: activity, classification: .operationalMetadata, payloadByteSize: hook.payload.count, occurrenceTime: hook.occurrenceTime, sourceCursor: cursorIncluded ? cursor : nil, ownership: ownership, attentionKind: attention, integrationMode: CodexCLIIntegration.integrationMode, capabilityID: CodexCLIIntegration.observationCapability, capabilityDirection: .observe, capabilityRevision: 1)
        }
        switch hook.name {
        case .sessionStart:
            return .success(.init(events: [event(.sessionDeclared, "declared"), event(.sessionActivity, "started", activity: .started, cursorIncluded: false)], protectedContent: content))
        case .userPromptSubmit:
            var events: [RawEventEnvelope] = []
            if let turn = hook.nativeTurnID { events.append(event(.turnDeclared, "turn", ownership: .init(nativeTurnID: turn))) }
            events.append(event(.sessionActivity, "working", activity: .working, ownership: hook.nativeTurnID.map { .init(nativeTurnID: $0) }, cursorIncluded: false))
            return .success(.init(events: events, protectedContent: content))
        case .preToolUse, .postToolUse, .preCompact, .postCompact, .activity:
            return .success(.init(events: [event(.sessionActivity, "activity", activity: .working, ownership: hook.nativeTurnID.map { .init(nativeTurnID: $0) })], protectedContent: content))
        case .permissionRequest:
            guard let request = hook.nativeTurnID, !request.isEmpty else { return .failure(.missingEventIdentity) }
            // A permission hook is a cue only. The native Host remains the sole response surface.
            return .success(.init(events: [event(.attentionRequest, "permission", ownership: .init(nativeTurnID: hook.nativeTurnID, nativeAttentionRequestID: request), attention: .opened)], permissionCue: .init(eventIdentity: hook.eventIdentity, sessionIdentity: identity, sourceObservedAt: hook.occurrenceTime), protectedContent: content))
        case .stop:
            guard let outcome = hook.terminalOutcome else { return .failure(.missingStopEvidence) }
            return .success(.init(events: [event(.sessionActivity, "stop", activity: outcome, ownership: hook.nativeTurnID.map { .init(nativeTurnID: $0) })], protectedContent: content))
        case .subagentStart:
            guard let child = hook.nativeChildID, let parent = hook.parentTurnID, !child.isEmpty, !parent.isEmpty else { return .failure(.invalidParentage) }
            return .success(.init(events: [event(.subagentRunDeclared, "child", ownership: .init(nativeTurnID: parent, nativeSubagentRunID: child)), event(.sessionActivity, "child-working", activity: .working, ownership: .init(nativeTurnID: parent, nativeSubagentRunID: child), cursorIncluded: false)], protectedContent: content))
        case .subagentStop:
            guard let child = hook.nativeChildID, let parent = hook.parentTurnID, !child.isEmpty, !parent.isEmpty, let outcome = hook.terminalOutcome else { return .failure(.unprovenChildStop) }
            return .success(.init(events: [event(.sessionActivity, "child-stop", activity: outcome, ownership: .init(nativeTurnID: parent, nativeSubagentRunID: child))], protectedContent: content))
        }
    }
}

private struct CodexEventOwnerKey: Hashable { let session: String; let event: String; let turn: String?; let child: String? }
private struct CodexChildOwnerKey: Hashable { let session: String; let parent: String; let child: String }

public actor CodexCLIAdapter {
    public let integrationInstanceID: IntegrationInstanceID
    public let helperID: String
    private let port: any AdapterIntakePort
    private let authenticator: ClaudeIPCAuthenticator
    private var snapshot: NegotiationSnapshot?
    private var enabled = false
    private var nonces: [String: Date] = [:]
    private var events: Set<CodexEventOwnerKey> = []
    private var children: Set<CodexChildOwnerKey> = []
    private var knownSessions: Set<AgentSessionIdentity> = []
    public init(port: any AdapterIntakePort, integrationInstanceID: IntegrationInstanceID, helperID: String, authenticator: ClaudeIPCAuthenticator) { self.port = port; self.integrationInstanceID = integrationInstanceID; self.helperID = helperID; self.authenticator = authenticator }
    public func setEnabledIntent(_ value: Bool) { enabled = value; if !value { children.removeAll() } }
    public func negotiate(version: CodexHooksVersionEvidence) async -> NegotiationOutcome {
        let available: CapabilityRecord.Availability = version.supported ? .available : .unavailable
        let records = [CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: available, fallback: .nativeHost), CapabilityRecord(id: CodexCLIIntegration.observationCapability, direction: .observe, availability: available, fallback: .nativeHost), CapabilityRecord(id: CodexCLIIntegration.permissionCueCapability, direction: .observe, availability: available, fallback: .nativeHost), CapabilityRecord(id: CodexCLIIntegration.configurationCapability, direction: .configure, availability: available, scope: .installation, fallback: .manualSetup)]
        let request = NegotiationRequest(integrationInstanceID: integrationInstanceID, adapterKind: CodexCLIIntegration.adapterKind, adapterBuildVersion: CodexCLIIntegration.adapterBuildVersion, productNamespace: CodexCLIIntegration.productNamespace, integrationMode: CodexCLIIntegration.integrationMode, offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0), requestedCapabilities: records.map(\.id), catalogRevision: CodexCLIIntegration.catalogRevision, productVersion: version.productVersion, interfaceVersion: version.interfaceVersion, probeEvidence: .init(compatibility: version.supported ? .compatible : .interfaceChanged, productVersion: version.productVersion, interfaceVersion: version.interfaceVersion, setup: version.documentedHooksAvailable ? .loaded : .unavailable, observedAt: version.observedAt), requestedCapabilityRecords: records, compatibility: version.supported ? .compatible : .interfaceChanged)
        let outcome = await port.negotiate(request)
        if case .compatible(let accepted) = outcome { snapshot = accepted; children.removeAll() }
        return outcome
    }
    public func ingest(_ message: ClaudeHookIPCMessage, at now: Date = Date()) async -> Result<CodexNormalizedObservation, CodexHookRejection> {
        guard enabled else { return .failure(.disabled) }
        guard message.payload.count <= SessionDomainValidator.maxPayloadBytes else { return .failure(.oversizedEnvelope) }
        guard message.installationID == integrationInstanceID else { return .failure(.crossOwner) }
        guard message.helperID == helperID else { return .failure(.untrustedHelper) }
        guard message.isAuthenticated(using: authenticator, expectedInstallationID: integrationInstanceID, expectedHelperID: helperID, receivedAt: now) else { return .failure(.unauthenticated) }
        guard nonces[message.nonce] == nil else { return .failure(.replayedNonce) }
        nonces[message.nonce] = now; nonces = nonces.filter { now.timeIntervalSince($0.value) <= 120 }
        guard let snapshot else { return .failure(.capabilityUnavailable) }
        let hook: CodexHookEnvelope
        do { hook = try .decode(message.payload) } catch let error as CodexHookRejection { return .failure(error) } catch { return .failure(.malformedEnvelope) }
        let key = CodexEventOwnerKey(session: hook.nativeSessionID, event: Self.eventID(hook.eventIdentity), turn: hook.nativeTurnID, child: hook.nativeChildID)
        guard !events.contains(key) else { return .failure(.duplicateEvent) }
        if hook.name == .subagentStop { guard let child = hook.nativeChildID, let parent = hook.parentTurnID, children.contains(.init(session: hook.nativeSessionID, parent: parent, child: child)) else { return .failure(.unprovenChildStop) } }
        let normalized = CodexHookNormalizer.normalize(hook, snapshot: snapshot, installationID: integrationInstanceID)
        guard case .success(let observation) = normalized else { return normalized }
        for envelope in observation.events { if case .rejected = await port.deliver(envelope) { return .failure(.malformedEnvelope) } }
        events.insert(key)
        if hook.name == .subagentStart, let child = hook.nativeChildID, let parent = hook.parentTurnID { children.insert(.init(session: hook.nativeSessionID, parent: parent, child: child)) }
        if hook.name == .subagentStop, let child = hook.nativeChildID, let parent = hook.parentTurnID { children.remove(.init(session: hook.nativeSessionID, parent: parent, child: child)) }
        knownSessions.insert(.init(productNamespace: CodexCLIIntegration.productNamespace, nativeSessionID: .init(hook.nativeSessionID)))
        return .success(observation)
    }
    /// Transport/helper loss is never completion evidence.
    public func reportHelperLoss() async { children.removeAll(); guard let snapshot else { return }; for identity in knownSessions { _ = await port.reportObservationBoundary(.init(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, identity: identity, reason: .transportLost)) } }
    private static func eventID(_ identity: EventIdentity) -> String { switch identity { case .stable(let value), .weak(let value): value } }
}

/// Read-only discovery and manifest-backed exact-entry installation. The
/// selected file is the sole configuration scope; CODEX_HOME is never scanned.
public final class CodexCLIInstallationCoordinator: @unchecked Sendable {
    private let coordinator = IntegrationInstallationCoordinator()
    public init() {}
    public func selector(helperPath: URL) -> ExactEntrySelector {
        let path: String = helperPath.path
        let digest: String = ExactEntryDigest.value(Data(path.utf8))
        let marker: String = "# agent-island-codex-hook \(digest)"
        let key: String = "codex-hooks-\(digest)"
        let rendered: String = "notify = [\"\(path)\"] \(marker)"
        return ExactEntrySelector(key: key, renderedLine: rendered, marker: marker)
    }
    public func discover(installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, manifest: OwnershipManifest? = nil, snapshot: NegotiationSnapshot? = nil, policy: ExactEntryWritePolicy = .allowed) -> IntegrationInstallationDiscovery { coordinator.discover(installationID: installationID, product: CodexCLIIntegration.productNamespace, integrationMode: CodexCLIIntegration.integrationMode, scope: scope, selector: selector(helperPath: helperPath), manifest: manifest, snapshot: snapshot, policy: policy) }
    public func makePlan(id: String, installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, snapshot: NegotiationSnapshot, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationPlan { coordinator.makePlan(id: id, installationID: installationID, product: CodexCLIIntegration.productNamespace, integrationMode: CodexCLIIntegration.integrationMode, scope: scope, selector: selector(helperPath: helperPath), snapshot: snapshot, policy: policy, now: now) }
    public func approve(_ plan: IntegrationInstallationPlan, personIdentifier: String, at date: Date = Date()) throws -> IntegrationInstallationApproval { try coordinator.approve(plan, personIdentifier: personIdentifier, at: date) }
    public func apply(_ approval: IntegrationInstallationApproval, currentSnapshot: NegotiationSnapshot, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationApplyResult { coordinator.apply(approval, currentSnapshot: currentSnapshot, policy: policy, now: now) }
    public func remove(_ approval: IntegrationInstallationApproval, manifest: OwnershipManifest, now: Date = Date()) -> OwnershipManifestRemovalReport { coordinator.remove(approval, manifest: manifest, now: now) }
}
