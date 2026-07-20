import Foundation

/// A stable, redacted fingerprint of one configuration source.  Fingerprints
/// are evidence only; they are never used to infer ownership of a file.
public struct ExactEntryFingerprint: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// The exact line Agent Island may add or remove.  The editor treats every
/// other byte as opaque, so comments, ordering, unknown keys and formatting
/// survive an installation lifecycle unchanged.
public struct ExactEntrySelector: Codable, Equatable, Hashable, Sendable {
    public let key: String
    public let marker: String
    public let renderedLine: String

    public init(key: String, renderedLine: String, marker: String? = nil) {
        self.key = key
        self.renderedLine = renderedLine
        self.marker = marker ?? "agent-island:\(key)"
    }

    public var fingerprint: ExactEntryFingerprint {
        ExactEntryFingerprint(ExactEntryDigest.value(Data(renderedLine.utf8)))
    }

    public var isLossless: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !marker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !renderedLine.contains("\n") && !renderedLine.contains("\r") &&
            renderedLine.contains(marker)
    }
}

public typealias ExactEntry = ExactEntrySelector

/// The location and state of one source, captured without retaining its whole
/// content in a manifest.
public struct ExactEntrySourceFingerprint: Codable, Equatable, Hashable, Sendable {
    public let content: ExactEntryFingerprint?
    public let symlinkTarget: String?
    public let permissionBits: UInt16?

    public init(content: ExactEntryFingerprint?, symlinkTarget: String? = nil, permissionBits: UInt16? = nil) {
        self.content = content
        self.symlinkTarget = symlinkTarget
        self.permissionBits = permissionBits
    }
}

public struct ExactEntryFileSnapshot: Codable, Equatable, Hashable, Sendable {
    public let path: String
    public let exists: Bool
    public let symlinkTarget: String?
    public let resolvedPath: String?
    public let content: Data?
    public let fingerprint: ExactEntrySourceFingerprint

    public init(path: String, exists: Bool, symlinkTarget: String?, resolvedPath: String?, content: Data?, fingerprint: ExactEntrySourceFingerprint) {
        self.path = path
        self.exists = exists
        self.symlinkTarget = symlinkTarget
        self.resolvedPath = resolvedPath
        self.content = content
        self.fingerprint = fingerprint
    }

    public var sourceFingerprint: ExactEntrySourceFingerprint { fingerprint }
    public var contentFingerprint: ExactEntryFingerprint? { fingerprint.content }
}

public enum ExactEntryInspectionState: String, Codable, Equatable, Hashable, Sendable {
    case notConfigured
    case ownedIntact
    case ownedDrifted
    case externalCandidate
    case shadowedManaged
    case unsupported
    case unavailable
}

public struct ExactEntryInspection: Codable, Equatable, Hashable, Sendable {
    public let state: ExactEntryInspectionState
    public let source: ExactEntryFileSnapshot
    public let matchingEntryCount: Int
    public let reason: ExactEntryFailureReason?

    public init(state: ExactEntryInspectionState, source: ExactEntryFileSnapshot, matchingEntryCount: Int, reason: ExactEntryFailureReason? = nil) {
        self.state = state
        self.source = source
        self.matchingEntryCount = matchingEntryCount
        self.reason = reason
    }
}

public enum ExactEntryFailureReason: String, Codable, Equatable, Hashable, Sendable {
    case sourceChanged
    case symlinkChanged
    case unsupported
    case lossy
    case ambiguous
    case policyDenied
    case unavailable
    case interrupted
    case verificationFailed
    case notManifestProven
}

public enum ExactEntryEditorError: Error, Codable, Equatable, Hashable, Sendable {
    case invalidSelector
    case sourceChanged
    case symlinkChanged
    case unsupported
    case lossy
    case ambiguous
    case policyDenied
    case unavailable
    case interrupted
    case verificationFailed
    case notManifestProven
    case ioFailure
}

public struct ExactEntryWritePolicy: Codable, Equatable, Hashable, Sendable {
    public let allowsMutation: Bool
    public let reason: String?

    public init(allowsMutation: Bool = true, reason: String? = nil) {
        self.allowsMutation = allowsMutation
        self.reason = reason
    }

    public static let allowed = Self()
    public static let denied = Self(allowsMutation: false, reason: "policy")
}

public enum ExactEntryWriteInterruption: String, Codable, Equatable, Hashable, Sendable {
    case none
    case afterTemporaryWrite
    case afterReplace
}

