import Foundation
import Combine
import SessionDomain

/// A volatile, typed display boundary for Usage Snapshots. It deliberately
/// holds no SessionStore, notification, queue, action, or navigation port.
/// Adapters call this only after a live negotiated `usage.observation` claim
/// and after supplying a source-owned snapshot; no screen scraping or
/// arithmetic-derived usage can enter here.
@MainActor
final class UsagePresentationModel: ObservableObject {
    struct Source: Equatable {
        let snapshot: UsageSnapshot
        let negotiation: NegotiationSnapshot
        let sessionIdentity: AgentSessionIdentity?
        let receivedAt: Date

        var isLiveCompatible: Bool {
            negotiation.grants(WellKnownCapability.usageObservation, direction: .observe)
        }
    }

    struct Rendered: Equatable {
        let state: UsageSnapshotState
        let snapshot: UsageSnapshot?
        let valueKind: UsageValueKind
        let unavailableReason: String?

        var canAppearInExpandedHeader: Bool {
            snapshot != nil && [.fresh, .stale, .missing].contains(state)
        }
    }

    @Published private(set) var preferences: UsageDisplayPreferences
    @Published private(set) var rendered: Rendered

    var availableProviders: [String] {
        Array(Set(sources.values.filter(\.isLiveCompatible).map { $0.snapshot.provider })).sorted()
    }

    private var sources: [String: Source] = [:]
    private var selectedActiveSession: AgentSessionIdentity?
    private let staleAfter: TimeInterval

    init(preferences: UsageDisplayPreferences = .default, staleAfter: TimeInterval = 300) {
        self.preferences = preferences
        self.staleAfter = staleAfter
        self.rendered = Rendered(state: .unavailable, snapshot: nil, valueKind: preferences.valueKind, unavailableReason: "No live Agent Adapter has supplied Usage Snapshot evidence. Cursor Hooks and ACP do not expose usage observation.")
    }

    func updatePreferences(_ preferences: UsageDisplayPreferences, now: Date = Date()) {
        self.preferences = preferences
        recompute(now: now)
    }

    /// The caller's negotiation is checked again at the presentation seam;
    /// a Product name alone can never make a source eligible.
    func receive(_ source: Source, now: Date = Date()) {
        guard source.isLiveCompatible else { return }
        sources[source.snapshot.sourceID] = source
        recompute(now: now)
    }

    func withdraw(sourceID: String, now: Date = Date()) {
        sources.removeValue(forKey: sourceID)
        recompute(now: now)
    }

    /// Selection is provided as exact source-owned identity by composition.
    /// Nil/multiple selection never falls back to a plausible provider.
    func selectActiveSession(_ identity: AgentSessionIdentity?, now: Date = Date()) {
        selectedActiveSession = identity
        recompute(now: now)
    }

    func refresh(now: Date = Date()) { recompute(now: now) }

    private func recompute(now: Date) {
        guard preferences.isVisible else {
            rendered = Rendered(state: .disabled, snapshot: nil, valueKind: preferences.valueKind, unavailableReason: "Usage display is off.")
            return
        }
        let eligible = sources.values.filter(\.isLiveCompatible)
        let matching: [Source]
        switch preferences.providerSelection {
        case let .preferred(provider):
            matching = eligible.filter { $0.snapshot.provider == provider }
        case .followSelectedActiveSession:
            guard let selectedActiveSession else {
                rendered = Rendered(state: .unavailable, snapshot: nil, valueKind: preferences.valueKind, unavailableReason: "No single selected active Agent Session has eligible Usage Snapshot evidence.")
                return
            }
            matching = eligible.filter { $0.sessionIdentity == selectedActiveSession }
        }
        guard matching.count == 1, let source = matching.first else {
            rendered = Rendered(state: .unavailable, snapshot: nil, valueKind: preferences.valueKind, unavailableReason: matching.isEmpty ? "The selected source is unavailable." : "More than one source matched; select a preferred provider.")
            return
        }
        let snapshot = source.snapshot
        let state: UsageSnapshotState
        if !snapshot.hasSourcedValue || preferences.valueKind.value(in: snapshot) == nil {
            state = .missing
        } else if now.timeIntervalSince(snapshot.observedAt) > staleAfter {
            state = .stale
        } else {
            state = .fresh
        }
        rendered = Rendered(state: state, snapshot: snapshot, valueKind: preferences.valueKind, unavailableReason: nil)
    }
}

/// Small local preferences boundary separate from Atlas presentation state.
/// It persists only a person's display choices, never Usage Snapshot values
/// or Product/session identifiers.
struct UsageSettingsRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "com.agentisland.usage.display-preferences") {
        self.defaults = defaults; self.key = key
    }

    func load() -> UsageDisplayPreferences {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(UsageDisplayPreferences.self, from: data) else { return .default }
        return value
    }

    func save(_ value: UsageDisplayPreferences) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

@MainActor
final class UsageSettingsModel: ObservableObject {
    @Published private(set) var preferences: UsageDisplayPreferences
    let presentation: UsagePresentationModel
    private let repository: UsageSettingsRepository

    init(repository: UsageSettingsRepository = UsageSettingsRepository(), presentation: UsagePresentationModel? = nil) {
        self.repository = repository
        let preferences = repository.load()
        self.preferences = preferences
        self.presentation = presentation ?? UsagePresentationModel(preferences: preferences)
    }

    func update(_ change: (inout UsageDisplayPreferences) -> Void) {
        var next = preferences
        change(&next)
        guard next != preferences else { return }
        preferences = next
        repository.save(next)
        presentation.updatePreferences(next)
    }
}
