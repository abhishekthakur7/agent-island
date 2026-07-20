import Foundation
import Darwin
import CryptoKit
import Security

/// The documented command-line entry points that Agent Island may inspect.
/// Discovery is evidence only: it never changes an Agent Product or infers
/// whether an integration is configured or healthy.
public enum ProductCLI: String, CaseIterable, Codable, Hashable, Sendable {
    case claudeCode
    case codexCLI
    case cursor

    public var executableName: String {
        switch self {
        case .claudeCode: "claude"
        case .codexCLI: "codex"
        case .cursor: "cursor"
        }
    }
}

public enum ProductInstallationStatus: String, Codable, Hashable, Sendable {
    case verified
    case presentUnverified
    case notFound
    /// More than one distinct executable reported a valid product version.
    /// Read-only presentation may report this state, but it is never a target
    /// selection for an Integration Installation.
    case ambiguous
}

public enum ProductInstallationSource: String, Codable, Hashable, Sendable {
    case explicitPath
    case path
    case userLocal
    case claudeLocal
    case homebrew
    case usrLocal
    case usrBin
    case cursorApplications
    case cursorUserApplications
}

public enum ProductInstallationReason: String, Codable, Hashable, Sendable {
    case launchFailed
    case nonZeroExit
    case timedOut
    case cancelled
    case outputLimitExceeded
    case identityMismatch
    case missingVersion
    case ambiguousCandidates
    case unsafePath
    case untrustedOrigin
    case identityUnavailable
    case identityChanged
}

/// Path evidence for one executable candidate. `path` preserves the candidate
/// location; `canonicalPath` follows symlinks and is used for deduplication.
public struct ProductInstallationEvidence: Codable, Hashable, Sendable {
    public let path: String
    public let canonicalPath: String
    public let source: ProductInstallationSource
    public let version: String?
    public let reason: ProductInstallationReason?

    public init(path: String, canonicalPath: String, source: ProductInstallationSource, version: String? = nil, reason: ProductInstallationReason? = nil) {
        self.path = path
        self.canonicalPath = canonicalPath
        self.source = source
        self.version = version
        self.reason = reason
    }
}

public struct ProductInstallationResult: Codable, Hashable, Sendable {
    public let product: ProductCLI
    public let status: ProductInstallationStatus
    public let evidence: ProductInstallationEvidence?

    public init(product: ProductCLI, status: ProductInstallationStatus, evidence: ProductInstallationEvidence? = nil) {
        self.product = product
        self.status = status
        self.evidence = evidence
    }
}

/// Stable filesystem facts captured for one executable at discovery time.
/// `contentSHA256` complements inode metadata so revalidation detects both a
/// replacement and an in-place modification.
public struct ProductExecutableFileIdentity: Codable, Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let size: UInt64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int64
    public let contentSHA256: String

    public init(device: UInt64, inode: UInt64, size: UInt64, modificationSeconds: Int64, modificationNanoseconds: Int64, contentSHA256: String) {
        self.device = device
        self.inode = inode
        self.size = size
        self.modificationSeconds = modificationSeconds
        self.modificationNanoseconds = modificationNanoseconds
        self.contentSHA256 = contentSHA256
    }
}

/// The policy rule that supplied origin provenance for an installation-grade
/// executable. A pathname catalog alone is not attestation.
public enum ProductInstallationOriginRule: String, Codable, Hashable, Sendable {
    case codeSignature
    case externalAttestation
}

public struct ProductInstallationOrigin: Codable, Hashable, Sendable {
    public let rule: ProductInstallationOriginRule
    public let identifier: String

    public init(rule: ProductInstallationOriginRule, identifier: String) {
        self.rule = rule
        self.identifier = identifier
    }
}

/// Immutable evidence required to hand an executable to installation code.
/// It is deliberately separate from `ProductInstallationEvidence`, which is
/// useful for read-only UI presence reporting but is not authority to install.
public struct VerifiedProductIdentity: Codable, Hashable, Sendable {
    public let product: ProductCLI
    public let canonicalPath: String
    public let fileIdentity: ProductExecutableFileIdentity
    public let version: String
    public let source: ProductInstallationSource
    public let origin: ProductInstallationOrigin

