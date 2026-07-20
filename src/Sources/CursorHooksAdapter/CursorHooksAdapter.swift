import Foundation
import SessionDomain
import AdapterPort
import ClaudeCodeAdapter

/// Cursor Hooks v1 observation only. No hook response, action route, prompt,
/// command output, or live Cursor locator is represented here.
public enum CursorHooksIntegration {
    public static let productNamespace = ProductNamespace("cursor")
    public static let integrationMode = "cursor.documentedHooksObservation"
    public static let adapterKind = "cursor.documented-hooks"
    public static let adapterBuildVersion = "1.1.0"
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

public struct CursorHooksContractEvidence: Hashable, Sendable, Codable {
    public let productVersion: String; public let interfaceVersion: String
    public let reviewedCursorVersions: Set<String>; public let observedAt: Date
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
    public let reason: CursorHookRejection; public let observedAt: Date
    public init(_ reason: CursorHookRejection, observedAt: Date = Date()) { self.reason = reason; self.observedAt = observedAt }
    public var redactedDescription: String { "cursor-hooks:\(reason.rawValue)" }
}
public enum CursorHookIntakeOutcome: Sendable, Equatable {
    case delivered([IntakeOutcome]); case unavailable(CursorHookDiagnostic); case degraded(CursorHookDiagnostic)
}

/// Protected ingress-only identifiers do not conform to Codable or String.
private struct CursorIdentity: Hashable, Sendable { let conversationID: String; let generationID: String }
private struct CursorEnvelope: Sendable {
    let name: CursorHookName; let identity: CursorIdentity; let version: String
    let status: String?; let reason: String?; let exitCode: Int?
    let childID: String?; let parentConversationID: String?
}

/// Strict, flat documented-hook view. Unknown fields remain inside this
/// bounded authenticated ingress and are never copied to facts/diagnostics.
public enum CursorHookEnvelope {
    public static let maximumBytes = 65_536
    public static func isValid(_ data: Data) -> Bool { (try? decode(data)) != nil }
    fileprivate static func decode(_ data: Data) throws -> CursorEnvelope {
        guard data.count <= maximumBytes,
              (try? ClaudeJSONHookEditor.validateJSONObject(data)) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CursorHookRejection.malformedEnvelope }
        func string(_ key: String) -> String? { (object[key] as? String).flatMap { !$0.isEmpty && $0.utf8.count <= 1024 ? $0 : nil } }
        func optional(_ key: String) -> String? { object[key] == nil ? nil : string(key) }
        func code() -> Int? { guard let value = object["exit_code"] as? Int, (-1_000_000...1_000_000).contains(value) else { return nil }; return value }
        guard let rawName = string("hook_event_name"), let name = CursorHookName(rawValue: rawName),
              let conversation = string("conversation_id"), let generation = string("generation_id"), let version = string("cursor_version"),
              (object["status"] == nil || optional("status") != nil), (object["reason"] == nil || optional("reason") != nil),
              (object["subagent_id"] == nil || optional("subagent_id") != nil), (object["parent_conversation_id"] == nil || optional("parent_conversation_id") != nil),
              (object["exit_code"] == nil || code() != nil) else { throw CursorHookRejection.malformedEnvelope }
        return .init(name: name, identity: .init(conversationID: conversation, generationID: generation), version: version, status: optional("status"), reason: optional("reason"), exitCode: code(), childID: optional("subagent_id"), parentConversationID: optional("parent_conversation_id"))
    }
}

private struct CursorChildOwnerKey: Hashable, Sendable { let session: AgentSessionIdentity; let parentTurnID: String; let childID: String }

/// Cursor-specific frame receiver. Composition binds this to the app-owned
/// Cursor socket; decoding happens before the adapter so malformed frames
/// cannot reach the canonical intake. It has no reply/action channel.
public actor CursorHooksReceiver {
    private let adapter: CursorHooksAdapter
    public init(adapter: CursorHooksAdapter) { self.adapter = adapter }
    public func receive(frame: Data, at receiptTime: Date = Date()) async -> CursorHookIntakeOutcome {
        do { return await adapter.ingest(try ClaudeHookIPCFrame.decode(frame), at: receiptTime) }
        catch let error as ClaudeHookHelperError {
            switch error {
            case .frameTooLarge, .oversizedStdin:
                return .degraded(.init(.oversizedEnvelope, observedAt: receiptTime))
            case .malformedJSON:
                return .degraded(.init(.malformedEnvelope, observedAt: receiptTime))
            default:
                return .degraded(.init(.transportFailure, observedAt: receiptTime))
            }
        } catch { return .degraded(.init(.transportFailure, observedAt: receiptTime)) }
    }
    public func transportLost(at date: Date = Date()) async { await adapter.reportHelperLoss(at: date) }
}

