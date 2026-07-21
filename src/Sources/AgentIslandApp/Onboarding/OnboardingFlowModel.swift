import Foundation

/// Per-agent install lifecycle `OnboardingConnectView`'s cards render
/// (AB-166 §2.3, AC-2.3-b). Keyed by `OnboardingAgent` (not
/// `AtlasIntegrationKind`) so every one of `orderedSelectedAgents` — including
/// the nine agents with no `integrationKind` — has an entry:
/// `idle` (before `beginAgentInstalls()` runs; never actually on screen) →
/// `installing` (spinner + "Installing X hooks…") → `connected` (settled,
/// check + "Connected"). `failed` is the real driver reporting
/// `.refused`/`.failed`; `skipped` is a `nil` `integrationKind` — nothing in
/// this codebase installs for it, so it is acknowledged immediately rather
/// than spinning on nothing.
enum OnboardingAgentInstallState: Equatable {
    case idle
    case installing
    case connected
    case failed(String)
    case skipped
}

/// AB-166's install-driver seam. The exact shape
/// `LaunchIntegrationAutoInstaller.installOnRequest()` already returns, and
/// the exact shape `AtlasSettingsModel.installHooks`
/// (`Settings/AtlasSettingsRepository.swift:232`) already injects elsewhere in
/// this codebase — reused verbatim rather than inventing a parallel type, per
/// this ticket's "wire the types to the real path" instruction.
///
/// `nil` (this file's only reachable value today) means there is no real
/// installer to call: the onboarding flow is not wired into `AppDelegate`'s
/// live startup yet (`OnboardingWindowCoordinator`'s own doc comment), so
/// `beginAgentInstalls()` falls back to its own safe timed placeholder
/// instead of ever fabricating a `LaunchInstallationReport` (constructing a
/// genuine `.installed` case needs a real negotiated `NegotiationSnapshot`,
/// which only a real adapter can produce). Once a later ticket wires
/// `OnboardingWindowCoordinator` into `AppDelegate`, the composition root
/// passes the same closure it already builds for Settings there
/// (`{ [installerRef] in await installerRef.value?.installOnRequest() ?? [:] }`,
/// `AppDelegate.swift:151`) in here too.
typealias OnboardingHookInstallDriver = @Sendable () async -> [AtlasIntegrationKind: LaunchInstallationReport]

/// AB-167's persistence seam ("A few preferences", §2.4). The exact two
/// setters this screen's two rows need on the real settings types —
/// `NotificationPolicySettingsModel.masterEnabled` (`SessionDomain`'s
/// `NotificationPolicy.masterEnabled` — the master gate for whether *any*
/// notification is allowed at all, `NotificationPolicySettingsModel.swift:17`,
/// default `true`) and `AtlasGeneralPreferences.launchAtLogin` (the
/// product-language alias over `launchBehavior`, `AtlasSettingsModels.swift:118`,
/// default `.manual` i.e. off) — reused as this seam's closure parameter
/// types rather than inventing a parallel enum, per this ticket's "wire the
/// types to the real path" instruction.
///
/// `nil` (this file's only reachable value today) means there is no real
/// settings model to write into yet — the same integration gap
/// `OnboardingHookInstallDriver` documents above: onboarding is not wired
/// into `AppDelegate`'s live startup yet. Once it is, the composition root
/// passes both closures over the two settings models it already owns there
/// (`notificationSettings`, `AppDelegate.swift:50`; `atlasSettings`,
/// `AppDelegate.swift:48/146`) — nothing new to construct:
/// `OnboardingPreferencesPersistence(
///     applyNotificationsEnabled: { [notificationSettings] in notificationSettings.masterEnabled = $0 },
///     applyLaunchAtLogin: { [atlasSettings] in atlasSettings.updateGeneral { $0.launchAtLogin = $1 } }
/// )`.
struct OnboardingPreferencesPersistence {
    var applyNotificationsEnabled: (Bool) -> Void
    var applyLaunchAtLogin: (Bool) -> Void
}

/// AB-164 — the shared onboarding flow model, originally forward-navigation
/// only. AB-165 (§2.2 agents grid) added the first real state — agent
/// multi-select — below; AB-166 (connect) extends this same file's shape
/// with per-agent install state rather than inventing its own model; AB-167
/// (a few preferences) does the same for the two preference toggles.
@MainActor
final class OnboardingFlowModel: ObservableObject {

