import Darwin
import Foundation
import SessionDomain
import XCTest
@testable import AgentIslandApp

final class DurableInstallationFoundationTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-island-installation-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testManifestAndJournalRoundTripInPrivateApplicationSupportDirectory() throws {
        let store = try DurableInstallationStore(applicationSupportDirectory: temporaryDirectory)
        let ownership = OwnershipManifest(
            id: "ownership-1",
            installationID: "install-1",
            product: ProductNamespace("codex"),
            integrationMode: "event-hook",
            scope: IntegrationInstallationScope(kind: .user, identifier: "user", path: "/test/.codex/config.toml"),
            sourcePath: "/test/.codex/config.toml",
            entries: [
                ExactEntryReceipt(
                    selector: ExactEntrySelector(key: "agent-island-hook", renderedLine: "agent-island-hook", marker: "agent-island-hook"),
                    path: "/test/.codex/config.toml",
                    sourceFingerprint: ExactEntrySourceFingerprint(content: ExactEntryFingerprint("source-fingerprint")),
                    createdAt: Date(timeIntervalSince1970: 1)
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let manifest = DurableInstallationManifest(
            installationID: "install-1",
            product: .codex,
            configurationPath: "/test/.codex/config.toml",
            managedEntryIdentifiers: ["agent-island-hook"],
            ownershipManifest: ownership
        )
        let journal = DurableInstallationJournal(
            transactionID: "transaction-1",
            installationID: manifest.installationID,
            phase: .prepared,
            configurationPath: manifest.configurationPath
        )

        try store.withExclusiveLock {
            try store.saveManifest(manifest)
            try store.saveJournal(journal)
        }

        XCTAssertEqual(try store.manifest(installationID: manifest.installationID), manifest)
        XCTAssertEqual(try store.journal(transactionID: journal.transactionID), journal)
        XCTAssertEqual(POSIXFileSafety.mode(try POSIXFileSafety.lstat(store.directory)), 0o700)
    }

    func testLegacyManifestWithoutOwnershipManifestDecodes() throws {
        let data = Data("""
        {
          "schemaVersion": 1,
          "installationID": "install-1",
          "product": "codex",
          "configurationPath": "/test/.codex/config.toml",
          "managedEntryIdentifiers": ["agent-island-hook"],
          "createdAt": "1970-01-01T00:00:01Z",
          "updatedAt": "1970-01-01T00:00:02Z"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest = try decoder.decode(DurableInstallationManifest.self, from: data)

        XCTAssertNil(manifest.ownershipManifest)
        XCTAssertEqual(manifest.installationID, "install-1")
    }

    func testStoreRejectsTraversalInstallationIdentifier() throws {
        let store = try DurableInstallationStore(applicationSupportDirectory: temporaryDirectory)
        let manifest = DurableInstallationManifest(
            installationID: "../outside",
            product: .cursor,
            configurationPath: "/test/.cursor/hooks.json",
            managedEntryIdentifiers: []
        )

        XCTAssertThrowsError(try store.saveManifest(manifest)) { error in
            XCTAssertEqual(error as? DurableInstallationError, .unsafePath("../outside"))
        }
    }

    func testClaudeResolverRejectsJsonAndJsoncAmbiguity() throws {
        let claude = temporaryDirectory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: claude.appendingPathComponent("settings.json").path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: claude.appendingPathComponent("settings.jsonc").path, contents: Data("{}".utf8))

        let resolver = UserInstallationConfigurationResolver(homeDirectory: temporaryDirectory)
        XCTAssertThrowsError(try resolver.resolve(for: .claude)) { error in
            guard case let DurableInstallationError.configurationAmbiguous(paths) = error else {
                return XCTFail("expected ambiguity, got \(error)")
            }
            XCTAssertEqual(paths.count, 2)
        }
    }

    func testResolverUsesExistingCodexTargetAndReportsMissingCursorTarget() throws {
        let codex = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let config = codex.appendingPathComponent("hooks.json")
        FileManager.default.createFile(atPath: config.path, contents: Data("{\"hooks\":{}}".utf8))
        let resolver = UserInstallationConfigurationResolver(homeDirectory: temporaryDirectory)

        XCTAssertEqual(try resolver.resolve(for: .codex), .existing(config))
        XCTAssertEqual(try resolver.resolve(for: .cursor), .missing(temporaryDirectory.appendingPathComponent(".cursor/hooks.json")))
    }

    func testSecureWriterPreservesModeAndRejectsContentDrift() throws {
        let config = temporaryDirectory.appendingPathComponent("config.json")
        FileManager.default.createFile(atPath: config.path, contents: Data("old".utf8))
        XCTAssertEqual(chmod(config.path, 0o640), 0)
        let writer = SecureConfigurationWriter()
        let precondition = try writer.precondition(for: config)

        try writer.replace(Data("new".utf8), at: config, expecting: precondition)
        XCTAssertEqual(try Data(contentsOf: config), Data("new".utf8))
        XCTAssertEqual(POSIXFileSafety.mode(try POSIXFileSafety.lstat(config)), 0o640)

        let stale = try writer.precondition(for: config)
        try Data("someone else".utf8).write(to: config)
        XCTAssertThrowsError(try writer.replace(Data("replacement".utf8), at: config, expecting: stale)) { error in
            XCTAssertEqual(error as? DurableInstallationError, .configurationChanged(config.path))
        }
    }

    func testResolverRejectsSymlinkedConfiguration() throws {
        let codex = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let destination = temporaryDirectory.appendingPathComponent("actual.json")
        FileManager.default.createFile(atPath: destination.path, contents: Data())
        let config = codex.appendingPathComponent("hooks.json")
        XCTAssertEqual(symlink(destination.path, config.path), 0)

        XCTAssertThrowsError(try UserInstallationConfigurationResolver(homeDirectory: temporaryDirectory).resolve(for: .codex)) { error in
            XCTAssertEqual(error as? DurableInstallationError, .invalidFileType(config.path))
        }
    }
}
