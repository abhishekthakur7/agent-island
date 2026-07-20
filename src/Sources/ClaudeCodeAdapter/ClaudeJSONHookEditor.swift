import Foundation
import SessionDomain

/// Lossless editor for Claude's documented nested `hooks` settings object.
/// It parses only enough JSON/JSONC structure to locate one exact hook object
/// and applies byte-range insertions/removals. It never serializes the source
/// tree, so comments, unknown fields, ordering, whitespace, line endings and
/// arrays outside the marked entry remain byte-for-byte unchanged.
public enum ClaudeJSONHookEditor {
    public static let markerPrefix = "agent-island:claude-code-hooks-observation"

    public enum EditorError: Error, Codable, Equatable, Sendable {
        case invalidUTF8
        case malformed
        case commentsInJSON
        case unsupported
        case ambiguous
        case sourceChanged
        case symlink
        case policyDenied
        case unavailable
        case notManifestProven
        case verificationFailed
    }

    public struct Inspection: Sendable, Equatable {
        public let source: ExactEntryFileSnapshot
        public let format: String
        public let markerMatches: Int
        public let exactMatches: Int
        public let supported: Bool

        public init(source: ExactEntryFileSnapshot, format: String, markerMatches: Int, exactMatches: Int, supported: Bool) {
            self.source = source; self.format = format; self.markerMatches = markerMatches; self.exactMatches = exactMatches; self.supported = supported
        }
    }

    public struct Entry: Sendable, Equatable {
        public let selector: ExactEntrySelector
        /// Exact documented event spelling; the lossless editor itself is
        /// product-neutral and does not broaden any Product contract.
        public let event: String
        public let helperPath: String

        public init(selector: ExactEntrySelector, event: String, helperPath: String) {
            self.selector = selector; self.event = event; self.helperPath = helperPath
        }
    }

    public static func entry(for event: ClaudeHookName = .sessionStart, helperPath: URL) -> Entry {
        let marker = "\(markerPrefix):\(event.rawValue)"
        let command = shellQuote(helperPath.path) + " # " + marker
        let rendered = "{\"type\":\"command\",\"command\":\"\(jsonEscape(command))\"}"
        return Entry(selector: ExactEntrySelector(key: "claude-code-hooks-\(event.rawValue)", renderedLine: rendered, marker: marker), event: event.rawValue, helperPath: helperPath.path)
    }

    public static func entry(eventName: String, markerPrefix: String, helperPath: URL) -> Entry {
        entry(eventName: eventName, markerPrefix: markerPrefix, command: shellQuote(helperPath.path))
    }

    public static func entry(eventName: String, markerPrefix: String, command: String) -> Entry {
        let marker = "\(markerPrefix):\(eventName)"
        let markedCommand = command + " # " + marker
        let rendered = "{\"command\":\"\(jsonEscape(markedCommand))\"}"
        return Entry(selector: ExactEntrySelector(key: "documented-hooks-\(eventName)", renderedLine: rendered, marker: marker), event: eventName, helperPath: command)
    }

    /// Shared strict JSON gate for untrusted hook envelopes. Foundation's
    /// decoder accepts duplicate object keys, while the adapter must not pick
    /// an arbitrary winner for identity or ownership fields.
    public static func validateJSONObject(_ data: Data) throws {
        let parsed = try ParsedSource(data: data, jsonc: false)
        guard parsed.root.kind == .object else { throw EditorError.unsupported }
    }

    public static func inspect(at path: URL, entry: Entry) -> Inspection {
        let source = ExactEntryEditor.snapshot(at: path)
        let ext = path.pathExtension.lowercased()
        guard ext == "json" || ext == "jsonc", source.symlinkTarget == nil,
              let parsed = try? ParsedSource(data: source.content ?? Data("{}".utf8), jsonc: ext == "jsonc") else {
            return Inspection(source: source, format: ext, markerMatches: 0, exactMatches: 0, supported: false)
        }
        let objects = parsed.hookEntries(for: entry.event)
        let markerMatches = objects.filter { parsed.raw($0).contains(entry.selector.marker) }.count
        let exactMatches = objects.filter { parsed.raw($0) == entry.selector.renderedLine }.count
        return Inspection(source: source, format: ext, markerMatches: markerMatches, exactMatches: exactMatches, supported: true)
    }

