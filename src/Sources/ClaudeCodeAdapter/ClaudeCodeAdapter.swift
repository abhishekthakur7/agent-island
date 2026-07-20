import Foundation
import CryptoKit
import SessionDomain
import AdapterPort

/// Claude Code's documented Hooks observation mode.  The namespace and mode
/// are stable local identity/provenance values; neither is a transcript or a
/// process identity.
public enum ClaudeCodeIntegration {
    public static let productNamespace = ProductNamespace("claude-code")
    public static let integrationMode = "claudeCode.documentedHooksObservation"
    public static let adapterKind = "claude-code.documented-hooks"
    public static let adapterBuildVersion = "1.0.0"
    public static let interfaceVersion = "hooks-v1"
    public static let catalogRevision = "claude-hooks.catalog.v1"
    public static let helperVersion = "1.0.0"

    public static let observationCapability = "claude.hooks.sessionObservation"
    public static let attentionCapability = "claude.hooks.attentionObservation"
    public static let questionCapability = "claude.hooks.questionObservation"
    public static let planCapability = "claude.hooks.planObservation"
    public static let subagentCapability = "claude.hooks.subagentObservation"
    public static let configurationCapability = WellKnownCapability.configuration

    public static let allObservationCapabilities = [
        observationCapability,
        attentionCapability,
        questionCapability,
        planCapability,
        subagentCapability
    ]

    /// A functional, non-secret launcher. The application-owned executable
    /// performs bounded stdin intake and authenticated local IPC; this file
    /// contains no installation secret, native command, or hook payload.
    /// This is deliberately an absolute, application-owned executable. A hook
    /// runs in a Product-controlled environment, so an environment override
    /// would turn configuration ownership into command authority.
    public static let helperExecutablePath = "/Applications/Agent Island.app/Contents/MacOS/ClaudeHookHelper"
    public static let helperBootstrap = Data("#!/bin/sh\nset -eu\nexec \"/Applications/Agent Island.app/Contents/MacOS/ClaudeHookHelper\"\n".utf8)

    /// The launcher carries only non-secret owner labels. The helper resolves
    /// its credential from the app-owned Keychain service at runtime.
    public static func helperBootstrap(installationID: IntegrationInstanceID, helperID: String) -> Data {
        let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return Data("#!/bin/sh\nset -eu\nexport AGENT_ISLAND_INSTALLATION_ID=\(quote(installationID.rawValue))\nexport AGENT_ISLAND_HELPER_ID=\(quote(helperID))\nexec \"\(helperExecutablePath)\"\n".utf8)
    }

    public static func helperID(for helperPath: URL) -> String { "helper-" + ExactEntryDigest.value(Data(helperPath.path.utf8)) }
}

public struct ClaudeCodeVersion: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let rawValue: String

    public init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count >= 2, pieces.count <= 3,
              let major = Int(pieces[0]), let minor = Int(pieces[1]),
              pieces.dropFirst(2).allSatisfy({ Int($0) != nil }),
              major >= 0, minor >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = pieces.count == 3 ? Int(pieces[2])! : 0
        self.rawValue = trimmed
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public enum ClaudeVersionSupport: String, Codable, Hashable, Sendable {
    case known
    case unknown
    case newerThanReviewed
    case unsupported
}

/// Compatibility is intentionally explicit. A caller may provide a reviewed
/// set from a fresh executable probe; no Product version is trusted merely
/// because its namespace says Claude.
public struct ClaudeHooksVersionEvidence: Codable, Hashable, Sendable {
    public let productVersion: String
    public let interfaceVersion: String
    public let executablePath: String?
    public let support: ClaudeVersionSupport
    public let observedAt: Date

    public init(
        productVersion: String,
        interfaceVersion: String = ClaudeCodeIntegration.interfaceVersion,
        executablePath: String? = nil,
        support: ClaudeVersionSupport? = nil,
        observedAt: Date = Date()
    ) {
        self.productVersion = productVersion
        self.interfaceVersion = interfaceVersion
        self.executablePath = executablePath
        self.support = support ?? ClaudeHooksVersionEvidence.evaluate(productVersion: productVersion, interfaceVersion: interfaceVersion)
        self.observedAt = observedAt
    }

    public static func evaluate(productVersion: String, interfaceVersion: String) -> ClaudeVersionSupport {
        guard let version = ClaudeCodeVersion(productVersion) else { return .unknown }
        guard interfaceVersion == ClaudeCodeIntegration.interfaceVersion else { return .unsupported }
        // The documented Hooks v1 contract has been reviewed through 1.x. A
        // later major is new Product evidence and must not be guessed at.
        if version.major > 1 { return .newerThanReviewed }
        if version.major < 1 { return .unsupported }
        return .known
    }

    public var isObservationCompatible: Bool { support == .known && interfaceVersion == ClaudeCodeIntegration.interfaceVersion }
}

public enum ClaudeHookName: String, Codable, Hashable, Sendable, CaseIterable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case permissionDenied = "PermissionDenied"
    case askUserQuestion = "AskUserQuestion"
    case exitPlanMode = "ExitPlanMode"
    case sessionEnd = "SessionEnd"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case configChange = "ConfigChange"
    case wakeup = "Wakeup"
    case backgroundTask = "BackgroundTask"

    public init?(documentedName: String) {
        let normalized = documentedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = Self(rawValue: normalized) { self = exact; return }
        // A few Claude releases used lower camel-case in fixtures while the
        // documented names remained title-cased. Accept only this closed set.
        guard let match = Self.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(normalized) == .orderedSame }) else { return nil }
        self = match
    }
}

public enum ClaudeHookRejection: String, Codable, Hashable, Sendable, Error {
    case disabled
    case unauthenticated
    case untrustedHelper
    case oversizedEnvelope
    case malformedEnvelope
    case unsupportedHook
    case unknownVersion
    case unsupportedVersion
    case newerVersion
    case missingNativeSessionIdentity
    case crossOwner
    case duplicateEvent
    case replayedNonce
    case missingEventIdentity
    case invalidParentage
    case unprovenChildStop
    case missingStopEvidence
    case unsupportedResponseSemantics
    case capabilityUnavailable
    case transportUnavailable
    case policyBlocked
}

public enum ClaudeHookConfigurationStatus: String, Codable, Hashable, Sendable {
    case safe
    case bare
    case disabled
    case invalidSettings
    case managedPolicy
    case shadowed
    case drifted
    case missing
    case unknown
}

/// No-action helper/configuration probe evidence. It contains only enum and
/// boolean health facts; it never reads transcripts or adopts external setup.
public struct ClaudeHookReconciliationEvidence: Codable, Hashable, Sendable {
    public let status: ClaudeHookConfigurationStatus
    public let workspaceTrusted: Bool?
    public let helperReachable: Bool
    public let observedAt: Date

    public init(status: ClaudeHookConfigurationStatus, workspaceTrusted: Bool? = nil, helperReachable: Bool, observedAt: Date = Date()) {
        self.status = status
        self.workspaceTrusted = workspaceTrusted
        self.helperReachable = helperReachable
        self.observedAt = observedAt
    }
}

public enum ClaudeNotificationCueKind: String, Codable, Hashable, Sendable {
    case notification
    case permissionContext
    case questionContext
    case planContext
}

/// A reveal cue never contains an Action Lease or a typed Product action.
public struct ClaudeNotificationCue: Codable, Hashable, Sendable {
    public let kind: ClaudeNotificationCueKind
    public let eventIdentity: EventIdentity
    public let sessionIdentity: AgentSessionIdentity
    public let sourceObservedAt: Date?

    public init(kind: ClaudeNotificationCueKind, eventIdentity: EventIdentity, sessionIdentity: AgentSessionIdentity, sourceObservedAt: Date?) {
        self.kind = kind
        self.eventIdentity = eventIdentity
        self.sessionIdentity = sessionIdentity
        self.sourceObservedAt = sourceObservedAt
    }
}

public struct ClaudeProtectedObservationContent: Codable, Hashable, Sendable {
    public let contentID: String
    public let bytes: Data
    public let classification: PayloadClassification
    public let sessionIdentity: AgentSessionIdentity
    public let nativeTurnID: String?
    public let nativeAttentionRequestID: String?

    public init(contentID: String, bytes: Data, sessionIdentity: AgentSessionIdentity, nativeTurnID: String? = nil, nativeAttentionRequestID: String? = nil) {
        self.contentID = contentID
        self.bytes = bytes
        self.classification = .interactionContent
        self.sessionIdentity = sessionIdentity
        self.nativeTurnID = nativeTurnID
        self.nativeAttentionRequestID = nativeAttentionRequestID
    }

    public var sessionHistoryContent: SessionHistoryContent {
        SessionHistoryContent(contentID: contentID, bytes: bytes, nativeTurnID: nativeTurnID, nativeAttentionRequestID: nativeAttentionRequestID)
    }
}

public struct ClaudePlanObservation: Codable, Hashable, Sendable {
    public let eventIdentity: EventIdentity
    public let sessionIdentity: AgentSessionIdentity
    public let nativeTurnID: String?
    public let markdown: ClaudeProtectedObservationContent
    public let semanticShape: GuidedSemanticShape

