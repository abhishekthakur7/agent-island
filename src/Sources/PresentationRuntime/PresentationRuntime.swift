import Combine
import SessionDomain
import PresentationPort

/// Main-actor projection subscriber. This is the only view of application
/// state SwiftUI ever binds to; it cannot call an Adapter/Product client or
/// the canonical store because this target depends on `PresentationPort`
/// only, never on `SessionStore` or `AdapterPort`.
@MainActor
public final class PresentationRuntime: ObservableObject {
    @Published public private(set) var cards: [AgentSessionCardSnapshot] = []
    @Published public private(set) var ledgerRevision: Int64 = 0

    private nonisolated(unsafe) var subscription: Task<Void, Never>?

    public init(port: any PresentationPort) {
        let stream = port.presentationStream()
        subscription = Task { [weak self] in
            for await revision in stream {
                self?.apply(revision)
            }
        }
    }

    deinit {
        subscription?.cancel()
    }

    private func apply(_ revision: ProjectionRevision) {
        ledgerRevision = revision.ledgerRevision
        cards = revision.sessions.values
            .map(AgentSessionCardSnapshot.init(projection:))
            .sorted { lhs, rhs in
                // Horizon is a chronological flow. Source time is only used
                // when supplied by the Agent Product; stable identity makes
                // unsupplied/equal times deterministic without inventing an
                // order from receipt delivery.
                switch (lhs.sourceLastUpdated, rhs.sourceLastUpdated) {
                case let (left?, right?) where left != right:
                    return left > right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.id < rhs.id
                }
            }
    }
}
