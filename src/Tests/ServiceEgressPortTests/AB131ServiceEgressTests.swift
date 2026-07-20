import XCTest
import Foundation
@testable import SessionDomain
@testable import ServiceEgressPort

final class AB131ServiceEgressTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_000)

    private func telemetryChangeSet(
        id: String = "egress-1111111111111111",
        consent: ServiceEgressConsent? = nil,
        classification: ServiceEgressClassification = .aggregateTelemetry,
        schema: ServiceEgressSchemaVersion = .current,
        extensions: [String] = []
    ) throws -> ServiceEgressChangeSet {
        let consent = try consent ?? ServiceEgressConsent(purpose: .telemetry, version: 1, grantedAt: date)
        let payload = try ServiceEgressTelemetrySnapshot(metrics: [.sessionsObserved: 2, .attentionRequests: 1])
        return try ServiceEgressChangeSet(
            id: try ServiceEgressChangeSetID(id),
            schemaVersion: schema,
            purpose: .telemetry,
            destination: .telemetry,
            scope: .installationAggregate,
            consent: consent,
            classification: classification,
            payload: .telemetry(payload),
            extensions: extensions,
            createdAt: date
        )
    }

    private func hostedChangeSet(consent: ServiceEgressConsent? = nil) throws -> ServiceEgressChangeSet {
        let identity = AgentSessionIdentity(productNamespace: ProductNamespace("fixture"), nativeSessionID: NativeSessionID("native-session-secret"))
        let pseudonym = ServiceEgressPseudonym.derived(for: identity, destination: .hostedPersistence)
        let state = try ServiceEgressSessionState(pseudonym: pseudonym, execution: .working, observation: .fresh, attention: .none, lineage: .current, turnCount: 2)
        let payload = try ServiceEgressHostedSnapshot(ledgerRevision: 4, sessions: [state])
        let consent = try consent ?? ServiceEgressConsent(purpose: .hostedPersistence, version: 1, grantedAt: date)
        let scope = try ServiceEgressScope(kind: .selectedSessions, pseudonyms: [pseudonym])
        return try ServiceEgressChangeSet(
            id: try ServiceEgressChangeSetID("egress-2222222222222222"),
            purpose: .hostedPersistence,
            destination: .hostedPersistence,
            scope: scope,
            consent: consent,
            classification: .redactedSessionState,
            payload: .hostedPersistence(payload),
            createdAt: date
        )
    }

    func testAbsentPortIsAFeatureAndLeavesOnlyRedactedLocalEvidence() async throws {
        let dispatcher = ServiceEgressDispatcher()
        let consent = try ServiceEgressConsent(purpose: .telemetry, version: 1, grantedAt: date)
        _ = await dispatcher.grant(consent)
        try await dispatcher.enqueue(telemetryChangeSet(consent: consent))

        let diagnostics = await dispatcher.dispatchPending(at: date.addingTimeInterval(1))
        XCTAssertEqual(diagnostics.map(\.status), [.unavailable])
        XCTAssertEqual(diagnostics.first?.reason, .noPort)
        let pending = await dispatcher.pending()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertFalse(String(describing: diagnostics).contains("sessionsObserved"))
    }

    func testFailedPortIsOneAttemptWithNoRetryOrFalseDeliveryClaim() async throws {
        let port = FailingPort()
        let dispatcher = ServiceEgressDispatcher(port: port)
        let consent = try ServiceEgressConsent(purpose: .telemetry, version: 1, grantedAt: date)
        _ = await dispatcher.grant(consent)
        try await dispatcher.enqueue(telemetryChangeSet(consent: consent))

        let first = await dispatcher.dispatchPending(at: date.addingTimeInterval(1))
        let second = await dispatcher.dispatchPending(at: date.addingTimeInterval(2))
        XCTAssertEqual(first.first?.status, .failed)
        XCTAssertEqual(first.first?.reason, .portFailed)
        XCTAssertTrue(second.isEmpty)
        let receivedCount = await port.receivedCount
        XCTAssertEqual(receivedCount, 1)
    }

    func testDeniedRevokedAndPurposeIsolationAreCheckedAtDispatch() async throws {
        let dispatcher = ServiceEgressDispatcher()
        let telemetryConsent = try ServiceEgressConsent(purpose: .telemetry, version: 1, grantedAt: date)
        _ = await dispatcher.grant(telemetryConsent)
        try await dispatcher.enqueue(telemetryChangeSet(consent: telemetryConsent))
        try await dispatcher.enqueue(hostedChangeSet())
        _ = await dispatcher.revoke(purpose: .telemetry, at: date.addingTimeInterval(1))

        let diagnostics = await dispatcher.dispatchPending(at: date.addingTimeInterval(2))
        XCTAssertEqual(diagnostics.map(\.status), [.denied, .denied])
        XCTAssertEqual(diagnostics.map(\.reason), [.consentRevoked, .consentNotGranted])
        let telemetrySnapshot = await dispatcher.consentSnapshot(for: .telemetry)
        let hostedSnapshot = await dispatcher.consentSnapshot(for: .hostedPersistence)
        XCTAssertEqual(telemetrySnapshot.status, .revoked)
        XCTAssertEqual(hostedSnapshot.status, .disabled)
    }

    func testPurposeSpecificDisableDeletesOnlyThatOutboxScope() async throws {
        let dispatcher = ServiceEgressDispatcher()
        let telemetryConsent = try ServiceEgressConsent(purpose: .telemetry, version: 1, grantedAt: date)
        let hostedConsent = try ServiceEgressConsent(purpose: .hostedPersistence, version: 1, grantedAt: date)
        _ = await dispatcher.grant(telemetryConsent)
        _ = await dispatcher.grant(hostedConsent)
        try await dispatcher.enqueue(telemetryChangeSet(consent: telemetryConsent))
        try await dispatcher.enqueue(hostedChangeSet(consent: hostedConsent))

        let deleted = await dispatcher.disableAndDelete(purpose: .telemetry, at: date.addingTimeInterval(1))
        XCTAssertEqual(deleted, 1)
        let pending = await dispatcher.pending()
        let telemetrySnapshot = await dispatcher.consentSnapshot(for: .telemetry)
        let hostedSnapshot = await dispatcher.consentSnapshot(for: .hostedPersistence)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(telemetrySnapshot.status, .disabled)
        XCTAssertEqual(hostedSnapshot.status, .granted)
    }

    func testBoundaryRejectsForbiddenClassificationExtensionsSchemaAndRawPseudonym() throws {
        let consent = try ServiceEgressConsent(purpose: .telemetry, version: 1, grantedAt: date)
        for forbidden in ServiceEgressClassification.allCases where !forbidden.isAllowed {
            XCTAssertThrowsError(try telemetryChangeSet(consent: consent, classification: forbidden)) { error in
                XCTAssertEqual(error as? ServiceEgressContractError, .forbiddenClassification)
            }
        }
        XCTAssertThrowsError(try telemetryChangeSet(consent: consent, extensions: ["future.raw"])) { error in
            XCTAssertEqual(error as? ServiceEgressContractError, .unknownExtension)
        }
        XCTAssertThrowsError(try telemetryChangeSet(consent: consent, schema: ServiceEgressSchemaVersion(major: 2, minor: 0))) { error in
            XCTAssertEqual(error as? ServiceEgressContractError, .unsupportedSchema)
        }
        XCTAssertThrowsError(try ServiceEgressPseudonym(destination: .telemetry, value: "native-session-secret")) { error in
            XCTAssertEqual(error as? ServiceEgressContractError, .invalidPseudonym)
        }
    }

    func testSuccessfulDeliveryIsOneWayAndPayloadContainsNoRawLocalIdentity() async throws {
        let port = RecordingPort()
        let dispatcher = ServiceEgressDispatcher(port: port)
        let consent = try ServiceEgressConsent(purpose: .hostedPersistence, version: 1, grantedAt: date)
        _ = await dispatcher.grant(consent)
        let changeSet = try hostedChangeSet(consent: consent)
        try await dispatcher.enqueue(changeSet)

        let diagnostics = await dispatcher.dispatchPending(at: date.addingTimeInterval(1))
        XCTAssertEqual(diagnostics.first?.status, .delivered)
        XCTAssertEqual(diagnostics.first?.reason, .delivered)
        XCTAssertEqual(await port.receivedCount, 1)
        let received = await port.firstReceived()
        let encoded = try JSONEncoder().encode(received!)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("native-session-secret"))
        XCTAssertTrue(text.contains("pseudonym-"))
    }

    func testSupportDiagnosticRequiresSeparateExplicitConfirmation() throws {
        let evidence = DiagnosticEvidence(operation: .inspect, outcome: .degraded, scope: DiagnosticScope(component: .integration), reason: .unknown, occurredAt: date, correlationID: .generated())
        XCTAssertThrowsError(try ServiceEgressSupportDiagnostic(records: [evidence], explicitlyConfirmedAt: nil)) { error in
            XCTAssertEqual(error as? ServiceEgressContractError, .supportDiagnosticConfirmationRequired)
        }
        XCTAssertNoThrow(try ServiceEgressSupportDiagnostic(records: [evidence], explicitlyConfirmedAt: date))
    }
}

private actor FailingPort: ServiceEgressPort {
    private(set) var receivedCount = 0

    func dispatch(_ changeSet: ServiceEgressChangeSet) async -> ServiceEgressPortOutcome {
        receivedCount += 1
        return .failed
    }
}

private actor RecordingPort: ServiceEgressPort {
    private(set) var received: [ServiceEgressChangeSet] = []
    var receivedCount: Int { received.count }

    func firstReceived() -> ServiceEgressChangeSet? { received.first }

    func dispatch(_ changeSet: ServiceEgressChangeSet) async -> ServiceEgressPortOutcome {
        received.append(changeSet)
        return .delivered
    }
}