    public init(eventIdentity: EventIdentity, sessionIdentity: AgentSessionIdentity, nativeTurnID: String?, markdown: ClaudeProtectedObservationContent) {
        self.eventIdentity = eventIdentity
        self.sessionIdentity = sessionIdentity
        self.nativeTurnID = nativeTurnID
        self.markdown = markdown
        self.semanticShape = GuidedSemanticShape(kind: .planReview)
    }
}

public struct ClaudeQuestionObservation: Codable, Hashable, Sendable {
    public let eventIdentity: EventIdentity
    public let sessionIdentity: AgentSessionIdentity
    public let nativeAttentionRequestID: String
    public let content: ClaudeProtectedObservationContent
    public let semanticShape: GuidedSemanticShape

    public init(eventIdentity: EventIdentity, sessionIdentity: AgentSessionIdentity, nativeAttentionRequestID: String, content: ClaudeProtectedObservationContent, semanticShape: GuidedSemanticShape) {
        self.eventIdentity = eventIdentity
        self.sessionIdentity = sessionIdentity
        self.nativeAttentionRequestID = nativeAttentionRequestID
        self.content = content
        self.semanticShape = semanticShape
    }
}

/// Product-attributed context retained for correlation only. These values are
/// never merge keys, lifecycle evidence, or diagnostic text. Transcript paths
/// are deliberately discarded: this adapter neither reads nor displays them.
public struct ClaudeAttributedContext: Codable, Hashable, Sendable {
    public let model: String?
    public let workingDirectory: String?
    public let promptID: String?

    public init(model: String? = nil, workingDirectory: String? = nil, promptID: String? = nil) {
        self.model = model
        self.workingDirectory = workingDirectory
        self.promptID = promptID
    }
}

public struct ClaudeNormalizedObservation: Sendable {
    public let events: [RawEventEnvelope]
    public let cue: ClaudeNotificationCue?
    public let question: ClaudeQuestionObservation?
    public let plan: ClaudePlanObservation?
    public let protectedContent: ClaudeProtectedObservationContent?
    public let sourceName: ClaudeHookName
    public let attributedContext: ClaudeAttributedContext

    public init(events: [RawEventEnvelope], cue: ClaudeNotificationCue? = nil, question: ClaudeQuestionObservation? = nil, plan: ClaudePlanObservation? = nil, protectedContent: ClaudeProtectedObservationContent? = nil, sourceName: ClaudeHookName, attributedContext: ClaudeAttributedContext = ClaudeAttributedContext()) {
        self.events = events
        self.cue = cue
        self.question = question
        self.plan = plan
        self.protectedContent = protectedContent
        self.sourceName = sourceName
        self.attributedContext = attributedContext
    }
}

public struct ClaudeHookIntakeReport: Sendable {
    public let accepted: Bool
    public let duplicate: Bool
    public let events: [RawEventEnvelope]
    public let observation: ClaudeNormalizedObservation?
    public let rejection: ClaudeHookRejection?
    public let protectedContent: ClaudeProtectedObservationContent?
    public let cue: ClaudeNotificationCue?
    public let question: ClaudeQuestionObservation?
    public let plan: ClaudePlanObservation?

    public init(accepted: Bool, duplicate: Bool = false, events: [RawEventEnvelope] = [], observation: ClaudeNormalizedObservation? = nil, rejection: ClaudeHookRejection? = nil, protectedContent: ClaudeProtectedObservationContent? = nil, cue: ClaudeNotificationCue? = nil, question: ClaudeQuestionObservation? = nil, plan: ClaudePlanObservation? = nil) {
        self.accepted = accepted
        self.duplicate = duplicate
        self.events = events
        self.observation = observation
        self.rejection = rejection
        self.protectedContent = protectedContent
        self.cue = cue
        self.question = question
        self.plan = plan
    }
}

public struct ClaudeIntegrationHealth: Codable, Hashable, Sendable {
    public let enabledIntent: Bool
    public let observedHealth: IntegrationHealthVector
    public let observationCapability: CapabilityRecord.Availability
    public let questionCapability: CapabilityRecord.Availability
    public let planCapability: CapabilityRecord.Availability
    public let configurationState: IntegrationInstallationDiscoveryState?
    public let configurationProbeStatus: ClaudeHookConfigurationStatus
    public let helperReachability: HealthDimensionStatus
    public let lastReason: ClaudeHookRejection?
    public let observedAt: Date

    public init(enabledIntent: Bool = false, observedHealth: IntegrationHealthVector = IntegrationHealthVector(), observationCapability: CapabilityRecord.Availability = .unknown, questionCapability: CapabilityRecord.Availability = .unknown, planCapability: CapabilityRecord.Availability = .unknown, helperReachability: HealthDimensionStatus = .unknown, lastReason: ClaudeHookRejection? = nil, configurationState: IntegrationInstallationDiscoveryState? = nil, configurationProbeStatus: ClaudeHookConfigurationStatus = .unknown, observedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.enabledIntent = enabledIntent
        self.observedHealth = observedHealth
        self.observationCapability = observationCapability
        self.questionCapability = questionCapability
        self.planCapability = planCapability
        self.configurationState = configurationState
        self.configurationProbeStatus = configurationProbeStatus
        self.helperReachability = helperReachability
        self.lastReason = lastReason
        self.observedAt = observedAt
    }

    public var summary: IntegrationHealthSummary { observedHealth.summary }

    /// Closed, redacted evidence suitable for a Diagnostic Bundle. It carries
    /// no Product/native identifiers, paths, commands, payloads, prompts, or
    /// credentials.
    public var redactedDiagnostic: DiagnosticEvidence {
        let reason: DiagnosticReason = switch lastReason {
        case .unauthenticated, .untrustedHelper: .permissionDenied
        case .crossOwner: .ownerAmbiguous
        case .oversizedEnvelope: .payloadTooLarge
        case .malformedEnvelope, .unsupportedHook, .missingNativeSessionIdentity, .missingEventIdentity, .invalidParentage, .unprovenChildStop, .missingStopEvidence, .unsupportedResponseSemantics: .malformedInput
        case .duplicateEvent, .replayedNonce: .duplicateDelivery
        case .unknownVersion, .unsupportedVersion, .newerVersion: .staleEvidence
        case .capabilityUnavailable: .capabilityNotGranted
        case .transportUnavailable: .transportUnavailable
        case .policyBlocked: .policyFiltered
        case .disabled, nil: enabledIntent ? .unknown : .policyFiltered
        }
        let outcome: DiagnosticOutcome = switch lastReason {
        case .duplicateEvent, .replayedNonce: .deduplicated
        case .disabled, .capabilityUnavailable, .transportUnavailable: .unavailable
        case nil where summary == .healthy: .accepted
        case nil: .degraded
        default: .rejected
        }
        let operation: DiagnosticOperation = switch outcome {
        case .accepted: .accept
        case .deduplicated: .deduplicate
        case .unavailable: .unavailable
        case .degraded: .degrade
        default: .reject
        }
        let safe: DiagnosticSafeNextStep = switch lastReason {
        case .newerVersion, .unsupportedVersion, .unknownVersion: .update
        case .transportUnavailable: .retry
        case .disabled: .enableIntent
        case .policyBlocked: .manualRemedy
        default: .inspect
        }
        return DiagnosticEvidence(operation: operation, outcome: outcome, scope: DiagnosticScope(component: .integration, owner: .integration, capability: .observation), reason: reason, occurredAt: observedAt, correlationID: .generated(), health: DiagnosticHealthDimensions(vector: observedHealth), safeNextStep: safe)
    }
}

public struct ClaudeIPCAuthenticator: Sendable {
    private let secret: Data

    public init(secret: Data) {
        self.secret = secret
    }

    public init(secret: String) {
        self.init(secret: Data(secret.utf8))
    }

    public var isUsable: Bool { !secret.isEmpty }

    public func tag(installationID: IntegrationInstanceID, helperID: String, nonce: String, payload: Data, issuedAt: Date = Date(timeIntervalSince1970: 0)) -> String {
        var data = Data()
        data.append(Data(installationID.rawValue.utf8)); data.append(0)
        data.append(Data(helperID.utf8)); data.append(0)
        data.append(Data(nonce.utf8)); data.append(0)
        data.append(Data(String(format: "%.6f", issuedAt.timeIntervalSince1970).utf8)); data.append(0)
        data.append(payload)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: secret))
        return Data(mac).base64EncodedString()
    }

    public func verify(tag: String, installationID: IntegrationInstanceID, helperID: String, nonce: String, payload: Data, issuedAt: Date = Date(timeIntervalSince1970: 0)) -> Bool {
        guard isUsable else { return false }
        guard let supplied = Data(base64Encoded: tag) else { return false }
        let expected = Data(base64Encoded: self.tag(installationID: installationID, helperID: helperID, nonce: nonce, payload: payload, issuedAt: issuedAt)) ?? Data()
        guard supplied.count == expected.count else { return false }
        var difference: UInt8 = 0
        for (lhs, rhs) in zip(supplied, expected) { difference |= lhs ^ rhs }
        return difference == 0
    }
}

/// The boundary transport carries an untrusted, bounded hook payload. It has
/// no callback, command, Action Lease, or transcript reader field.
public struct ClaudeHookIPCMessage: Codable, Hashable, Sendable {
    public let installationID: IntegrationInstanceID
    public let helperID: String
    public let nonce: String
    public let payload: Data
    public let issuedAt: Date
    public let authenticationTag: String