    public static func add(entry: Entry, at path: URL, expected: ExactEntrySourceFingerprint? = nil, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) throws -> ExactEntryReceipt {
        guard policy.allowsMutation else { throw EditorError.policyDenied }
        let source = ExactEntryEditor.snapshot(at: path)
        guard source.symlinkTarget == nil else { throw EditorError.symlink }
        if let expected, expected != source.fingerprint { throw EditorError.sourceChanged }
        let ext = path.pathExtension.lowercased()
        guard ext == "json" || ext == "jsonc" else { throw EditorError.unsupported }
        let data = source.content ?? Data("{}".utf8)
        let parsed = try ParsedSource(data: data, jsonc: ext == "jsonc")
        guard parsed.root.kind == .object else { throw EditorError.unsupported }
        let existing = parsed.hookEntries(for: entry.event)
        let markerCount = existing.filter { parsed.raw($0).contains(entry.selector.marker) }.count
        guard markerCount == 0 else { throw markerCount > 1 ? EditorError.ambiguous : EditorError.sourceChanged }
        let next: Data
        if parsed.hasRootMember("hooks") && parsed.rootObjectMember("hooks") == nil { throw EditorError.unsupported }
        if let hooks = parsed.rootObjectMember("hooks"), let eventArray = try parsed.eventArray(for: entry.event, hooks: hooks) {
            next = parsed.inserting(entry.selector.renderedLine, into: eventArray)
        } else if let hooks = parsed.rootObjectMember("hooks") {
            next = parsed.insertingProperty("\"\(entry.event)\": [\(entry.selector.renderedLine)]", into: hooks)
        } else {
            next = parsed.insertingProperty("\"hooks\": {\"\(entry.event)\": [\(entry.selector.renderedLine)]}", into: parsed.root)
        }
        try write(next, to: path, preserving: source)
        let verified = ExactEntryEditor.snapshot(at: path)
        let check = inspect(at: path, entry: entry)
        guard check.supported, check.exactMatches == 1 else { throw EditorError.verificationFailed }
        return ExactEntryReceipt(selector: entry.selector, path: path.path, sourceFingerprint: verified.fingerprint, createdAt: now)
    }

    public static func remove(receipt: ExactEntryReceipt, event: String, at path: URL, expected: ExactEntrySourceFingerprint? = nil, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) throws -> ExactEntryReceipt {
        guard policy.allowsMutation else { throw EditorError.policyDenied }
        let source = ExactEntryEditor.snapshot(at: path)
        guard source.symlinkTarget == nil else { throw EditorError.symlink }
        if let expected, expected != source.fingerprint { throw EditorError.sourceChanged }
        let ext = path.pathExtension.lowercased()
        guard (ext == "json" || ext == "jsonc"), let data = source.content else { throw EditorError.unavailable }
        let parsed = try ParsedSource(data: data, jsonc: ext == "jsonc")
        guard parsed.root.kind == .object else { throw EditorError.unsupported }
        guard let hooks = parsed.rootObjectMember("hooks") else { throw EditorError.notManifestProven }
        guard let array = try parsed.eventArray(for: event, hooks: hooks) else { throw EditorError.notManifestProven }
        let candidates = array.elements.filter { parsed.raw($0).contains(receipt.selector.marker) }
        guard candidates.count == 1, let candidate = candidates.first else { throw candidates.isEmpty ? EditorError.notManifestProven : EditorError.ambiguous }
        let actualDigest = ExactEntryDigest.value(Data(parsed.raw(candidate).utf8))
        guard actualDigest == receipt.entryFingerprint.rawValue else { throw EditorError.notManifestProven }
        let next = try parsed.removing(candidate, from: array, jsonc: ext == "jsonc")
        try write(next, to: path, preserving: source)
        let verified = ExactEntryEditor.snapshot(at: path)
        let check = inspect(at: path, entry: Entry(selector: receipt.selector, event: event, helperPath: ""))
        guard check.supported, check.markerMatches == 0 else { throw EditorError.verificationFailed }
        return ExactEntryReceipt(selector: receipt.selector, path: path.path, sourceFingerprint: verified.fingerprint, createdAt: now)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func jsonEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    fileprivate static func write(_ data: Data, to path: URL, preserving source: ExactEntryFileSnapshot) throws {
        let destination = URL(fileURLWithPath: source.resolvedPath ?? path.path)
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else { throw EditorError.unavailable }
        let temporary = parent.appendingPathComponent(".agent-island-claude-hooks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        if let bits = source.fingerprint.permissionBits {
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: bits)], ofItemAtPath: temporary.path)
            guard ExactEntryEditor.snapshot(at: temporary).fingerprint.permissionBits == bits else { throw EditorError.verificationFailed }
        }
        // Recheck at the commit boundary. Parsing and rendering can race with
        // another writer; never replace bytes or a symlink that were not the
        // exact source inspected above.
        let immediate = ExactEntryEditor.snapshot(at: destination)
        guard immediate.symlinkTarget == nil, immediate.fingerprint == source.fingerprint else {
            throw EditorError.sourceChanged
        }
        if source.exists { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: destination) }
        if let bits = source.fingerprint.permissionBits {
            guard ExactEntryEditor.snapshot(at: destination).fingerprint.permissionBits == bits else { throw EditorError.verificationFailed }
        }
    }
}