    public init(product: ProductCLI, canonicalPath: String, fileIdentity: ProductExecutableFileIdentity, version: String, source: ProductInstallationSource, origin: ProductInstallationOrigin) {
        self.product = product
        self.canonicalPath = canonicalPath
        self.fileIdentity = fileIdentity
        self.version = version
        self.source = source
        self.origin = origin
    }
}

public enum ProductInstallationIdentityResult: Hashable, Sendable {
    case verified(VerifiedProductIdentity)
    case unavailable(reason: ProductInstallationReason)
}

public enum ProductIdentityRevalidationResult: Hashable, Sendable {
    case valid
    case unavailable
    case replaced
}

public protocol ProductInstallationDetecting: Sendable {
    func detectAll() async -> [ProductInstallationResult]
    /// When supplied, `explicitPath` is validated as the selected target only;
    /// it does not silently fall back to another installation.
    func detect(product: ProductCLI, explicitPath: String?) async -> ProductInstallationResult
}

/// Opt-in extension for callers that need an executable as an installation
/// target rather than read-only product-presence evidence.
public protocol ProductInstallationIdentityVerifying: ProductInstallationDetecting {
    func verifyInstallationIdentity(product: ProductCLI, explicitPath: String?) async -> ProductInstallationIdentityResult
    func revalidateInstallationIdentity(_ identity: VerifiedProductIdentity) -> ProductIdentityRevalidationResult
}

public struct ProductInstallationCandidate: Hashable, Sendable {
    public let path: String
    public let source: ProductInstallationSource

    public init(path: String, source: ProductInstallationSource) {
        self.path = path
        self.source = source
    }
}

public struct ProductExecutableFile: Hashable, Sendable {
    public let canonicalPath: String
    /// Nil means that this candidate remains available for read-only presence
    /// reporting, but cannot be used as an Integration Installation target.
    public let identity: ProductExecutableFileIdentity?
    /// Whether the current account can write the executable or a canonical
    /// ancestor. This is a separate fact because a stat/hash cannot prove
    /// that a pathname is not replaceable.
    public let isPathSafeForInstallation: Bool

    public init(canonicalPath: String, identity: ProductExecutableFileIdentity? = nil, isPathSafeForInstallation: Bool = false) {
        self.canonicalPath = canonicalPath
        self.identity = identity
        self.isPathSafeForInstallation = isPathSafeForInstallation
    }
}

public protocol ProductInstallationCandidateProviding: Sendable {
    func candidates(for product: ProductCLI) -> [ProductInstallationCandidate]
}

public protocol ProductExecutableInspecting: Sendable {
    /// Returns only executable regular files. A symlink is accepted only when
    /// its resolved destination is such a file.
    func executable(at path: String) -> ProductExecutableFile?
}

public enum ProductCLIProbeResult: Hashable, Sendable {
    case completed(exitCode: Int32, stdout: String, stderr: String)
    case launchFailed
    case timedOut
    case cancelled
    case outputLimitExceeded
}

public protocol ProductCLIProbing: Sendable {
    /// Runs the candidate directly with the fixed `--version` argument.
    func probeVersion(at executable: String) async -> ProductCLIProbeResult
}

/// Catalogues the paths whose origin needs independent attestation. This
/// intentionally does not declare an executable trusted merely because it is
/// in a documented location.
public protocol ProductInstallationOriginCataloging: Sendable {
    func requiredRule(for product: ProductCLI, candidate: ProductInstallationCandidate, executable: ProductExecutableFile) -> ProductInstallationOriginRule?
}

/// Supplies provenance for a catalogued executable. Callers can inject a
/// narrower or fixture attestor, while the detector defaults to the reviewed
/// native code-signature attestor below.
public protocol ProductInstallationOriginAttesting: Sendable {
    func attest(product: ProductCLI, candidate: ProductInstallationCandidate, executable: ProductExecutableFile, requiredRule: ProductInstallationOriginRule) -> ProductInstallationOrigin?
}

public struct DocumentedProductInstallationOriginCatalog: ProductInstallationOriginCataloging {
    public init() {}

    public func requiredRule(for product: ProductCLI, candidate: ProductInstallationCandidate, executable: ProductExecutableFile) -> ProductInstallationOriginRule? {
        ReviewedProductOriginLayout.matching(product: product, canonicalPath: executable.canonicalPath) == nil ? nil : .codeSignature
    }
}