    public init(installationID: IntegrationInstanceID, helperID: String, nonce: String, payload: Data, issuedAt: Date = Date(), authenticator: ClaudeIPCAuthenticator) {
        self.installationID = installationID
        self.helperID = helperID
        self.nonce = nonce
        self.payload = payload
        self.issuedAt = issuedAt
        self.authenticationTag = authenticator.tag(installationID: installationID, helperID: helperID, nonce: nonce, payload: payload, issuedAt: issuedAt)
    }

    public init(installationID: IntegrationInstanceID, helperID: String, nonce: String, payload: Data, issuedAt: Date = Date(), authenticationTag: String) {
        self.installationID = installationID; self.helperID = helperID; self.nonce = nonce; self.payload = payload; self.issuedAt = issuedAt; self.authenticationTag = authenticationTag
    }

    public func isAuthenticated(using authenticator: ClaudeIPCAuthenticator, expectedInstallationID: IntegrationInstanceID, expectedHelperID: String, receivedAt: Date? = nil, maxClockSkew: TimeInterval = 120) -> Bool {
        guard payload.count <= SessionDomainValidator.maxPayloadBytes,
              installationID == expectedInstallationID,
              helperID == expectedHelperID,
              nonce.utf8.count <= 128,
              !nonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              issuedAt.timeIntervalSince1970.isFinite,
              authenticator.verify(tag: authenticationTag, installationID: installationID, helperID: helperID, nonce: nonce, payload: payload, issuedAt: issuedAt) else { return false }
        if let receivedAt { return abs(receivedAt.timeIntervalSince(issuedAt)) <= maxClockSkew }
        return true
    }
}

/// A strict, bounded view of a documented Claude hook JSON object. Unknown
/// fields remain opaque and are never promoted to Agent Island state.
public struct ClaudeHookEnvelope: Sendable {
    public let name: ClaudeHookName
    public let eventIdentity: EventIdentity
    public let nativeSessionID: String
    public let nativeTurnID: String?
    public let nativeAttentionRequestID: String?
    public let nativeSubagentRunID: String?
    public let parentTurnID: String?
    public let parentSessionID: String?
    public let sourceSequence: Int64?
    public let occurrenceTime: Date?
    public let model: String?
    public let workingDirectory: String?
    public let promptID: String?
    public let payload: Data
    public let backgroundTaskCount: Int?
    public let scheduledWakeup: Bool?
    public let stopEvidencePresent: Bool

    private init(name: ClaudeHookName, eventIdentity: EventIdentity, nativeSessionID: String, nativeTurnID: String?, nativeAttentionRequestID: String?, nativeSubagentRunID: String?, parentTurnID: String?, parentSessionID: String?, sourceSequence: Int64?, occurrenceTime: Date?, model: String?, workingDirectory: String?, promptID: String?, payload: Data, backgroundTaskCount: Int?, scheduledWakeup: Bool?, stopEvidencePresent: Bool) {
        self.name = name; self.eventIdentity = eventIdentity; self.nativeSessionID = nativeSessionID; self.nativeTurnID = nativeTurnID; self.nativeAttentionRequestID = nativeAttentionRequestID; self.nativeSubagentRunID = nativeSubagentRunID; self.parentTurnID = parentTurnID; self.parentSessionID = parentSessionID; self.sourceSequence = sourceSequence; self.occurrenceTime = occurrenceTime; self.model = model; self.workingDirectory = workingDirectory; self.promptID = promptID; self.payload = payload; self.backgroundTaskCount = backgroundTaskCount; self.scheduledWakeup = scheduledWakeup; self.stopEvidencePresent = stopEvidencePresent
    }

    public static func decode(_ data: Data, maxBytes: Int = SessionDomainValidator.maxPayloadBytes) throws -> Self {
        guard data.count <= maxBytes else { throw ClaudeHookRejection.oversizedEnvelope }
        guard (try? ClaudeJSONHookEditor.validateJSONObject(data)) != nil else { throw ClaudeHookRejection.malformedEnvelope }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeHookRejection.malformedEnvelope }
        func string(_ keys: [String]) -> String? {
            for key in keys { if let value = object[key] as? String, value.utf8.count <= SessionDomainValidator.maxMetadataStringBytes { return value } }
            return nil
        }
        guard let eventName = string(["hook_event_name", "event", "eventName"]), let name = ClaudeHookName(documentedName: eventName) else { throw ClaudeHookRejection.unsupportedHook }
        guard let session = string(["session_id", "sessionId", "nativeSessionID"]), !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeHookRejection.missingNativeSessionIdentity }
        guard let sourceID = string(["event_id", "eventId", "hook_id", "id"]), !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeHookRejection.missingEventIdentity }
        let sequence = (object["sequence"] as? NSNumber)?.int64Value ?? (object["sequence_number"] as? NSNumber)?.int64Value
        let timestamp = (object["timestamp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let eventNamespace = string(["product_namespace", "productNamespace"])
        if let eventNamespace, eventNamespace != ClaudeCodeIntegration.productNamespace.rawValue { throw ClaudeHookRejection.crossOwner }
        let count = (object["background_task_count"] as? NSNumber)?.intValue ?? (object["backgroundTaskCount"] as? NSNumber)?.intValue
        let wake = (object["scheduled_wakeup"] as? NSNumber)?.boolValue ?? (object["scheduledWakeup"] as? NSNumber)?.boolValue
        let stopEvidence = string(["stop_reason", "stopReason", "result", "result_status"]) != nil || object["result"] != nil || object["stop_reason"] != nil
        let identity: EventIdentity = .stable(sourceID)
        return Self(name: name, eventIdentity: identity, nativeSessionID: session, nativeTurnID: string(["turn_id", "turnId", "nativeTurnID"]), nativeAttentionRequestID: string(["request_id", "requestId", "attention_request_id"]), nativeSubagentRunID: string(["subagent_run_id", "subagentRunId", "child_id"]), parentTurnID: string(["parent_turn_id", "parentTurnId"]), parentSessionID: string(["parent_session_id", "parentSessionId"]), sourceSequence: sequence, occurrenceTime: timestamp, model: string(["model"]), workingDirectory: string(["cwd", "working_directory", "workingDirectory"]), promptID: string(["prompt_id", "promptId"]), payload: data, backgroundTaskCount: count, scheduledWakeup: wake, stopEvidencePresent: stopEvidence)
    }
}