public struct ExactEntryWriteOptions: Codable, Equatable, Hashable, Sendable {
    public let interruption: ExactEntryWriteInterruption
    public let createMissingSource: Bool

    public init(interruption: ExactEntryWriteInterruption = .none, createMissingSource: Bool = true) {
        self.interruption = interruption
        self.createMissingSource = createMissingSource
    }

    public static let normal = Self()
}

/// The receipt persisted by an Ownership Manifest.  It proves one exact line
/// and its post-write evidence, not ownership of the containing file.
public struct ExactEntryReceipt: Codable, Equatable, Hashable, Sendable {
    public let selector: ExactEntrySelector
    public let path: String
    public let sourceFingerprint: ExactEntrySourceFingerprint
    public let entryFingerprint: ExactEntryFingerprint
    public let symlinkTarget: String?
    public let permissionBits: UInt16?
    public let createdAt: Date

    public init(selector: ExactEntrySelector, path: String, sourceFingerprint: ExactEntrySourceFingerprint, entryFingerprint: ExactEntryFingerprint? = nil, symlinkTarget: String? = nil, permissionBits: UInt16? = nil, createdAt: Date = Date()) {
        self.selector = selector
        self.path = path
        self.sourceFingerprint = sourceFingerprint
        self.entryFingerprint = entryFingerprint ?? selector.fingerprint
        self.symlinkTarget = symlinkTarget ?? sourceFingerprint.symlinkTarget
        self.permissionBits = permissionBits ?? sourceFingerprint.permissionBits
        self.createdAt = createdAt
    }
}

public enum ExactEntryDigest {
    /// A deterministic non-content digest. It is deliberately small and
    /// sufficient for change detection; manifests do not claim cryptographic
    /// authenticity or retain source bytes.
    public static func value(_ data: Data) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}

public enum ExactEntryEditor {
    public static func snapshot(at path: String) -> ExactEntryFileSnapshot { snapshot(at: URL(fileURLWithPath: path)) }

    public static func snapshot(at path: URL) -> ExactEntryFileSnapshot {
        let fm = FileManager.default
        let pathString = path.path
        let symlink: String?
        if let value = try? fm.destinationOfSymbolicLink(atPath: pathString) {
            symlink = value
        } else {
            symlink = nil
        }
        let resolved: URL?
        if let symlink {
            resolved = URL(fileURLWithPath: symlink, relativeTo: path.deletingLastPathComponent()).standardizedFileURL
        } else {
            resolved = path.standardizedFileURL
        }
        guard let resolved, fm.fileExists(atPath: resolved.path) else {
            return ExactEntryFileSnapshot(path: pathString, exists: false, symlinkTarget: symlink, resolvedPath: resolved?.path, content: nil, fingerprint: ExactEntrySourceFingerprint(content: nil, symlinkTarget: symlink, permissionBits: nil))
        }
        let content = try? Data(contentsOf: resolved)
        let permissions = (try? fm.attributesOfItem(atPath: resolved.path)[.posixPermissions] as? NSNumber).map { UInt16(truncating: $0) }
        let contentFingerprint = content.map { ExactEntryFingerprint(ExactEntryDigest.value($0)) }
        return ExactEntryFileSnapshot(path: pathString, exists: true, symlinkTarget: symlink, resolvedPath: resolved.path, content: content, fingerprint: ExactEntrySourceFingerprint(content: contentFingerprint, symlinkTarget: symlink, permissionBits: permissions))
    }