/// The identity facts extracted from a cryptographically valid code signature.
/// The signature checker deliberately receives a pathname rather than a
/// candidate so the reviewed attestor can require an enclosing app signature
/// for bundle-provided command shims.
public struct ProductCodeSignature: Hashable, Sendable {
    public let identifier: String
    public let teamIdentifier: String

    public init(identifier: String, teamIdentifier: String) {
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
    }
}

public protocol ProductCodeSignatureInspecting: Sendable {
    /// Returns identity only after the code at `path` passes macOS code-signature
    /// validity checking. It returns nil for unsigned, invalid, or unreadable code.
    func signature(at path: String) -> ProductCodeSignature?
}

/// Production code-signature inspection using Security.framework. This avoids
/// a shell and makes the signature check independently injectable in tests.
public struct SecurityProductCodeSignatureInspector: ProductCodeSignatureInspecting {
    public init() {}

    public func signature(at path: String) -> ProductCodeSignature? {
        guard let sanitized = ProductInstallationPathSanitizer.candidatePath(path) else { return nil }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: sanitized) as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess else { return nil }
        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation) == errSecSuccess,
              let signingInformation,
              let identifier = (signingInformation as NSDictionary).object(forKey: kSecCodeInfoIdentifier) as? String,
              let teamIdentifier = (signingInformation as NSDictionary).object(forKey: kSecCodeInfoTeamIdentifier) as? String else { return nil }
        return .init(identifier: identifier, teamIdentifier: teamIdentifier)
    }
}

/// Attests only the reviewed, canonical Product layouts. The resulting value
/// contains public signature identity and a reviewed-layout revision, so it is
/// stable and can be checked again before an Integration Installation write.
public struct ReviewedProductInstallationOriginAttestor: ProductInstallationOriginAttesting {
    private let signatureInspector: any ProductCodeSignatureInspecting

    public init(signatureInspector: any ProductCodeSignatureInspecting = SecurityProductCodeSignatureInspector()) {
        self.signatureInspector = signatureInspector
    }

    public func attest(product: ProductCLI, candidate: ProductInstallationCandidate, executable: ProductExecutableFile, requiredRule: ProductInstallationOriginRule) -> ProductInstallationOrigin? {
        guard requiredRule == .codeSignature,
              let layout = ReviewedProductOriginLayout.matching(product: product, canonicalPath: executable.canonicalPath),
              signatureInspector.signature(at: layout.signaturePath) == layout.expectedSignature else { return nil }
        return .init(rule: .codeSignature, identifier: layout.attestationIdentifier)
    }
}

/// Retained for callers that explicitly want a fail-closed, unavailable
/// attestor instead of the reviewed production implementation.
public struct UnavailableProductInstallationOriginAttestor: ProductInstallationOriginAttesting {
    public init() {}
    public func attest(product: ProductCLI, candidate: ProductInstallationCandidate, executable: ProductExecutableFile, requiredRule: ProductInstallationOriginRule) -> ProductInstallationOrigin? { nil }
}

private enum ReviewedProductOriginLayout {
    case claudeCode(executablePath: String)
    case codexCLI(executablePath: String)
    case cursor(appPath: String)

    static func matching(product: ProductCLI, canonicalPath: String) -> Self? {
        let components = canonicalPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        switch product {
        case .claudeCode:
            guard components.count == 6,
                  components[0...3].elementsEqual(["opt", "homebrew", "Caskroom", "claude-code"]),
                  !components[4].isEmpty,
                  components[5] == "claude" else { return nil }
            return .claudeCode(executablePath: canonicalPath)
        case .codexCLI:
            guard components.count == 6,
                  components[0...3].elementsEqual(["opt", "homebrew", "Caskroom", "codex"]),
                  !components[4].isEmpty,
                  components[5] == "codex-aarch64-apple-darwin" else { return nil }
            return .codexCLI(executablePath: canonicalPath)
        case .cursor:
            guard components == ["Applications", "Cursor.app", "Contents", "Resources", "app", "bin", "code"] ||
                    components == ["Applications", "Cursor.app", "Contents", "Resources", "app", "bin", "cursor"] else { return nil }
            return .cursor(appPath: "/Applications/Cursor.app")
        }
    }