    /// The four onboarding screens, in flow order. `Hashable` so a future
    /// screen can key off it (e.g. `.tag(_:)` in a `TabView`, or a
    /// `Dictionary` of per-screen state) without needing to add conformance
    /// later.
    enum OnboardingScreen: Hashable {
        case welcome
        case agents
        case connect
        case preferences
    }

    /// The screen currently on screen. `OnboardingRootView` switches on this.
    @Published var screen: OnboardingScreen = .welcome

    /// Called once the flow is finished (today: only reachable by a future
    /// ticket calling `complete()` from `.preferences`). The window
    /// coordinator or composition root is expected to set this — e.g. to
    /// close the onboarding window — so this model stays owner-agnostic and
    /// is still usable on its own (SwiftUI previews, standalone testing)
    /// with the harmless no-op default.
    var onComplete: () -> Void = {}

    /// See `OnboardingHookInstallDriver`'s doc comment above — `nil` (the
    /// default) is the only value anything constructs today, since nothing
    /// yet wires this model into `AppDelegate`'s live startup.
    private let installDriver: OnboardingHookInstallDriver?

    /// See `OnboardingPreferencesPersistence`'s doc comment above — `nil`
    /// (the default) is the only value anything constructs today, for the
    /// same reason `installDriver` is.
    private let preferencesPersistence: OnboardingPreferencesPersistence?

    init(
        installDriver: OnboardingHookInstallDriver? = nil,
        preferencesPersistence: OnboardingPreferencesPersistence? = nil
    ) {
        self.installDriver = installDriver
        self.preferencesPersistence = preferencesPersistence
    }

    // MARK: - Agent selection (AB-165 §2.2)

    /// The agents currently checked in the 3-column grid (AC-2.2-b). A `Set`
    /// because selection itself is unordered/toggle-only; `orderedSelectedAgents`
    /// below is the ordered view any consumer — including this screen's own
    /// grid highlighting and AB-166's Connect screen — should read instead of
    /// iterating this directly.
    @Published var selectedAgents: Set<OnboardingAgent> = []

    /// `selectedAgents` as the ordered subset of `OnboardingAgent.allCases` —
    /// i.e. in the same fixed grid order `OnboardingAgentsView` renders,
    /// never `Set`'s unspecified iteration order. AB-166 (Connect screen) is
    /// expected to read this — not `selectedAgents` directly — to show only
    /// the chosen agents in the order the user saw them.
    var orderedSelectedAgents: [OnboardingAgent] {
        OnboardingAgent.allCases.filter { selectedAgents.contains($0) }
    }

    /// Toggles one agent's membership in `selectedAgents`. The single
    /// mutation point `OnboardingAgentsView`'s card tap calls into, so
    /// selection logic lives here rather than duplicated at the call site.
    func toggleAgentSelection(_ agent: OnboardingAgent) {
        if selectedAgents.contains(agent) {
            selectedAgents.remove(agent)
        } else {
            selectedAgents.insert(agent)
        }
    }

    // MARK: - Agent connect / install (AB-166 §2.3)

    /// `OnboardingConnectView`'s per-card state (AC-2.3-b). Absent entries
    /// read as `.idle` (before `beginAgentInstalls()` has run for that
    /// agent) rather than crashing a lookup.
    @Published private(set) var installStates: [OnboardingAgent: OnboardingAgentInstallState] = [:]

    private var installTask: Task<Void, Never>?

