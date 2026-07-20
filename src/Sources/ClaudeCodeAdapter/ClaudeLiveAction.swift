import Foundation
import CryptoKit
import SessionDomain

/// The only documented synchronous Claude hook decisions that Agent Island
/// can route.  This is deliberately not a generic "reply" protocol.
public enum ClaudeLiveActionSemantic: String, Codable, Hashable, Sendable {
    case permission
    case permissionSuggestion
    case questionAnswers
    case planApproval
}

/// Identity of one invocation that is still blocked in Claude.  It is kept
/// volatile by the router; nonce and callback fingerprint are never included
/// in diagnostics or durable request evidence.
public struct ClaudeLiveCallbackIdentity: Hashable, Sendable {
    public let nativeSessionID: NativeSessionID
    public let promptID: String?
    public let hook: ClaudeHookName
    public let toolUseID: String?
    public let callbackInputFingerprint: String
    public let nonce: UUID

    public init(nativeSessionID: NativeSessionID, promptID: String?, hook: ClaudeHookName, toolUseID: String?, callbackInputFingerprint: String, nonce: UUID = UUID()) {
        self.nativeSessionID = nativeSessionID
        self.promptID = promptID
        self.hook = hook
        self.toolUseID = toolUseID
        self.callbackInputFingerprint = callbackInputFingerprint
        self.nonce = nonce
    }

    public var isWellFormed: Bool {
        guard !nativeSessionID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !callbackInputFingerprint.isEmpty else { return false }
        switch hook {
        case .permissionRequest: return toolUseID == nil
        case .preToolUse: return toolUseID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        default: return false
        }
    }
}

public enum ClaudePermissionDecision: String, Codable, Hashable, Sendable { case allow, deny }

/// A Product-offered permission update. The exact encoded JSON remains only in
/// the live callback, while this opaque ID is sufficient for the Guided UI.
public struct ClaudeOfferedPermissionSuggestion: Hashable, Sendable {
    public let id: String
    public let persistenceScope: String
    public let exactNativeJSON: Data

    public init(id: String, persistenceScope: String, exactNativeJSON: Data) {
        self.id = id
        self.persistenceScope = persistenceScope
        self.exactNativeJSON = exactNativeJSON
    }
}

public struct ClaudeQuestionGroup: Hashable, Sendable {
    public let questionIndex: Int
    public let choiceIDs: [String]
    public let allowsMultiple: Bool

    public init(questionIndex: Int, choiceIDs: [String], allowsMultiple: Bool) {
        self.questionIndex = questionIndex; self.choiceIDs = choiceIDs; self.allowsMultiple = allowsMultiple
    }
}

/// Protected, callback-specific contract. It is neither Codable nor durable:
/// encoding native input, suggestions, nonce, or fingerprints into snapshots
/// would turn an observation into stale action authority.
public struct ClaudeLiveCallback: Sendable {
    public let identity: ClaudeLiveCallbackIdentity
    public let owner: GuidedAttentionOwner
    public let requestID: GuidedAttentionRequestID
    public let capability: CapabilityRecord
    public let semantic: ClaudeLiveActionSemantic
    public let semanticShape: GuidedSemanticShape
    public let deadline: Date
    public let nativeInput: Data
    public let offeredSuggestion: ClaudeOfferedPermissionSuggestion?
    public let questionGroups: [ClaudeQuestionGroup]

    public init(identity: ClaudeLiveCallbackIdentity, owner: GuidedAttentionOwner, capability: CapabilityRecord, semantic: ClaudeLiveActionSemantic, semanticShape: GuidedSemanticShape, deadline: Date, nativeInput: Data, offeredSuggestion: ClaudeOfferedPermissionSuggestion? = nil, questionGroups: [ClaudeQuestionGroup] = []) {
        self.identity = identity; self.owner = owner
        self.requestID = GuidedAttentionRequestID(productNamespace: owner.productNamespace, nativeSessionID: owner.nativeSessionID, nativeAttentionRequestID: owner.nativeAttentionRequestID)
        self.capability = capability; self.semantic = semantic; self.semanticShape = semanticShape; self.deadline = deadline; self.nativeInput = nativeInput; self.offeredSuggestion = offeredSuggestion; self.questionGroups = questionGroups
    }