    var signaturePath: String {
        switch self {
        case .claudeCode(let path), .codexCLI(let path): path
        case .cursor(let appPath): appPath
        }
    }

    var expectedSignature: ProductCodeSignature {
        switch self {
        case .claudeCode:
            .init(identifier: "com.anthropic.claude-code", teamIdentifier: "Q6L2SF6YDW")
        case .codexCLI:
            .init(identifier: "codex", teamIdentifier: "2DC432GLL2")
        case .cursor:
            .init(identifier: "com.todesktop.230313mzl4w4u92", teamIdentifier: "VDXQ22DGB9")
        }
    }

    var attestationIdentifier: String {
        switch self {
        case .claudeCode:
            "reviewed-code-signature-v1:claude-code:com.anthropic.claude-code:Q6L2SF6YDW"
        case .codexCLI:
            "reviewed-code-signature-v1:codex:codex:2DC432GLL2"
        case .cursor:
            "reviewed-code-signature-v1:cursor:com.todesktop.230313mzl4w4u92:VDXQ22DGB9"
        }
    }
}

public enum ProductCLIVersionVerification: Hashable, Sendable {
    case verified(version: String)
    case unverified(reason: ProductInstallationReason)
}

/// Strict, product-specific parsing for direct `--version` output.
public enum ProductCLIVersionParser {
    public static func verify(product: ProductCLI, stdout: String, stderr: String) -> ProductCLIVersionVerification {
        let output = stdout + "\n" + stderr
        switch product {
        case .claudeCode:
            let named = verifyLine(output, expression: #"(?im)^\s*claude(?:\s+code)?\s+v?([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][0-9a-z.-]+)?)\s*$"#)
            if case .verified = named { return named }
            // Current signed Homebrew Cask releases print this documented
            // product marker rather than placing the name before the version.
            return verifyLine(output, expression: #"(?im)^\s*v?([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][0-9a-z.-]+)?)\s+\(claude\s+code\)\s*$"#)
        case .codexCLI:
            return verifyLine(output, expression: #"(?im)^\s*codex(?:-cli)?\s+v?([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][0-9a-z.-]+)?)\s*$"#)
        case .cursor:
            if isOfficialCursorMultiline(output), let version = output.split(whereSeparator: \.isNewline).first.flatMap({ wholeSemanticVersion(in: String($0)) }) {
                return .verified(version: version)
            }
            if let version = cursorCommandLineVersion(in: output) {
                return .verified(version: version)
            }
            return verifyLine(output, expression: #"(?im)^\s*cursor(?:\s+(?:command\s+line|cli))?\s+v?([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][0-9a-z.-]+)?)\s*$"#)
        }
    }

    private static func verifyLine(_ output: String, expression: String) -> ProductCLIVersionVerification {
        guard let regex = try? NSRegularExpression(pattern: expression), let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)), let range = Range(match.range(at: 1), in: output) else {
            let hasAnyVersion = semanticVersion(in: output) != nil
            return .unverified(reason: hasAnyVersion ? .identityMismatch : .missingVersion)
        }
        return .verified(version: String(output[range]))
    }

    private static func isOfficialCursorMultiline(_ output: String) -> Bool {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard lines.count >= 3, wholeSemanticVersion(in: lines[0]) != nil else { return false }
        let commit = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let architecture = lines[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let commitLooksOfficial = commit.range(of: #"^[0-9a-f]{8,64}$"#, options: .regularExpression) != nil
        return commitLooksOfficial && ["arm64", "x64", "x86_64", "universal"].contains(architecture)
    }

    private static func cursorCommandLineVersion(in output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard lines.count == 2, lines[1].lowercased() == "cursor command line" else { return nil }
        return wholeSemanticVersion(in: lines[0])
    }

    private static func semanticVersion(in text: String) -> String? {
        let expression = #"(?i)(?:^|[^0-9])v?([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][0-9a-z.-]+)?)"#
        return match(expression, in: text)
    }

    private static func wholeSemanticVersion(in text: String) -> String? {
        let expression = #"(?i)^\s*v?([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][0-9a-z.-]+)?)\s*$"#
        return match(expression, in: text)
    }

    private static func match(_ expression: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: expression), let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), result.numberOfRanges > 1, let range = Range(result.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

public struct LocalProductInstallationCandidates: ProductInstallationCandidateProviding {
    private let environment: [String: String]
    private let homeDirectory: String

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, homeDirectory: String = NSHomeDirectory()) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    public func candidates(for product: ProductCLI) -> [ProductInstallationCandidate] {
        let executable = product.executableName
        var candidates = (environment["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: false).compactMap { component -> ProductInstallationCandidate? in
            let directory = String(component)
            guard let directory = ProductInstallationPathSanitizer.directory(directory) else { return nil }
            return .init(path: URL(fileURLWithPath: directory).appendingPathComponent(executable).standardizedFileURL.path, source: .path)
        }
        candidates += [
            .init(path: "\(homeDirectory)/.local/bin/\(executable)", source: .userLocal),
            .init(path: "/opt/homebrew/bin/\(executable)", source: .homebrew),
            .init(path: "/usr/local/bin/\(executable)", source: .usrLocal),
            .init(path: "/usr/bin/\(executable)", source: .usrBin),
        ]
        if product == .claudeCode {
            candidates.append(.init(path: "\(homeDirectory)/.claude/local/claude", source: .claudeLocal))
        }
        if product == .cursor {
            candidates += [
                .init(path: "/Applications/Cursor.app/Contents/Resources/app/bin/cursor", source: .cursorApplications),
                .init(path: "\(homeDirectory)/Applications/Cursor.app/Contents/Resources/app/bin/cursor", source: .cursorUserApplications),
            ]
        }
        // Fixed locations include the account home directory, which is also
        // process-provided input. Apply the same boundary sanitization to all
        // candidates before exposing them to callers.
        return candidates.compactMap { candidate in
            guard let path = ProductInstallationPathSanitizer.candidatePath(candidate.path) else { return nil }
            return .init(path: path, source: candidate.source)
        }
    }
}

public enum ProductInstallationPathSanitizer {
    /// PATH is untrusted process input. Accept only non-empty absolute paths
    /// without control characters, then standardize before any filesystem use.
    public static func candidatePath(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { $0.value <= 0x1F || $0.value == 0x7F }) else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    fileprivate static func directory(_ path: String) -> String? {
        guard let sanitized = candidatePath(path), sanitized != "/" else { return nil }
        return sanitized
    }
}

public struct LocalProductExecutableInspector: ProductExecutableInspecting {
    public init() {}

    public func executable(at path: String) -> ProductExecutableFile? {
        guard let safeInput = ProductInstallationPathSanitizer.candidatePath(path) else { return nil }
        let original = URL(fileURLWithPath: safeInput)
        let resolved = original.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolved.path), FileManager.default.isExecutableFile(atPath: resolved.path),
              (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        let identity = fingerprint(at: resolved.path)
        return .init(canonicalPath: resolved.path, identity: identity, isPathSafeForInstallation: identity != nil && isSafeForInstallation(resolved))
    }

    private func fingerprint(at path: String) -> ProductExecutableFileIdentity? {
        var metadata = stat()
        guard path.withCString({ lstat($0, &metadata) }) == 0, metadata.st_size >= 0, let hash = contentSHA256(at: path) else { return nil }
        return .init(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            size: UInt64(metadata.st_size),
            modificationSeconds: Int64(metadata.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(metadata.st_mtimespec.tv_nsec),
            contentSHA256: hash
        )
    }

    private func contentSHA256(at path: String) -> String? {
        // A CLI executable may be large, but discovery must remain bounded.
        // Current reviewed Cask binaries are larger than 128 MiB. Keep the
        // fingerprint bounded while allowing those installation targets.
        let maximumBytes = 512 * 1024 * 1024
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var total = 0
        while true {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            total += chunk.count
            guard total <= maximumBytes else { return nil }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Cask and application bundles can legitimately be owned by the current
    /// account, so writability alone cannot reject them. Require every resolved
    /// ancestor to be root- or current-user-owned, non-world-writable, and
    /// outside temporary roots. Origin attestation then narrows this general
    /// filesystem fact to reviewed layouts and signatures.
    private func isSafeForInstallation(_ executable: URL) -> Bool {
        guard !isTemporaryPath(executable.path) else { return false }
        let allowedOwners: Set<uid_t> = [0, getuid()]
        var current = executable
        while true {
            var metadata = stat()
            guard current.path.withCString({ lstat($0, &metadata) }) == 0,
                  allowedOwners.contains(metadata.st_uid),
                  metadata.st_mode & mode_t(S_IWOTH) == 0 else { return false }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return true }
            current = parent
        }
    }

    private func isTemporaryPath(_ path: String) -> Bool {
        ["/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp", "/var/folders", "/private/var/folders"].contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }
}

public struct LocalProductCLIProbe: ProductCLIProbing {
    public let timeout: TimeInterval
    public let maxOutputBytes: Int

    public init(timeout: TimeInterval = 2, maxOutputBytes: Int = 64 * 1024) {
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }

    public func probeVersion(at executable: String) async -> ProductCLIProbeResult {
        let execution = ProductVersionProcessExecution(timeout: timeout, maxOutputBytes: maxOutputBytes)
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: execution.run(executable: executable))
                }
            }
        }, onCancel: {
            execution.cancel()
        })
    }
}

/// Production, read-only detector. It keeps PATH ordering, then documented
/// fixed locations. Invalid executable candidates do not stop later checks.
public struct LocalProductInstallationDetector: ProductInstallationIdentityVerifying {
    private let candidateProvider: any ProductInstallationCandidateProviding
    private let executableInspector: any ProductExecutableInspecting
    private let probe: any ProductCLIProbing
    private let originCatalog: any ProductInstallationOriginCataloging
    private let originAttestor: any ProductInstallationOriginAttesting

    public init(
        candidateProvider: any ProductInstallationCandidateProviding = LocalProductInstallationCandidates(),
        executableInspector: any ProductExecutableInspecting = LocalProductExecutableInspector(),
        probe: any ProductCLIProbing = LocalProductCLIProbe(),
        originCatalog: any ProductInstallationOriginCataloging = DocumentedProductInstallationOriginCatalog(),
        originAttestor: any ProductInstallationOriginAttesting = ReviewedProductInstallationOriginAttestor()
    ) {
        self.candidateProvider = candidateProvider
        self.executableInspector = executableInspector
        self.probe = probe
        self.originCatalog = originCatalog
        self.originAttestor = originAttestor
    }

    public func detectAll() async -> [ProductInstallationResult] {
        var results: [ProductInstallationResult] = []
        for product in ProductCLI.allCases {
            results.append(await detect(product: product, explicitPath: nil))
        }
        return results
    }

    public func detect(product: ProductCLI, explicitPath: String? = nil) async -> ProductInstallationResult {
        let candidates: [ProductInstallationCandidate]
        if let explicitPath {
            guard let sanitized = ProductInstallationPathSanitizer.candidatePath(explicitPath) else { return .init(product: product, status: .notFound) }
            candidates = [.init(path: sanitized, source: .explicitPath)]
        } else {
            candidates = candidateProvider.candidates(for: product)
        }

        let evaluation = await evaluate(product: product, candidates: candidates)
        if evaluation.verified.count > 1 {
            let first = evaluation.verified[0]
            return .init(
                product: product,
                status: .ambiguous,
                evidence: .init(path: first.candidate.path, canonicalPath: first.executable.canonicalPath, source: first.candidate.source, version: first.version, reason: .ambiguousCandidates)
            )
        }
        if let verified = evaluation.verified.first {
            return .init(product: product, status: .verified, evidence: .init(path: verified.candidate.path, canonicalPath: verified.executable.canonicalPath, source: verified.candidate.source, version: verified.version))
        }
        return .init(product: product, status: evaluation.firstUnverified == nil ? .notFound : .presentUnverified, evidence: evaluation.firstUnverified)
    }

    /// Produces an immutable identity suitable only for an explicit
    /// Integration Installation handoff. The production default attests only
    /// reviewed canonical paths with the expected code-signature identity.
    public func verifyInstallationIdentity(product: ProductCLI, explicitPath: String? = nil) async -> ProductInstallationIdentityResult {
        let candidates: [ProductInstallationCandidate]
        if let explicitPath {
            guard let sanitized = ProductInstallationPathSanitizer.candidatePath(explicitPath) else { return .unavailable(reason: .identityUnavailable) }
            candidates = [.init(path: sanitized, source: .explicitPath)]
        } else {
            candidates = candidateProvider.candidates(for: product)
        }

        let evaluation = await evaluate(product: product, candidates: candidates)
        guard evaluation.verified.count == 1, let verified = evaluation.verified.first else {
            return .unavailable(reason: evaluation.verified.count > 1 ? .ambiguousCandidates : evaluation.firstUnverified?.reason ?? .identityUnavailable)
        }
        // The direct probe is asynchronous. Inspect once more before creating
        // a handoff identity so a replacement during `--version` fails closed.
        guard let current = executableInspector.executable(at: verified.candidate.path),
              current.canonicalPath == verified.executable.canonicalPath,
              current.identity == verified.executable.identity else { return .unavailable(reason: .identityChanged) }
        guard current.isPathSafeForInstallation else { return .unavailable(reason: .unsafePath) }
        guard let fileIdentity = current.identity else { return .unavailable(reason: .identityUnavailable) }
        guard let requiredRule = originCatalog.requiredRule(for: product, candidate: verified.candidate, executable: current),
              let origin = originAttestor.attest(product: product, candidate: verified.candidate, executable: current, requiredRule: requiredRule) else {
            return .unavailable(reason: .untrustedOrigin)
        }
        return .verified(.init(product: product, canonicalPath: current.canonicalPath, fileIdentity: fileIdentity, version: verified.version, source: verified.candidate.source, origin: origin))
    }

    /// Re-inspects the canonical target and compares every captured stat/hash
    /// fact before a caller performs an installation action.
    public func revalidateInstallationIdentity(_ identity: VerifiedProductIdentity) -> ProductIdentityRevalidationResult {
        guard let executable = executableInspector.executable(at: identity.canonicalPath) else { return .unavailable }
        guard executable.canonicalPath == identity.canonicalPath, executable.identity == identity.fileIdentity else { return .replaced }
        guard executable.isPathSafeForInstallation else { return .replaced }
        let candidate = ProductInstallationCandidate(path: identity.canonicalPath, source: identity.source)
        guard originCatalog.requiredRule(for: identity.product, candidate: candidate, executable: executable) == identity.origin.rule,
              originAttestor.attest(product: identity.product, candidate: candidate, executable: executable, requiredRule: identity.origin.rule) == identity.origin else {
            return .unavailable
        }
        return .valid
    }

    private func evaluate(product: ProductCLI, candidates: [ProductInstallationCandidate]) async -> Evaluation {
        var checkedCanonicalPaths = Set<String>()
        var firstUnverified: ProductInstallationEvidence?
        var verified: [VerifiedCandidate] = []
        candidateLoop: for candidate in candidates {
            guard let sanitized = ProductInstallationPathSanitizer.candidatePath(candidate.path) else { continue }
            let sanitizedCandidate = ProductInstallationCandidate(path: sanitized, source: candidate.source)
            guard let executable = executableInspector.executable(at: sanitizedCandidate.path),
                  ProductInstallationPathSanitizer.candidatePath(executable.canonicalPath) == executable.canonicalPath,
                  checkedCanonicalPaths.insert(executable.canonicalPath).inserted else { continue }
            // Never execute an arbitrary PATH candidate merely to ask its
            // version. Official origin and path safety are prerequisites to
            // direct process launch, not facts inferred from its output.
            guard executable.isPathSafeForInstallation,
                  let requiredRule = originCatalog.requiredRule(for: product, candidate: sanitizedCandidate, executable: executable),
                  originAttestor.attest(product: product, candidate: sanitizedCandidate, executable: executable, requiredRule: requiredRule) != nil else {
                if firstUnverified == nil {
                    firstUnverified = .init(path: sanitizedCandidate.path, canonicalPath: executable.canonicalPath, source: sanitizedCandidate.source, reason: executable.isPathSafeForInstallation ? .untrustedOrigin : .unsafePath)
                }
                continue
            }
            let probeResult = await probe.probeVersion(at: executable.canonicalPath)
            let verification: ProductCLIVersionVerification
            switch probeResult {
            case .completed(let exitCode, let stdout, let stderr):
                verification = exitCode == 0 ? ProductCLIVersionParser.verify(product: product, stdout: stdout, stderr: stderr) : .unverified(reason: .nonZeroExit)
            case .launchFailed: verification = .unverified(reason: .launchFailed)
            case .timedOut: verification = .unverified(reason: .timedOut)
            case .cancelled: verification = .unverified(reason: .cancelled)
            case .outputLimitExceeded: verification = .unverified(reason: .outputLimitExceeded)
            }
            switch verification {
            case .verified(let version):
                verified.append(.init(candidate: sanitizedCandidate, executable: executable, version: version))
            case .unverified(let reason):
                if firstUnverified == nil {
                    firstUnverified = .init(path: sanitizedCandidate.path, canonicalPath: executable.canonicalPath, source: sanitizedCandidate.source, reason: reason)
                }
                if case .cancelled = reason {
                    break candidateLoop
                }
            }
        }
        return .init(verified: verified, firstUnverified: firstUnverified)
    }

    private struct VerifiedCandidate: Sendable {
        let candidate: ProductInstallationCandidate
        let executable: ProductExecutableFile
        let version: String
    }

    private struct Evaluation: Sendable {
        let verified: [VerifiedCandidate]
        let firstUnverified: ProductInstallationEvidence?
    }
}

private final class ProductVersionProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let timeout: TimeInterval
    private let maxOutputBytes: Int
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    private var outputExceeded = false
    private var stdout = Data()
    private var stderr = Data()

    init(timeout: TimeInterval, maxOutputBytes: Int) {
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }

    func cancel() {
        let process: Process?
        lock.lock()
        cancelled = true
        process = self.process
        lock.unlock()
        if let process { terminate(process) }
    }

    func run(executable: String) -> ProductCLIProbeResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        lock.lock()
        if cancelled { lock.unlock(); return .cancelled }
        self.process = process
        lock.unlock()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--version"]
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let executableDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        let runtimePath = ([executableDirectory, inheritedPath, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        process.environment = ["PATH": runtimePath, "LANG": "C", "LC_ALL": "C"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            // Put the version probe in its own group when the kernel still
            // permits it. Timeout/cancellation then cannot leave descendants
            // running; the signal helper safely falls back to the child PID.
            _ = setpgid(process.processIdentifier, process.processIdentifier)
        } catch {
            return .launchFailed
        }

        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            drain(outputPipe.fileHandleForReading, isStandardError: false)
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            drain(errorPipe.fileHandleForReading, isStandardError: true)
            readers.leave()
        }
        let watchdog = DispatchWorkItem { [self] in
            lock.lock()
            guard self.process?.isRunning == true else { lock.unlock(); return }
            timedOut = true
            let running = self.process
            lock.unlock()
            if let running { terminate(running) }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        // A probe may spawn a descendant which inherits these write ends. Do
        // not let such a descendant hold discovery open after the leader has
        // exited or been killed.
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
        _ = readers.wait(timeout: .now() + 0.5)

        lock.lock()
        self.process = nil
        let result: ProductCLIProbeResult
        if cancelled { result = .cancelled }
        else if outputExceeded { result = .outputLimitExceeded }
        else if timedOut { result = .timedOut }
        else { result = .completed(exitCode: process.terminationStatus, stdout: String(decoding: stdout, as: UTF8.self), stderr: String(decoding: stderr, as: UTF8.self)) }
        lock.unlock()
        return result
    }

    private func drain(_ handle: FileHandle, isStandardError: Bool) {
        while true {
            let data = handle.availableData
            guard !data.isEmpty else { return }
            var shouldTerminate = false
            lock.lock()
            let currentSize = stdout.count + stderr.count
            if currentSize + data.count > maxOutputBytes {
                shouldTerminate = !outputExceeded
                outputExceeded = true
            } else if isStandardError {
                stderr.append(data)
            } else {
                stdout.append(data)
            }
            let running = process
            lock.unlock()
            if shouldTerminate, let running { terminate(running) }
        }
    }

    private func terminate(_ process: Process) {
        let pid = process.processIdentifier
        guard pid > 0 else { process.terminate(); return }
        // A negative PID addresses the probe's process group. If setpgid raced
        // with exec and failed, signalling the concrete PID is the fallback.
        _ = Darwin.kill(-pid, SIGTERM)
        _ = Darwin.kill(pid, SIGTERM)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
            // Always signal the group: the leader may have exited while a
            // descendant still owns the probe pipes.
            _ = Darwin.kill(-pid, SIGKILL)
            if process.isRunning { _ = Darwin.kill(pid, SIGKILL) }
        }
    }
}
