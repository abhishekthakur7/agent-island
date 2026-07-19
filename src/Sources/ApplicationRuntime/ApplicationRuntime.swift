import Foundation
import SessionDomain
import AdapterPort
import PresentationPort
import SessionStore

/// Intake orchestration and projection publication. This is the *only*
/// component in the package that holds a `SessionStore` reference — Adapter
/// fixtures/implementations reach it solely through `AdapterIntakePort`, and
/// presentation code reach it solely through `PresentationPort`. Generated
/// IDs and receipt time are assigned here, at the trusted boundary, never
/// inside `SessionDomain` and never trusted from the envelope itself.
public actor ApplicationRuntime: AdapterIntakePort, PresentationPort {
    private let store: SessionStore
    private let idGenerator: @Sendable () -> String
    private let clock: @Sendable () -> Date

    public init(
        store: SessionStore,
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.idGenerator = idGenerator
        self.clock = clock
    }

    public func negotiate(_ request: NegotiationRequest) async -> NegotiationOutcome {
        let outcome = SessionDomainNegotiator.negotiate(
            request,
            id: NegotiationSnapshotID(idGenerator()),
            negotiatedAt: clock()
        )
        if case .compatible(let snapshot) = outcome {
            await store.registerNegotiation(snapshot)
        }
        return outcome
    }

    public func deliver(_ envelope: RawEventEnvelope) async -> IntakeOutcome {
        await store.intake(envelope, receiptTime: clock())
    }

    /// Transport loss/exit is degradation evidence, not Product truth. It is
    /// routed through the same validated intake path as any other envelope
    /// so it obeys the same negotiation/ownership checks and can only ever
    /// move a session toward `unresolved`/`unavailable` (AB-118 AC6).
    public func reportObservationBoundary(_ report: ObservationBoundaryReport) async -> IntakeOutcome {
        let envelope = RawEventEnvelope(
            negotiationSnapshotID: report.negotiationSnapshotID,
            integrationInstanceID: report.integrationInstanceID,
            contractVersion: ContractVersion(major: SessionDomainValidator.supportedContractMajor, minor: 0),
            productNamespace: report.identity.productNamespace.rawValue,
            nativeSessionID: report.identity.nativeSessionID.rawValue,
            eventIdentity: .weak(idGenerator()),
            family: .observationBoundary,
            sourceVariant: "boundary.\(report.reason.rawValue)",
            boundaryReason: report.reason,
            classification: .operationalMetadata,
            payloadByteSize: 0
        )
        return await deliver(envelope)
    }

    /// Synchronous per `PresentationPort`; reads only `store`, a nonisolated
    /// `let` reference to another actor, so no isolation hop is required to
    /// hand back the stream.
    nonisolated public func presentationStream() -> AsyncStream<ProjectionRevision> {
        AsyncStream { continuation in
            let task = Task {
                for await revision in await store.presentationStream() {
                    continuation.yield(revision)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