/// Exact-entry editor for Claude's documented top-level Status Line setting.
/// It refuses to replace an existing Status Line: preserving a person's
/// visible output takes precedence over installation convenience. The bridge
/// therefore has one reversible, marked entry only when the setting is absent.
public enum ClaudeStatusLineBridgeEditor {
    public static let marker = "agent-island:claude-status-line-usage"

    public static func selector() -> ExactEntrySelector {
        let command = "/Applications/Agent Island.app/Contents/MacOS/AgentIslandUsageStatusLine # \(marker)"
        let rendered = "{\"type\":\"command\",\"command\":\"\(command)\"}"
        return ExactEntrySelector(key: "claude-status-line", renderedLine: rendered, marker: marker)
    }

    public static func inspect(at path: URL, selector: ExactEntrySelector = selector()) -> ExactEntryInspection {
        let source = ExactEntryEditor.snapshot(at: path)
        let ext = path.pathExtension.lowercased()
        guard source.symlinkTarget == nil, (ext == "json" || ext == "jsonc"), let data = source.content,
              let parsed = try? ParsedSource(data: data, jsonc: ext == "jsonc"), parsed.root.kind == .object
        else { return ExactEntryInspection(state: .unsupported, source: source, matchingEntryCount: 0, reason: .unsupported) }
        guard let member = parsed.rootMember(named: "statusLine") else {
            return ExactEntryInspection(state: .notConfigured, source: source, matchingEntryCount: 0)
        }
        let raw = parsed.raw(member.value)
        let matches = raw.contains(selector.marker) ? 1 : 0
        if matches == 0 { return ExactEntryInspection(state: .externalCandidate, source: source, matchingEntryCount: 1) }
        return ExactEntryInspection(state: raw == selector.renderedLine ? .ownedIntact : .ownedDrifted, source: source, matchingEntryCount: matches, reason: raw == selector.renderedLine ? nil : .sourceChanged)
    }

