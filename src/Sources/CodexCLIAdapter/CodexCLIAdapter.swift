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
    public static let helperExecutablePath = "/Applications/Agent Island.app/Contents/MacOS/CodexHookHelper"
    public static let helperEndpointFileName = "codex-hooks.sock"

    /// This launcher carries only the installation/helper owner labels and an
    /// immutable observation-only mode. It has no secret, callback, or action
    /// endpoint; the dedicated helper refuses to start without this mode.
    public static func helperBootstrap(installationID: IntegrationInstanceID, helperID: String) -> Data {
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return Data("#!/bin/sh\nset -eu\nexport AGENT_ISLAND_INSTALLATION_ID=\(quote(installationID.rawValue))\nexport AGENT_ISLAND_HELPER_ID=\(quote(helperID))\nexport AGENT_ISLAND_CODEX_OBSERVATION_ONLY=1\nexec \"\(helperExecutablePath)\"\n".utf8)
    }
    public static func helperID(for helperPath: URL) -> String { "codex-helper-" + ExactEntryDigest.value(Data(helperPath.path.utf8)) }
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

/// The configuration grammar below is a reviewed adapter contract fixture,
/// not a claim that an arbitrary installed Codex version accepts it.  A live
/// Product probe must attest this exact interface version before any mutation.
public enum CodexHooksConfigurationContract {
    public static let reviewedInterfaceVersion = CodexCLIIntegration.interfaceVersion
    public static let schemaFixtureName = "configuration-contract.json"
    public static func accepts(_ snapshot: NegotiationSnapshot) -> Bool {
        snapshot.interfaceVersion == reviewedInterfaceVersion && snapshot.grants(CodexCLIIntegration.configurationCapability, direction: .configure)
    }
    /// A deliberately conservative, selected-file-only preflight.  Until a
    /// full reviewed TOML grammar is available, any existing event-qualified
    /// definition is ambiguous ownership rather than an entry to merge,
    /// rewrite, or silently shadow.
    public static func hasExistingEventDefinition(at path: URL) -> Bool {
        guard let data = ExactEntryEditor.snapshot(at: path).content, let text = String(data: data, encoding: .utf8) else { return false }
        let lines = text.split(whereSeparator: \ .isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return CodexHookName.allCases.contains { event in
            lines.contains { line in !line.hasPrefix("#") && line.hasPrefix("hooks.\(event.rawValue)") }
        }
    }
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
    case disabled, unauthenticated, untrustedHelper, oversizedEnvelope, malformedEnvelope, unsupportedHook, unsupportedVersion, missingNativeSessionIdentity, missingEventIdentity, missingSourceOrdering, crossOwner, duplicateEvent, replayedNonce, invalidParentage, unprovenChildStop, missingStopEvidence, capabilityUnavailable, transportUnavailable
}

/// A quarantine is an outcome, not an event ledger.  It deliberately retains
/// no raw payload, identifier, credential, prompt, or command.
public struct CodexHookQuarantine: Codable, Hashable, Sendable {
    public let reason: CodexHookRejection
    public let observedAt: Date
    public init(reason: CodexHookRejection, observedAt: Date) { self.reason = reason; self.observedAt = observedAt }
    public var redactedDiagnostic: String { "codex-hook-quarantined:\(reason.rawValue)" }
}

public enum CodexHookIntakeOutcome: Sendable {
    case delivered(CodexNormalizedObservation)
    case unresolved(CodexHookUnresolved)
    case quarantined(CodexHookQuarantine)
}

/// Valid authenticated evidence whose source sequence cannot yet support a
/// lifecycle projection. It intentionally is not a quarantine: one bounded,
/// non-exhaustive reconciliation fact is delivered and no event/nonce/child
/// state is consumed, so an exact later redelivery may prove continuity.
public struct CodexHookUnresolved: Codable, Hashable, Sendable {
    public enum Reason: String, Codable, Hashable, Sendable { case missingBaseline, sourceGap, reordered }
    public let reason: Reason
    public let observedAt: Date
    public init(reason: Reason, observedAt: Date) { self.reason = reason; self.observedAt = observedAt }
}

public enum CodexIntegrationHealthReason: String, Codable, Hashable, Sendable {
    case healthy, disabled, helperMissing, transportTimeout, duplicateDefinition, configurationDrift, unsupportedVersion, unsupportedInterface, orderingUnresolved, quarantinedInput
}

/// Health is intentionally separate from session lifecycle.  Its diagnostic
/// vocabulary is closed and therefore cannot leak Interaction Content.
public struct CodexIntegrationHealth: Codable, Hashable, Sendable {
    public let enabledIntent: Bool
    public let reason: CodexIntegrationHealthReason
    public let observedAt: Date
    public init(enabledIntent: Bool, reason: CodexIntegrationHealthReason, observedAt: Date = Date()) { self.enabledIntent = enabledIntent; self.reason = reason; self.observedAt = observedAt }
    public var redactedDiagnostic: String { "codex-hooks-health:\(reason.rawValue)" }
    public var manualRemedy: String {
        switch reason {
        case .healthy: return "No remedy required."
        case .disabled: return "Enable local observation intent; external configuration is unchanged."
        case .helperMissing, .transportTimeout: return "Restore the application-owned helper and re-probe; use the native Host meanwhile."
        case .duplicateDefinition, .configurationDrift: return "Review the selected configuration and remove or repair only the manifest-proven entry."
        case .unsupportedVersion, .unsupportedInterface: return "Update the reviewed adapter only after the documented Codex interface is verified."
        case .orderingUnresolved: return "Await documented source continuity or reconcile in the native Host; no lifecycle was inferred."
        case .quarantinedInput: return "Inspect the documented hook helper and owner configuration; no input was accepted."
        }
    }
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
    private let rawPayload: Data
    public let payloadByteSize: Int
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
        return Self(name: name, eventIdentity: .stable(event), nativeSessionID: session, nativeTurnID: text(["turn_id", "turnId"]), nativeChildID: text(["subagent_run_id", "child_id", "subagent_id"]), parentTurnID: text(["parent_turn_id", "parentTurnId"]), sourceSequence: sequence, occurrenceTime: occurrence, rawPayload: data, payloadByteSize: data.count, terminalOutcome: outcome)
    }

