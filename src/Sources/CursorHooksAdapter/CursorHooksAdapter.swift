import Foundation
import SessionDomain
import AdapterPort
import ClaudeCodeAdapter

/// Cursor Hooks contract, fetched from https://cursor.com/docs/hooks.md on
/// 2026-07-20.  This is an observation-only boundary: no hook response is
/// ever produced and no Product action capability exists in this module.
public enum CursorHooksIntegration {
    public static let productNamespace = ProductNamespace("cursor")
    public static let integrationMode = "cursor.documentedHooksObservation"
    public static let adapterKind = "cursor.documented-hooks"
    public static let adapterBuildVersion = "1.0.0"
    public static let interfaceVersion = "hooks-config-v1"
    public static let catalogRevision = "cursor-hooks.catalog.v1"
    public static let observationCapability = "cursor.hooks.sessionObservation"
    public static let helperExecutablePath = "/Applications/Agent Island.app/Contents/MacOS/CursorHookHelper"
    public static let markerPrefix = "agent-island:cursor-hooks-observation:v1"
    public static let contractProvenance = "https://cursor.com/docs/hooks.md (retrieved 2026-07-20)"
    public static func helperID(for helperPath: URL) -> String { "cursor-helper-" + ExactEntryDigest.value(Data(helperPath.path.utf8)) }
}

public enum CursorHookName: String, CaseIterable, Codable, Hashable, Sendable {
    case sessionStart, sessionEnd, preToolUse, postToolUse, postToolUseFailure
    case subagentStart, subagentStop, beforeShellExecution, afterShellExecution
    case beforeMCPExecution, afterMCPExecution, beforeReadFile, afterFileEdit
    case beforeSubmitPrompt, preCompact, stop, afterAgentResponse, afterAgentThought
}

/// Docs provide a received `cursor_version`, but do not publish a broad
/// compatibility range.  A composition root must therefore name each exact
/// reviewed version; the empty default deliberately remains unavailable.
public struct CursorHooksContractEvidence: Hashable, Sendable, Codable {
    public let productVersion: String
    public let interfaceVersion: String
    public let reviewedCursorVersions: Set<String>
    public let observedAt: Date
    public init(productVersion: String = "unknown", interfaceVersion: String = CursorHooksIntegration.interfaceVersion, reviewedCursorVersions: Set<String> = [], observedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.productVersion = productVersion; self.interfaceVersion = interfaceVersion; self.reviewedCursorVersions = reviewedCursorVersions; self.observedAt = observedAt
    }
    public var isCompatible: Bool { interfaceVersion == CursorHooksIntegration.interfaceVersion && reviewedCursorVersions.contains(productVersion) }
    public var compatibility: NegotiationCompatibility { isCompatible ? .compatible : (interfaceVersion == CursorHooksIntegration.interfaceVersion ? .unknown : .interfaceChanged) }
    public var probe: NegotiationProbeEvidence { .init(compatibility: compatibility, productVersion: productVersion, interfaceVersion: interfaceVersion, setup: isCompatible ? .loaded : .unavailable, observedAt: observedAt) }
}

public enum CursorHookRejection: String, Error, Hashable, Sendable, Codable {
    case unsupportedVersion, malformedEnvelope, oversizedEnvelope, unavailable, timeout, transportFailure
    case orphanBeforeActivation, duplicateOrCollision, deliveryGap, unresolvedSubagentStop, ambiguousOwnership
}

public struct CursorHookDiagnostic: Hashable, Sendable, Codable {
    public let reason: CursorHookRejection
    public let observedAt: Date
    public init(_ reason: CursorHookRejection, observedAt: Date = Date()) { self.reason = reason; self.observedAt = observedAt }
    public var redactedDescription: String { "cursor-hooks:\(reason.rawValue)" }
}

/// No native ID, path, model, command, output, prompt, response, thought, or
/// transcript can leave this module in a projection.  `nestedChildCount` is
/// the sole child presentation fact and is backed only by documented start
/// fields (`subagent_id`, `parent_conversation_id`).
public struct CursorSessionProjection: Hashable, Sendable, Codable {
    public var turnCount: Int
    public var nestedChildCount: Int
    public var lifecycle: String
    public var unresolved: Bool
}
public struct CursorObservationProjection: Hashable, Sendable, Codable {
    public let sessions: [CursorSessionProjection]
    public let ordering: String
    public let dispatchCount: Int
}
public enum CursorHookIntakeOutcome: Sendable {
    case delivered(CursorObservationProjection)
    case unavailable(CursorHookDiagnostic)
    case degraded(CursorHookDiagnostic)
}

