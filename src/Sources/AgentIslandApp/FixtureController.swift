import Combine
import AdapterPort
import AdapterFixtureKit

/// Owns only a typed `AdapterIntakePort` reference — never `SessionStore` or
/// `ApplicationRuntime` concretely — so the SwiftUI buttons that trigger it
/// exercise exactly the same boundary a real Adapter would.
@MainActor
final class FixtureController: ObservableObject {
    @Published private(set) var log: [FixtureScenarioResult] = []
    @Published private(set) var isRunning = false

    private let port: any AdapterIntakePort

    init(port: any AdapterIntakePort) {
        self.port = port
    }

    func run(_ scenario: @escaping (any AdapterIntakePort) async -> FixtureScenarioResult) {
        guard !isRunning else { return }
        isRunning = true
        let boundPort = port
        Task { [weak self] in
            let result = await scenario(boundPort)
            self?.log.append(result)
            self?.isRunning = false
        }
    }
}