    /// Only an explicitly classified scalar can cross the protected-content
    /// boundary.  The envelope itself (including operational IDs) never can.
    fileprivate func classifiedContent() -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: rawPayload) as? [String: Any] else { return nil }
        let directKeys: [String] = switch name {
        case .userPromptSubmit: ["prompt", "user_prompt"]
        case .preToolUse, .postToolUse: ["command", "tool_input"]
        case .permissionRequest: ["permission_context"]
        case .preCompact, .postCompact: ["summary"]
        default: []
        }
        for key in directKeys {
            if let value = root[key] as? String, !value.isEmpty { return Data(value.utf8) }
            if key == "tool_input", let input = root[key] as? [String: Any], let command = input["command"] as? String, !command.isEmpty { return Data(command.utf8) }
        }
        return nil
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
        let content = contentConsent.localPresentationEnabled ? hook.classifiedContent().map { CodexProtectedObservationContent(bytes: $0, sessionIdentity: identity, nativeTurnID: hook.nativeTurnID) } : nil
        let cursor = hook.sourceSequence.map { SourceCursor(scope: "codex-session:\(hook.nativeSessionID)", value: $0) }
        func id(_ suffix: String) -> EventIdentity { switch hook.eventIdentity { case .stable(let value): .stable(value + ":" + suffix); case .weak(let value): .weak(value + ":" + suffix) } }
        func event(_ family: EventFamily, _ suffix: String, activity: SessionActivityKind? = nil, ownership: LifecycleOwnership? = nil, attention: AttentionRequestKind? = nil, cursorIncluded: Bool = true) -> RawEventEnvelope {
            RawEventEnvelope(negotiationSnapshotID: snapshot.id, integrationInstanceID: installationID, contractVersion: snapshot.contractVersion, productNamespace: CodexCLIIntegration.productNamespace.rawValue, nativeSessionID: hook.nativeSessionID, eventIdentity: id(suffix), family: family, sourceVariant: "codex.hook." + hook.name.rawValue, activityKind: activity, classification: .operationalMetadata, payloadByteSize: hook.payloadByteSize, occurrenceTime: hook.occurrenceTime, sourceCursor: cursorIncluded ? cursor : nil, ownership: ownership, attentionKind: attention, integrationMode: CodexCLIIntegration.integrationMode, capabilityID: CodexCLIIntegration.observationCapability, capabilityDirection: .observe, capabilityRevision: 1)
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
            guard hook.sourceSequence != nil else { return .failure(.missingSourceOrdering) }
            guard let outcome = hook.terminalOutcome else { return .failure(.missingStopEvidence) }
            return .success(.init(events: [event(.sessionActivity, "stop", activity: outcome, ownership: hook.nativeTurnID.map { .init(nativeTurnID: $0) })], protectedContent: content))
        case .subagentStart:
            guard let child = hook.nativeChildID, let parent = hook.parentTurnID, !child.isEmpty, !parent.isEmpty else { return .failure(.invalidParentage) }
            return .success(.init(events: [event(.subagentRunDeclared, "child", ownership: .init(nativeTurnID: parent, nativeSubagentRunID: child)), event(.sessionActivity, "child-working", activity: .working, ownership: .init(nativeTurnID: parent, nativeSubagentRunID: child), cursorIncluded: false)], protectedContent: content))
        case .subagentStop:
            guard hook.sourceSequence != nil, let child = hook.nativeChildID, let parent = hook.parentTurnID, !child.isEmpty, !parent.isEmpty, let outcome = hook.terminalOutcome else { return .failure(.unprovenChildStop) }
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
    private var lastSourceSequence: [String: Int64] = [:]
    private var children: Set<CodexChildOwnerKey> = []
    private var knownSessions: Set<AgentSessionIdentity> = []
    private var currentHealth = CodexIntegrationHealth(enabledIntent: false, reason: .disabled)
    public init(port: any AdapterIntakePort, integrationInstanceID: IntegrationInstanceID, helperID: String, authenticator: ClaudeIPCAuthenticator) { self.port = port; self.integrationInstanceID = integrationInstanceID; self.helperID = helperID; self.authenticator = authenticator }
    public func setEnabledIntent(_ value: Bool) { enabled = value; currentHealth = .init(enabledIntent: value, reason: value ? .healthy : .disabled); if !value { children.removeAll() } }
    public func health() -> CodexIntegrationHealth { currentHealth }
    public func reportConfiguration(reason: CodexIntegrationHealthReason, at date: Date = Date()) { currentHealth = .init(enabledIntent: enabled, reason: reason, observedAt: date) }
    public func negotiate(version: CodexHooksVersionEvidence) async -> NegotiationOutcome {
        let available: CapabilityRecord.Availability = version.supported ? .available : .unavailable
        let records = [CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: available, fallback: .nativeHost), CapabilityRecord(id: CodexCLIIntegration.observationCapability, direction: .observe, availability: available, fallback: .nativeHost), CapabilityRecord(id: CodexCLIIntegration.permissionCueCapability, direction: .observe, availability: available, fallback: .nativeHost), CapabilityRecord(id: CodexCLIIntegration.configurationCapability, direction: .configure, availability: available, scope: .installation, fallback: .manualSetup)]
        let request = NegotiationRequest(integrationInstanceID: integrationInstanceID, adapterKind: CodexCLIIntegration.adapterKind, adapterBuildVersion: CodexCLIIntegration.adapterBuildVersion, productNamespace: CodexCLIIntegration.productNamespace, integrationMode: CodexCLIIntegration.integrationMode, offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0), requestedCapabilities: records.map(\.id), catalogRevision: CodexCLIIntegration.catalogRevision, productVersion: version.productVersion, interfaceVersion: version.interfaceVersion, probeEvidence: .init(compatibility: version.supported ? .compatible : .interfaceChanged, productVersion: version.productVersion, interfaceVersion: version.interfaceVersion, setup: version.documentedHooksAvailable ? .loaded : .unavailable, observedAt: version.observedAt), requestedCapabilityRecords: records, compatibility: version.supported ? .compatible : .interfaceChanged)
        let outcome = await port.negotiate(request)
        if case .compatible(let accepted) = outcome { snapshot = accepted; children.removeAll(); currentHealth = .init(enabledIntent: enabled, reason: .healthy) }
        else { currentHealth = .init(enabledIntent: enabled, reason: version.supported ? .unsupportedInterface : .unsupportedVersion) }
        return outcome
    }
    /// All rejected input has exactly one redacted quarantine outcome and no
    /// delivery, nonce, duplicate, child, or session mutation.
    public func ingestOutcome(_ message: ClaudeHookIPCMessage, at now: Date = Date()) async -> CodexHookIntakeOutcome {
        func quarantine(_ reason: CodexHookRejection) -> CodexHookIntakeOutcome {
            currentHealth = .init(enabledIntent: enabled, reason: .quarantinedInput, observedAt: now)
            return .quarantined(.init(reason: reason, observedAt: now))
        }
        guard enabled else { return quarantine(.disabled) }
        guard message.payload.count <= SessionDomainValidator.maxPayloadBytes else { return quarantine(.oversizedEnvelope) }
        guard message.installationID == integrationInstanceID else { return quarantine(.crossOwner) }
        guard message.helperID == helperID else { return quarantine(.untrustedHelper) }
        guard message.isAuthenticated(using: authenticator, expectedInstallationID: integrationInstanceID, expectedHelperID: helperID, receivedAt: now) else { return quarantine(.unauthenticated) }
        guard nonces[message.nonce] == nil else { return quarantine(.replayedNonce) }
        guard let snapshot else { return quarantine(.capabilityUnavailable) }
        let hook: CodexHookEnvelope
        do { hook = try .decode(message.payload) } catch let error as CodexHookRejection { return quarantine(error) } catch { return quarantine(.malformedEnvelope) }
        let key = CodexEventOwnerKey(session: hook.nativeSessionID, event: Self.eventID(hook.eventIdentity), turn: hook.nativeTurnID, child: hook.nativeChildID)
        guard !events.contains(key) else { return quarantine(.duplicateEvent) }
        let normalized = CodexHookNormalizer.normalize(hook, snapshot: snapshot, installationID: integrationInstanceID)
        guard case .success(let observation) = normalized else { if case .failure(let reason) = normalized { return quarantine(reason) }; return quarantine(.malformedEnvelope) }
        guard let sequence = hook.sourceSequence else { return quarantine(.missingSourceOrdering) }
        let sequenceScope = "codex-session:\(hook.nativeSessionID)"
        let ordering: CodexHookUnresolved.Reason?
        if let previous = lastSourceSequence[sequenceScope] {
            ordering = sequence == previous + 1 ? nil : (sequence > previous ? .sourceGap : .reordered)
        } else {
            // Source sequence 1 on SessionStart is the only documented local
            // baseline. Receipt order, a terminal Stop, and child evidence can
            // never establish a session's omitted source history.
            ordering = hook.name == .sessionStart && sequence == 1 ? nil : .missingBaseline
        }
        if let ordering {
            let gap = RawEventEnvelope(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, contractVersion: snapshot.contractVersion, productNamespace: CodexCLIIntegration.productNamespace.rawValue, nativeSessionID: hook.nativeSessionID, eventIdentity: .stable("\(Self.eventID(hook.eventIdentity)):ordering-\(ordering.rawValue)"), family: .reconciliation, sourceVariant: "codex.hook.ordering-\(ordering.rawValue)", classification: .operationalMetadata, payloadByteSize: 0, reconciliationScope: .nonExhaustive, integrationMode: CodexCLIIntegration.integrationMode, capabilityID: CodexCLIIntegration.observationCapability, capabilityDirection: .observe, capabilityRevision: 1)
            _ = await port.deliver(gap)
            currentHealth = .init(enabledIntent: enabled, reason: .orderingUnresolved, observedAt: now)
            return .unresolved(.init(reason: ordering, observedAt: now))
        }
        if hook.name == .subagentStop { guard let child = hook.nativeChildID, let parent = hook.parentTurnID, children.contains(.init(session: hook.nativeSessionID, parent: parent, child: child)) else { return quarantine(.unprovenChildStop) } }
        for envelope in observation.events { if case .rejected = await port.deliver(envelope) { return quarantine(.malformedEnvelope) } }
        nonces[message.nonce] = now; nonces = nonces.filter { now.timeIntervalSince($0.value) <= 120 }
        events.insert(key)
        lastSourceSequence[sequenceScope] = sequence
        if hook.name == .subagentStart, let child = hook.nativeChildID, let parent = hook.parentTurnID { children.insert(.init(session: hook.nativeSessionID, parent: parent, child: child)) }
        if hook.name == .subagentStop, let child = hook.nativeChildID, let parent = hook.parentTurnID { children.remove(.init(session: hook.nativeSessionID, parent: parent, child: child)) }
        knownSessions.insert(.init(productNamespace: CodexCLIIntegration.productNamespace, nativeSessionID: .init(hook.nativeSessionID)))
        currentHealth = .init(enabledIntent: enabled, reason: .healthy, observedAt: now)
        return .delivered(observation)
    }
    public func ingest(_ message: ClaudeHookIPCMessage, at now: Date = Date()) async -> Result<CodexNormalizedObservation, CodexHookRejection> {
        switch await ingestOutcome(message, at: now) { case .delivered(let observation): return .success(observation); case .unresolved: return .failure(.missingSourceOrdering); case .quarantined(let artifact): return .failure(artifact.reason) }
    }
    /// Transport/helper loss is never completion evidence.
    public func reportHelperLoss() async { currentHealth = .init(enabledIntent: enabled, reason: .helperMissing); children.removeAll(); guard let snapshot else { return }; for identity in knownSessions { _ = await port.reportObservationBoundary(.init(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, identity: identity, reason: .transportLost)) } }
    public func reportTimeout() { currentHealth = .init(enabledIntent: enabled, reason: .transportTimeout) }
    private static func eventID(_ identity: EventIdentity) -> String { switch identity { case .stable(let value), .weak(let value): value } }
}