    public static func add(selector: ExactEntrySelector = selector(), at path: URL, expected: ExactEntrySourceFingerprint, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) throws -> ExactEntryReceipt {
        guard policy.allowsMutation else { throw ClaudeJSONHookEditor.EditorError.policyDenied }
        let source = ExactEntryEditor.snapshot(at: path)
        guard source.fingerprint == expected else { throw ClaudeJSONHookEditor.EditorError.sourceChanged }
        guard source.symlinkTarget == nil, let data = source.content else { throw ClaudeJSONHookEditor.EditorError.unavailable }
        let ext = path.pathExtension.lowercased(); guard ext == "json" || ext == "jsonc" else { throw ClaudeJSONHookEditor.EditorError.unsupported }
        let parsed = try ParsedSource(data: data, jsonc: ext == "jsonc")
        guard parsed.root.kind == .object, parsed.rootMember(named: "statusLine") == nil else { throw ClaudeJSONHookEditor.EditorError.sourceChanged }
        try ClaudeJSONHookEditor.write(parsed.insertingProperty("\"statusLine\": \(selector.renderedLine)", into: parsed.root), to: path, preserving: source)
        let verified = ExactEntryEditor.snapshot(at: path)
        guard inspect(at: path, selector: selector).state == .ownedIntact else { throw ClaudeJSONHookEditor.EditorError.verificationFailed }
        return ExactEntryReceipt(selector: selector, path: path.path, sourceFingerprint: verified.fingerprint, createdAt: now)
    }

    public static func remove(receipt: ExactEntryReceipt, at path: URL, expected: ExactEntrySourceFingerprint, policy: ExactEntryWritePolicy = .allowed, now: Date = Date()) throws -> ExactEntryReceipt {
        guard policy.allowsMutation else { throw ClaudeJSONHookEditor.EditorError.policyDenied }
        let source = ExactEntryEditor.snapshot(at: path)
        guard source.fingerprint == expected else { throw ClaudeJSONHookEditor.EditorError.sourceChanged }
        guard source.symlinkTarget == nil, let data = source.content else { throw ClaudeJSONHookEditor.EditorError.unavailable }
        let ext = path.pathExtension.lowercased(); guard ext == "json" || ext == "jsonc" else { throw ClaudeJSONHookEditor.EditorError.unsupported }
        let parsed = try ParsedSource(data: data, jsonc: ext == "jsonc")
        guard let member = parsed.rootMember(named: "statusLine"), parsed.raw(member.value).contains(receipt.selector.marker), ExactEntryDigest.value(Data(parsed.raw(member.value).utf8)) == receipt.entryFingerprint.rawValue else { throw ClaudeJSONHookEditor.EditorError.notManifestProven }
        try ClaudeJSONHookEditor.write(try parsed.removingMember(member, from: parsed.root, jsonc: ext == "jsonc"), to: path, preserving: source)
        let verified = ExactEntryEditor.snapshot(at: path)
        guard inspect(at: path, selector: receipt.selector).state == .notConfigured else { throw ClaudeJSONHookEditor.EditorError.verificationFailed }
        return ExactEntryReceipt(selector: receipt.selector, path: path.path, sourceFingerprint: verified.fingerprint, createdAt: now)
    }
}

private final class JSONNode: @unchecked Sendable {
    enum Kind { case object, array, scalar }
    let kind: Kind
    let start: Int
    let end: Int
    let open: Int?
    let close: Int?
    var members: [(key: String, value: JSONNode, start: Int)] = []
    var elements: [JSONNode] = []
    init(kind: Kind, start: Int, end: Int, open: Int? = nil, close: Int? = nil) { self.kind = kind; self.start = start; self.end = end; self.open = open; self.close = close }
}

private struct JSONToken {
    enum Kind { case leftBrace, rightBrace, leftBracket, rightBracket, colon, comma, string(String), scalar }
    let kind: Kind
    let start: Int
    let end: Int
}

private struct ParsedSource: @unchecked Sendable {
    let data: Data
    let root: JSONNode
    let tokens: [JSONToken]

    init(data: Data, jsonc: Bool) throws {
        // String(decoding:) would silently replace malformed UTF-8. Settings
        // source is opaque unless it is valid UTF-8 JSON/JSONC.
        guard String(data: data, encoding: .utf8) != nil else {
            throw ClaudeJSONHookEditor.EditorError.invalidUTF8
        }
        self.data = data
        var lexer = JSONLexer(bytes: Array(data), jsonc: jsonc)
        let tokens = try lexer.lex()
        guard !tokens.isEmpty else { throw ClaudeJSONHookEditor.EditorError.malformed }
        var parser = JSONParser(tokens: tokens, allowTrailingComma: jsonc)
        let root = try parser.parse()
        guard parser.index == tokens.count else { throw ClaudeJSONHookEditor.EditorError.malformed }
        self.root = root; self.tokens = tokens
    }

