import Foundation
import XCTest
@testable import LocalProductDiscovery

final class LocalProductDiscoveryTests: XCTestCase {
    func testCandidateOrderSkipsSparseAndRelativePATHComponents() {
        let candidates = LocalProductInstallationCandidates(
            environment: ["PATH": "relative::/first:/second:"],
            homeDirectory: "/person"
        ).candidates(for: .claudeCode)

        XCTAssertEqual(Array(candidates.prefix(2)).map(\.path), ["/first/claude", "/second/claude"])
        XCTAssertEqual(Array(candidates.prefix(2)).map(\.source), [.path, .path])
        XCTAssertEqual(candidates.dropFirst(2).first, .init(path: "/person/.local/bin/claude", source: .userLocal))
        XCTAssertTrue(candidates.contains(.init(path: "/person/.claude/local/claude", source: .claudeLocal)))
    }

    func testParserRequiresProductIdentityAndVersionForEachProduct() {
        XCTAssertEqual(ProductCLIVersionParser.verify(product: .claudeCode, stdout: "Claude Code 1.2.3", stderr: ""), .verified(version: "1.2.3"))
        XCTAssertEqual(ProductCLIVersionParser.verify(product: .claudeCode, stdout: "2.1.205 (Claude Code)", stderr: ""), .verified(version: "2.1.205"))
        XCTAssertEqual(ProductCLIVersionParser.verify(product: .codexCLI, stdout: "codex-cli 0.44.1", stderr: ""), .verified(version: "0.44.1"))
        XCTAssertEqual(ProductCLIVersionParser.verify(product: .cursor, stdout: "0.48.0\nCursor command line", stderr: ""), .verified(version: "0.48.0"))
        XCTAssertEqual(ProductCLIVersionParser.verify(product: .cursor, stdout: "0.48.0\n0123456789abcdef0123456789abcdef01234567\narm64", stderr: ""), .verified(version: "0.48.0"))
        XCTAssertEqual(ProductCLIVersionParser.verify(product: .cursor, stdout: "0.48.0\nanything\narm64", stderr: ""), .unverified(reason: .identityMismatch))
        XCTAssertEqual(ProductCLIVersionParser.verify(product: .cursor, stdout: "0.48.0", stderr: ""), .unverified(reason: .identityMismatch))
        XCTAssertEqual(ProductCLIVersionParser.verify(product: .claudeCode, stdout: "claude", stderr: ""), .unverified(reason: .missingVersion))
        XCTAssertEqual(ProductCLIVersionParser.verify(product: .codexCLI, stdout: "cursor 1.0.0", stderr: ""), .unverified(reason: .identityMismatch))
    }

