import Foundation

public struct DiagnosticBundleDestination: Codable, Equatable, Hashable, Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        guard directory.isFileURL else { throw DiagnosticBundleError.destinationNotLocal }
        self.directory = directory.standardizedFileURL
    }

    public init(directoryPath: String) throws { try self.init(directory: URL(fileURLWithPath: directoryPath)) }
}

public enum DiagnosticBundleError: Error, Codable, Equatable, Hashable, Sendable {
    case destinationNotLocal
    case destinationUnavailable
    case invalidName
    case writeFailed
    case unsafeRecord
}

/// A bundle carries only already-redacted evidence. It intentionally has no
/// source-store reference, destination, raw events, or export contents.
public struct DiagnosticBundle: Codable, Equatable, Hashable, Sendable {
    public static let schemaVersion = 1
    public let schema: Int
    public let generatedAt: Date
    public let records: [DiagnosticEvidence]
    public let humanReadable: String
    public let machineReadable: Data

    public init(records: [DiagnosticEvidence], generatedAt: Date = Date()) throws {
        guard records.allSatisfy(Self.isStructurallySafe) else { throw DiagnosticBundleError.unsafeRecord }
        self.schema = Self.schemaVersion
        self.generatedAt = generatedAt
        self.records = records.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
            return lhs.correlationID.value < rhs.correlationID.value
        }
        self.humanReadable = Self.markdown(for: self.records, generatedAt: generatedAt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.machineReadable = try encoder.encode(self.records)
    }

    private static func isStructurallySafe(_ evidence: DiagnosticEvidence) -> Bool {
        // All fields are closed enums or a locally hashed correlation value.
        // Keep this check explicit so a future model expansion cannot silently
        // make bundle generation accept arbitrary text.
        evidence.correlationID.value.hasPrefix("corr-") &&
            evidence.correlationID.value.count <= 32
    }

    private static func markdown(for records: [DiagnosticEvidence], generatedAt: Date) -> String {
        var lines = [
            "# Agent Island Diagnostic Bundle",
            "schema: \(schemaVersion)",
            "generated: \(iso8601(generatedAt))",
            "",
            "This local bundle contains redacted operational evidence only. It is not an upload, backup, or user-data export.",
            ""
        ]
        for (index, record) in records.enumerated() {
            lines.append("## Evidence \(index + 1)")
            lines.append("- component: \(record.scope.component.rawValue)")
            lines.append("- owner_scope: \(record.scope.owner.rawValue)")
            if let capability = record.scope.capability { lines.append("- capability: \(capability.rawValue)") }
            lines.append("- operation: \(record.operation.rawValue)")
            lines.append("- outcome: \(record.outcome.rawValue)")
            lines.append("- reason: \(record.reason.rawValue)")
            lines.append("- occurred_at: \(iso8601(record.occurredAt))")
            lines.append("- correlation: \(record.correlationID.value)")
            lines.append("- health_summary: \(record.health.summary.rawValue)")
            lines.append("- next_step: \(record.safeNextStep.rawValue)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

public struct DiagnosticBundleArtifacts: Codable, Equatable, Hashable, Sendable {
    public let markdown: URL
    public let machineReadableJSON: URL

    public init(markdown: URL, machineReadableJSON: URL) {
        self.markdown = markdown
        self.machineReadableJSON = machineReadableJSON
    }
}

/// Foreground-only writer for a person-initiated Diagnostic Bundle. It writes
/// exactly two visible files in the selected local directory and performs no
/// open, upload, network, or hidden-copy operation.
public enum DiagnosticBundleWriter {
    public static func write(
        _ bundle: DiagnosticBundle,
        to destination: DiagnosticBundleDestination,
        name: String = "agent-island-diagnostic-bundle"
    ) throws -> DiagnosticBundleArtifacts {
        guard !name.isEmpty,
              name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
        else { throw DiagnosticBundleError.invalidName }
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destination.directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DiagnosticBundleError.destinationUnavailable
        }
        let markdownURL = destination.directory.appendingPathComponent(name).appendingPathExtension("md")
        let jsonURL = destination.directory.appendingPathComponent(name).appendingPathExtension("json")
        guard !fm.fileExists(atPath: markdownURL.path), !fm.fileExists(atPath: jsonURL.path) else {
            throw DiagnosticBundleError.writeFailed
        }
        do {
            try Data(bundle.humanReadable.utf8).write(to: markdownURL, options: [.atomic])
            try bundle.machineReadable.write(to: jsonURL, options: [.atomic])
            return DiagnosticBundleArtifacts(markdown: markdownURL, machineReadableJSON: jsonURL)
        } catch {
            // Do not leave a partial local bundle behind. This is the visible
            // foreground operation's only cleanup; no backup is retained.
            try? fm.removeItem(at: markdownURL)
            try? fm.removeItem(at: jsonURL)
            throw DiagnosticBundleError.writeFailed
        }
    }
}

public typealias DiagnosticBundlePreview = DiagnosticBundle
