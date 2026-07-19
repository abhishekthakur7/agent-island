import XCTest
@testable import StorageCore

final class StorageCoreTests: XCTestCase {
    func testRepresentativeFixtureHasThirtyUniqueRecords() throws {
        let records = RepresentativeFixture.records
        XCTAssertEqual(records.count, 30)
        XCTAssertEqual(Set(records.map(\.sourceID)).count, 30)
        XCTAssertEqual(records.filter { $0.state == "attention" }.count, 8)
        XCTAssertEqual(records.filter { $0.childRunCount > 0 }.count, 10)
    }

    func testProjectionIsDeterministicAndOrderIndependent() throws {
        let first = try ProjectionBuilder.rebuild(records: RepresentativeFixture.records)
        let second = try ProjectionBuilder.rebuild(records: RepresentativeFixture.records.reversed())
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.digest, "7d4db561e017f26875e7893cf64fa3ec459c376aac7b3d9deae7a0fd25942530")
    }

    func testProjectionRejectsDuplicateSourceEvidence() {
        var records = RepresentativeFixture.records
        records.append(records[0])
        XCTAssertThrowsError(try ProjectionBuilder.rebuild(records: records))
    }

    func testMigrationPolicyFailsClosedOnUnknownFutureSchema() {
        XCTAssertThrowsError(try MigrationPolicy.validateSource(version: 3, recordCount: 30)) { error in
            XCTAssertEqual(error as? ProtectedStoreFailure, .unsupportedSchema(found: 3, supported: 2))
        }
    }

    func testSHA256ReferenceVector() {
        XCTAssertEqual(SHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