    public static func inspect(at path: URL, selector: ExactEntrySelector, receipt: ExactEntryReceipt? = nil) -> ExactEntryInspection {
        guard selector.isLossless else {
            return ExactEntryInspection(state: .unsupported, source: snapshot(at: path), matchingEntryCount: 0, reason: .lossy)
        }
        let source = snapshot(at: path)
        guard source.exists, let data = source.content else {
            if source.symlinkTarget != nil || source.exists { return ExactEntryInspection(state: .unavailable, source: source, matchingEntryCount: 0, reason: .unavailable) }
            return ExactEntryInspection(state: .notConfigured, source: source, matchingEntryCount: 0)
        }
        guard let text = String(data: data, encoding: .utf8), !data.contains(0) else {
            return ExactEntryInspection(state: .unsupported, source: source, matchingEntryCount: 0, reason: .unsupported)
        }
        let count: Int
        if let receipt, receipt.selector.key == selector.key, receipt.selector.marker == selector.marker {
            count = lines(in: text).filter { $0.contains(selector.marker) && ExactEntryDigest.value(Data($0.utf8)) == receipt.entryFingerprint.rawValue }.count
        } else {
            count = lines(in: text).filter { $0 == selector.renderedLine }.count
        }
        if count > 1 {
            return ExactEntryInspection(state: .shadowedManaged, source: source, matchingEntryCount: count, reason: .ambiguous)
        }
        guard count == 1 else {
            // A marker owned by another installation is an external candidate;
            // never adopt it merely because it looks familiar.
            let markerCount = lines(in: text).filter { $0.contains(selector.marker) }.count
            return ExactEntryInspection(state: markerCount > 0 ? .externalCandidate : .notConfigured, source: source, matchingEntryCount: markerCount)
        }
        guard let receipt else {
            return ExactEntryInspection(state: .externalCandidate, source: source, matchingEntryCount: count)
        }
        let state: ExactEntryInspectionState = receipt.sourceFingerprint == source.fingerprint ? .ownedIntact : .ownedDrifted
        return ExactEntryInspection(state: state, source: source, matchingEntryCount: count, reason: state == .ownedDrifted ? .sourceChanged : nil)
    }

    public static func inspect(at path: String, selector: ExactEntrySelector, receipt: ExactEntryReceipt? = nil) -> ExactEntryInspection {
        inspect(at: URL(fileURLWithPath: path), selector: selector, receipt: receipt)
    }

    public static func add(selector: ExactEntrySelector, at path: URL, expected: ExactEntrySourceFingerprint? = nil, policy: ExactEntryWritePolicy = .allowed, options: ExactEntryWriteOptions = .normal, now: Date = Date()) throws -> ExactEntryReceipt {
        try mutate(selector: selector, at: path, expected: expected, policy: policy, options: options, removalReceipt: nil, now: now)
    }

    public static func add(selector: ExactEntrySelector, at path: String, expected: ExactEntrySourceFingerprint? = nil, policy: ExactEntryWritePolicy = .allowed, options: ExactEntryWriteOptions = .normal, now: Date = Date()) throws -> ExactEntryReceipt {
        try add(selector: selector, at: URL(fileURLWithPath: path), expected: expected, policy: policy, options: options, now: now)
    }

    public static func remove(receipt: ExactEntryReceipt, at path: URL, expected: ExactEntrySourceFingerprint? = nil, policy: ExactEntryWritePolicy = .allowed, options: ExactEntryWriteOptions = .normal, now: Date = Date()) throws -> ExactEntryReceipt {
        try mutate(selector: receipt.selector, at: path, expected: expected, policy: policy, options: options, removalReceipt: receipt, now: now)
    }

    public static func remove(receipt: ExactEntryReceipt, at path: String, expected: ExactEntrySourceFingerprint? = nil, policy: ExactEntryWritePolicy = .allowed, options: ExactEntryWriteOptions = .normal, now: Date = Date()) throws -> ExactEntryReceipt {
        try remove(receipt: receipt, at: URL(fileURLWithPath: path), expected: expected, policy: policy, options: options, now: now)
    }