    public var isWellFormed: Bool {
        guard identity.isWellFormed, deadline > Date(timeIntervalSince1970: 0), capability.direction == .act,
              capability.provenance?.snapshotID == owner.negotiationSnapshotID,
              capability.provenance?.integrationInstanceID == owner.integrationInstanceID,
              capability.provenance?.productNamespace == owner.productNamespace else { return false }
        switch semantic {
        case .permission: return identity.hook == .permissionRequest && semanticShape.kind == .allowDeny
        case .permissionSuggestion: return identity.hook == .permissionRequest && semanticShape.kind == .persistentSuggestion && offeredSuggestion != nil
        case .questionAnswers: return identity.hook == .preToolUse && semanticShape.kind == .structuredChoice && !questionGroups.isEmpty
        case .planApproval: return identity.hook == .preToolUse && semanticShape.kind == .planReview
        }
    }
}

/// Product-specific output. There is intentionally no string command, shell
/// input, cancellation, revision text, or mode-control case.
public enum ClaudeTypedHookResponse: Sendable, Equatable {
    case permission(ClaudePermissionDecision, exactSuggestionJSON: Data?)
    case preToolAllow(updatedInput: Data)
}

public enum ClaudeLiveActionRejection: String, Sendable, Equatable, Error {
    case malformedCallback
    case unsupportedAction
    case ownerMismatch
    case staleCallback
    case expired
    case duplicateCallback
    case invalidAnswer
    case missingConfirmation
    case managedPolicy
    case sourceResolved
    case capabilityUnavailable
    case helperUnavailable
}