/// Read-only discovery and manifest-backed exact-entry installation.  The
/// selected TOML file is the sole configuration scope; this deliberately does
/// not inspect CODEX_HOME, rollouts, session files, SQLite, or scrollback.
///
/// `notify` is a generic end-of-turn notification setting, not the documented
/// lifecycle hook contract, and is therefore never installed here.
public final class CodexCLIInstallationCoordinator: @unchecked Sendable {
    private let coordinator = IntegrationInstallationCoordinator()
    private let runtimeContract: any CodexHookRuntimeContract
    public init(runtimeContract: any CodexHookRuntimeContract = CodexUnprovenHookRuntimeContract()) { self.runtimeContract = runtimeContract }
    public func selector(event: CodexHookName = .sessionStart, helperPath: URL) -> ExactEntrySelector {
        let path: String = helperPath.path
        let digest: String = ExactEntryDigest.value(Data((path + event.rawValue).utf8))
        let marker: String = "# agent-island-codex-hook \(event.rawValue) \(digest)"
        let key: String = "codex-hooks-\(event.rawValue)-\(digest)"
        // This reviewed-contract fixture is event-qualified and intentionally
        // distinct from Codex's generic notification command.  It is written
        // only after the exact contract/version probe above succeeds.
        let rendered: String = "hooks.\(event.rawValue) = [\"\(path)\"] \(marker)"
        return ExactEntrySelector(key: key, renderedLine: rendered, marker: marker)
    }
    public func selectors(helperPath: URL) -> [ExactEntrySelector] { CodexHookName.allCases.map { selector(event: $0, helperPath: helperPath) } }
    public func discover(installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, manifest: OwnershipManifest? = nil, snapshot: NegotiationSnapshot? = nil, policy: ExactEntryWritePolicy = .allowed) -> IntegrationInstallationDiscovery {
        let entries = selectors(helperPath: helperPath)
        let found = entries.map { ExactEntryEditor.inspect(at: scope.url, selector: $0, receipt: manifest?.proving($0, at: scope.path)) }
        let source = found.first?.source ?? ExactEntryEditor.snapshot(at: scope.url)
        let compatibility: IntegrationInstallationCompatibility = (snapshot.map(CodexHooksConfigurationContract.accepts) ?? false) && isTOMLSafeHelperPath(helperPath) && runtimeContract.isProven(installationID: installationID, helperID: CodexCLIIntegration.helperID(for: helperPath)) ? .compatible : .interfaceChanged
        let markerCount = found.reduce(0) { $0 + $1.matchingEntryCount }
        let state: ExactEntryInspectionState
        let reason: ExactEntryFailureReason?
        if compatibility != .compatible { state = .unsupported; reason = .unsupported }
        else if found.contains(where: { $0.source.symlinkTarget != nil || $0.state == .unsupported || $0.state == .unavailable }) { state = .unsupported; reason = source.symlinkTarget == nil ? .unsupported : .symlinkChanged }
        else if found.contains(where: { $0.state == .shadowedManaged }) { state = .shadowedManaged; reason = .ambiguous }
        else if markerCount == 0 && !CodexHooksConfigurationContract.hasExistingEventDefinition(at: scope.url) { state = .notConfigured; reason = nil }
        else if let manifest, found.indices.allSatisfy({ found[$0].state == .ownedIntact && manifest.proving(entries[$0], at: scope.path) != nil }) { state = .ownedIntact; reason = nil }
        else { state = .externalCandidate; reason = .ambiguous }
        let inspection = ExactEntryInspection(state: state, source: source, matchingEntryCount: markerCount, reason: reason)
        return .init(installationID: installationID, product: CodexCLIIntegration.productNamespace, integrationMode: CodexCLIIntegration.integrationMode, scope: scope, state: IntegrationInstallationDiscoveryState(rawValue: state.rawValue) ?? .unsupported, inspection: inspection, compatibility: compatibility, affectedCapabilities: [CodexCLIIntegration.configurationCapability], safeToMutate: state == .notConfigured && compatibility == .compatible && policy.allowsMutation)
    }
    public func makePlan(id: String, installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, snapshot: NegotiationSnapshot, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationPlan {
        let helperID = CodexCLIIntegration.helperID(for: helperPath)
        let bootstrap = CodexCLIIntegration.helperBootstrap(installationID: installationID, helperID: helperID)
        let artifact = OwnershipManifestArtifactReceipt(path: helperPath.path, kind: .generatedFile, fingerprint: ExactEntryFingerprint(ExactEntryDigest.value(bootstrap)), createdAt: now)
        let plan = coordinator.makePlan(id: id, installationID: installationID, product: CodexCLIIntegration.productNamespace, integrationMode: CodexCLIIntegration.integrationMode, scope: scope, selectors: selectors(helperPath: helperPath), snapshot: snapshot, policy: policy, now: now)
        guard CodexHooksConfigurationContract.accepts(snapshot), isTOMLSafeHelperPath(helperPath), runtimeContract.isProven(installationID: installationID, helperID: helperID) else { return copied(plan, artifacts: [artifact], entries: isTOMLSafeHelperPath(helperPath) ? plan.entries : [], compatibility: .interfaceChanged, manualRemedy: "Verify the reviewed hooks-v1 fixture, TOML-safe helper path, and provisioned Codex observation helper contract manually; no configuration was applied.") }
        let preflight = plan.entries.map { ExactEntryEditor.inspect(at: scope.url, selector: $0) }
        guard preflight.allSatisfy({ $0.matchingEntryCount == 0 }) && !CodexHooksConfigurationContract.hasExistingEventDefinition(at: scope.url) else {
            return copied(plan, artifacts: [artifact], compatibility: .incompatible, manualRemedy: "Duplicate or externally owned Codex Hook entries require manual review; no configuration was applied.")
        }
        return copied(plan, artifacts: [artifact])
    }
    public func approve(_ plan: IntegrationInstallationPlan, personIdentifier: String, at date: Date = Date()) throws -> IntegrationInstallationApproval { try coordinator.approve(plan, personIdentifier: personIdentifier, at: date) }
    public func apply(_ approval: IntegrationInstallationApproval, currentSnapshot: NegotiationSnapshot, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationApplyResult {
        let plan = approval.plan
        guard plan.artifacts.count == 1, let artifact = plan.artifacts.first,
              runtimeContract.isProven(installationID: plan.installationID, helperID: CodexCLIIntegration.helperID(for: URL(fileURLWithPath: artifact.path))) else { return .init(status: .blocked, reason: .notManifestProven) }
        let helperPath = URL(fileURLWithPath: artifact.path)
        let bootstrap = CodexCLIIntegration.helperBootstrap(installationID: plan.installationID, helperID: CodexCLIIntegration.helperID(for: helperPath))
        let before = ExactEntryEditor.snapshot(at: helperPath)
        guard before.symlinkTarget == nil else { return .init(status: .blocked, reason: .symlinkChanged) }
        let existed = FileManager.default.fileExists(atPath: helperPath.path)
        if existed { guard before.fingerprint.content == artifact.fingerprint, before.fingerprint.permissionBits == 0o700 else { return .init(status: .blocked, reason: .sourceChanged) } }
        else { do { try writePrivateHelper(bootstrap, to: helperPath) } catch { return .init(status: .unavailable, reason: .unavailable) } }
        let result = coordinator.apply(approval, currentSnapshot: currentSnapshot, policy: policy, probe: { ExactEntryEditor.snapshot(at: helperPath).symlinkTarget == nil && ExactEntryEditor.snapshot(at: helperPath).fingerprint.content == artifact.fingerprint && ExactEntryEditor.snapshot(at: helperPath).fingerprint.permissionBits == 0o700 }, now: now)
        if result.manifest == nil && !existed { try? FileManager.default.removeItem(at: helperPath) }
        return result
    }
    public func makeRemovalPlan(id: String, installationID: IntegrationInstanceID, manifest: OwnershipManifest, snapshot: NegotiationSnapshot, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationPlan { coordinator.makeRemovalPlan(id: id, installationID: installationID, manifest: manifest, snapshot: snapshot, policy: policy, now: now) }
    public func remove(_ approval: IntegrationInstallationApproval, manifest: OwnershipManifest, now: Date = Date()) -> OwnershipManifestRemovalReport {
        // The shared coordinator removes artifacts even when a source entry
        // drifted. Keep the private launcher until every manifest-proven hook
        // was removed, exactly as the Claude lifecycle does.
        let plan = approval.plan
        guard plan.action == .remove, plan.isFresh(at: now), plan.compatibility == .compatible, plan.sourcePath == manifest.sourcePath else { return .init(outcome: .notRemoved, reason: .sourceChanged, manifest: manifest) }
        var expected = plan.sourceFingerprint; var removed: [ExactEntrySelector] = []; var residual: [ExactEntrySelector] = []
        for receipt in manifest.entries { do { _ = try ExactEntryEditor.remove(receipt: receipt, at: URL(fileURLWithPath: receipt.path), expected: expected, now: now); removed.append(receipt.selector); expected = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: receipt.path)).fingerprint } catch { residual.append(receipt.selector) } }
        var removedArtifacts: [String] = []; var notRemovedArtifacts: [String] = []
        if residual.isEmpty { for artifact in manifest.artifacts { let current = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: artifact.path)); guard current.symlinkTarget == nil, current.fingerprint.content == artifact.fingerprint else { notRemovedArtifacts.append(artifact.path); continue }; do { try FileManager.default.removeItem(atPath: artifact.path); removedArtifacts.append(artifact.path) } catch { notRemovedArtifacts.append(artifact.path) } } } else { notRemovedArtifacts = manifest.artifacts.map(\.path) }
        let complete = residual.isEmpty && notRemovedArtifacts.isEmpty
        return .init(outcome: complete ? .removed : ((removed.isEmpty && removedArtifacts.isEmpty) ? .notRemoved : .partialWithResidual), removedEntries: removed, residualEntries: residual, removedArtifacts: removedArtifacts, notRemovedArtifacts: notRemovedArtifacts, reason: complete ? nil : .sourceChanged, manifest: manifest.replacing(lifecycle: complete ? .removed : .partial, at: now))
    }

    private func isTOMLSafeHelperPath(_ path: URL) -> Bool { !path.path.unicodeScalars.contains { $0.value < 0x20 || $0 == "\"" || $0 == "\\" } }
    private func writePrivateHelper(_ bootstrap: Data, to path: URL) throws { let fm = FileManager.default; guard fm.fileExists(atPath: path.deletingLastPathComponent().path), ExactEntryEditor.snapshot(at: path).symlinkTarget == nil else { throw ExactEntryEditorError.unavailable }; try bootstrap.write(to: path, options: .atomic); try fm.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: path.path); let snapshot = ExactEntryEditor.snapshot(at: path); guard snapshot.symlinkTarget == nil, snapshot.fingerprint.content == ExactEntryFingerprint(ExactEntryDigest.value(bootstrap)), snapshot.fingerprint.permissionBits == 0o700 else { throw ExactEntryEditorError.verificationFailed } }
    private func copied(_ plan: IntegrationInstallationPlan, artifacts: [OwnershipManifestArtifactReceipt], entries: [ExactEntrySelector]? = nil, compatibility: IntegrationInstallationCompatibility? = nil, manualRemedy: String? = nil) -> IntegrationInstallationPlan { .init(id: plan.id, installationID: plan.installationID, action: plan.action, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, sourcePath: plan.sourcePath, entries: entries ?? plan.entries, artifacts: artifacts, compatibility: compatibility ?? plan.compatibility, productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion, policyFingerprint: plan.policyFingerprint, sourceFingerprint: plan.sourceFingerprint, permissionSummary: plan.permissionSummary, affectedCapabilities: plan.affectedCapabilities, capabilityEvidence: plan.capabilityEvidence, rollback: plan.rollback, manualRemedy: manualRemedy ?? plan.manualRemedy, nonEffects: plan.nonEffects, createdAt: plan.createdAt, expiresAt: plan.expiresAt, manifestID: plan.manifestID) }
}