    func raw(_ node: JSONNode) -> String { String(decoding: data[node.start..<node.end], as: UTF8.self) }

    func rootObjectMember(_ key: String) -> JSONNode? {
        guard root.kind == .object else { return nil }
        guard let member = root.members.first(where: { $0.key == key }) else { return nil }
        return member.value.kind == .object ? member.value : nil
    }

    func rootMember(named key: String) -> (key: String, value: JSONNode, start: Int)? {
        root.members.first(where: { $0.key == key })
    }

    func hasRootMember(_ key: String) -> Bool { root.kind == .object && root.members.contains(where: { $0.key == key }) }

    func eventArray(for event: String, hooks: JSONNode) throws -> JSONNode? {
        guard let member = hooks.members.first(where: { $0.key == event }) else { return nil }
        guard member.value.kind == .array else { throw ClaudeJSONHookEditor.EditorError.unsupported }
        return member.value
    }

    func hookEntries(for event: String) -> [JSONNode] {
        guard let hooks = root.members.first(where: { $0.key == "hooks" })?.value,
              hooks.kind == .object,
              let array = hooks.members.first(where: { $0.key == event })?.value,
              array.kind == .array else { return [] }
        return array.elements
    }

    func inserting(_ rendered: String, into array: JSONNode) -> Data {
        guard let close = array.close else { return data }
        if let trailing = token(before: close), trailing.kind.isComma {
            return insert(rendered, before: trailing.start, separator: ",")
        }
        return insert(rendered, before: close, separator: array.elements.isEmpty ? "" : ",")
    }

    func insertingProperty(_ rendered: String, into object: JSONNode) -> Data {
        guard let close = object.close else { return data }
        if let trailing = token(before: close), trailing.kind.isComma {
            return insert(rendered, before: trailing.start, separator: ",")
        }
        return insert(rendered, before: close, separator: object.members.isEmpty ? "" : ",")
    }

    func removing(_ node: JSONNode, from container: JSONNode, jsonc: Bool) throws -> Data {
        // Comments are deliberately absent from tokens. Try each syntactically
        // meaningful separator ownership choice, retaining every non-entry
        // byte, and accept only a fully reparsable result. If comments make
        // neither lossless choice representable, fail before touching disk.
        var candidates: [[(Int, Int)]] = []
        if let comma = token(after: node.end), comma.kind.isComma {
            candidates.append([(node.start, node.end), (comma.start, comma.end)])
        }
        if let comma = token(before: node.start), comma.kind.isComma {
            candidates.append([(comma.start, comma.end), (node.start, node.end)])
        }
        if candidates.isEmpty { candidates.append([(node.start, node.end)]) }
        for ranges in candidates {
            var result = data
            for (start, end) in ranges.sorted(by: { $0.0 > $1.0 }) { result.removeSubrange(start..<end) }
            if (try? ParsedSource(data: result, jsonc: jsonc)) != nil { return result }
        }
        throw ClaudeJSONHookEditor.EditorError.unsupported
    }

    func removingMember(_ member: (key: String, value: JSONNode, start: Int), from container: JSONNode, jsonc: Bool) throws -> Data {
        let start = member.start; let end = member.value.end
        var candidates: [[(Int, Int)]] = []
        if let comma = token(after: end), comma.kind.isComma { candidates.append([(start, end), (comma.start, comma.end)]) }
        if let comma = token(before: start), comma.kind.isComma { candidates.append([(comma.start, comma.end), (start, end)]) }
        if candidates.isEmpty { candidates.append([(start, end)]) }
        for ranges in candidates {
            var result = data
            for (rangeStart, rangeEnd) in ranges.sorted(by: { $0.0 > $1.0 }) { result.removeSubrange(rangeStart..<rangeEnd) }
            if (try? ParsedSource(data: result, jsonc: jsonc)) != nil { return result }
        }
        throw ClaudeJSONHookEditor.EditorError.unsupported
    }