    private static func mutate(selector: ExactEntrySelector, at path: URL, expected: ExactEntrySourceFingerprint?, policy: ExactEntryWritePolicy, options: ExactEntryWriteOptions, removalReceipt: ExactEntryReceipt?, now: Date) throws -> ExactEntryReceipt {
        guard selector.isLossless else { throw ExactEntryEditorError.lossy }
        guard policy.allowsMutation else { throw ExactEntryEditorError.policyDenied }
        let source = snapshot(at: path)
        if let expected, expected != source.fingerprint {
            if expected.symlinkTarget != source.fingerprint.symlinkTarget { throw ExactEntryEditorError.symlinkChanged }
            throw ExactEntryEditorError.sourceChanged
        }
        let currentText: String
        if source.exists {
            guard let data = source.content else { throw ExactEntryEditorError.unavailable }
            guard !data.contains(0), let decoded = String(data: data, encoding: .utf8) else { throw ExactEntryEditorError.unsupported }
            currentText = decoded
        } else {
            guard options.createMissingSource else { throw ExactEntryEditorError.unavailable }
            currentText = ""
        }
        let currentLines = lines(in: currentText)
        let markerMatches = currentLines.filter { $0.contains(selector.marker) }.count
        let next: Data
        if let removalReceipt {
            guard markerMatches == 1, removalReceipt.selector.key == selector.key, removalReceipt.selector.marker == selector.marker else { throw ExactEntryEditorError.notManifestProven }
            let lineToRemove: String
            if removalReceipt.entryFingerprint.rawValue == selector.fingerprint.rawValue {
                lineToRemove = selector.renderedLine
            } else if let candidate = currentLines.first(where: { $0.contains(selector.marker) && ExactEntryDigest.value(Data($0.utf8)) == removalReceipt.entryFingerprint.rawValue }) {
                lineToRemove = candidate
            } else {
                throw ExactEntryEditorError.notManifestProven
            }
            next = removeLine(Data(currentText.utf8), lineToRemove)
        } else {
            guard markerMatches == 0 else { throw markerMatches > 1 ? ExactEntryEditorError.ambiguous : ExactEntryEditorError.sourceChanged }
            next = appendLine(Data(currentText.utf8), selector.renderedLine)
        }
        let destination = URL(fileURLWithPath: source.resolvedPath ?? path.standardizedFileURL.path)
        do {
            try writeLosslessly(next, to: destination, preserving: source, interruption: options.interruption)
        } catch let error as ExactEntryEditorError {
            throw error
        } catch {
            throw ExactEntryEditorError.ioFailure
        }
        let verified = snapshot(at: path)
        let expectedLinePresent = removalReceipt == nil ? lines(in: String(data: verified.content ?? Data(), encoding: .utf8) ?? "").contains(selector.renderedLine) : !lines(in: String(data: verified.content ?? Data(), encoding: .utf8) ?? "").contains(selector.renderedLine)
        guard expectedLinePresent else { throw ExactEntryEditorError.verificationFailed }
        return ExactEntryReceipt(selector: selector, path: path.path, sourceFingerprint: verified.fingerprint, createdAt: now)
    }

    private static func writeLosslessly(_ data: Data, to destination: URL, preserving source: ExactEntryFileSnapshot, interruption: ExactEntryWriteInterruption) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            // Creating an unselected parent would silently claim setup outside
            // the exact scope. The person must create/select that path first.
            throw ExactEntryEditorError.unavailable
        }
        let temporary = parent.appendingPathComponent(".agent-island-exact-entry-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        defer { try? fm.removeItem(at: temporary) }
        if let bits = source.fingerprint.permissionBits {
            try? fm.setAttributes([.posixPermissions: NSNumber(value: bits)], ofItemAtPath: temporary.path)
        }
        if interruption == .afterTemporaryWrite { throw ExactEntryEditorError.interrupted }
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: destination)
        }
        if interruption == .afterReplace { throw ExactEntryEditorError.interrupted }
    }

    private static func lines(in text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }

    private static func appendLine(_ data: Data, _ line: String) -> Data {
        let lineData = Data(line.utf8)
        guard !data.isEmpty else { return lineData }
        let newline = data.range(of: Data([13, 10])) != nil ? Data([13, 10]) : Data([10])
        var result = Data(data)
        if data.suffix(newline.count) != newline { result.append(newline) }
        result.append(lineData)
        return result
    }

    private static func removeLine(_ data: Data, _ line: String) -> Data {
        let expected = Data(line.utf8)
        var result = Data()
        var cursor = 0
        var ranges: [(start: Int, contentEnd: Int, end: Int, content: Data)] = []
        let bytes = Array(data)
        while cursor < bytes.count {
            let start = cursor
            while cursor < bytes.count && bytes[cursor] != 10 { cursor += 1 }
            let contentEnd = cursor > start && bytes[cursor - 1] == 13 ? cursor - 1 : cursor
            let end = cursor < bytes.count ? cursor + 1 : cursor
            ranges.append((start, contentEnd, end, Data(bytes[start..<contentEnd])))
            cursor = end
        }
        guard let index = ranges.firstIndex(where: { $0.content == expected }) else { return data }
        let range = ranges[index]
        var removeStart = range.start
        var removeEnd = range.end
        if range.end == data.count, range.start > 0 {
            removeStart = ranges[index - 1].end
            removeEnd = range.end
        }
        result.append(data.prefix(removeStart))
        result.append(data.suffix(from: removeEnd))
        return result
    }
}
