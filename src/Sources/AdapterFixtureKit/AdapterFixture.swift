import Foundation
import SessionDomain
import AdapterPort

/// A controllable, faithful first-party Adapter fixture. It builds envelopes
/// exactly the way a real Claude Code/Codex/Cursor Adapter would and submits
/// them through the same typed `AdapterIntakePort` real integrations use —
/// it never sees `SessionStore` because this target does not depend on it.
public actor AdapterFixture {
    public let integrationInstanceID: IntegrationInstanceID
    public let productNamespace: ProductNamespace
    private let port: any AdapterIntakePort
    private var sequence = 0

    public init(
        port: any AdapterIntakePort,
        integrationInstanceID: IntegrationInstanceID = IntegrationInstanceID("fixture.claude-code.default"),
        productNamespace: ProductNamespace = ProductNamespace("claude-code")
    ) {
        self.port = port
        self.integrationInstanceID = integrationInstanceID
        self.productNamespace = productNamespace
    }

    private func nextEventID(_ label: String) -> String {
        sequence += 1
        return "\(label)-\(sequence)"
    }

    private func standardRequest(contractMajor: Int) -> NegotiationRequest {
        NegotiationRequest(
            integrationInstanceID: integrationInstanceID,
            adapterKind: "fixture.first-party",
            adapterBuildVersion: "0.1.0-fixture",
            productNamespace: productNamespace,
            integrationMode: "fixtureObservation",
            offeredContractVersion: ContractVersion(major: contractMajor, minor: 0),
            requestedCapabilities: [WellKnownCapability.sessionObservation]
        )
    }

    /// AB-124 read-only discovery evidence.  The fixture never scans the
    /// filesystem or writes Product configuration; callers explicitly choose
    /// a returned candidate before activation.
    public static func discoveryCandidates(observedAt: Date? = nil) -> [IntegrationDiscoveryCandidate] {
        let evidence = DiscoveryVersionEvidence(
            productVersion: "fixture-product-1.0",
            interfaceVersion: "hooks-v1",
            adapterVersion: "0.1.0-fixture",
            observedAt: observedAt
        )
        return [
            IntegrationDiscoveryCandidate(
                id: "fixture.claude-code.default",
                product: ProductNamespace("claude-code"),
                versionEvidence: evidence,
                availableModes: ["fixtureObservation"],
                compatibility: .compatible,
                probeState: .verified,
                setup: .manifestLoaded,
                requiredPermissions: [DiscoveryPermission(identifier: "events", granted: true)],
                probePlan: NonMutatingProbePlan(surfaces: ["documented.fixture.surface"])
            )
        ]
    }

    public static func discoverReadOnly(observedAt: Date? = nil) -> DiscoveryResult {
        ReadOnlyAdapterDiscovery.discover(DiscoveryRequest(candidates: discoveryCandidates(observedAt: observedAt), observedAt: observedAt))
    }

    public func negotiateInterfaceChanged() async -> NegotiationOutcome {
        await port.negotiate(
            NegotiationRequest(
                integrationInstanceID: integrationInstanceID,
                adapterKind: "fixture.first-party",
                adapterBuildVersion: "0.1.0-fixture",
                productNamespace: productNamespace,
                integrationMode: "fixtureObservation",
                offeredContractVersion: ContractVersion(major: SessionDomainValidator.supportedContractMajor, minor: 1),
                requestedCapabilities: [WellKnownCapability.sessionObservation, WellKnownCapability.sessionAction],
                productVersion: "fixture-product-2.0",
                interfaceVersion: "hooks-v2",
                probeEvidence: NegotiationProbeEvidence(compatibility: .interfaceChanged, productVersion: "fixture-product-2.0", interfaceVersion: "hooks-v2"),
                requestedCapabilityRecords: [
                    CapabilityRecord(id: WellKnownCapability.sessionObservation, direction: .observe, availability: .available),
                    CapabilityRecord(id: WellKnownCapability.sessionAction, direction: .act, availability: .available)
                ],
                compatibility: .interfaceChanged
            )
        )
    }

    public func negotiateUnknownInterface() async -> NegotiationOutcome {
        await port.negotiate(
            NegotiationRequest(
                integrationInstanceID: integrationInstanceID,
                adapterKind: "fixture.first-party",
                adapterBuildVersion: "0.1.0-fixture",
                productNamespace: productNamespace,
                integrationMode: "fixtureObservation",
                offeredContractVersion: ContractVersion(major: SessionDomainValidator.supportedContractMajor, minor: 99),
                requestedCapabilities: [WellKnownCapability.sessionObservation, WellKnownCapability.sessionAction],
                compatibility: .unknown
            )
        )
    }

    public func close(_ direction: CapabilityRecord.Direction, for snapshot: NegotiationSnapshot) -> NegotiationSnapshot {
        snapshot.applying(killSwitches: snapshot.killSwitches.closing(direction))
    }

    public func negotiateCompatible() async -> NegotiationSnapshot? {
        guard case .compatible(let snapshot) = await port.negotiate(standardRequest(contractMajor: SessionDomainValidator.supportedContractMajor)) else {
            return nil
        }
        return snapshot
    }

    public func negotiateIncompatible(major: Int = 99) async -> NegotiationOutcome {
        await port.negotiate(standardRequest(contractMajor: major))
    }

    public func deliverSessionDeclared(
        snapshot: NegotiationSnapshot,
        nativeSessionID: String,
        stableEventID: String? = nil,
        displayTitle: String? = nil,
        hostLabel: String? = "iTerm2"
    ) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: productNamespace.rawValue,
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(stableEventID ?? nextEventID("session-declared")),
            family: .sessionDeclared,
            sourceVariant: "claudeCode.sessionDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 128,
            displayTitle: displayTitle,
            hostLabel: hostLabel
        )
        return await port.deliver(envelope)
    }

    public func deliverActivity(
        snapshot: NegotiationSnapshot,
        nativeSessionID: String,
        kind: SessionActivityKind,
        stableEventID: String? = nil
    ) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: productNamespace.rawValue,
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(stableEventID ?? nextEventID("session-activity-\(kind.rawValue)")),
            family: .sessionActivity,
            sourceVariant: "claudeCode.turn.\(kind.rawValue)",
            activityKind: kind,
            classification: .operationalMetadata,
            payloadByteSize: 96
        )
        return await port.deliver(envelope)
    }

    /// Horizon evidence only: the same typed fixture boundary can supply a
    /// source-proven Attention Request without giving presentation code any
    /// ability to create one.
    public func deliverAttentionRequest(
        snapshot: NegotiationSnapshot,
        nativeSessionID: String,
        nativeAttentionRequestID: String,
        kind: AttentionRequestKind
    ) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: productNamespace.rawValue,
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(nextEventID("attention-\(kind.rawValue)")),
            family: .attentionRequest,
            sourceVariant: "claudeCode.attention.\(kind.rawValue)",
            classification: .operationalMetadata,
            payloadByteSize: 96,
            ownership: LifecycleOwnership(nativeAttentionRequestID: nativeAttentionRequestID),
            attentionKind: kind
        )
        return await port.deliver(envelope)
    }

    /// Child execution is always delivered with its Product-native child and
    /// owner Turn identifiers. The fixture supplies no task/progress text, so
    /// Horizon can prove it omits unsourced child detail.
    public func deliverSubagentRunDeclared(
        snapshot: NegotiationSnapshot,
        nativeSessionID: String,
        nativeTurnID: String,
        nativeSubagentRunID: String
    ) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: productNamespace.rawValue,
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(nextEventID("subagent-declared")),
            family: .subagentRunDeclared,
            sourceVariant: "claudeCode.subagentRunDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 96,
            ownership: LifecycleOwnership(nativeTurnID: nativeTurnID, nativeSubagentRunID: nativeSubagentRunID)
        )
        return await port.deliver(envelope)
    }

    public func deliverSubagentActivity(
        snapshot: NegotiationSnapshot,
        nativeSessionID: String,
        nativeSubagentRunID: String,
        kind: SessionActivityKind
    ) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: productNamespace.rawValue,
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(nextEventID("subagent-activity-\(kind.rawValue)")),
            family: .sessionActivity,
            sourceVariant: "claudeCode.subagent.\(kind.rawValue)",
            activityKind: kind,
            classification: .operationalMetadata,
            payloadByteSize: 96,
            ownership: LifecycleOwnership(nativeSubagentRunID: nativeSubagentRunID)
        )
        return await port.deliver(envelope)
    }

    public func deliverMissingOwnerIdentity(snapshot: NegotiationSnapshot) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: productNamespace.rawValue,
            nativeSessionID: "   ",
            eventIdentity: .stable(nextEventID("invalid-owner")),
            family: .sessionDeclared,
            sourceVariant: "claudeCode.sessionDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 64
        )
        return await port.deliver(envelope)
    }

    public func deliverMalformedActivity(snapshot: NegotiationSnapshot, nativeSessionID: String) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: productNamespace.rawValue,
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(nextEventID("malformed-activity")),
            family: .sessionActivity,
            sourceVariant: "claudeCode.turn.unknown",
            activityKind: nil,
            classification: .operationalMetadata,
            payloadByteSize: 64
        )
        return await port.deliver(envelope)
    }

    public func deliverOversizedPayload(snapshot: NegotiationSnapshot, nativeSessionID: String) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            contractVersion: snapshot.contractVersion,
            productNamespace: productNamespace.rawValue,
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(nextEventID("oversized")),
            family: .sessionActivity,
            sourceVariant: "claudeCode.turn.started",
            activityKind: .started,
            classification: .operationalMetadata,
            payloadByteSize: SessionDomainValidator.maxPayloadBytes + 1
        )
        return await port.deliver(envelope)
    }

    public func deliverWithArbitrarySnapshotID(_ snapshotID: NegotiationSnapshotID, nativeSessionID: String) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: snapshotID,
            integrationInstanceID: integrationInstanceID,
            contractVersion: ContractVersion(major: SessionDomainValidator.supportedContractMajor, minor: 0),
            productNamespace: productNamespace.rawValue,
            nativeSessionID: nativeSessionID,
            eventIdentity: .stable(nextEventID("unregistered-snapshot")),
            family: .sessionDeclared,
            sourceVariant: "claudeCode.sessionDeclared",
            classification: .operationalMetadata,
            payloadByteSize: 64
        )
        return await port.deliver(envelope)
    }

    public func reportTransportLost(snapshot: NegotiationSnapshot, nativeSessionID: String) async -> IntakeOutcome {
        let identity = AgentSessionIdentity(
            productNamespace: productNamespace,
            nativeSessionID: NativeSessionID(nativeSessionID)
        )
        let report = ObservationBoundaryReport(
            negotiationSnapshotID: snapshot.id,
            integrationInstanceID: integrationInstanceID,
            identity: identity,
            reason: .transportLost
        )
        return await port.reportObservationBoundary(report)
    }
}
