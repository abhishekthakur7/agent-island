import XCTest
@testable import AgentIslandApp
import LocalProductDiscovery

final class AtlasProductInstallationTests: XCTestCase {
    @MainActor
    func testAutomaticDetectionIsTransientAndDoesNotChangeIntegrationIntent() async throws {
        let suite = "AtlasProductInstallationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AtlasSettingsRepository(defaults: defaults, namespace: "test.installations")
        let detector = CountingDetector(results: [
            .init(product: .claudeCode, status: .verified, evidence: .init(path: "/tools/claude", canonicalPath: "/tools/claude", source: .path, version: "1.2.3")),
            .init(product: .codexCLI, status: .notFound),
            .init(product: .cursor, status: .presentUnverified, evidence: .init(path: "/tools/cursor", canonicalPath: "/tools/cursor", source: .path, reason: .identityMismatch)),
        ])
        let model = AtlasSettingsModel(repository: repository, productInstallationDetector: detector)

        model.loadProductInstallationsIfNeeded()
        model.loadProductInstallationsIfNeeded()
        for _ in 0..<100 where model.productInstallations[.claudeCode]?.result == nil {
            await Task.yield()
        }

        XCTAssertEqual(model.productInstallations[.claudeCode]?.result?.status, .verified)
        XCTAssertEqual(model.productInstallations[.cursor]?.result?.status, .presentUnverified)
        let initialScanCount = await detector.scanCount()
        XCTAssertEqual(initialScanCount, 1)
        XCTAssertTrue(model.integrations.allSatisfy { !$0.enabledIntent })
        XCTAssertTrue(model.integrations.allSatisfy { !$0.detected })
        XCTAssertTrue(repository.loadIntegrations().allSatisfy { !$0.detected })
    }

    @MainActor
    func testManualRefreshRunsAgainAndKeepsPreviousEvidenceWhileChecking() async throws {
        let detector = CountingDetector(results: ProductCLI.allCases.map { .init(product: $0, status: .notFound) })
        let model = AtlasSettingsModel(productInstallationDetector: detector)
        model.loadProductInstallationsIfNeeded()
        for _ in 0..<100 where model.productInstallations[.cursor]?.result == nil { await Task.yield() }

        model.refreshProductInstallations()
        if case .checking(let previous) = model.productInstallations[.cursor] {
            XCTAssertEqual(previous?.status, .notFound)
        } else {
            XCTFail("refresh must publish checking with prior evidence")
        }
        for _ in 0..<100 {
            if await detector.scanCount() >= 2 { break }
            await Task.yield()
        }
        let refreshedScanCount = await detector.scanCount()
        XCTAssertEqual(refreshedScanCount, 2)
    }
}

private actor CountingDetector: ProductInstallationDetecting {
    private let results: [ProductInstallationResult]
    private var count = 0

    init(results: [ProductInstallationResult]) { self.results = results }

    func detectAll() async -> [ProductInstallationResult] {
        count += 1
        await Task.yield()
        return results
    }

    func detect(product: ProductCLI, explicitPath: String?) async -> ProductInstallationResult {
        results.first { $0.product == product } ?? .init(product: product, status: .notFound)
    }

    func scanCount() -> Int { count }
}
