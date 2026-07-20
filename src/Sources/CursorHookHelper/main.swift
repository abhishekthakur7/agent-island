import Foundation
import CursorHooksAdapter

/// A fail-open placeholder for a future documented Cursor Hook command.
/// It intentionally writes nothing and always exits successfully so a
/// Product session cannot be blocked by an unsupported observation adapter.
@main
struct CursorHookHelperMain {
    static func main() {
        var body = Data()
        while let chunk = try? FileHandle.standardInput.read(upToCount: 8_193), !chunk.isEmpty {
            body.append(chunk)
            if body.count > CursorHookEnvelope.maximumBytes { return }
        }
        _ = CursorHookEnvelope.validate(body, contract: .init())
    }
}