public enum ClaudeHookNormalizer {
    public static func normalize(_ hook: ClaudeHookEnvelope, snapshot: NegotiationSnapshot, integrationInstanceID: IntegrationInstanceID, receiptTime: Date) -> Result<ClaudeNormalizedObservation, ClaudeHookRejection> {
        guard snapshot.productNamespace == ClaudeCodeIntegration.productNamespace,
              snapshot.integrationInstanceID == integrationInstanceID,
              snapshot.grants(ClaudeCodeIntegration.observationCapability, direction: .observe)
        else { return .failure(.capabilityUnavailable) }
        if let parentSessionID = hook.parentSessionID, parentSessionID != hook.nativeSessionID { return .failure(.invalidParentage) }
        let identity = AgentSessionIdentity(productNamespace: ClaudeCodeIntegration.productNamespace, nativeSessionID: NativeSessionID(hook.nativeSessionID))
        let context = ClaudeAttributedContext(model: hook.model, workingDirectory: hook.workingDirectory, promptID: hook.promptID)
        let cursor = hook.sourceSequence.map { SourceCursor(scope: "claude-session:" + hook.nativeSessionID, value: $0) }
        func envelope(family: EventFamily, activity: SessionActivityKind? = nil, boundary: ObservationBoundaryReason? = nil, attention: AttentionRequestKind? = nil, ownership: LifecycleOwnership? = nil, reconciliation: ReconciliationScope? = nil, suffix: String? = nil, includeCursor: Bool = true) -> RawEventEnvelope {
            let eventIdentity: EventIdentity = suffix.map { .stable(sourceID(hook.eventIdentity) + ":" + $0) } ?? hook.eventIdentity
            return RawEventEnvelope(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, contractVersion: snapshot.contractVersion, productNamespace: ClaudeCodeIntegration.productNamespace.rawValue, nativeSessionID: hook.nativeSessionID, eventIdentity: eventIdentity, family: family, sourceVariant: "claude.hook." + hook.name.rawValue, activityKind: activity, boundaryReason: boundary, classification: .operationalMetadata, payloadByteSize: hook.payload.count, occurrenceTime: hook.occurrenceTime, sourceCursor: includeCursor ? cursor : nil, ownership: ownership, attentionKind: attention, reconciliationScope: reconciliation)
        }
        switch hook.name {
        case .sessionStart:
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .sessionDeclared, suffix: "declared"), envelope(family: .sessionActivity, activity: .started, suffix: "started", includeCursor: false)], sourceName: hook.name, attributedContext: context))
        case .userPromptSubmit:
            var events: [RawEventEnvelope] = []
            if let turnID = hook.nativeTurnID { events.append(envelope(family: .turnDeclared, ownership: LifecycleOwnership(nativeTurnID: turnID), suffix: "turn")) }
            events.append(envelope(family: .sessionActivity, activity: .working, ownership: hook.nativeTurnID.map { LifecycleOwnership(nativeTurnID: $0) }, suffix: "working", includeCursor: false))
            return .success(ClaudeNormalizedObservation(events: events, sourceName: hook.name, attributedContext: context))
        case .preToolUse:
            let content = ClaudeProtectedObservationContent(contentID: "claude-content-" + sourceID(hook.eventIdentity), bytes: hook.payload, sessionIdentity: identity, nativeTurnID: hook.nativeTurnID, nativeAttentionRequestID: hook.nativeAttentionRequestID)
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .sessionActivity, activity: .working, ownership: hook.nativeTurnID.map { LifecycleOwnership(nativeTurnID: $0) }, suffix: "working")], protectedContent: content, sourceName: hook.name, attributedContext: context))
        case .permissionRequest:
            guard let requestID = hook.nativeAttentionRequestID, !requestID.isEmpty else { return .failure(.missingEventIdentity) }
            let content = ClaudeProtectedObservationContent(contentID: "claude-content-" + sourceID(hook.eventIdentity), bytes: hook.payload, sessionIdentity: identity, nativeTurnID: hook.nativeTurnID, nativeAttentionRequestID: requestID)
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .attentionRequest, attention: .opened, ownership: LifecycleOwnership(nativeTurnID: hook.nativeTurnID, nativeAttentionRequestID: requestID), suffix: "attention")], protectedContent: content, sourceName: hook.name, attributedContext: context))
        case .askUserQuestion:
            guard snapshot.grants(ClaudeCodeIntegration.questionCapability, direction: .observe), let requestID = hook.nativeAttentionRequestID, let shape = questionShape(from: hook.payload) else { return .failure(.unsupportedResponseSemantics) }
            let content = ClaudeProtectedObservationContent(contentID: "claude-content-" + sourceID(hook.eventIdentity), bytes: hook.payload, sessionIdentity: identity, nativeTurnID: hook.nativeTurnID, nativeAttentionRequestID: requestID)
            let question = ClaudeQuestionObservation(eventIdentity: hook.eventIdentity, sessionIdentity: identity, nativeAttentionRequestID: requestID, content: content, semanticShape: shape)
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .attentionRequest, attention: .opened, ownership: LifecycleOwnership(nativeTurnID: hook.nativeTurnID, nativeAttentionRequestID: requestID), suffix: "question")], question: question, protectedContent: content, sourceName: hook.name, attributedContext: context))
        case .exitPlanMode:
            guard snapshot.grants(ClaudeCodeIntegration.planCapability, direction: .observe), let requestID = hook.nativeAttentionRequestID, !containsRevisionSemantics(hook.payload) else { return .failure(.unsupportedResponseSemantics) }
            let content = ClaudeProtectedObservationContent(contentID: "claude-content-" + sourceID(hook.eventIdentity), bytes: hook.payload, sessionIdentity: identity, nativeTurnID: hook.nativeTurnID, nativeAttentionRequestID: requestID)
            let plan = ClaudePlanObservation(eventIdentity: hook.eventIdentity, sessionIdentity: identity, nativeTurnID: hook.nativeTurnID, markdown: content)
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .attentionRequest, attention: .opened, ownership: LifecycleOwnership(nativeTurnID: hook.nativeTurnID, nativeAttentionRequestID: requestID), suffix: "plan")], plan: plan, protectedContent: content, sourceName: hook.name, attributedContext: context))
        case .notification:
            return .success(ClaudeNormalizedObservation(events: [], cue: ClaudeNotificationCue(kind: .notification, eventIdentity: hook.eventIdentity, sessionIdentity: identity, sourceObservedAt: hook.occurrenceTime), sourceName: hook.name, attributedContext: context))
        case .stop:
            let activeBackground = (hook.backgroundTaskCount ?? 0) > 0 || hook.scheduledWakeup == true
            if activeBackground { return .success(ClaudeNormalizedObservation(events: [envelope(family: .sessionActivity, activity: .waiting, ownership: hook.nativeTurnID.map { LifecycleOwnership(nativeTurnID: $0) }, suffix: "stop")], sourceName: hook.name, attributedContext: context)) }
            guard hook.stopEvidencePresent else { return .failure(.missingStopEvidence) }
            let outcome = explicitStopOutcome(from: hook.payload)
            guard let outcome else { return .failure(.missingStopEvidence) }
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .sessionActivity, activity: outcome, ownership: hook.nativeTurnID.map { LifecycleOwnership(nativeTurnID: $0) }, suffix: "stop")], sourceName: hook.name, attributedContext: context))
        case .stopFailure, .permissionDenied:
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .sessionActivity, activity: .failed, ownership: hook.nativeTurnID.map { LifecycleOwnership(nativeTurnID: $0) }, suffix: "failure")], sourceName: hook.name, attributedContext: context))
        case .sessionEnd:
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .observationBoundary, boundary: .integrationStopped, suffix: "end")], sourceName: hook.name, attributedContext: context))
        case .subagentStart:
            guard let childID = hook.nativeSubagentRunID, let parentTurnID = hook.parentTurnID ?? hook.nativeTurnID, !childID.isEmpty, !parentTurnID.isEmpty else { return .failure(.invalidParentage) }
            let owner = LifecycleOwnership(nativeTurnID: parentTurnID, nativeSubagentRunID: childID)
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .subagentRunDeclared, ownership: owner, suffix: "child"), envelope(family: .sessionActivity, activity: .working, ownership: LifecycleOwnership(nativeTurnID: parentTurnID, nativeSubagentRunID: childID), suffix: "child-working", includeCursor: false)], sourceName: hook.name, attributedContext: context))
        case .subagentStop:
            guard let childID = hook.nativeSubagentRunID, !childID.isEmpty, let parentTurnID = hook.parentTurnID ?? hook.nativeTurnID, !parentTurnID.isEmpty, hook.stopEvidencePresent else { return .failure(.unprovenChildStop) }
            guard let outcome = explicitStopOutcome(from: hook.payload) else { return .failure(.unprovenChildStop) }
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .sessionActivity, activity: outcome, ownership: LifecycleOwnership(nativeTurnID: parentTurnID, nativeSubagentRunID: childID), suffix: "child-stop")], sourceName: hook.name, attributedContext: context))
        case .configChange:
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .reconciliation, reconciliation: .nonExhaustive, suffix: "reconcile")], sourceName: hook.name, attributedContext: context))
        case .wakeup:
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .sessionActivity, activity: .working, suffix: "wakeup")], sourceName: hook.name, attributedContext: context))
        case .backgroundTask:
            let state: SessionActivityKind = (hook.backgroundTaskCount ?? 0) > 0 ? .waiting : .working
            return .success(ClaudeNormalizedObservation(events: [envelope(family: .sessionActivity, activity: state, suffix: "background")], sourceName: hook.name, attributedContext: context))
        }
    }

    private static func sourceID(_ identity: EventIdentity) -> String {
        switch identity { case .stable(let value), .weak(let value): return value }
    }

    private static func explicitStopOutcome(from payload: Data) -> SessionActivityKind? {
        guard let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        let raw = (root["stop_reason"] as? String) ?? (root["stopReason"] as? String) ?? (root["result_status"] as? String) ?? ((root["result"] as? [String: Any])?["status"] as? String)
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ok", "success", "completed", "complete", "done", "end", "end_turn", "max_tokens": return .completed
        case "failure", "failed", "error", "tool_error": return .failed
        case "stopped", "cancelled", "canceled", "user_stop", "interrupt", "interrupted": return .stopped
        default: return nil
        }
    }

    private static func questionShape(from payload: Data) -> GuidedSemanticShape? {
        guard let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              (root["free_text"] as? Bool) != true,
              let questions = (root["questions"] as? [[String: Any]]) ?? (root["question"] as? [[String: Any]]),
              !questions.isEmpty else { return nil }
        var choices: [GuidedChoice] = []
        for (questionIndex, question) in questions.enumerated() {
            guard let options = question["options"] as? [[String: Any]], !options.isEmpty else { return nil }
            for (optionIndex, _) in options.enumerated() {
                // Labels and prompt text stay in protected content. The
                // semantic shape carries stable ordinal IDs only.
                choices.append(GuidedChoice(id: "q" + String(questionIndex) + "-o" + String(optionIndex), label: "Option " + String(optionIndex + 1)))
            }
        }
        return GuidedSemanticShape.structuredChoice(choices, allowsMultipleSelection: false, minimumSelections: 1, maximumSelections: 1)
    }

    private static func containsRevisionSemantics(_ payload: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return true }
        return (root["revision"] as? Bool) == true || (root["revision_requested"] as? Bool) == true || (root["revisionRequested"] as? Bool) == true
    }
}

/// An installation wrapper around the existing lossless exact-entry and
/// manifest coordinator. It owns only the one helper artifact and one exact
/// hook entry, never the Claude settings file or Product data root.
public final class ClaudeCodeInstallationCoordinator: @unchecked Sendable {
    private let coordinator = IntegrationInstallationCoordinator()

    public init() {}

    public func selector(helperPath: URL) -> ExactEntrySelector {
        ClaudeJSONHookEditor.entry(helperPath: helperPath).selector
    }