/// Protected identity never conforms to Codable or CustomStringConvertible.
private struct CursorProtectedIdentity: Hashable, Sendable { let conversationID: String; let generationID: String? }
private struct CursorSessionKey: Hashable, Sendable { let conversationID: String }
private struct CursorEnvelope: Sendable {
    let name: CursorHookName; let identity: CursorProtectedIdentity; let version: String; let status: String?
    let childID: String?; let parentConversationID: String?
}

public enum CursorHookEnvelope {
    public static let maximumBytes = 65_536
    public static func isValid(_ data: Data) -> Bool { (try? decode(data)) != nil }
    fileprivate static func decode(_ data: Data) throws -> CursorEnvelope {
        guard data.count <= maximumBytes else { throw CursorHookRejection.oversizedEnvelope }
        // Reject duplicate key ambiguity before Foundation chooses a value.
        guard (try? ClaudeJSONHookEditor.validateJSONObject(data)) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CursorHookRejection.malformedEnvelope }
        func required(_ key: String) -> String? { (object[key] as? String).flatMap { $0.isEmpty || $0.utf8.count > 1024 ? nil : $0 } }
        guard let rawName = required("hook_event_name"), let name = CursorHookName(rawValue: rawName),
              let conversation = required("conversation_id"), let generation = required("generation_id"),
              let version = required("cursor_version") else { throw CursorHookRejection.malformedEnvelope }
        return .init(name: name, identity: .init(conversationID: conversation, generationID: generation), version: version, status: object["status"] as? String, childID: object["subagent_id"] as? String, parentConversationID: object["parent_conversation_id"] as? String)
    }
}

/// The adapter retains only protected canonical identity during a live intake.
/// Receipt order is expressly not Product ordering: Cursor documents neither
/// event IDs nor sequence values, so a repeated weak owner key is degraded
/// instead of deduplicated optimistically.
public actor CursorHooksAdapter {
    public let integrationInstanceID: IntegrationInstanceID
    public let evidence: CursorHooksContractEvidence
    private var activated = false
    private var sessions: [CursorSessionKey: CursorSessionProjection] = [:]
    private var weakKeys: Set<String> = []

    public init(integrationInstanceID: IntegrationInstanceID, evidence: CursorHooksContractEvidence = .init()) { self.integrationInstanceID = integrationInstanceID; self.evidence = evidence }
    public func activateAfterInstallation() { activated = true }
    public func negotiationRequest() -> NegotiationRequest {
        let availability: CapabilityRecord.Availability = evidence.isCompatible ? .available : .unavailable
        let capability = CapabilityRecord(id: CursorHooksIntegration.observationCapability, direction: .observe, availability: availability, scope: .installation, maturity: .stable, constraints: .init(values: ["configVersion": "1", "cursorVersion": evidence.productVersion, "actions": "none"], requiresLiveEvidence: true), provenance: .init(integrationInstanceID: integrationInstanceID, productNamespace: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode), freshness: .stale, fallback: .unavailable, semanticVariant: "observation-only")
        return .init(integrationInstanceID: integrationInstanceID, adapterKind: CursorHooksIntegration.adapterKind, adapterBuildVersion: CursorHooksIntegration.adapterBuildVersion, productNamespace: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode, offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0), requestedCapabilities: [capability.id], catalogRevision: CursorHooksIntegration.catalogRevision, productVersion: evidence.productVersion, interfaceVersion: evidence.interfaceVersion, probeEvidence: evidence.probe, requestedCapabilityRecords: [capability], compatibility: evidence.compatibility)
    }
    public func receive(_ data: Data) -> CursorHookIntakeOutcome {
        let envelope: CursorEnvelope
        do { envelope = try CursorHookEnvelope.decode(data) }
        catch let reason as CursorHookRejection { return .degraded(.init(reason)) }
        catch { return .degraded(.init(.malformedEnvelope)) }
        guard evidence.isCompatible, envelope.version == evidence.productVersion else { return .unavailable(.init(.unsupportedVersion)) }
        guard activated else { return .degraded(.init(.orphanBeforeActivation)) }
        // Cursor documents no event ID/sequence. This owner-scoped key is
        // intentionally weak and collisions remain inspectable ambiguity.
        let weak = "\(envelope.name.rawValue)|\(envelope.identity.conversationID)|\(envelope.identity.generationID ?? "")|\(envelope.status ?? "")"
        guard weakKeys.insert(weak).inserted else { return .degraded(.init(.duplicateOrCollision)) }
        let sessionKey = CursorSessionKey(conversationID: envelope.identity.conversationID)
        var current = sessions[sessionKey] ?? .init(turnCount: 0, nestedChildCount: 0, lifecycle: "unresolved", unresolved: false)
        switch envelope.name {
        case .sessionStart: current.lifecycle = "started"
        case .sessionEnd: current.lifecycle = "ended"
        case .stop:
            guard let status = envelope.status, ["completed", "aborted", "error"].contains(status) else { current.unresolved = true; sessions[sessionKey] = current; return .degraded(.init(.ambiguousOwnership)) }
            current.lifecycle = status
        case .subagentStart:
            guard let child = envelope.childID, !child.isEmpty, envelope.parentConversationID == envelope.identity.conversationID else { current.unresolved = true; sessions[sessionKey] = current; return .degraded(.init(.ambiguousOwnership)) }
            current.nestedChildCount += 1
        case .subagentStop:
            // The documented stop payload has no subagent_id or parent id.
            current.unresolved = true; sessions[sessionKey] = current; return .degraded(.init(.unresolvedSubagentStop))
        case .preToolUse, .postToolUse, .postToolUseFailure, .beforeShellExecution, .afterShellExecution, .beforeMCPExecution, .afterMCPExecution, .beforeReadFile, .afterFileEdit, .beforeSubmitPrompt, .preCompact, .afterAgentResponse, .afterAgentThought:
            current.turnCount += 1; current.lifecycle = "working"
        }
        sessions[sessionKey] = current
        return .delivered(.init(sessions: sessions.values.sorted { $0.turnCount < $1.turnCount }, ordering: "weak-owner-key; Cursor supplies no documented event ID or sequence", dispatchCount: 0))
    }
    public func reportHelperFailure(_ reason: CursorHookRejection) -> CursorHookIntakeOutcome { .degraded(.init(reason)) }
    public func reportWeakOrderingGap() -> CursorHookIntakeOutcome { .degraded(.init(.deliveryGap)) }
}