    private func insert(_ rendered: String, before offset: Int, separator: String) -> Data {
        let bytes = Array(data)
        let lineStart = (bytes[..<offset].lastIndex(of: 10).map { $0 + 1 }) ?? 0
        let closeIndent = String(decoding: bytes[lineStart..<offset].prefix { $0 == 32 || $0 == 9 }, as: UTF8.self)
        let newline = data.range(of: Data([13, 10])) != nil ? "\r\n" : "\n"
        let between = String(decoding: bytes[(lineStart)..<offset], as: UTF8.self)
        let oneLine = !between.contains("\n") && !between.contains("\r")
        let insertion: String
        if oneLine { insertion = separator + rendered }
        else { insertion = separator + newline + closeIndent + "  " + rendered + newline + closeIndent }
        var result = Data(); result.append(data.prefix(offset)); result.append(Data(insertion.utf8)); result.append(data.suffix(from: offset)); return result
    }

    private func token(after offset: Int) -> JSONToken? { tokens.first(where: { $0.start >= offset }) }
    private func token(before offset: Int) -> JSONToken? { tokens.last(where: { $0.end <= offset }) }
}

private extension JSONToken.Kind { var isComma: Bool { if case .comma = self { return true }; return false } }

private struct JSONLexer {
    let bytes: [UInt8]
    let jsonc: Bool
    var index = 0

    mutating func lex() throws -> [JSONToken] {
        var result: [JSONToken] = []
        while index < bytes.count {
            let c = bytes[index]
            if c == 32 || c == 9 || c == 10 || c == 13 { index += 1; continue }
            if c == 47 {
                guard jsonc, index + 1 < bytes.count else { throw ClaudeJSONHookEditor.EditorError.commentsInJSON }
                if bytes[index + 1] == 47 { index += 2; while index < bytes.count && bytes[index] != 10 { index += 1 }; continue }
                if bytes[index + 1] == 42 { index += 2; var closed = false; while index + 1 < bytes.count { if bytes[index] == 42 && bytes[index + 1] == 47 { index += 2; closed = true; break }; index += 1 }; guard closed else { throw ClaudeJSONHookEditor.EditorError.malformed }; continue }
                throw ClaudeJSONHookEditor.EditorError.malformed
            }
            let start = index
            switch c {
            case 123: result.append(JSONToken(kind: .leftBrace, start: start, end: start + 1)); index += 1
            case 125: result.append(JSONToken(kind: .rightBrace, start: start, end: start + 1)); index += 1
            case 91: result.append(JSONToken(kind: .leftBracket, start: start, end: start + 1)); index += 1
            case 93: result.append(JSONToken(kind: .rightBracket, start: start, end: start + 1)); index += 1
            case 58: result.append(JSONToken(kind: .colon, start: start, end: start + 1)); index += 1
            case 44: result.append(JSONToken(kind: .comma, start: start, end: start + 1)); index += 1
            case 34:
                index += 1; var escaped = false; var end: Int? = nil
                while index < bytes.count { let b = bytes[index]; if b == 10 || b == 13 { throw ClaudeJSONHookEditor.EditorError.malformed }; if escaped { escaped = false; index += 1; continue }; if b == 92 { escaped = true; index += 1; continue }; if b == 34 { end = index + 1; index += 1; break }; index += 1 }
                guard let end else { throw ClaudeJSONHookEditor.EditorError.malformed }
                let inner = String(decoding: bytes[(start + 1)..<(end - 1)], as: UTF8.self)
                guard let decoded = try? JSONDecoder().decode(String.self, from: Data(("\"" + inner + "\"").utf8)) else { throw ClaudeJSONHookEditor.EditorError.malformed }
                result.append(JSONToken(kind: .string(decoded), start: start, end: end))
            default:
                guard c == 45 || (c >= 48 && c <= 57) || (c >= 65 && c <= 122) else { throw ClaudeJSONHookEditor.EditorError.malformed }
                index += 1; while index < bytes.count && ![32,9,10,13,44,58,93,125].contains(bytes[index]) { index += 1 }
                let raw = String(decoding: bytes[start..<index], as: UTF8.self)
                if raw.first?.isLetter == true {
                    guard raw == "true" || raw == "false" || raw == "null" else { throw ClaudeJSONHookEditor.EditorError.malformed }
                } else {
                    guard (try? JSONSerialization.jsonObject(with: Data(("[" + raw + "]").utf8))) != nil else { throw ClaudeJSONHookEditor.EditorError.malformed }
                }
                result.append(JSONToken(kind: .scalar, start: start, end: index))
            }
        }
        return result
    }
}