    func testCanonicalDedupAndInvalidEarlierCandidateDoNotBlockLaterVerification() async {
        let candidates = CandidateProvider([
            .claudeCode: [
                .init(path: "/first", source: .path),
                .init(path: "/same-alias", source: .homebrew),
                .init(path: "/later", source: .userLocal),
            ],
        ])
        let inspector = Inspector(["/first": "/canonical/first", "/same-alias": "/canonical/first", "/later": "/canonical/later"])
        let probe = Probe([
            "/canonical/first": .completed(exitCode: 0, stdout: "claude", stderr: ""),
            "/canonical/later": .completed(exitCode: 0, stdout: "claude 1.2.3", stderr: ""),
        ])
        let detector = LocalProductInstallationDetector(candidateProvider: candidates, executableInspector: inspector, probe: probe, originCatalog: Catalog(), originAttestor: Attestor())

        let result = await detector.detect(product: .claudeCode, explicitPath: nil)
        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.evidence?.path, "/later")
        XCTAssertEqual(result.evidence?.canonicalPath, "/canonical/later")
        XCTAssertEqual(await probe.paths(), ["/canonical/first", "/canonical/later"])
    }

    func testPresentUnverifiedNotFoundAndExplicitTargetDoesNotFallBack() async {
        let candidates = CandidateProvider([.codexCLI: [.init(path: "/normal", source: .path)]])
        let inspector = Inspector(["/normal": "/normal", "/chosen": "/chosen"])
        let probe = Probe([
            "/normal": .completed(exitCode: 1, stdout: "codex 1.0.0", stderr: ""),
            "/chosen": .completed(exitCode: 0, stdout: "claude 1.0.0", stderr: ""),
        ])
        let detector = LocalProductInstallationDetector(candidateProvider: candidates, executableInspector: inspector, probe: probe, originCatalog: Catalog(), originAttestor: Attestor())

        let unverified = await detector.detect(product: .codexCLI, explicitPath: nil)
        XCTAssertEqual(unverified.status, .presentUnverified)
        XCTAssertEqual(unverified.evidence?.reason, .nonZeroExit)

        let explicit = await detector.detect(product: .codexCLI, explicitPath: "/chosen")
        XCTAssertEqual(explicit.status, .presentUnverified)
        XCTAssertEqual(explicit.evidence?.source, .explicitPath)
        XCTAssertEqual(explicit.evidence?.reason, .identityMismatch)

        let missing = await LocalProductInstallationDetector(candidateProvider: candidates, executableInspector: Inspector([:]), probe: probe).detect(product: .cursor, explicitPath: nil)
        XCTAssertEqual(missing.status, .notFound)
        XCTAssertNil(missing.evidence)
    }

    func testProbeCapsOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("local-product-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("noisy")
        try "#!/bin/sh\nwhile :; do printf 0123456789; done\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let result = await LocalProductCLIProbe(timeout: 1, maxOutputBytes: 1024).probeVersion(at: script.path)
        XCTAssertEqual(result, .outputLimitExceeded)
    }

    func testCanonicalAliasesDoNotCreateInstallationAmbiguity() async {
        let identity = executableIdentity("same")
        let detector = LocalProductInstallationDetector(
            candidateProvider: CandidateProvider([.codexCLI: [.init(path: "/alias-a", source: .path), .init(path: "/alias-b", source: .homebrew)]]),
            executableInspector: DetailedInspector(["/alias-a": .init(canonicalPath: "/trusted/codex", identity: identity, isPathSafeForInstallation: true), "/alias-b": .init(canonicalPath: "/trusted/codex", identity: identity, isPathSafeForInstallation: true)]),
            probe: Probe(["/trusted/codex": .completed(exitCode: 0, stdout: "codex-cli 1.2.3", stderr: "")]),
            originCatalog: Catalog(),
            originAttestor: Attestor()
        )

        let result = await detector.verifyInstallationIdentity(product: .codexCLI)
        guard case .verified(let verified) = result else { return XCTFail("expected verified identity") }
        XCTAssertEqual(verified.canonicalPath, "/trusted/codex")
    }

    func testDistinctVerifiedCandidatesAreAmbiguousAndCannotBeInstallationTarget() async {
        let detector = LocalProductInstallationDetector(
            candidateProvider: CandidateProvider([.claudeCode: [.init(path: "/one", source: .path), .init(path: "/two", source: .usrBin)]]),
            executableInspector: DetailedInspector([
                "/one": .init(canonicalPath: "/one", identity: executableIdentity("one"), isPathSafeForInstallation: true),
                "/two": .init(canonicalPath: "/two", identity: executableIdentity("two"), isPathSafeForInstallation: true),
            ]),
            probe: Probe([
                "/one": .completed(exitCode: 0, stdout: "claude 1.2.3", stderr: ""),
                "/two": .completed(exitCode: 0, stdout: "Claude Code 1.2.4", stderr: ""),
            ]),
            originCatalog: Catalog(),
            originAttestor: Attestor()
        )

        let readOnly = await detector.detect(product: .claudeCode, explicitPath: nil)
        XCTAssertEqual(readOnly.status, .ambiguous)
        XCTAssertEqual(readOnly.evidence?.reason, .ambiguousCandidates)
        let installation = await detector.verifyInstallationIdentity(product: .claudeCode)
        XCTAssertEqual(installation, .unavailable(reason: .ambiguousCandidates))
    }

    func testWritableOrUnsanitizedCandidateCannotBecomeTrustedIdentity() async {
        let detector = LocalProductInstallationDetector(
            candidateProvider: CandidateProvider([.codexCLI: [.init(path: "/writable/codex", source: .path), .init(path: "/bad\npath", source: .path)]]),
            executableInspector: DetailedInspector(["/writable/codex": .init(canonicalPath: "/writable/codex", identity: executableIdentity("writable"), isPathSafeForInstallation: false)]),
            probe: Probe(["/writable/codex": .completed(exitCode: 0, stdout: "codex 1.2.3", stderr: "")]),
            originCatalog: Catalog(),
            originAttestor: Attestor()
        )

        let installation = await detector.verifyInstallationIdentity(product: .codexCLI)
        XCTAssertEqual(installation, .unavailable(reason: .unsafePath))
    }

    func testRevalidationDetectsExecutableReplacement() async {
        let initial = executableIdentity("before")
        let replacement = executableIdentity("after")
        let inspector = MutableInspector(.init(canonicalPath: "/trusted/codex", identity: initial, isPathSafeForInstallation: true))
        let detector = LocalProductInstallationDetector(
            candidateProvider: CandidateProvider([.codexCLI: [.init(path: "/trusted/codex", source: .usrBin)]]),
            executableInspector: inspector,
            probe: Probe(["/trusted/codex": .completed(exitCode: 0, stdout: "codex-cli 1.2.3", stderr: "")]),
            originCatalog: Catalog(),
            originAttestor: Attestor()
        )
        guard case .verified(let identity) = await detector.verifyInstallationIdentity(product: .codexCLI) else { return XCTFail("expected verified identity") }
        XCTAssertEqual(detector.revalidateInstallationIdentity(identity), .valid)

        inspector.file = .init(canonicalPath: "/trusted/codex", identity: replacement, isPathSafeForInstallation: true)
        XCTAssertEqual(detector.revalidateInstallationIdentity(identity), .replaced)
    }

    func testReviewedOriginCatalogAcceptsOnlyCanonicalOfficialLayouts() {
        let catalog = DocumentedProductInstallationOriginCatalog()
        let accepted: [(ProductCLI, String)] = [
            (.claudeCode, "/opt/homebrew/Caskroom/claude-code/1.2.3/claude"),
            (.codexCLI, "/opt/homebrew/Caskroom/codex/0.44.1/codex-aarch64-apple-darwin"),
            (.cursor, "/Applications/Cursor.app/Contents/Resources/app/bin/code"),
            (.cursor, "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"),
        ]
        for (product, path) in accepted {
            let executable = ProductExecutableFile(canonicalPath: path)
            XCTAssertEqual(catalog.requiredRule(for: product, candidate: .init(path: path, source: .path), executable: executable), .codeSignature, path)
        }

        let arbitrary = "/Users/person/bin/claude"
        XCTAssertNil(catalog.requiredRule(for: .claudeCode, candidate: .init(path: arbitrary, source: .path), executable: .init(canonicalPath: arbitrary)))
        let unsupportedCodexArchitecture = "/opt/homebrew/Caskroom/codex/0.44.1/codex-x86_64-apple-darwin"
        XCTAssertNil(catalog.requiredRule(for: .codexCLI, candidate: .init(path: unsupportedCodexArchitecture, source: .path), executable: .init(canonicalPath: unsupportedCodexArchitecture)))
    }

    func testReviewedOriginAttestorRequiresExpectedSignatureAtReviewedLocation() {
        let claudePath = "/opt/homebrew/Caskroom/claude-code/1.2.3/claude"
        let codexPath = "/opt/homebrew/Caskroom/codex/0.44.1/codex-aarch64-apple-darwin"
        let cursorPath = "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
        let attestor = ReviewedProductInstallationOriginAttestor(signatureInspector: SignatureInspector([
            claudePath: .init(identifier: "com.anthropic.claude-code", teamIdentifier: "Q6L2SF6YDW"),
            codexPath: .init(identifier: "codex", teamIdentifier: "2DC432GLL2"),
            "/Applications/Cursor.app": .init(identifier: "com.todesktop.230313mzl4w4u92", teamIdentifier: "VDXQ22DGB9"),
        ]))

        XCTAssertEqual(
            attestor.attest(product: .claudeCode, candidate: .init(path: claudePath, source: .homebrew), executable: .init(canonicalPath: claudePath), requiredRule: .codeSignature),
            .init(rule: .codeSignature, identifier: "reviewed-code-signature-v1:claude-code:com.anthropic.claude-code:Q6L2SF6YDW")
        )
        XCTAssertEqual(
            attestor.attest(product: .codexCLI, candidate: .init(path: codexPath, source: .homebrew), executable: .init(canonicalPath: codexPath), requiredRule: .codeSignature),
            .init(rule: .codeSignature, identifier: "reviewed-code-signature-v1:codex:codex:2DC432GLL2")
        )
        XCTAssertEqual(
            attestor.attest(product: .cursor, candidate: .init(path: cursorPath, source: .cursorApplications), executable: .init(canonicalPath: cursorPath), requiredRule: .codeSignature),
            .init(rule: .codeSignature, identifier: "reviewed-code-signature-v1:cursor:com.todesktop.230313mzl4w4u92:VDXQ22DGB9")
        )

        let arbitraryPath = "/Users/person/bin/claude"
        XCTAssertNil(attestor.attest(product: .claudeCode, candidate: .init(path: arbitraryPath, source: .path), executable: .init(canonicalPath: arbitraryPath), requiredRule: .codeSignature))
        let wrongSignature = ReviewedProductInstallationOriginAttestor(signatureInspector: SignatureInspector([
            claudePath: .init(identifier: "com.attacker.claude", teamIdentifier: "Q6L2SF6YDW"),
        ]))
        XCTAssertNil(wrongSignature.attest(product: .claudeCode, candidate: .init(path: claudePath, source: .homebrew), executable: .init(canonicalPath: claudePath), requiredRule: .codeSignature))
    }
}