    /// Claude's documented settings map is keyed by hook event. One exact
    /// marked entry is installed per supported event; each receipt is scoped
    /// independently so a Product or policy-owned event can remain untouched.
    public func selectors(helperPath: URL) -> [ExactEntrySelector] {
        ClaudeHookName.allCases.map { ClaudeJSONHookEditor.entry(for: $0, helperPath: helperPath).selector }
    }

    public func discover(installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, manifest: OwnershipManifest? = nil, snapshot: NegotiationSnapshot? = nil, policy: ExactEntryWritePolicy = .allowed) -> IntegrationInstallationDiscovery {
        if isClaudeJSON(scope.url) {
            let entries = ClaudeHookName.allCases.map { ClaudeJSONHookEditor.entry(for: $0, helperPath: helperPath) }
            let found = entries.map { ClaudeJSONHookEditor.inspect(at: scope.url, entry: $0) }
            let inspectionState: ExactEntryInspectionState
            let reason: ExactEntryFailureReason?
            let source = found.first?.source ?? ExactEntryEditor.snapshot(at: scope.url)
            let markerCount = found.reduce(0) { $0 + $1.markerMatches }
            let compatibility = claudeCompatibility(snapshot: snapshot, policy: policy)
            if compatibility == .policyBlocked { inspectionState = .unsupported; reason = .policyDenied }
            else if found.contains(where: { !$0.supported || $0.source.symlinkTarget != nil }) { inspectionState = .unsupported; reason = source.symlinkTarget == nil ? .unsupported : .symlinkChanged }
            else if found.contains(where: { $0.markerMatches > 1 }) { inspectionState = .shadowedManaged; reason = .ambiguous }
            else if markerCount == 0 { inspectionState = .notConfigured; reason = nil }
            else if let manifest, found.indices.allSatisfy({ found[$0].markerMatches == 1 && manifest.proving(entries[$0].selector, at: scope.path) != nil }) { inspectionState = .ownedIntact; reason = nil }
            else if manifest != nil { inspectionState = .ownedDrifted; reason = .sourceChanged }
            else { inspectionState = .externalCandidate; reason = nil }
            let inspection = ExactEntryInspection(state: inspectionState, source: source, matchingEntryCount: markerCount, reason: reason)
            let safe = inspectionState == .notConfigured && compatibility == .compatible && policy.allowsMutation
            return IntegrationInstallationDiscovery(installationID: installationID, product: ClaudeCodeIntegration.productNamespace, integrationMode: ClaudeCodeIntegration.integrationMode, scope: scope, state: mapInspection(inspectionState), inspection: inspection, compatibility: compatibility, affectedCapabilities: snapshot?.capabilities.filter { $0.availability == .available }.map(\.id) ?? ClaudeCodeIntegration.allObservationCapabilities, safeToMutate: safe)
        }
        guard supportsLosslessHookSource(scope.url) else {
            let source = ExactEntryEditor.snapshot(at: scope.url)
            let inspection = ExactEntryInspection(state: .unsupported, source: source, matchingEntryCount: 0, reason: .unsupported)
            return IntegrationInstallationDiscovery(installationID: installationID, product: ClaudeCodeIntegration.productNamespace, integrationMode: ClaudeCodeIntegration.integrationMode, scope: scope, state: .unsupported, inspection: inspection, compatibility: .interfaceChanged, affectedCapabilities: ClaudeCodeIntegration.allObservationCapabilities, safeToMutate: false)
        }
        return coordinator.discover(installationID: installationID, product: ClaudeCodeIntegration.productNamespace, integrationMode: ClaudeCodeIntegration.integrationMode, scope: scope, selector: selector(helperPath: helperPath), manifest: manifest, snapshot: snapshot, policy: policy)
    }

    public func makePlan(id: String, installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, snapshot: NegotiationSnapshot, policy: ExactEntryWritePolicy = .allowed, now: Date = Date(), expiresIn: TimeInterval = 300) -> IntegrationInstallationPlan {
        let bootstrap = ClaudeCodeIntegration.helperBootstrap(installationID: installationID, helperID: ClaudeCodeIntegration.helperID(for: helperPath))
        let helper = OwnershipManifestArtifactReceipt(path: helperPath.path, kind: .generatedFile, fingerprint: ExactEntryFingerprint(ExactEntryDigest.value(bootstrap)), createdAt: now)
        let base = coordinator.makePlan(id: id, installationID: installationID, action: .enable, product: ClaudeCodeIntegration.productNamespace, integrationMode: ClaudeCodeIntegration.integrationMode, scope: scope, selectors: selectors(helperPath: helperPath), snapshot: snapshot, policy: policy, now: now, expiresIn: expiresIn)
        let compatibility = supportsLosslessHookSource(scope.url) ? base.compatibility : .interfaceChanged
        return IntegrationInstallationPlan(id: base.id, installationID: base.installationID, action: base.action, product: base.product, integrationMode: base.integrationMode, scope: base.scope, sourcePath: base.sourcePath, entries: base.entries, artifacts: [helper], compatibility: compatibility, productVersion: base.productVersion, interfaceVersion: base.interfaceVersion, policyFingerprint: base.policyFingerprint, sourceFingerprint: base.sourceFingerprint, permissionSummary: base.permissionSummary, affectedCapabilities: base.affectedCapabilities, capabilityEvidence: base.capabilityEvidence, rollback: base.rollback, manualRemedy: supportsLosslessHookSource(scope.url) ? base.manualRemedy : "The selected Claude settings source is not losslessly editable by this adapter; use Claude's documented setup manually.", nonEffects: base.nonEffects, createdAt: base.createdAt, expiresAt: base.expiresAt, manifestID: base.manifestID)
    }

    public func approve(_ plan: IntegrationInstallationPlan, personIdentifier: String, at date: Date = Date()) throws -> IntegrationInstallationApproval { try coordinator.approve(plan, personIdentifier: personIdentifier, at: date) }