/// Separate Cursor receiver/coordinator. Shared framed IPC is a primitive;
/// its owner/helper/secret/nonce are checked again here before Cursor facts.
public actor CursorHooksAdapter {
    public let integrationInstanceID: IntegrationInstanceID; public let evidence: CursorHooksContractEvidence; public let helperID: String
    private let port: any AdapterIntakePort; private let authenticator: ClaudeIPCAuthenticator
    private var snapshot: NegotiationSnapshot?; private var activationEpoch = 0
    private var seenNonces: [String: Date] = [:]; private var activeSessions: Set<AgentSessionIdentity> = []
    private var weakClaims: [String: String] = [:]
    private var liveChildren: Set<CursorChildOwnerKey> = []

    public init(port: any AdapterIntakePort, integrationInstanceID: IntegrationInstanceID, helperID: String, authenticator: ClaudeIPCAuthenticator, evidence: CursorHooksContractEvidence = .init()) {
        self.port = port; self.integrationInstanceID = integrationInstanceID; self.helperID = helperID; self.authenticator = authenticator; self.evidence = evidence
    }
    public func negotiationRequest() -> NegotiationRequest {
        let availability: CapabilityRecord.Availability = evidence.isCompatible ? .available : .unavailable
        let generic = CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: availability, scope: .installation, fallback: .unavailable)
        let capability = CapabilityRecord(id: CursorHooksIntegration.observationCapability, direction: .observe, availability: availability, scope: .installation, maturity: .stable, constraints: .init(values: ["configVersion": "1", "cursorVersion": evidence.productVersion, "actions": "none"], requiresLiveEvidence: true), provenance: .init(integrationInstanceID: integrationInstanceID, productNamespace: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode), freshness: .current, fallback: .unavailable, semanticVariant: "observation-only")
        return .init(integrationInstanceID: integrationInstanceID, adapterKind: CursorHooksIntegration.adapterKind, adapterBuildVersion: CursorHooksIntegration.adapterBuildVersion, productNamespace: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode, offeredContractVersion: .init(major: SessionDomainValidator.supportedContractMajor, minor: 0), requestedCapabilities: [generic.id, capability.id], catalogRevision: CursorHooksIntegration.catalogRevision, productVersion: evidence.productVersion, interfaceVersion: evidence.interfaceVersion, probeEvidence: evidence.probe, requestedCapabilityRecords: [generic, capability], compatibility: evidence.compatibility)
    }
    @discardableResult public func negotiate() async -> NegotiationOutcome {
        let result = await port.negotiate(negotiationRequest())
        if case .compatible(let next) = result, next.grants(CursorHooksIntegration.observationCapability, direction: .observe) {
            snapshot = next; activationEpoch += 1; seenNonces.removeAll(); activeSessions.removeAll(); weakClaims.removeAll(); liveChildren.removeAll()
        } else { snapshot = nil; activeSessions.removeAll(); weakClaims.removeAll() }
        return result
    }
    /// Test-only raw ingress. Production composition must use
    /// `CursorHooksReceiver.receive(frame:)`, which authenticates a frame.
    func receiveFixture(_ data: Data) async -> CursorHookIntakeOutcome { await normalizeAndDeliver(data) }
    public func ingest(_ message: ClaudeHookIPCMessage, at receiptTime: Date = Date()) async -> CursorHookIntakeOutcome {
        guard message.payload.count <= CursorHookEnvelope.maximumBytes else { return .degraded(.init(.oversizedEnvelope, observedAt: receiptTime)) }
        guard message.installationID == integrationInstanceID, message.helperID == helperID,
              message.isAuthenticated(using: authenticator, expectedInstallationID: integrationInstanceID, expectedHelperID: helperID, receivedAt: receiptTime) else { return .degraded(.init(.unavailable, observedAt: receiptTime)) }
        guard seenNonces[message.nonce] == nil else { return .degraded(.init(.duplicateOrCollision, observedAt: receiptTime)) }
        if seenNonces.count >= 1_024, let oldest = seenNonces.min(by: { $0.value < $1.value })?.key { seenNonces.removeValue(forKey: oldest) }
        seenNonces[message.nonce] = receiptTime
        return await normalizeAndDeliver(message.payload, at: receiptTime)
    }
    private func normalizeAndDeliver(_ data: Data, at receiptTime: Date = Date()) async -> CursorHookIntakeOutcome {
        let input: CursorEnvelope
        do { input = try CursorHookEnvelope.decode(data) } catch let rejection as CursorHookRejection { return .degraded(.init(rejection, observedAt: receiptTime)) } catch { return .degraded(.init(.malformedEnvelope, observedAt: receiptTime)) }
        guard evidence.isCompatible, input.version == evidence.productVersion else { return .unavailable(.init(.unsupportedVersion, observedAt: receiptTime)) }
        guard let snapshot, activationEpoch > 0, snapshot.grants(CursorHooksIntegration.observationCapability, direction: .observe) else { return .degraded(.init(.orphanBeforeActivation, observedAt: receiptTime)) }
        let identity = AgentSessionIdentity(productNamespace: CursorHooksIntegration.productNamespace, nativeSessionID: .init(input.identity.conversationID))
        guard input.name == .sessionStart || activeSessions.contains(identity) else { return .degraded(.init(.orphanBeforeActivation, observedAt: receiptTime)) }
        let turn = LifecycleOwnership(nativeTurnID: input.identity.generationID)
        func fact(_ family: EventFamily, _ suffix: String, activity: SessionActivityKind? = nil, boundary: ObservationBoundaryReason? = nil, owner: LifecycleOwnership? = nil, reconciliation: ReconciliationScope? = nil, semantic: String? = nil) -> RawEventEnvelope {
            let key = "cursor-v1:e\(activationEpoch):\(input.name.rawValue):\(input.identity.conversationID):\(input.identity.generationID):\(suffix)"
            return .init(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, contractVersion: snapshot.contractVersion, productNamespace: CursorHooksIntegration.productNamespace.rawValue, nativeSessionID: input.identity.conversationID, eventIdentity: .weak(key), family: family, sourceVariant: "cursor.hook." + input.name.rawValue + (semantic.map { ".\($0)" } ?? ""), activityKind: activity, boundaryReason: boundary, classification: .operationalMetadata, payloadByteSize: data.count, ownership: owner, reconciliationScope: reconciliation, integrationMode: CursorHooksIntegration.integrationMode, capabilityID: CursorHooksIntegration.observationCapability, capabilityDirection: .observe, capabilityRevision: 1)
        }
        let events: [RawEventEnvelope]
        switch input.name {
        case .sessionStart: events = [fact(.sessionDeclared, "declared"), fact(.sessionActivity, "started", activity: .started)]
        case .sessionEnd:
            if let outcome = terminal(input.status ?? input.reason) { events = [fact(.sessionActivity, "terminal", activity: outcome)] }
            else if isUserOrWindowClose(input.status ?? input.reason) { events = [fact(.observationBoundary, "user-window-close", boundary: .integrationStopped)] }
            else { events = [fact(.reconciliation, "end-unresolved", reconciliation: .nonExhaustive)] }
        case .stop:
            guard let outcome = terminal(input.status ?? input.reason) else { return .degraded(.init(.ambiguousOwnership, observedAt: receiptTime)) }
            events = [fact(.sessionActivity, "terminal", activity: outcome)]
        case .subagentStart:
            guard let child = input.childID, input.parentConversationID == input.identity.conversationID else { return .degraded(.init(.ambiguousOwnership, observedAt: receiptTime)) }
            let childOwner = LifecycleOwnership(nativeTurnID: input.identity.generationID, nativeSubagentRunID: child)
            liveChildren.insert(.init(session: identity, parentTurnID: input.identity.generationID, childID: child))
            events = [fact(.turnDeclared, "parent-turn", owner: turn), fact(.subagentRunDeclared, "child-declared", owner: childOwner), fact(.sessionActivity, "child-working", activity: .working, owner: childOwner)]
        case .subagentStop:
            // Cursor documents no child tuple here. It cannot close a child or parent.
            let health = await commitReconciliation(
                for: identity,
                suffix: "subagent-stop-unresolved:\(input.identity.generationID)",
                variant: "cursor.hook.subagentStop.unresolved",
                ownership: turn,
                scope: .nonExhaustive
            )
            return healthOutcome([health], degraded: .unresolvedSubagentStop, at: receiptTime)
        case .preCompact:
            // Sourced compaction, explicitly non-exhaustive—not ordinary work.
            events = [fact(.reconciliation, "compaction", reconciliation: .nonExhaustive)]
        case .afterShellExecution:
            if let code = input.exitCode { events = [fact(.sessionActivity, "shell-outcome", activity: .working, owner: turn, semantic: code == 0 ? "succeeded" : "failed")] }
            else { events = [fact(.sessionActivity, "shell-outcome", activity: .working, owner: turn, semantic: "unknown")] }
        case .postToolUseFailure: events = [fact(.sessionActivity, "tool-outcome", activity: .working, owner: turn, semantic: "failed")]
        case .preToolUse, .postToolUse, .beforeShellExecution, .beforeMCPExecution, .afterMCPExecution, .beforeReadFile, .afterFileEdit, .beforeSubmitPrompt, .afterAgentResponse, .afterAgentThought:
            events = [fact(.turnDeclared, "turn", owner: turn), fact(.sessionActivity, "working", activity: .working, owner: turn)]
        }
        var outcomes: [IntakeOutcome] = []; var conflictingWeakClaim = false
        for event in events {
            let outcome = await port.deliver(event); outcomes.append(outcome)
            if case .rejected = outcome { return .degraded(.init(.unavailable, observedAt: receiptTime)) }
            if case .storageUnavailable = outcome { return .degraded(.init(.transportFailure, observedAt: receiptTime)) }
            if case let .weak(key)? = event.eventIdentity {
                let claim = "\(event.family)|\(event.sourceVariant)|\(String(describing: event.activityKind))|\(String(describing: event.boundaryReason))|\(String(describing: event.ownership))|\(String(describing: event.reconciliationScope))"
                if case .committed = outcome {
                    if let prior = weakClaims[key], prior != claim { conflictingWeakClaim = true }
                    else { weakClaims[key] = claim }
                }
            }
        }
        if outcomes.contains(where: { if case .duplicateIgnored = $0 { return true }; return false }) { return .degraded(.init(.duplicateOrCollision, observedAt: receiptTime)) }
        if conflictingWeakClaim { return .degraded(.init(.duplicateOrCollision, observedAt: receiptTime)) }
        if input.name == .sessionStart, outcomes.allSatisfy({ if case .committed = $0 { return true }; return false }) { activeSessions.insert(identity) }
        return .delivered(outcomes)
    }
    public func reportHelperLoss(at date: Date = Date()) async {
        liveChildren.removeAll(); seenNonces.removeAll(); guard let snapshot else { return }
        for identity in activeSessions { _ = await port.reportObservationBoundary(.init(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, identity: identity, reason: .transportLost)) }
        activeSessions.removeAll(); weakClaims.removeAll(); self.snapshot = nil
    }
    /// Health reports are canonical evidence too. A timeout leaves continuity
    /// uncertain, while a lost/unavailable helper closes this local liveness
    /// epoch with an observation boundary; neither manufactures completion.
    public func reportHelperFailure(_ reason: CursorHookRejection, at date: Date = Date()) async -> CursorHookIntakeOutcome {
        switch reason {
        case .timeout, .deliveryGap:
            return await reportReconciliationGap(reason, at: date)
        case .transportFailure, .unavailable:
            guard let snapshot else { return .degraded(.init(reason, observedAt: date)) }
            var outcomes: [IntakeOutcome] = []
            for identity in activeSessions {
                outcomes.append(await port.reportObservationBoundary(.init(negotiationSnapshotID: snapshot.id, integrationInstanceID: integrationInstanceID, identity: identity, reason: .transportLost)))
            }
            guard outcomes.allSatisfy(isCommittedOrDuplicate) else { return healthOutcome(outcomes, degraded: reason, at: date) }
            liveChildren.removeAll(); seenNonces.removeAll(); activeSessions.removeAll(); weakClaims.removeAll(); self.snapshot = nil
            return .degraded(.init(reason, observedAt: date))
        default:
            // A malformed single envelope says nothing about every currently
            // active Agent Session, so it remains diagnostic-only.
            return .degraded(.init(reason, observedAt: date))
        }
    }
    public func reportWeakOrderingGap(at date: Date = Date()) async -> CursorHookIntakeOutcome {
        await reportReconciliationGap(.deliveryGap, at: date)
    }
    private func reportReconciliationGap(_ reason: CursorHookRejection, at date: Date) async -> CursorHookIntakeOutcome {
        var outcomes: [IntakeOutcome] = []
        for identity in activeSessions {
            outcomes.append(await commitReconciliation(
                for: identity,
                suffix: "health:\(reason.rawValue):\(identity.nativeSessionID.rawValue)",
                variant: "cursor.hook.health.\(reason.rawValue)",
                scope: .nonExhaustive
            ))
        }
        return healthOutcome(outcomes, degraded: reason, at: date)
    }
    private func commitReconciliation(for identity: AgentSessionIdentity, suffix: String, variant: String, ownership: LifecycleOwnership? = nil, scope: ReconciliationScope) async -> IntakeOutcome {
        guard let snapshot else { return .rejected(.unknownNegotiationSnapshot) }
        let key = "cursor-v1:e\(activationEpoch):\(suffix):\(identity.nativeSessionID.rawValue)"
        return await port.deliver(.init(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: identity.productNamespace.rawValue,
            nativeSessionID: identity.nativeSessionID.rawValue,
            eventIdentity: .weak(key),
            family: .reconciliation,
            sourceVariant: variant,
            classification: .operationalMetadata,
            payloadByteSize: 0,
            ownership: ownership,
            reconciliationScope: scope,
            integrationMode: CursorHooksIntegration.integrationMode,
            capabilityID: CursorHooksIntegration.observationCapability,
            capabilityDirection: .observe,
            capabilityRevision: 1
        ))
    }
    private func healthOutcome(_ outcomes: [IntakeOutcome], degraded reason: CursorHookRejection, at date: Date) -> CursorHookIntakeOutcome {
        guard outcomes.allSatisfy(isCommittedOrDuplicate) else {
            if outcomes.contains(where: { if case .storageUnavailable = $0 { return true }; return false }) { return .degraded(.init(.transportFailure, observedAt: date)) }
            return .unavailable(.init(.unavailable, observedAt: date))
        }
        return .degraded(.init(reason, observedAt: date))
    }
    private func isCommittedOrDuplicate(_ outcome: IntakeOutcome) -> Bool {
        switch outcome { case .committed, .duplicateIgnored: return true; default: return false }
    }
    private func terminal(_ raw: String?) -> SessionActivityKind? { switch raw?.lowercased() { case "completed", "complete", "success", "succeeded": .completed; case "failed", "failure", "error", "crashed": .failed; case "stopped", "aborted", "cancelled", "canceled": .stopped; default: nil } }
    private func isUserOrWindowClose(_ raw: String?) -> Bool { ["window_close", "window-closed", "user_close", "user-closed"].contains(raw?.lowercased() ?? "") }
}

