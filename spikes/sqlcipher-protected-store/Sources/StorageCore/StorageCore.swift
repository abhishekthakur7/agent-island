import Foundation

public enum ProtectedStoreFailure: Error, Equatable, Sendable {
    case missingKeychainKey
    case corruptDatabase
    case interruptedWrite
    case unsupportedSchema(found: Int, supported: Int)
    case integrityCheckFailed
    case migrationFailed
    case encryptionUnavailable
    case invalidSource

    public var diagnosticCode: String {
        switch self {
        case .missingKeychainKey: "storage.keychain_key_missing"
        case .corruptDatabase: "storage.database_corrupt"
        case .interruptedWrite: "storage.interrupted_write"
        case .unsupportedSchema: "storage.schema_incompatible"
        case .integrityCheckFailed: "storage.integrity_failed"
        case .migrationFailed: "storage.migration_failed"
        case .encryptionUnavailable: "storage.sqlcipher_unavailable"
        case .invalidSource: "storage.source_invalid"
        }
    }
}

/// Diagnostics deliberately carry no paths, SQL, record payloads, or key data.
public struct RedactedDiagnostic: Codable, Equatable, Sendable {
    public let code: String
    public let operation: String
    public let schemaVersion: Int?

    public init(code: String, operation: String, schemaVersion: Int? = nil) {
        self.code = code
        self.operation = operation
        self.schemaVersion = schemaVersion
    }
}

public struct FixtureRecord: Codable, Hashable, Sendable {
    public let sourceID: String
    public let ordinal: Int
    public let kind: String
    public let state: String
    public let project: String
    public let product: String
    public let host: String
    public let childRunCount: Int

    public init(sourceID: String, ordinal: Int, kind: String, state: String, project: String, product: String, host: String, childRunCount: Int) {
        self.sourceID = sourceID
        self.ordinal = ordinal
        self.kind = kind
        self.state = state
        self.project = project
        self.product = product
        self.host = host
        self.childRunCount = childRunCount
    }
}

/// A spike-only generic workload, not a production Agent Session schema.
public enum RepresentativeFixture {
    public static let schemaVersion = 1

    public static let records: [FixtureRecord] = (1...30).map { index in
        let states = ["working", "attention", "waiting", "complete"]
        let projects = ["island", "adapter-lab", "release-tools"]
        let products = ["Codex CLI", "Claude Code", "Cursor"]
        let hosts = ["Terminal", "iTerm", "Cursor"]
        return FixtureRecord(
            sourceID: String(format: "fixture-%02d", index),
            ordinal: index,
            kind: "representative-agent-session",
            state: states[(index - 1) % states.count],
            project: projects[(index - 1) % projects.count],
            product: products[(index - 1) % products.count],
            host: hosts[(index - 1) % hosts.count],
            childRunCount: index % 4 == 0 ? 2 : (index % 7 == 0 ? 1 : 0)
        )
    }
}

public struct DerivedProjection: Codable, Equatable, Sendable {
    public let recordCount: Int
    public let stateCounts: [String: Int]
    public let projectCounts: [String: Int]
    public let digest: String
}

/// Replaceable deterministic view. It never becomes a source of truth.
public enum ProjectionBuilder {
    public static func rebuild(records: [FixtureRecord]) throws -> DerivedProjection {
        guard Set(records.map(\.sourceID)).count == records.count,
              records.allSatisfy({ !$0.sourceID.isEmpty && $0.ordinal > 0 && !$0.kind.isEmpty }) else {
            throw ProtectedStoreFailure.invalidSource
        }
        let ordered = records.sorted { ($0.ordinal, $0.sourceID) < ($1.ordinal, $1.sourceID) }
        let stateCounts = Dictionary(grouping: ordered, by: \.state).mapValues(\.count)
        let projectCounts = Dictionary(grouping: ordered, by: \.project).mapValues(\.count)
        let canonical = ordered.map { "\($0.sourceID)|\($0.ordinal)|\($0.kind)|\($0.state)|\($0.project)|\($0.product)|\($0.host)|\($0.childRunCount)" }.joined(separator: "\n")
        return DerivedProjection(recordCount: ordered.count, stateCounts: stateCounts, projectCounts: projectCounts, digest: SHA256.hex(Data(canonical.utf8)))
    }
}

public enum MigrationPolicy {
    public static let currentSchema = 2

    public static func validateSource(version: Int, recordCount: Int) throws {
        guard version > 0, version <= currentSchema, recordCount >= 0 else {
            throw version > currentSchema
                ? ProtectedStoreFailure.unsupportedSchema(found: version, supported: currentSchema)
                : ProtectedStoreFailure.invalidSource
        }
    }

    public static func needsMigration(version: Int) -> Bool { version < currentSchema }
}

public enum SHA256 {
    // Compact dependency-free SHA-256 for deterministic projection proof.
    public static func hex(_ data: Data) -> String {
        var bytes = [UInt8](data)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        bytes += (0..<8).reversed().map { UInt8((bitLength >> UInt64($0 * 8)) & 0xff) }
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        let k: [UInt32] = [
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]
        for chunk in stride(from: 0, to: bytes.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { w[i] = (0..<4).reduce(0) { ($0 << 8) | UInt32(bytes[chunk + i * 4 + $1]) } }
            for i in 16..<64 { w[i] = small1(w[i - 2]) &+ w[i - 7] &+ small0(w[i - 15]) &+ w[i - 16] }
            var a=h[0], b=h[1], c=h[2], d=h[3], e=h[4], f=h[5], g=h[6], x=h[7]
            for i in 0..<64 { let t1 = x &+ big1(e) &+ choose(e,f,g) &+ k[i] &+ w[i]; let t2 = big0(a) &+ majority(a,b,c); x=g; g=f; f=e; e=d &+ t1; d=c; c=b; b=a; a=t1 &+ t2 }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= x
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
    private static func choose(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) ^ (~x & z) }
    private static func majority(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) ^ (x & z) ^ (y & z) }
    private static func big0(_ x: UInt32) -> UInt32 { rotr(x,2) ^ rotr(x,13) ^ rotr(x,22) }
    private static func big1(_ x: UInt32) -> UInt32 { rotr(x,6) ^ rotr(x,11) ^ rotr(x,25) }
    private static func small0(_ x: UInt32) -> UInt32 { rotr(x,7) ^ rotr(x,18) ^ (x >> 3) }
    private static func small1(_ x: UInt32) -> UInt32 { rotr(x,17) ^ rotr(x,19) ^ (x >> 10) }
}