private struct JSONParser {
    let tokens: [JSONToken]
    let allowTrailingComma: Bool
    var index = 0

    init(tokens: [JSONToken], allowTrailingComma: Bool) {
        self.tokens = tokens; self.allowTrailingComma = allowTrailingComma
    }

    mutating func parse() throws -> JSONNode { try parseValue() }

    private mutating func parseValue() throws -> JSONNode {
        guard index < tokens.count else { throw ClaudeJSONHookEditor.EditorError.malformed }
        let token = tokens[index]
        switch token.kind {
        case .leftBrace:
            index += 1; let node = JSONNode(kind: .object, start: token.start, end: token.end, open: token.start)
            var keys = Set<String>()
            if peek(.rightBrace) { let close = tokens[index]; index += 1; return JSONNode(kind: .object, start: node.start, end: close.end, open: node.start, close: close.start) }
            while true {
                let keyStart = tokens[index].start
                guard case .string(let key) = tokens[index].kind else { throw ClaudeJSONHookEditor.EditorError.malformed }
                guard keys.insert(key).inserted else { throw ClaudeJSONHookEditor.EditorError.ambiguous }
                index += 1; guard peek(.colon) else { throw ClaudeJSONHookEditor.EditorError.malformed }; index += 1
                let value = try parseValue(); node.members.append((key, value, keyStart))
                if peek(.rightBrace) { let close = tokens[index]; index += 1; let finished = JSONNode(kind: .object, start: node.start, end: close.end, open: node.start, close: close.start); finished.members = node.members; return finished }
                guard peek(.comma) else { throw ClaudeJSONHookEditor.EditorError.malformed }; index += 1
                if peek(.rightBrace) { if allowTrailingComma { let close = tokens[index]; index += 1; let finished = JSONNode(kind: .object, start: node.start, end: close.end, open: node.start, close: close.start); finished.members = node.members; return finished }; throw ClaudeJSONHookEditor.EditorError.malformed }
            }
        case .leftBracket:
            index += 1; let node = JSONNode(kind: .array, start: token.start, end: token.end, open: token.start)
            if peek(.rightBracket) { let close = tokens[index]; index += 1; return JSONNode(kind: .array, start: node.start, end: close.end, open: node.start, close: close.start) }
            while true {
                node.elements.append(try parseValue())
                if peek(.rightBracket) { let close = tokens[index]; index += 1; let finished = JSONNode(kind: .array, start: node.start, end: close.end, open: node.start, close: close.start); finished.elements = node.elements; return finished }
                guard peek(.comma) else { throw ClaudeJSONHookEditor.EditorError.malformed }; index += 1
                if peek(.rightBracket) { if allowTrailingComma { let close = tokens[index]; index += 1; let finished = JSONNode(kind: .array, start: node.start, end: close.end, open: node.start, close: close.start); finished.elements = node.elements; return finished }; throw ClaudeJSONHookEditor.EditorError.malformed }
            }
        case .string, .scalar:
            index += 1; return JSONNode(kind: .scalar, start: token.start, end: token.end)
        default: throw ClaudeJSONHookEditor.EditorError.malformed
        }
    }

    private func peek(_ kind: JSONToken.Kind) -> Bool {
        guard index < tokens.count else { return false }
        switch (tokens[index].kind, kind) {
        case (.rightBrace, .rightBrace), (.rightBracket, .rightBracket), (.colon, .colon), (.comma, .comma): return true
        default: return false
        }
    }
}