/// Selected-scope v1 configuration. `beforeSubmitPrompt` is a command hook;
/// no prompt-type hook and no hook response is installed. Cursor's default
/// failClosed=false is intentionally preserved, so helper failures are silent.
public final class CursorHooksInstallationCoordinator: @unchecked Sendable {
    private let runtimeContract: any CursorHookRuntimeContract
    public init(runtimeContract: any CursorHookRuntimeContract = CursorUnprovenHookRuntimeContract()) { self.runtimeContract = runtimeContract }
    public func entries(installationID: IntegrationInstanceID, helperPath: URL) -> [ClaudeJSONHookEditor.Entry] {
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "AGENT_ISLAND_CURSOR_OBSERVATION_ONLY=1 AGENT_ISLAND_INSTALLATION_ID=\(quote(installationID.rawValue)) AGENT_ISLAND_HELPER_ID=\(quote(CursorHooksIntegration.helperID(for: helperPath))) exec \(quote(helperPath.path))"
        return CursorHookName.allCases.map { ClaudeJSONHookEditor.entry(eventName: $0.rawValue, markerPrefix: CursorHooksIntegration.markerPrefix, command: command) }
    }
    public func discover(installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, manifest: OwnershipManifest? = nil, evidence: CursorHooksContractEvidence, policy: ExactEntryWritePolicy = .allowed) -> IntegrationInstallationDiscovery {
        let source = ExactEntryEditor.snapshot(at: scope.url); let all = entries(installationID: installationID, helperPath: helperPath).map { ClaudeJSONHookEditor.inspect(at: scope.url, entry: $0) }; let count = all.reduce(0) { $0 + $1.markerMatches }
        let compatible = evidence.isCompatible && eligible(scope) && (!source.exists || validVersionOne(source)) && runtimeContract.isProven(installationID: installationID, helperID: CursorHooksIntegration.helperID(for: helperPath), helperPath: helperPath)
        let state: IntegrationInstallationDiscoveryState; let reason: ExactEntryFailureReason?
        if source.symlinkTarget != nil { state = .unsupported; reason = .symlinkChanged }
        else if !compatible { state = .unsupported; reason = .unsupported }
        else if all.contains(where: { !$0.supported || $0.markerMatches > 1 }) { state = .unsupported; reason = .ambiguous }
        else if count == 0 { state = .notConfigured; reason = nil }
        else if let manifest, manifest.product == CursorHooksIntegration.productNamespace, manifest.integrationMode == CursorHooksIntegration.integrationMode, manifest.entries.count == all.count, zip(entries(installationID: installationID, helperPath: helperPath), all).allSatisfy({ $0.1.exactMatches == 1 && manifest.proving($0.0.selector, at: scope.path) != nil }) { state = .ownedIntact; reason = nil }
        else { state = .externalCandidate; reason = .ambiguous }
        return .init(installationID: installationID, product: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode, scope: scope, state: state, inspection: .init(state: ExactEntryInspectionState(rawValue: state.rawValue) ?? .unsupported, source: source, matchingEntryCount: count, reason: reason), compatibility: compatible ? .compatible : .interfaceChanged, affectedCapabilities: [CursorHooksIntegration.observationCapability], safeToMutate: state == .notConfigured && policy.allowsMutation)
    }
    public func makePlan(id: String, installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, evidence: CursorHooksContractEvidence, action: IntegrationInstallationPlanAction = .enable, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationPlan {
        let source = ExactEntryEditor.snapshot(at: scope.url); let compatible = evidence.isCompatible && eligible(scope) && (!source.exists || validVersionOne(source)) && runtimeContract.isProven(installationID: installationID, helperID: CursorHooksIntegration.helperID(for: helperPath), helperPath: helperPath)
        return .init(id: id, installationID: installationID, action: action, product: CursorHooksIntegration.productNamespace, integrationMode: CursorHooksIntegration.integrationMode, scope: scope, sourcePath: scope.path, entries: compatible ? entries(installationID: installationID, helperPath: helperPath).map(\.selector) : [], compatibility: compatible && policy.allowsMutation ? .compatible : (policy.allowsMutation ? .interfaceChanged : .policyBlocked), productVersion: evidence.productVersion, interfaceVersion: evidence.interfaceVersion, sourceFingerprint: source.fingerprint, permissionSummary: ["writes only selected hooks.json exact entries", "hook failures remain fail-open"], affectedCapabilities: [CursorHooksIntegration.observationCapability], rollback: "Remove only exact receipts created by this apply.", manualRemedy: "Resolve unsupported version, policy, malformed JSON, drift, symlink, or marker collision before retrying.", createdAt: now)
    }
    public func approve(_ plan: IntegrationInstallationPlan, personIdentifier: String, at date: Date = Date()) -> IntegrationInstallationApproval { .init(plan: plan, personIdentifier: personIdentifier, approvedAt: date) }
    public func apply(_ approval: IntegrationInstallationApproval, helperPath: URL, evidence: CursorHooksContractEvidence, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationApplyResult {
        let plan = approval.plan; let url = URL(fileURLWithPath: plan.sourcePath); let before = ExactEntryEditor.snapshot(at: url)
        guard (plan.action == .enable || plan.action == .repair), plan.isFresh(at: now), plan.compatibility == .compatible, evidence.isCompatible, plan.productVersion == evidence.productVersion, eligible(plan.scope), before.fingerprint == plan.sourceFingerprint else { return .init(status: .stale, reason: .sourceChanged) }
        guard before.symlinkTarget == nil, policy.allowsMutation, helperReady(helperPath), parentSafe(for: url), runtimeContract.isProven(installationID: plan.installationID, helperID: CursorHooksIntegration.helperID(for: helperPath), helperPath: helperPath) else { return .init(status: .blocked, reason: .policyDenied) }
        // Full preflight makes collision/malformed failure atomic before any write.
        if before.exists && !validVersionOne(before) { return .init(status: .blocked, reason: .unsupported) }
        let desired = entries(installationID: plan.installationID, helperPath: helperPath)
        guard desired.allSatisfy({ let i = ClaudeJSONHookEditor.inspect(at: url, entry: $0); return i.supported && i.markerMatches == 0 && i.exactMatches == 0 }) else { return .init(status: .blocked, reason: .ambiguous) }
        var madeFile = false; var receipts: [ExactEntryReceipt] = []; var expected = before.fingerprint
        do {
            if !before.exists { try Data("{\"version\":1}".utf8).write(to: url, options: .atomic); madeFile = true; expected = ExactEntryEditor.snapshot(at: url).fingerprint }
            for entry in desired { let receipt = try ClaudeJSONHookEditor.add(entry: entry, at: url, expected: expected, policy: policy, now: now); receipts.append(receipt); expected = receipt.sourceFingerprint }
            let final = ExactEntryEditor.snapshot(at: url)
            guard validVersionOne(final), desired.allSatisfy({ ClaudeJSONHookEditor.inspect(at: url, entry: $0).exactMatches == 1 }) else { throw ClaudeJSONHookEditor.EditorError.ambiguous }
            let manifest = OwnershipManifest(id: plan.manifestID, installationID: plan.installationID.rawValue, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, sourcePath: plan.sourcePath, entries: receipts, artifacts: [], productVersion: plan.productVersion, interfaceVersion: plan.interfaceVersion, policyFingerprint: plan.policyFingerprint, verification: .init(verifiedAt: now, reread: true, probeSucceeded: runtimeContract.isProven(installationID: plan.installationID, helperID: CursorHooksIntegration.helperID(for: helperPath), helperPath: helperPath), sourceFingerprint: final.fingerprint, capabilityIDs: plan.affectedCapabilities), createdAt: now, updatedAt: now)
            return .init(status: .applied, manifest: manifest, installation: .init(id: plan.installationID, product: plan.product, integrationMode: plan.integrationMode, scope: plan.scope, manifestID: manifest.id, lifecycle: .enabled, enabledIntent: true, capabilities: plan.affectedCapabilities, health: nil))
        } catch {
            var rollbackExpected = ExactEntryEditor.snapshot(at: url).fingerprint
            for receipt in receipts.reversed() { if let result = try? ClaudeJSONHookEditor.remove(receipt: receipt, event: desired.first(where: { $0.selector == receipt.selector })?.event ?? "", at: url, expected: rollbackExpected, policy: policy, now: now) { rollbackExpected = result.sourceFingerprint } }
            if madeFile, ExactEntryEditor.snapshot(at: url).content == Data("{\"version\":1}".utf8) { try? FileManager.default.removeItem(at: url) }
            return .init(status: .blocked, reason: .ambiguous)
        }
    }
    public func verify(_ manifest: OwnershipManifest, helperPath: URL) -> IntegrationInstallationApplyResult {
        let url = URL(fileURLWithPath: manifest.sourcePath); let source = ExactEntryEditor.snapshot(at: url)
        guard let verification = manifest.verification, verification.probeSucceeded, manifest.product == CursorHooksIntegration.productNamespace, manifest.integrationMode == CursorHooksIntegration.integrationMode, eligible(manifest.scope), source.symlinkTarget == nil, validVersionOne(source), helperReady(helperPath), runtimeContract.isProven(installationID: .init(manifest.installationID), helperID: CursorHooksIntegration.helperID(for: helperPath), helperPath: helperPath), source.fingerprint == verification.sourceFingerprint else { return .init(status: .degraded, reason: .sourceChanged) }
        let owned = entries(installationID: .init(manifest.installationID), helperPath: helperPath).allSatisfy { entry in ClaudeJSONHookEditor.inspect(at: url, entry: entry).exactMatches == 1 && manifest.proving(entry.selector, at: manifest.sourcePath) != nil }
        return .init(status: owned ? .applied : .degraded, manifest: owned ? manifest : nil, reason: owned ? nil : .sourceChanged)
    }
    public func disable(_ manifest: OwnershipManifest, helperPath: URL, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationApplyResult { removeEntries(manifest, helperPath: helperPath, policy: policy, now: now, lifecycle: .disabled) }
    public func repair(id: String, installationID: IntegrationInstanceID, scope: IntegrationInstallationScope, helperPath: URL, evidence: CursorHooksContractEvidence, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationPlan { makePlan(id: id, installationID: installationID, scope: scope, helperPath: helperPath, evidence: evidence, action: .repair, policy: policy, now: now) }
    public func remove(_ manifest: OwnershipManifest, helperPath: URL, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) -> IntegrationInstallationApplyResult { removeEntries(manifest, helperPath: helperPath, policy: policy, now: now, lifecycle: .removed) }
    private func removeEntries(_ manifest: OwnershipManifest, helperPath: URL, policy: ExactEntryWritePolicy, now: Date, lifecycle: IntegrationInstallationLifecycle) -> IntegrationInstallationApplyResult {
        let url = URL(fileURLWithPath: manifest.sourcePath); guard policy.allowsMutation, sourceOwned(manifest, helperPath: helperPath), ExactEntryEditor.snapshot(at: url).symlinkTarget == nil else { return .init(status: .partial, reason: .sourceChanged) }
        var expected = ExactEntryEditor.snapshot(at: url).fingerprint
        do { for entry in entries(installationID: .init(manifest.installationID), helperPath: helperPath) { guard let receipt = manifest.proving(entry.selector, at: manifest.sourcePath) else { throw ClaudeJSONHookEditor.EditorError.notManifestProven }; expected = try ClaudeJSONHookEditor.remove(receipt: receipt, event: entry.event, at: url, expected: expected, policy: policy, now: now).sourceFingerprint } }
        catch { return .init(status: .partial, reason: .sourceChanged) }
        return .init(status: .applied, installation: .init(id: .init(manifest.installationID), product: manifest.product, integrationMode: manifest.integrationMode, scope: manifest.scope, manifestID: manifest.id, lifecycle: lifecycle, enabledIntent: false, capabilities: [CursorHooksIntegration.observationCapability], health: nil))
    }
    private func sourceOwned(_ manifest: OwnershipManifest, helperPath: URL) -> Bool { manifest.product == CursorHooksIntegration.productNamespace && manifest.integrationMode == CursorHooksIntegration.integrationMode && entries(installationID: .init(manifest.installationID), helperPath: helperPath).allSatisfy { manifest.proving($0.selector, at: manifest.sourcePath) != nil } }
    private func eligible(_ scope: IntegrationInstallationScope) -> Bool {
        guard scope.url.lastPathComponent == "hooks.json" else { return false }
        switch scope.kind { case .user: return scope.path.hasSuffix("/.cursor/hooks.json"); case .project: return scope.path.hasSuffix("/.cursor/hooks.json"); case .customPath: return scope.identifier.hasPrefix("test-") && scope.path.hasSuffix("/hooks.json"); default: return false }
    }
    private func parentSafe(for url: URL) -> Bool { var isDirectory: ObjCBool = false; return FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDirectory) && isDirectory.boolValue }
    private func helperReady(_ helperPath: URL) -> Bool { FileManager.default.isExecutableFile(atPath: helperPath.path) && (try? FileManager.default.destinationOfSymbolicLink(atPath: helperPath.path)) == nil }
    private func validVersionOne(_ source: ExactEntryFileSnapshot) -> Bool { guard source.symlinkTarget == nil, let text = source.content.flatMap({ String(data: $0, encoding: .utf8) }) else { return false }; return text.range(of: "\\\"version\\\"\\s*:\\s*1", options: .regularExpression) != nil }
}

/// Installation requires application composition to prove the owner-scoped
/// credential, private endpoint, and exact helper path. Discovery and planning
/// are read-only and deliberately never provision those resources.
public protocol CursorHookRuntimeContract: Sendable { func isProven(installationID: IntegrationInstanceID, helperID: String, helperPath: URL) -> Bool }
public struct CursorUnprovenHookRuntimeContract: CursorHookRuntimeContract {
    public init() {}
    public func isProven(installationID: IntegrationInstanceID, helperID: String, helperPath: URL) -> Bool { false }
}
public struct CursorFixtureHookRuntimeContract: CursorHookRuntimeContract {
    public let proven: Bool
    public init(proven: Bool = true) { self.proven = proven }
    public func isProven(installationID: IntegrationInstanceID, helperID: String, helperPath: URL) -> Bool { proven }
}
public struct CursorProvisionedHookRuntimeContract: CursorHookRuntimeContract, Sendable {
    private let credentialStore: any ClaudeHookCredentialStore
    private let endpoint: ClaudeLocalEndpoint
    private let executablePath: String
    public init(credentialStore: any ClaudeHookCredentialStore, endpoint: ClaudeLocalEndpoint, executablePath: String = CursorHooksIntegration.helperExecutablePath) { self.credentialStore = credentialStore; self.endpoint = endpoint; self.executablePath = executablePath }
    public func isProven(installationID: IntegrationInstanceID, helperID: String, helperPath: URL) -> Bool {
        guard helperPath.standardizedFileURL.path == URL(fileURLWithPath: executablePath).standardizedFileURL.path,
              let secret = credentialStore.secret(for: installationID, helperID: helperID), !secret.isEmpty,
              case .success = endpoint.validate() else { return false }
        let helper = ExactEntryEditor.snapshot(at: executablePath)
        guard helper.exists, helper.symlinkTarget == nil, let permissions = helper.fingerprint.permissionBits, (permissions & 0o111) != 0 else { return false }
        return true
    }
}

public struct CursorAttentionPresentation: Hashable, Sendable, Codable {
    public let availability: String; public let jumpBackLevel: String; public let dispatchCount: Int
    public init() { availability = "Unavailable: respond in Cursor."; jumpBackLevel = "App-only: Cursor Hooks provide no documented live locator."; dispatchCount = 0 }
}