/// Explicit, selected-scope v1 configuration lifecycle. It installs only
/// marked command entries; `failClosed` is deliberately omitted so Cursor's
/// documented default `false` keeps the hook nonblocking/fail-open.
public final class CursorHooksInstallationCoordinator: @unchecked Sendable {
    public init() {}
    public func entries(installationID: IntegrationInstanceID, helperPath: URL) -> [ClaudeJSONHookEditor.Entry] {
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "AGENT_ISLAND_CURSOR_OBSERVATION_ONLY=1 AGENT_ISLAND_INSTALLATION_ID=\(quote(installationID.rawValue)) AGENT_ISLAND_HELPER_ID=\(quote(CursorHooksIntegration.helperID(for: helperPath))) exec \(quote(helperPath.path))"
        return CursorHookName.allCases.map { ClaudeJSONHookEditor.entry(eventName: $0.rawValue, markerPrefix: CursorHooksIntegration.markerPrefix, command: command) }
    }
    public func discover(installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, manifest: OwnershipManifest? = nil, evidence: CursorHooksContractEvidence, policy: ExactEntryWritePolicy = .allowed) -> IntegrationInstallationDiscovery {
        let source = ExactEntryEditor.snapshot(at: scope.url)
        let all = entries(installationID: installationID, helperPath: helperPath).map { ClaudeJSONHookEditor.inspect(at: scope.url, entry: $0) }
        let count = all.reduce(0) { $0 + $1.markerMatches }
        let compatible = evidence.isCompatible && isHooksPath(scope) && validVersionOne(source)
        let state: IntegrationInstallationDiscoveryState
        let reason: ExactEntryFailureReason?
        if source.symlinkTarget != nil { state = .unsupported; reason = .symlinkChanged }
        else if !compatible { state = .unsupported; reason = .unsupported }
        else if all.contains(where: { !$0.supported || $0.markerMatches > 1 }) { state = .unsupported; reason = .ambiguous }
        else if count == 0 { state = .notConfigured; reason = nil }
        else if let manifest, all.allSatisfy({ $0.exactMatches == 1 }), manifest.entries.count == all.count { state = .ownedIntact; reason = nil }
        else { state = .externalCandidate; reason = .ambiguous }
        return .init(installationID: installationID, product: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode, scope: scope, state: state, inspection: .init(state: ExactEntryInspectionState(rawValue: state.rawValue) ?? .unsupported, source: source, matchingEntryCount: count, reason: reason), compatibility: compatible ? .compatible : .interfaceChanged, affectedCapabilities: [CursorHooksIntegration.observationCapability], safeToMutate: state == .notConfigured && policy.allowsMutation)
    }
    public func makePlan(id: String, installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, evidence: CursorHooksContractEvidence, action: IntegrationInstallationPlanAction = .enable, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationPlan {
        let source = ExactEntryEditor.snapshot(at: scope.url)
        let compatible = evidence.isCompatible && isHooksPath(scope) && (source.exists ? validVersionOne(source) : true)
        return .init(id: id, installationID: installationID, action: action, product: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode, scope: scope, sourcePath: scope.path, entries: compatible ? entries(installationID: installationID, helperPath: helperPath).map(\.selector) : [], compatibility: compatible && policy.allowsMutation ? .compatible : (policy.allowsMutation ? .interfaceChanged : .policyBlocked), productVersion: evidence.productVersion, interfaceVersion: evidence.interfaceVersion, sourceFingerprint: source.fingerprint, permissionSummary: ["writes only selected hooks.json exact entries", "hook failures remain fail-open"], affectedCapabilities: [CursorHooksIntegration.observationCapability], rollback: "Remove only Ownership Manifest-proven Cursor command entries.", manualRemedy: "Resolve unsupported version, policy, malformed JSON/JSONC, drift, symlink, or marker collision before retrying.", createdAt: now)
    }
    public func approve(_ plan: IntegrationInstallationPlan, personIdentifier: String, at date: Date = Date()) -> IntegrationInstallationApproval { .init(plan: plan, personIdentifier: personIdentifier, approvedAt: date) }
    public func apply(_ approval: IntegrationInstallationApproval, helperPath: URL, evidence: CursorHooksContractEvidence, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationApplyResult {
        let plan = approval.plan; let url = URL(fileURLWithPath: plan.sourcePath)
        guard plan.action == .enable || plan.action == .repair, plan.isFresh(at: now), plan.compatibility == .compatible, evidence.isCompatible, plan.productVersion == evidence.productVersion else { return .init(status: .stale, reason: .sourceChanged) }
        let before = ExactEntryEditor.snapshot(at: url)
        guard before.fingerprint == plan.sourceFingerprint else { return .init(status: .stale, reason: .sourceChanged) }
        guard before.symlinkTarget == nil, policy.allowsMutation else { return .init(status: .blocked, reason: before.symlinkTarget == nil ? .policyDenied : .symlinkChanged) }
        do {
            if !before.exists { try Data("{\"version\":1}".utf8).write(to: url, options: .atomic) }
            guard validVersionOne(ExactEntryEditor.snapshot(at: url)) else { return .init(status: .blocked, reason: .unsupported) }
            var expected = ExactEntryEditor.snapshot(at: url).fingerprint; var receipts: [ExactEntryReceipt] = []
            for entry in entries(installationID: plan.installationID, helperPath: helperPath) {
                let inspection = ClaudeJSONHookEditor.inspect(at: url, entry: entry)
                guard inspection.markerMatches == 0 else { throw ClaudeJSONHookEditor.EditorError.ambiguous }
                let receipt = try ClaudeJSONHookEditor.add(entry: entry, at: url, expected: expected, policy: policy, now: now); receipts.append(receipt); expected = receipt.sourceFingerprint
            }
            let final = ExactEntryEditor.snapshot(at: url)
            let manifest = OwnershipManifest(id: plan.manifestID, installationID: plan.installationID.rawValue, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, sourcePath: plan.sourcePath, entries: receipts, artifacts: [], productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion, policyFingerprint: plan.policyFingerprint, verification: .init(verifiedAt: now, reread: true, probeSucceeded: true, sourceFingerprint: final.fingerprint, capabilityIDs: plan.affectedCapabilities), createdAt: now, updatedAt: now)
            return .init(status: .applied, manifest: manifest, installation: .init(id: plan.installationID, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, manifestID: manifest.id, lifecycle: .enabled, enabledIntent: true, capabilities: plan.affectedCapabilities, health: nil))
        } catch { return .init(status: .blocked, reason: .ambiguous) }
    }
    public func verify(_ manifest: OwnershipManifest, helperPath: URL) -> IntegrationInstallationApplyResult {
        let source = ExactEntryEditor.snapshot(at: URL(fileURLWithPath: manifest.sourcePath)); guard source.symlinkTarget == nil, validVersionOne(source) else { return .init(status: .degraded, reason: .sourceChanged) }
        let owned = entries(installationID: .init(manifest.installationID), helperPath: helperPath).allSatisfy { entry in let i = ClaudeJSONHookEditor.inspect(at: URL(fileURLWithPath: manifest.sourcePath), entry: entry); return i.exactMatches == 1 && manifest.proving(entry.selector, at: manifest.sourcePath) != nil }
        return .init(status: owned ? .applied : .degraded, manifest: owned ? manifest : nil, reason: owned ? nil : .sourceChanged)
    }
    public func disable(_ manifest: OwnershipManifest, helperPath: URL, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationApplyResult { removeEntries(manifest, helperPath: helperPath, policy: policy, now: now, lifecycle: .disabled) }
    public func repair(id: String, installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, evidence: CursorHooksContractEvidence, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationPlan { makePlan(id: id, installationID: installationID, scope: scope, helperPath: helperPath, evidence: evidence, action: .repair, policy: policy, now: now) }
    public func remove(_ manifest: OwnershipManifest, helperPath: URL, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationApplyResult { removeEntries(manifest, helperPath: helperPath, policy: policy, now: now, lifecycle: .removed) }
    private func removeEntries(_ manifest: OwnershipManifest, helperPath: URL, policy: ExactEntryWritePolicy, now: Date, lifecycle: IntegrationInstallationLifecycle) -> IntegrationInstallationApplyResult {
        let url = URL(fileURLWithPath: manifest.sourcePath); guard policy.allowsMutation, ExactEntryEditor.snapshot(at: url).symlinkTarget == nil else { return .init(status: .blocked, reason: .policyDenied) }
        var expected = ExactEntryEditor.snapshot(at: url).fingerprint
        do { for entry in entries(installationID: .init(manifest.installationID), helperPath: helperPath) { guard let receipt = manifest.proving(entry.selector, at: manifest.sourcePath) else { throw ClaudeJSONHookEditor.EditorError.notManifestProven }; let result = try ClaudeJSONHookEditor.remove(receipt: receipt, event: entry.event, at: url, expected: expected, policy: policy, now: now); expected = result.sourceFingerprint } }
        catch { return .init(status: .partial, reason: .sourceChanged) }
        return .init(status: .applied, installation: .init(id: .init(manifest.installationID), product: manifest.product, integrationMode: manifest.integrationMode, scope: manifest.scope, manifestID: manifest.id, lifecycle: lifecycle, enabledIntent: false, capabilities: [CursorHooksIntegration.observationCapability], health: nil))
    }
    private func isHooksPath(_ scope: IntegrationInstallationScope) -> Bool { ["hooks.json", "hooks.jsonc"].contains(scope.url.lastPathComponent) && (scope.kind == .user || scope.kind == .project || scope.kind == .customPath) }
    private func validVersionOne(_ source: ExactEntryFileSnapshot) -> Bool { guard source.symlinkTarget == nil, let text = source.content.flatMap({ String(data: $0, encoding: .utf8) }) else { return false }; return text.range(of: "\\\"version\\\"\\s*:\\s*1", options: .regularExpression) != nil }
}

/// Cursor Hooks exposes no documented live Host locator.  Attention remains
/// unavailable in Agent Island and directs a person back to Cursor; no route,
/// lease, terminal input, question, plan, cancellation, or dispatch exists.
public struct CursorAttentionPresentation: Hashable, Sendable, Codable {
    public let availability: String
    public let jumpBackLevel: String
    public let dispatchCount: Int
    public init() { availability = "Unavailable: respond in Cursor."; jumpBackLevel = "App-only: Cursor Hooks provide no documented live locator."; dispatchCount = 0 }
}