/// Strict construction from documented Hook fields. It rejects unsupported
/// combinations instead of guessing from command text or later observations.
public enum ClaudeLiveCallbackFactory {
    public static func make(hook: ClaudeHookEnvelope, snapshot: NegotiationSnapshot, integrationInstanceID: IntegrationInstanceID, deadline: Date) -> Result<ClaudeLiveCallback, ClaudeLiveActionRejection> {
        guard snapshot.productNamespace == ClaudeCodeIntegration.productNamespace,
              snapshot.integrationInstanceID == integrationInstanceID,
              let root = try? JSONSerialization.jsonObject(with: hook.payload) as? [String: Any] else { return .failure(.malformedCallback) }
        let session = NativeSessionID(hook.nativeSessionID)
        let toolName = ((root["tool_name"] ?? root["toolName"]) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = (root["tool_input"] ?? root["toolInput"]) as? [String: Any] ?? root
        let fingerprint = SHA256.hash(data: hook.payload).map { String(format: "%02x", $0) }.joined()
        func callback(requestID: String, capabilityID: String, semantic: ClaudeLiveActionSemantic, shape: GuidedSemanticShape, suggestion: ClaudeOfferedPermissionSuggestion? = nil, groups: [ClaudeQuestionGroup] = []) -> Result<ClaudeLiveCallback, ClaudeLiveActionRejection> {
            guard let capability = snapshot.capabilities.first(where: { $0.id == capabilityID && $0.direction == .act }), snapshot.grants(capability, at: deadline) else { return .failure(.capabilityUnavailable) }
            let owner = GuidedAttentionOwner(productNamespace: ClaudeCodeIntegration.productNamespace, nativeSessionID: session, nativeAttentionRequestID: requestID, nativeTurnID: hook.nativeTurnID, integrationInstanceID: integrationInstanceID, negotiationSnapshotID: snapshot.id)
            return .success(ClaudeLiveCallback(identity: ClaudeLiveCallbackIdentity(nativeSessionID: session, promptID: hook.promptID, hook: hook.name, toolUseID: hook.nativeToolUseID, callbackInputFingerprint: fingerprint), owner: owner, capability: capability, semantic: semantic, semanticShape: shape, deadline: deadline, nativeInput: hook.payload, offeredSuggestion: suggestion, questionGroups: groups))
        }
        switch hook.name {
        case .permissionRequest:
            guard let requestID = hook.nativeAttentionRequestID, !requestID.isEmpty, hook.nativeToolUseID == nil else { return .failure(.malformedCallback) }
            guard let mode = input["permission_mode"] as? String ?? root["permission_mode"] as? String,
                  mode.lowercased() != "bypasspermissions", mode.lowercased() != "bypass_permissions" else { return .failure(.managedPolicy) }
            if let suggestion = offeredSuggestion(in: input) ?? offeredSuggestion(in: root) {
                return callback(requestID: requestID, capabilityID: ClaudeCodeIntegration.permissionSuggestionCapability, semantic: .permissionSuggestion, shape: .persistentSuggestion, suggestion: suggestion)
            }
            return callback(requestID: requestID, capabilityID: ClaudeCodeIntegration.permissionCapability, semantic: .permission, shape: .allowDeny)
        case .preToolUse where toolName == "AskUserQuestion":
            guard let toolUse = hook.nativeToolUseID, !toolUse.isEmpty, let parsed = questions(in: input) else { return .failure(.unsupportedAction) }
            return callback(requestID: toolUse, capabilityID: ClaudeCodeIntegration.questionActionCapability, semantic: .questionAnswers, shape: parsed.shape, groups: parsed.groups)
        case .preToolUse where toolName == "ExitPlanMode":
            guard let toolUse = hook.nativeToolUseID, !toolUse.isEmpty, input["plan"] != nil, !hasRevisionSemantics(input) else { return .failure(.unsupportedAction) }
            return callback(requestID: toolUse, capabilityID: ClaudeCodeIntegration.planApprovalCapability, semantic: .planApproval, shape: GuidedSemanticShape(kind: .planReview))
        default: return .failure(.unsupportedAction)
        }
    }

    private static func offeredSuggestion(in root: [String: Any]) -> ClaudeOfferedPermissionSuggestion? {
        guard let suggestions = root["permission_suggestions"] as? [[String: Any]], suggestions.count == 1,
              let scope = (suggestions[0]["scope"] ?? suggestions[0]["destination"] ?? suggestions[0]["persistence_scope"]) as? String,
              !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              JSONSerialization.isValidJSONObject(suggestions[0]),
              let exact = try? JSONSerialization.data(withJSONObject: suggestions[0], options: [.sortedKeys]) else { return nil }
        let id = SHA256.hash(data: exact).map { String(format: "%02x", $0) }.joined()
        return ClaudeOfferedPermissionSuggestion(id: id, persistenceScope: scope, exactNativeJSON: exact)
    }

    private static func questions(in root: [String: Any]) -> (shape: GuidedSemanticShape, groups: [ClaudeQuestionGroup])? {
        guard (root["free_text"] as? Bool) != true,
              let questions = root["questions"] as? [[String: Any]], (1...4).contains(questions.count) else { return nil }
        var choices: [GuidedChoice] = []; var groups: [ClaudeQuestionGroup] = []
        for (questionIndex, question) in questions.enumerated() {
            guard let options = question["options"] as? [[String: Any]], !options.isEmpty else { return nil }
            let multiple = (question["multi_select"] as? Bool) ?? (question["multiSelect"] as? Bool) ?? false
            let ids = options.indices.map { "q\(questionIndex)-o\($0)" }
            choices += ids.enumerated().map { GuidedChoice(id: $0.element, label: "Option \($0.offset + 1)") }
            groups.append(ClaudeQuestionGroup(questionIndex: questionIndex, choiceIDs: ids, allowsMultiple: multiple))
        }
        return (GuidedSemanticShape.structuredChoice(choices, allowsMultipleSelection: groups.contains(where: \.allowsMultiple), minimumSelections: groups.count, maximumSelections: choices.count), groups)
    }

    private static func hasRevisionSemantics(_ root: [String: Any]) -> Bool {
        (root["revision"] as? Bool) == true || (root["revision_requested"] as? Bool) == true || (root["revisionRequested"] as? Bool) == true
    }
}