    public func apply(_ approval: IntegrationInstallationApproval, currentSnapshot: NegotiationSnapshot, helperPath: URL, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationApplyResult {
        if isClaudeJSON(URL(fileURLWithPath: approval.plan.sourcePath)) {
            return applyJSON(approval, currentSnapshot: currentSnapshot, helperPath: helperPath, policy: policy, now: now)
        }
        guard supportsLosslessHookSource(URL(fileURLWithPath: approval.plan.sourcePath)) else { return IntegrationInstallationApplyResult(status: .blocked, reason: .unsupported) }
        let bootstrap = ClaudeCodeIntegration.helperBootstrap(installationID: approval.plan.installationID, helperID: ClaudeCodeIntegration.helperID(for: helperPath))
        let helper = OwnershipManifestArtifactReceipt(path: helperPath.path, kind: .generatedFile, fingerprint: ExactEntryFingerprint(ExactEntryDigest.value(bootstrap)), createdAt: now)
        let helperBefore = ExactEntryEditor.snapshot(at: helperPath)
        guard helperBefore.symlinkTarget == nil else { return IntegrationInstallationApplyResult(status: .blocked, reason: .symlinkChanged) }
        let existed = FileManager.default.fileExists(atPath: helperPath.path)
        if existed {
            guard helperBefore.fingerprint.content == helper.fingerprint, helperBefore.fingerprint.permissionBits == 0o700 else { return IntegrationInstallationApplyResult(status: .blocked, reason: .sourceChanged) }
        } else {
            guard FileManager.default.fileExists(atPath: helperPath.deletingLastPathComponent().path) else { return IntegrationInstallationApplyResult(status: .unavailable, reason: .unavailable) }
            do { try writePrivateHelper(bootstrap, to: helperPath) } catch {
                try? FileManager.default.removeItem(at: helperPath)
                return IntegrationInstallationApplyResult(status: .unavailable, reason: .unavailable)
            }
        }
        let result = coordinator.apply(approval, currentSnapshot: currentSnapshot, policy: policy, probe: { ExactEntryEditor.snapshot(at: helperPath).fingerprint.content == helper.fingerprint }, now: now)
        if result.manifest == nil && !existed { try? FileManager.default.removeItem(at: helperPath) }
        return result
    }

    public func disable(_ installation: IntegrationInstallation) -> IntegrationInstallation { coordinator.disable(installation) }

    public func makeRemovalPlan(id: String, installationID: IntegrationInstanceID, manifest: OwnershipManifest, snapshot: NegotiationSnapshot, now: Date = Date()) -> IntegrationInstallationPlan {
        let base = coordinator.makeRemovalPlan(id: id, installationID: installationID, manifest: manifest, snapshot: snapshot, now: now)
        guard !supportsLosslessHookSource(URL(fileURLWithPath: manifest.sourcePath)) else { return base }
        return IntegrationInstallationPlan(id: base.id, installationID: base.installationID, action: base.action, product: base.product, integrationMode: base.integrationMode, scope: base.scope, sourcePath: base.sourcePath, entries: base.entries, artifacts: base.artifacts, compatibility: .interfaceChanged, productVersion: base.productVersion, interfaceVersion: base.interfaceVersion, policyFingerprint: base.policyFingerprint, sourceFingerprint: base.sourceFingerprint, permissionSummary: base.permissionSummary, affectedCapabilities: base.affectedCapabilities, capabilityEvidence: base.capabilityEvidence, rollback: base.rollback, manualRemedy: "Review and remove only the manifest-proven documented hook entry manually.", nonEffects: base.nonEffects, createdAt: base.createdAt, expiresAt: base.expiresAt, manifestID: base.manifestID)
    }

    public func remove(_ approval: IntegrationInstallationApproval, manifest: OwnershipManifest, now: Date = Date()) -> OwnershipManifestRemovalReport {
        if isClaudeJSON(URL(fileURLWithPath: manifest.sourcePath)) { return removeJSON(approval, manifest: manifest, now: now) }
        return coordinator.remove(approval, manifest: manifest, now: now)
    }

    private func supportsLosslessHookSource(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.hasSuffix(".json") || path.hasSuffix(".jsonc") { return ClaudeJSONHookEditor.inspect(at: url, entry: ClaudeJSONHookEditor.entry(helperPath: URL(fileURLWithPath: "/dev/null"))).supported }
        return ExactEntryEditor.snapshot(at: url).symlinkTarget == nil
    }

    private func isClaudeJSON(_ url: URL) -> Bool { let ext = url.pathExtension.lowercased(); return ext == "json" || ext == "jsonc" }

    private func mapInspection(_ state: ExactEntryInspectionState) -> IntegrationInstallationDiscoveryState {
        switch state { case .notConfigured: .notConfigured; case .ownedIntact: .ownedIntact; case .ownedDrifted: .ownedDrifted; case .externalCandidate: .externalCandidate; case .shadowedManaged: .shadowedManaged; case .unsupported: .unsupported; case .unavailable: .unavailable }
    }

    private func claudeCompatibility(snapshot: NegotiationSnapshot?, policy: ExactEntryWritePolicy) -> IntegrationInstallationCompatibility {
        guard policy.allowsMutation else { return .policyBlocked }
        guard let snapshot else { return .unknown }
        guard snapshot.compatibility == .compatible, snapshot.grants(WellKnownCapability.configuration, direction: .configure), snapshot.killSwitches.isEnabled(.configure), snapshot.health.loadPolicy != .denied, snapshot.health.configured != .denied else { return .interfaceChanged }
        return .compatible
    }

    private func applyJSON(_ approval: IntegrationInstallationApproval, currentSnapshot: NegotiationSnapshot, helperPath: URL, policy: ExactEntryWritePolicy, now: Date) -> IntegrationInstallationApplyResult {
        let plan = approval.plan
        guard plan.action == .enable, plan.isFresh(at: now), plan.compatibility == .compatible, policy.allowsMutation,
              currentSnapshot.productNamespace == ClaudeCodeIntegration.productNamespace,
              currentSnapshot.grants(WellKnownCapability.configuration, direction: .configure) else { return IntegrationInstallationApplyResult(status: .blocked, reason: .policyDenied) }
        guard !plan.entries.isEmpty, plan.entries.allSatisfy({ $0.marker.hasPrefix(ClaudeJSONHookEditor.markerPrefix) }),
              plan.artifacts.first?.path == helperPath.path else { return IntegrationInstallationApplyResult(status: .blocked, reason: .notManifestProven) }
        var receipts: [(receipt: ExactEntryReceipt, event: ClaudeHookName)] = []
        var expected = plan.sourceFingerprint
        do {
            for selector in plan.entries {
                guard let event = ClaudeHookName(documentedName: selector.key.replacingOccurrences(of: "claude-code-hooks-", with: "")) else { throw ClaudeJSONHookEditor.EditorError.notManifestProven }
                let entry = ClaudeJSONHookEditor.Entry(selector: selector, event: event, helperPath: helperPath.path)
                let receipt = try ClaudeJSONHookEditor.add(entry: entry, at: URL(fileURLWithPath: plan.sourcePath), expected: expected, policy: policy, now: now)
                receipts.append((receipt, event)); expected = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: plan.sourcePath)).fingerprint
            }
        } catch let error as ClaudeJSONHookEditor.EditorError {
            rollbackJSON(receipts, sourcePath: plan.sourcePath, now: now)
            return IntegrationInstallationApplyResult(status: .blocked, reason: mapJSONError(error))
        } catch {
            rollbackJSON(receipts, sourcePath: plan.sourcePath, now: now)
            return IntegrationInstallationApplyResult(status: .unavailable, reason: .unavailable)
        }
        let helperExisted = FileManager.default.fileExists(atPath: helperPath.path)
        do {
            let helperSource = ExactEntryEditor.snapshot(at: helperPath)
            if helperSource.symlinkTarget != nil { throw ClaudeJSONHookEditor.EditorError.symlink }
            if helperExisted {
                guard helperSource.fingerprint.content == plan.artifacts[0].fingerprint, helperSource.fingerprint.permissionBits == 0o700 else { throw ClaudeJSONHookEditor.EditorError.sourceChanged }
            } else {
                guard FileManager.default.fileExists(atPath: helperPath.deletingLastPathComponent().path) else { throw ClaudeJSONHookEditor.EditorError.unavailable }
                let bootstrap = ClaudeCodeIntegration.helperBootstrap(installationID: plan.installationID, helperID: ClaudeCodeIntegration.helperID(for: helperPath))
                try writePrivateHelper(bootstrap, to: helperPath)
            }
        } catch let error as ClaudeJSONHookEditor.EditorError {
            rollbackJSON(receipts, sourcePath: plan.sourcePath, now: now)
            if !helperExisted { try? FileManager.default.removeItem(at: helperPath) }
            return IntegrationInstallationApplyResult(status: .blocked, reason: mapJSONError(error))
        } catch {
            rollbackJSON(receipts, sourcePath: plan.sourcePath, now: now)
            if !helperExisted { try? FileManager.default.removeItem(at: helperPath) }
            return IntegrationInstallationApplyResult(status: .unavailable, reason: .unavailable)
        }
        let bootstrap = ClaudeCodeIntegration.helperBootstrap(installationID: plan.installationID, helperID: ClaudeCodeIntegration.helperID(for: helperPath))
        let artifact = OwnershipManifestArtifactReceipt(path: helperPath.path, kind: .generatedFile, fingerprint: ExactEntryFingerprint(ExactEntryDigest.value(bootstrap)), createdAt: now)
        let source = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: plan.sourcePath))
        let evidence = OwnershipManifestVerificationEvidence(verifiedAt: now, reread: true, probeSucceeded: true, sourceFingerprint: source.fingerprint, capabilityIDs: plan.affectedCapabilities)
        let manifest = OwnershipManifest(id: plan.manifestID, installationID: plan.installationID.rawValue, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, sourcePath: plan.sourcePath, entries: receipts.map { $0.receipt }, artifacts: [artifact], productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion, policyFingerprint: plan.policyFingerprint, verification: evidence, createdAt: now, updatedAt: now)
        let installation = IntegrationInstallation(id: plan.installationID, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, manifestID: manifest.id, lifecycle: .enabled, enabledIntent: true, capabilities: plan.affectedCapabilities, health: nil)
        return IntegrationInstallationApplyResult(status: .applied, manifest: manifest, installation: installation)
    }

    private func rollbackJSON(_ receipts: [(receipt: ExactEntryReceipt, event: ClaudeHookName)], sourcePath: String, now: Date) {
        var current = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: sourcePath)).fingerprint
        for item in receipts.reversed() {
            guard let removed = try? ClaudeJSONHookEditor.remove(receipt: item.receipt, event: item.event, at: URL(fileURLWithPath: sourcePath), expected: current, now: now) else { continue }
            current = removed.sourceFingerprint
        }
    }

    private func writePrivateHelper(_ bootstrap: Data, to helperPath: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: helperPath.deletingLastPathComponent().path) else { throw ClaudeJSONHookEditor.EditorError.unavailable }
        guard ExactEntryEditor.snapshot(at: helperPath).symlinkTarget == nil else { throw ClaudeJSONHookEditor.EditorError.symlink }
        try bootstrap.write(to: helperPath, options: [.atomic])
        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: helperPath.path)
        let snapshot = ExactEntryEditor.snapshot(at: helperPath)
        guard snapshot.symlinkTarget == nil,
              snapshot.fingerprint.content == ExactEntryFingerprint(ExactEntryDigest.value(bootstrap)),
              snapshot.fingerprint.permissionBits == 0o700 else { throw ClaudeJSONHookEditor.EditorError.verificationFailed }
    }

    private func removeJSON(_ approval: IntegrationInstallationApproval, manifest: OwnershipManifest, now: Date) -> OwnershipManifestRemovalReport {
        let plan = approval.plan
        guard plan.action == .remove, plan.isFresh(at: now), plan.compatibility == .compatible, plan.sourcePath == manifest.sourcePath else { return OwnershipManifestRemovalReport(outcome: .notRemoved, reason: .sourceChanged, manifest: manifest) }
        var expected = plan.sourceFingerprint
        var removed: [ExactEntrySelector] = []
        var residual: [ExactEntrySelector] = []
        for receipt in manifest.entries {
            let eventName = receipt.selector.key.replacingOccurrences(of: "claude-code-hooks-", with: "")
            guard let event = ClaudeHookName(documentedName: eventName) else { residual.append(receipt.selector); continue }
            do {
                _ = try ClaudeJSONHookEditor.remove(receipt: receipt, event: event, at: URL(fileURLWithPath: manifest.sourcePath), expected: expected, now: now)
                removed.append(receipt.selector); expected = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: manifest.sourcePath)).fingerprint
            } catch { residual.append(receipt.selector) }
        }
        var removedArtifacts: [String] = []; var notRemovedArtifacts: [String] = []
        // Keep the helper while any manifest-proven hook remains. A partial
        // removal must never leave an exact owned entry pointing at a removed
        // artifact merely because another entry drifted or became ambiguous.
        if residual.isEmpty {
            for artifact in manifest.artifacts {
                let url = URL(fileURLWithPath: artifact.path); let current = ExactEntryEditor.snapshot(at: url)
                guard current.symlinkTarget == nil, current.fingerprint.content == artifact.fingerprint else { notRemovedArtifacts.append(artifact.path); continue }
                do { try FileManager.default.removeItem(at: url); removedArtifacts.append(artifact.path) } catch { notRemovedArtifacts.append(artifact.path) }
            }
        } else {
            notRemovedArtifacts = manifest.artifacts.map(\.path)
        }
        let complete = residual.isEmpty && notRemovedArtifacts.isEmpty
        let outcome: OwnershipManifestRemovalOutcome = complete ? .removed : ((removed.isEmpty && removedArtifacts.isEmpty) ? .notRemoved : .partialWithResidual)
        return OwnershipManifestRemovalReport(outcome: outcome, removedEntries: removed, residualEntries: residual, removedArtifacts: removedArtifacts, notRemovedArtifacts: notRemovedArtifacts, reason: complete ? nil : .sourceChanged, manifest: manifest.replacing(lifecycle: complete ? .removed : .partial, at: now))
    }

    private func mapJSONError(_ error: ClaudeJSONHookEditor.EditorError) -> ExactEntryFailureReason {
        switch error { case .sourceChanged: .sourceChanged; case .symlink: .symlinkChanged; case .policyDenied: .policyDenied; case .unsupported, .commentsInJSON: .unsupported; case .ambiguous: .ambiguous; case .notManifestProven: .notManifestProven; case .verificationFailed: .verificationFailed; case .unavailable, .invalidUTF8, .malformed: .unavailable }
    }
}

