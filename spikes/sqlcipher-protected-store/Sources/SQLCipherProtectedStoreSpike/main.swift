import Foundation
import Darwin
import StorageCore
import SQLCipherStore

struct RunResult: Codable {
    let status: String
    let operation: String
    let recordCount: Int?
    let projectionDigest: String?
    let encryptedAtRest: Bool?
    let diagnostic: RedactedDiagnostic?
}

@main
struct SQLCipherProtectedStoreSpike {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(fileURLWithPath: value(after: "--storage-root", in: arguments) ?? defaultRoot().path, isDirectory: true)
        let account: String
        do { account = try value(after: "--keychain-account", in: arguments) ?? installationAccount(root: root) }
        catch {
            let result = RunResult(status: "failed", operation: operation(arguments), recordCount: nil, projectionDigest: nil, encryptedAtRest: nil, diagnostic: RedactedDiagnostic(code: ProtectedStoreFailure.missingKeychainKey.diagnosticCode, operation: operation(arguments)))
            try? emit(result)
            return
        }
        let store = ProtectedStore(configuration: .init(databaseURL: root.appendingPathComponent("protected-store.db"), keychainAccount: account))
        do {
            if arguments.contains("--smoke") {
                try smoke(store: store)
            } else if arguments.contains("--bootstrap-legacy") {
                try store.bootstrapLegacySchemaForEvidenceOnly(records: RepresentativeFixture.records)
                try emit(.init(status: "ok", operation: "bootstrap-legacy", recordCount: RepresentativeFixture.records.count, projectionDigest: nil, encryptedAtRest: try store.encryptedAtRest(), diagnostic: nil))
            } else if arguments.contains("--migrate") {
                try store.migrateIfNeeded()
                let projection = try store.openAndRebuildProjection()
                try emit(.init(status: "ok", operation: "migrate", recordCount: projection.recordCount, projectionDigest: projection.digest, encryptedAtRest: try store.encryptedAtRest(), diagnostic: nil))
            } else if arguments.contains("--fail-migration-stage") {
                try store.migrateIfNeeded(failAfterStageVerification: true)
                throw ProtectedStoreFailure.migrationFailed
            } else if arguments.contains("--fail-migration-promotion") {
                try store.migrateIfNeeded(failAfterPromotion: true)
                throw ProtectedStoreFailure.migrationFailed
            } else if arguments.contains("--crash-after-stage-verify") {
                try store.migrateIfNeeded(crashAfterStageVerification: true)
                throw ProtectedStoreFailure.migrationFailed // SIGKILL must occur first
            } else if arguments.contains("--discard-interrupted-stage") {
                try store.discardInterruptedStageAfterVerifyingPrimary()
                try emit(.init(status: "ok", operation: "discard-interrupted-stage", recordCount: nil, projectionDigest: nil, encryptedAtRest: nil, diagnostic: nil))
            } else if arguments.contains("--write-mutated") {
                let projection = try store.write(records: mutatedFixture())
                try emit(.init(status: "ok", operation: "write-mutated", recordCount: projection.recordCount, projectionDigest: projection.digest, encryptedAtRest: try store.encryptedAtRest(), diagnostic: nil))
            } else if arguments.contains("--crash-before-commit") {
                _ = try store.write(records: mutatedFixture(), crashBeforeCommit: true)
                throw ProtectedStoreFailure.integrityCheckFailed // SIGKILL must occur first
            } else if arguments.contains("--benchmark") {
                try benchmark(store: store)
            } else if arguments.contains("--bootstrap") {
                try emit(.init(status: "ok", operation: "bootstrap", recordCount: try store.bootstrap(records: RepresentativeFixture.records).recordCount, projectionDigest: try store.openAndRebuildProjection().digest, encryptedAtRest: try store.encryptedAtRest(), diagnostic: nil))
            } else {
                let projection = try store.openAndRebuildProjection()
                try emit(.init(status: "ok", operation: "open", recordCount: projection.recordCount, projectionDigest: projection.digest, encryptedAtRest: try store.encryptedAtRest(), diagnostic: nil))
            }
        } catch {
            let result = RunResult(status: "failed", operation: operation(arguments), recordCount: nil, projectionDigest: nil, encryptedAtRest: nil, diagnostic: store.diagnostic(for: error, operation: operation(arguments)))
            try? emit(result)
            exit(1)
        }
    }

    private static func smoke(store: ProtectedStore) throws {
        try store.bootstrapLegacySchemaForEvidenceOnly(records: RepresentativeFixture.records)
        try store.migrateIfNeeded()
        let projection = try store.openAndRebuildProjection()
        let expected = try ProjectionBuilder.rebuild(records: RepresentativeFixture.records)
        let encrypted = try store.encryptedAtRest()
        let wrongKeyRejected = try store.rejectsWrongKeyForEvidence()
        guard projection == expected, encrypted, wrongKeyRejected else {
            throw ProtectedStoreFailure.integrityCheckFailed
        }
        try store.createInterruptedStageForTestOnly()
        do {
            _ = try store.openAndRebuildProjection()
            throw ProtectedStoreFailure.interruptedWrite // failure was not closed
        } catch ProtectedStoreFailure.interruptedWrite {
            try store.discardInterruptedStageAfterVerifyingPrimary()
        }
        let recovered = try store.openAndRebuildProjection()
        try emit(.init(status: "ok", operation: "smoke", recordCount: recovered.recordCount, projectionDigest: recovered.digest, encryptedAtRest: try store.encryptedAtRest(), diagnostic: nil))
    }

    private static func benchmark(store: ProtectedStore) throws {
        let started = ContinuousClock.now
        let projection = try store.bootstrap(records: RepresentativeFixture.records)
        let elapsed = started.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        let report: [String: Any] = [
            "schemaVersion": MigrationPolicy.currentSchema,
            "fixtureRecordCount": projection.recordCount,
            "projectionDigest": projection.digest,
            "bootstrapAndVerifiedWriteMs": milliseconds,
            "encryptedAtRest": try store.encryptedAtRest(),
            "note": "Single-run local feasibility sample; see Evidence report for required repeated measurements."
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func emit(_ value: RunResult) throws {
        let data = try JSONEncoder.sorted.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func operation(_ arguments: [String]) -> String {
        arguments.contains("--smoke") ? "smoke" : arguments.contains("--benchmark") ? "benchmark" : arguments.contains("--bootstrap-legacy") ? "bootstrap-legacy" : arguments.contains("--fail-migration-stage") ? "fail-migration-stage" : arguments.contains("--fail-migration-promotion") ? "fail-migration-promotion" : arguments.contains("--crash-after-stage-verify") ? "crash-after-stage-verify" : arguments.contains("--migrate") ? "migrate" : arguments.contains("--write-mutated") ? "write-mutated" : arguments.contains("--crash-before-commit") ? "crash-before-commit" : arguments.contains("--bootstrap") ? "bootstrap" : "open"
    }

    private static func defaultRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentIslandSQLCipherSpike", isDirectory: true)
    }

    /// The account is an installation identity, not a predictable app-wide
    /// constant. If its non-secret marker vanished while protected bytes still
    /// exist, opening fails rather than creating a new key identity.
    private static func installationAccount(root: URL) throws -> String {
        let marker = root.appendingPathComponent("installation-id")
        if let account = try? String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty {
            return account
        }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("protected-store.db").path) {
            throw ProtectedStoreFailure.missingKeychainKey
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let account = "ab117-install-\(UUID().uuidString.lowercased())"
        try Data(account.utf8).write(to: marker, options: .atomic)
        return account
    }

    private static func mutatedFixture() -> [FixtureRecord] {
        RepresentativeFixture.records.map {
            FixtureRecord(sourceID: $0.sourceID, ordinal: $0.ordinal, kind: $0.kind, state: "mutated", project: $0.project, product: $0.product, host: $0.host, childRunCount: $0.childRunCount)
        }
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return encoder }
}