/// Installation can mutate only after the application composition proves that
/// its Codex-only receiver and owner-scoped credential are live. The adapter
/// cannot create or inspect those privileged resources by itself.
public protocol CodexHookRuntimeContract: Sendable { func isProven(installationID: IntegrationInstanceID, helperID: String) -> Bool }
public struct CodexUnprovenHookRuntimeContract: CodexHookRuntimeContract {
    public init() {}
    public func isProven(installationID: IntegrationInstanceID, helperID: String) -> Bool { false }
}
public struct CodexFixtureHookRuntimeContract: CodexHookRuntimeContract { public let proven: Bool; public init(proven: Bool = true) { self.proven = proven }; public func isProven(installationID: IntegrationInstanceID, helperID: String) -> Bool { proven } }

/// Production composition may use this verifier after it has provisioned the
/// owner-scoped Keychain credential and its private Codex observation socket.
/// A missing executable, credential, socket, owner, permission, or symlink is
/// deliberately indistinguishable from an unproven contract to the installer.
public struct CodexProvisionedHookRuntimeContract: CodexHookRuntimeContract, Sendable {
    private let credentialStore: any ClaudeHookCredentialStore
    private let endpoint: ClaudeLocalEndpoint
    private let executablePath: String
    public init(credentialStore: any ClaudeHookCredentialStore, endpoint: ClaudeLocalEndpoint, executablePath: String = CodexCLIIntegration.helperExecutablePath) { self.credentialStore = credentialStore; self.endpoint = endpoint; self.executablePath = executablePath }
    public func isProven(installationID: IntegrationInstanceID, helperID: String) -> Bool {
        guard let secret = credentialStore.secret(for: installationID, helperID: helperID), !secret.isEmpty,
              case .success = endpoint.validate() else { return false }
        let source = ExactEntryEditor.snapshot(at: executablePath)
        guard source.exists, source.symlinkTarget == nil,
              let permissions = source.fingerprint.permissionBits,
              (permissions & 0o111) != 0 else { return false }
        return true
    }
}