private struct ClaudeEventOwnerKey: Hashable, Sendable {
    let productNamespace: ProductNamespace
    let nativeSessionID: String
    let eventID: String
    let nativeTurnID: String?
    let nativeSubagentRunID: String?
    let nativeAttentionRequestID: String?
}

private struct ClaudeChildOwnerKey: Hashable, Sendable {
    let productNamespace: ProductNamespace
    let nativeSessionID: String
    let parentTurnID: String
    let childID: String
}

public actor ClaudeCodeAdapter {
    public let integrationInstanceID: IntegrationInstanceID
    public let helperID: String
    private let port: any AdapterIntakePort
    private let authenticator: ClaudeIPCAuthenticator
    private var snapshot: NegotiationSnapshot?
    private var enabledIntent = false
    private var seenEventKeys: Set<ClaudeEventOwnerKey> = []
    private var seenNonces: [String: Date] = [:]
    private var knownSessions: Set<AgentSessionIdentity> = []
    private var liveChildren: Set<ClaudeChildOwnerKey> = []
    public private(set) var health = ClaudeIntegrationHealth()

    public init(port: any AdapterIntakePort, integrationInstanceID: IntegrationInstanceID, helperID: String, authenticator: ClaudeIPCAuthenticator) {
        self.port = port; self.integrationInstanceID = integrationInstanceID; self.helperID = helperID; self.authenticator = authenticator
    }

    @discardableResult
    public func setEnabledIntent(_ enabled: Bool, at date: Date = Date()) -> ClaudeIntegrationHealth {
        enabledIntent = enabled
        if !enabled { health = ClaudeIntegrationHealth(enabledIntent: false, observedHealth: health.observedHealth, observationCapability: .disabled, questionCapability: health.questionCapability, planCapability: health.planCapability, helperReachability: .disabled, lastReason: .disabled, configurationState: health.configurationState, configurationProbeStatus: .disabled, observedAt: date) }
        else { health = ClaudeIntegrationHealth(enabledIntent: true, observedHealth: health.observedHealth, observationCapability: health.observationCapability, questionCapability: health.questionCapability, planCapability: health.planCapability, helperReachability: health.helperReachability, lastReason: health.lastReason, configurationState: health.configurationState, observedAt: date) }
        return health
    }

    public func negotiate(version: ClaudeHooksVersionEvidence, at date: Date = Date()) async -> NegotiationOutcome {
        let known = version.isObservationCompatible
        let availability: CapabilityRecord.Availability = known ? .available : (version.support == .newerThanReviewed ? .unknown : .unavailable)
        let probeCompatibility: NegotiationCompatibility = known ? .compatible : (version.support == .newerThanReviewed ? .unknown : .interfaceChanged)
        // Keep the existing inward contract's generic observation grant for
        // RawEventEnvelope validation, while retaining Claude-specific
        // version/evidence-scoped capabilities for each semantic variant.
        let genericObservation = CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: availability, scope: .mode, fallback: known ? .nativeHost : .retryProbe)
        let records = [genericObservation] + ClaudeCodeIntegration.allObservationCapabilities.map { CapabilityRecord(id: $0, direction: .observe, availability: availability, scope: .mode, fallback: known ? .nativeHost : .retryProbe) } + [CapabilityRecord(id: ClaudeCodeIntegration.configurationCapability, direction: .configure, availability: known ? .available : .unavailable, scope: .installation, fallback: .manualSetup)]
        let request = NegotiationRequest(integrationInstanceID: integrationInstanceID, adapterKind: ClaudeCodeIntegration.adapterKind, adapterBuildVersion: ClaudeCodeIntegration.adapterBuildVersion, productNamespace: ClaudeCodeIntegration.productNamespace, integrationMode: ClaudeCodeIntegration.integrationMode, offeredContractVersion: ContractVersion(major: SessionDomainValidator.supportedContractMajor, minor: 0), requestedCapabilities: records.map(\.id), catalogRevision: ClaudeCodeIntegration.catalogRevision, productVersion: version.productVersion, interfaceVersion: version.interfaceVersion, probeEvidence: NegotiationProbeEvidence(compatibility: probeCompatibility, productVersion: version.productVersion, interfaceVersion: version.interfaceVersion, setup: .loaded, observedAt: version.observedAt), requestedCapabilityRecords: records, compatibility: .compatible)
        let outcome = await port.negotiate(request)
        if case .compatible(let negotiated) = outcome {
            // A new negotiation is a new helper/incarnation. Child authority
            // is never recovered from in-memory state across it.
            liveChildren.removeAll()
            snapshot = negotiated
            let obs = negotiated.capabilities.first(where: { $0.id == ClaudeCodeIntegration.observationCapability })?.availability ?? .unavailable
            let question = negotiated.capabilities.first(where: { $0.id == ClaudeCodeIntegration.questionCapability })?.availability ?? .unavailable
            let plan = negotiated.capabilities.first(where: { $0.id == ClaudeCodeIntegration.planCapability })?.availability ?? .unavailable
            health = ClaudeIntegrationHealth(enabledIntent: enabledIntent, observedHealth: negotiated.health, observationCapability: obs, questionCapability: question, planCapability: plan, helperReachability: .verified, lastReason: known ? nil : (version.support == .newerThanReviewed ? .newerVersion : .unsupportedVersion), configurationState: health.configurationState, observedAt: date)
        }
        return outcome
    }

    public func ingest(_ message: ClaudeHookIPCMessage, at receiptTime: Date = Date()) async -> ClaudeHookIntakeReport {
        guard enabledIntent else { return ClaudeHookIntakeReport(accepted: false, rejection: .disabled) }
        guard message.payload.count <= SessionDomainValidator.maxPayloadBytes else { return fail(.oversizedEnvelope, at: receiptTime) }
        guard message.installationID == integrationInstanceID else { return fail(.crossOwner, at: receiptTime) }
        guard message.helperID == helperID else { return fail(.untrustedHelper, at: receiptTime) }
        guard message.isAuthenticated(using: authenticator, expectedInstallationID: integrationInstanceID, expectedHelperID: helperID, receivedAt: receiptTime) else { return fail(.unauthenticated, at: receiptTime) }
        guard abs(receiptTime.timeIntervalSince(message.issuedAt)) <= 120 else { return fail(.unauthenticated, at: receiptTime) }
        guard !seenNonces.keys.contains(message.nonce) else { return fail(.replayedNonce, at: receiptTime) }
        if seenNonces.count >= 1_024, let oldest = seenNonces.min(by: { $0.value < $1.value })?.key { seenNonces.removeValue(forKey: oldest) }
        seenNonces[message.nonce] = message.issuedAt
        seenNonces = seenNonces.filter { abs(receiptTime.timeIntervalSince($0.value)) <= 120 }
        guard let snapshot, snapshot.grants(ClaudeCodeIntegration.observationCapability, direction: .observe) else { return fail(.capabilityUnavailable, at: receiptTime) }
        let hook: ClaudeHookEnvelope
        do { hook = try ClaudeHookEnvelope.decode(message.payload) } catch let rejection as ClaudeHookRejection { return fail(rejection, at: receiptTime) } catch { return fail(.malformedEnvelope, at: receiptTime) }
        guard !hook.nativeSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail(.missingNativeSessionIdentity, at: receiptTime) }
        let eventKey = ClaudeEventOwnerKey(productNamespace: ClaudeCodeIntegration.productNamespace, nativeSessionID: hook.nativeSessionID, eventID: sourceID(hook.eventIdentity), nativeTurnID: hook.nativeTurnID, nativeSubagentRunID: hook.nativeSubagentRunID, nativeAttentionRequestID: hook.nativeAttentionRequestID)
        guard !seenEventKeys.contains(eventKey) else { return ClaudeHookIntakeReport(accepted: false, duplicate: true, rejection: .duplicateEvent) }
        if hook.name == .subagentStop {
            guard let childID = hook.nativeSubagentRunID, let parentTurnID = hook.parentTurnID ?? hook.nativeTurnID,
                  liveChildren.contains(ClaudeChildOwnerKey(productNamespace: ClaudeCodeIntegration.productNamespace, nativeSessionID: hook.nativeSessionID, parentTurnID: parentTurnID, childID: childID)) else { return fail(.unprovenChildStop, at: receiptTime) }
        }
        let normalized = ClaudeHookNormalizer.normalize(hook, snapshot: snapshot, integrationInstanceID: integrationInstanceID, receiptTime: receiptTime)
        guard case .success(let observation) = normalized else { if case .failure(let reason) = normalized { return fail(reason, at: receiptTime) }; return fail(.malformedEnvelope, at: receiptTime) }
        for envelope in observation.events {
            let outcome = await port.deliver(envelope)
            switch outcome { case .rejected(let reason): return fail(Self.map(reason), at: receiptTime); case .storageUnavailable: return fail(.transportUnavailable, at: receiptTime); case .committed, .duplicateIgnored: break }
        }
        if seenEventKeys.count >= 4_096, let first = seenEventKeys.first { seenEventKeys.remove(first) }
        seenEventKeys.insert(eventKey)
        if hook.name == .subagentStart, let childID = hook.nativeSubagentRunID, let parentTurnID = hook.parentTurnID ?? hook.nativeTurnID {
            liveChildren.insert(ClaudeChildOwnerKey(productNamespace: ClaudeCodeIntegration.productNamespace, nativeSessionID: hook.nativeSessionID, parentTurnID: parentTurnID, childID: childID))
        } else if hook.name == .subagentStop, let childID = hook.nativeSubagentRunID, let parentTurnID = hook.parentTurnID ?? hook.nativeTurnID {
            liveChildren.remove(ClaudeChildOwnerKey(productNamespace: ClaudeCodeIntegration.productNamespace, nativeSessionID: hook.nativeSessionID, parentTurnID: parentTurnID, childID: childID))
        }
        knownSessions.insert(AgentSessionIdentity(productNamespace: ClaudeCodeIntegration.productNamespace, nativeSessionID: NativeSessionID(hook.nativeSessionID)))
        health = ClaudeIntegrationHealth(enabledIntent: enabledIntent, observedHealth: health.observedHealth, observationCapability: health.observationCapability, questionCapability: health.questionCapability, planCapability: health.planCapability, helperReachability: .verified, lastReason: nil, configurationState: health.configurationState, observedAt: receiptTime)
        return ClaudeHookIntakeReport(accepted: true, events: observation.events, observation: observation, protectedContent: observation.protectedContent, cue: observation.cue, question: observation.question, plan: observation.plan)
    }

    public func reportHelperLoss(at date: Date = Date()) async {
        liveChildren.removeAll()
        health = ClaudeIntegrationHealth(enabledIntent: enabledIntent, observedHealth: health.observedHealth, observationCapability: health.observationCapability, questionCapability: health.questionCapability, planCapability: health.planCapability, helperReachability: .unavailable, lastReason: .transportUnavailable, configurationState: health.configurationState, observedAt: date)
        guard let snapshot else { return }
        for identity in knownSessions {
            _ = await port.reportObservationBoundary(ObservationBoundaryReport(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, identity: identity, reason: .transportLost))
        }
    }

    /// Read-only reconciliation. It never adopts, rewrites, or repairs a
    /// Product entry; drift/policy/shadowing is retained as degraded health
    /// and a manual remedy remains the only next step.
    @discardableResult
    public func reconcile(discovery: IntegrationInstallationDiscovery, helperPresent: Bool, at date: Date = Date()) -> ClaudeIntegrationHealth {
        let configStatus: HealthDimensionStatus
        let summary: IntegrationHealthSummary
        let next: HealthSafeNextStep
        switch discovery.state {
        case .ownedIntact where helperPresent:
            configStatus = .verified; summary = .healthy; next = .none
        case .notConfigured:
            configStatus = .setupRequired; summary = .setupRequired; next = .configure
        case .ownedDrifted, .externalCandidate, .shadowedManaged:
            configStatus = .degraded; summary = .degraded; next = .inspect
        case .unsupported:
            configStatus = .incompatible; summary = .incompatible; next = .inspect
        case .unavailable:
            configStatus = .unavailable; summary = .unavailable; next = .retry
        case .ownedIntact:
            configStatus = .degraded; summary = .degraded; next = .retry
        }
        let prior = health.observedHealth
        let vector = IntegrationHealthVector(intent: prior.intent, ownership: prior.ownership, configured: configStatus, loadPolicy: prior.loadPolicy, reachability: helperPresent ? prior.reachability : .degraded, delivery: helperPresent ? prior.delivery : .stale, actionReadiness: .disabled, navigationReadiness: prior.navigationReadiness, summary: summary, evidenceAt: date, affectedCapabilities: discovery.affectedCapabilities, safeNextStep: next)
        let status: ClaudeHookConfigurationStatus = switch discovery.state {
        case .ownedIntact: helperPresent ? .safe : .drifted
        case .notConfigured: .missing
        case .ownedDrifted: .drifted
        case .externalCandidate: .bare
        case .shadowedManaged: .shadowed
        case .unsupported: .invalidSettings
        case .unavailable: .unknown
        }
        health = ClaudeIntegrationHealth(enabledIntent: enabledIntent, observedHealth: vector, observationCapability: health.observationCapability, questionCapability: health.questionCapability, planCapability: health.planCapability, helperReachability: helperPresent ? .verified : .unavailable, lastReason: helperPresent ? nil : .transportUnavailable, configurationState: discovery.state, configurationProbeStatus: status, observedAt: date)
        return health
    }

    @discardableResult
    public func reconcile(_ evidence: ClaudeHookReconciliationEvidence) -> ClaudeIntegrationHealth {
        let configStatus: HealthDimensionStatus = switch evidence.status {
        case .safe: .verified
        case .bare, .missing: .setupRequired
        case .disabled: .disabled
        case .invalidSettings: .incompatible
        case .managedPolicy: .denied
        case .shadowed, .drifted: .degraded
        case .unknown: .unknown
        }
        let summary: IntegrationHealthSummary = switch configStatus {
        case .verified: .healthy
        case .setupRequired: .setupRequired
        case .disabled: .disabled
        case .incompatible: .incompatible
        case .denied, .degraded: .degraded
        case .unknown, .stale, .unavailable: .unavailable
        }
        let prior = health.observedHealth
        let vector = IntegrationHealthVector(intent: prior.intent, ownership: prior.ownership, configured: configStatus, loadPolicy: evidence.status == .managedPolicy ? .denied : prior.loadPolicy, reachability: evidence.helperReachable ? prior.reachability : .degraded, delivery: evidence.helperReachable ? prior.delivery : .stale, actionReadiness: .disabled, navigationReadiness: prior.navigationReadiness, summary: summary, evidenceAt: evidence.observedAt, affectedCapabilities: health.observedHealth.affectedCapabilities, safeNextStep: summary == .healthy ? .none : .inspect)
        health = ClaudeIntegrationHealth(enabledIntent: enabledIntent, observedHealth: vector, observationCapability: health.observationCapability, questionCapability: health.questionCapability, planCapability: health.planCapability, helperReachability: evidence.helperReachable ? .verified : .unavailable, lastReason: evidence.helperReachable ? nil : .transportUnavailable, configurationState: health.configurationState, configurationProbeStatus: evidence.status, observedAt: evidence.observedAt)
        return health
    }

    private func fail(_ reason: ClaudeHookRejection, at date: Date) -> ClaudeHookIntakeReport {
        health = ClaudeIntegrationHealth(enabledIntent: enabledIntent, observedHealth: health.observedHealth, observationCapability: health.observationCapability, questionCapability: health.questionCapability, planCapability: health.planCapability, helperReachability: reason == .transportUnavailable ? .unavailable : health.helperReachability, lastReason: reason, configurationState: health.configurationState, observedAt: date)
        return ClaudeHookIntakeReport(accepted: false, rejection: reason)
    }

    private func sourceID(_ identity: EventIdentity) -> String { switch identity { case .stable(let value), .weak(let value): return value } }

    private static func map(_ reason: EnvelopeValidationError) -> ClaudeHookRejection {
        switch reason { case .payloadTooLarge: .oversizedEnvelope; case .crossOwnerProvenance, .missingOrAmbiguousOwnerIdentity: .crossOwner; case .capabilityNotGranted, .staleCapability, .killSwitchClosed: .capabilityUnavailable; default: .malformedEnvelope }
    }
}
