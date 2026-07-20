import XCTest
import Foundation
@testable import SessionDomain

final class OwnershipManifestTests: XCTestCase {
    func testManifestStoresReceiptsNotConfigurationContentsAndRoundTrips() throws {
        let scope = IntegrationInstallationScope(identifier: "user", path: "/tmp/selected.conf")
        let selector = ExactEntrySelector(key: "hooks", renderedLine: "hooks = agent-island # agent-island:hooks")
        let fingerprint = ExactEntrySourceFingerprint(content: ExactEntryFingerprint("source"), permissionBits: 0o600)
        let receipt = ExactEntryReceipt(selector: selector, path: scope.path, sourceFingerprint: fingerprint, createdAt: Date(timeIntervalSince1970: 1))
        let manifest = OwnershipManifest(id: "manifest", installationID: "installation", product: ProductNamespace("fixture"), integrationMode: "hooks", scope: scope, sourcePath: scope.path, entries: [receipt], productVersion: "1", interfaceVersion: "v1", createdAt: Date(timeIntervalSince1970: 1))
        let encoded = try JSONEncoder().encode(manifest)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("password"))
        let decoded = try JSONDecoder().decode(OwnershipManifest.self, from: encoded)
        XCTAssertEqual(decoded.id, manifest.id)
        XCTAssertEqual(decoded.entries.first?.entryFingerprint, receipt.entryFingerprint)
        XCTAssertEqual(decoded.proving(selector, at: scope.path)?.entryFingerprint, receipt.entryFingerprint)
    }
}
