import XCTest
@testable import ClaudeCodeAdapter
import SessionDomain

final class ClaudeStatusLineBridgeTests: XCTestCase {
    func testExistingStatusLineIsExternalAndNeverReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ab144-statusline-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("settings.jsonc")
        let original = "{\n // preserve\n \"statusLine\": {\"type\":\"command\",\"command\":\"person-output\"},\n \"unknown\": true\n}\n"
        try Data(original.utf8).write(to: config)
        let inspection = ClaudeStatusLineBridgeEditor.inspect(at: config)
        XCTAssertEqual(inspection.state, .externalCandidate)
        XCTAssertThrowsError(try ClaudeStatusLineBridgeEditor.add(at: config, expected: ExactEntryEditor.snapshot(at: config).fingerprint))
        XCTAssertEqual(ExactEntryEditor.snapshot(at: config).content, Data(original.utf8))
    }
}