    /// Starts the install pass for every currently `orderedSelectedAgents`,
    /// once. Called from `OnboardingConnectView`'s `.onAppear`; SwiftUI can
    /// re-fire `.onAppear` (e.g. window key-status churn), and a second call
    /// while one pass is already running must not restart or duplicate it.
    func beginAgentInstalls() {
        guard installTask == nil else { return }
        let agents = orderedSelectedAgents
        guard !agents.isEmpty else { return }
        for agent in agents {
            // A `nil` `integrationKind` (nine of the twelve agents) has
            // nothing installable in this codebase — acknowledged
            // immediately, never a spinner waiting on nothing.
            installStates[agent] = agent.integrationKind == nil ? .skipped : .installing
        }

        if let installDriver {
            // Real path: one bounded pass across every `AtlasIntegrationKind`
            // at once (ADR 0009 — `LaunchIntegrationAutoInstaller` cannot be
            // scoped to a single kind), exactly as `installOnRequest()`
            // already returns it.
            installTask = Task { [weak self] in
                let reports = await installDriver()
                guard !Task.isCancelled, let self else { return }
                for agent in agents {
                    guard let kind = agent.integrationKind else { continue }
                    self.installStates[agent] = Self.installState(forReport: reports[kind])
                }
                self.installTask = nil
            }
        } else {
            // SAFE DEFAULT DRIVER (placeholder): nothing constructs a real
            // `LaunchIntegrationAutoInstaller` at startup yet (see
            // `OnboardingHookInstallDriver`'s doc comment), so there is no
            // real installer to call here. This walks each installable
            // selected agent from `installing` to `connected` on a short,
            // staggered timer purely so this screen is self-contained and
            // visually verifiable standalone — it performs no file, hook, or
            // process I/O and reports no real installation outcome. It is a
            // UI-only stand-in for the real pass above, NOT a claim that a
            // real install happened, and this branch stops being reachable
            // the moment a real `installDriver` is injected.
            installTask = Task { [weak self] in
                for (index, agent) in agents.enumerated() where agent.integrationKind != nil {
                    let delayNanoseconds = 900_000_000 + UInt64(index) * 350_000_000
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    guard !Task.isCancelled else { return }
                    self?.installStates[agent] = .connected
                }
                self?.installTask = nil
            }
        }
    }

    private static func installState(forReport report: LaunchInstallationReport?) -> OnboardingAgentInstallState {
        switch report {
        case .installed: return .connected
        case .refused(let message), .failed(let message): return .failed(message)
        case nil: return .failed("No install outcome was reported for this agent.")
        }
    }

    // MARK: - Preferences (AB-167 §2.4)

    /// AC-2.4-b's "Notifications" row — ON by default, mirroring
    /// `NotificationPolicy.masterEnabled`'s own `true` default (see
    /// `OnboardingPreferencesPersistence`'s doc comment) so a fresh flow's
    /// resting value already matches the real setting it will eventually
    /// write, even before `complete()` ever applies it.
    @Published var notificationsEnabled: Bool = true

    /// AC-2.4-b's "Launch at login" row — OFF by default, mirroring
    /// `AtlasGeneralPreferences.launchBehavior`'s own `.manual` default.
    @Published var launchAtLoginEnabled: Bool = false

    /// Single mutation point for the "Notifications" row's tap — same style
    /// as `toggleAgentSelection(_:)` above.
    func toggleNotifications() {
        notificationsEnabled.toggle()
    }

    /// Single mutation point for the "Launch at login" row's tap.
    func toggleLaunchAtLogin() {
        launchAtLoginEnabled.toggle()
    }

    // MARK: - Navigation

    /// welcome → agents → connect → preferences. No-op once already on
    /// `.preferences`; that screen finishes the flow via `complete()`
    /// instead of advancing further.
    func advance() {
        switch screen {
        case .welcome: screen = .agents
        case .agents: screen = .connect
        case .connect: screen = .preferences
        case .preferences: break
        }
    }

    /// Reverse of `advance()`. No-op on `.welcome` — AC-2.1-b: the welcome
    /// screen has no back button, and there is nowhere before it to go back
    /// to.
    func back() {
        switch screen {
        case .welcome: break
        case .agents: screen = .welcome
        case .connect: screen = .agents
        case .preferences: screen = .connect
        }
    }

    /// Ends the flow. Applies the two preference rows to the injected
    /// `preferencesPersistence` seam, then invokes `onComplete`.
    ///
    /// Applied once, here, on the explicit "Continue" tap — not live as each
    /// row is toggled — since completing onboarding is this screen's one
    /// commit point and nothing needs the interim in-flight value to be
    /// durable before then. With no seam injected (today's only reachable
    /// case — see `OnboardingPreferencesPersistence`'s doc comment) this is
    /// UI-state-only: `notificationsEnabled`/`launchAtLoginEnabled` simply
    /// hold their toggled value in memory, and nothing is written to a real
    /// setting — NOT a claim that persistence happened, pending AppDelegate
    /// wiring a real seam.
    ///
    /// Deliberately does not reset `screen` itself, since the expected caller
    /// (the window coordinator) closes the window right after, and a fresh
    /// `OnboardingFlowModel` instance is the right way to reset for a
    /// subsequent run.
    func complete() {
        preferencesPersistence?.applyNotificationsEnabled(notificationsEnabled)
        preferencesPersistence?.applyLaunchAtLogin(launchAtLoginEnabled)
        onComplete()
    }
}