private func executableIdentity(_ marker: String) -> ProductExecutableFileIdentity {
    .init(device: 1, inode: UInt64(truncatingIfNeeded: marker.hashValue), size: 42, modificationSeconds: 1, modificationNanoseconds: 2, contentSHA256: marker)
}

private struct CandidateProvider: ProductInstallationCandidateProviding {
    let values: [ProductCLI: [ProductInstallationCandidate]]
    init(_ values: [ProductCLI: [ProductInstallationCandidate]]) { self.values = values }
    func candidates(for product: ProductCLI) -> [ProductInstallationCandidate] { values[product] ?? [] }
}

private struct Inspector: ProductExecutableInspecting {
    let values: [String: String]
    init(_ values: [String: String]) { self.values = values }
    func executable(at path: String) -> ProductExecutableFile? {
        values[path].map { ProductExecutableFile(canonicalPath: $0, identity: executableIdentity($0), isPathSafeForInstallation: true) }
    }
}

private struct DetailedInspector: ProductExecutableInspecting {
    let values: [String: ProductExecutableFile]
    init(_ values: [String: ProductExecutableFile]) { self.values = values }
    func executable(at path: String) -> ProductExecutableFile? { values[path] }
}

private final class MutableInspector: ProductExecutableInspecting, @unchecked Sendable {
    var file: ProductExecutableFile
    init(_ file: ProductExecutableFile) { self.file = file }
    func executable(at path: String) -> ProductExecutableFile? { path == file.canonicalPath ? file : nil }
}

private struct Catalog: ProductInstallationOriginCataloging {
    func requiredRule(for product: ProductCLI, candidate: ProductInstallationCandidate, executable: ProductExecutableFile) -> ProductInstallationOriginRule? { .externalAttestation }
}

private struct Attestor: ProductInstallationOriginAttesting {
    func attest(product: ProductCLI, candidate: ProductInstallationCandidate, executable: ProductExecutableFile, requiredRule: ProductInstallationOriginRule) -> ProductInstallationOrigin? {
        .init(rule: requiredRule, identifier: "test-attestation")
    }
}

private struct SignatureInspector: ProductCodeSignatureInspecting {
    let signatures: [String: ProductCodeSignature]
    init(_ signatures: [String: ProductCodeSignature]) { self.signatures = signatures }
    func signature(at path: String) -> ProductCodeSignature? { signatures[path] }
}

private actor Probe: ProductCLIProbing {
    let values: [String: ProductCLIProbeResult]
    private var invoked: [String] = []
    init(_ values: [String: ProductCLIProbeResult]) { self.values = values }
    func probeVersion(at executable: String) async -> ProductCLIProbeResult {
        invoked.append(executable)
        return values[executable] ?? .launchFailed
    }
    func paths() -> [String] { invoked }
}
