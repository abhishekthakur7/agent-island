import Foundation

public enum AtlasOnboardingLifecycle: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case notStarted
    case active
    case deferred
    case completed
}

/// The four durable education concepts.  Completion is tracked separately so
/// Back and Resume can never make a completed concept appear unfinished.
public enum AtlasOnboardingStep: Int, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case aggregation = 0
    case completionAwareness = 1
    case hostFallback = 2
    case setupAndDisplay = 3

    public static let first: Self = .aggregation
    public static let last: Self = .setupAndDisplay

    // Vocabulary aliases for callers that split setup and display in copy.
    public static var setup: Self { .setupAndDisplay }
    public static var display: Self { .setupAndDisplay }

    public var title: String {
        switch self {
        case .aggregation: "Aggregation"
        case .completionAwareness: "Completion awareness"
        case .hostFallback: "Host fallback"
        case .setupAndDisplay: "Setup and display"
        }
    }
}

public enum AtlasOnboardingAction: Equatable, Sendable {
    case start
    case back
    case next
    case skip
    case resume
    case complete
}

public struct AtlasOnboardingState: Codable, Equatable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var lifecycle: AtlasOnboardingLifecycle
    public var step: AtlasOnboardingStep
    public var completedSteps: Set<AtlasOnboardingStep>

    public init(
        schemaVersion: Int = AtlasOnboardingState.currentSchemaVersion,
        lifecycle: AtlasOnboardingLifecycle = .notStarted,
        step: AtlasOnboardingStep = .first,
        completedSteps: Set<AtlasOnboardingStep> = []
    ) {
        self.schemaVersion = schemaVersion
        self.lifecycle = lifecycle
        self.step = step
        self.completedSteps = completedSteps
    }

    public static let initial = AtlasOnboardingState()

    public static func resetForUnknownSchema() -> Self {
        Self(schemaVersion: currentSchemaVersion, lifecycle: .notStarted, step: .first, completedSteps: [])
    }

    public var allStepsCompleted: Bool { completedSteps.count == Self.steps.count }
    public var isComplete: Bool { lifecycle == .completed }
    public static var steps: [AtlasOnboardingStep] { AtlasOnboardingStep.allCases }

    /// Unknown schema is reset only to the onboarding baseline.  Invalid
    /// completion IDs are dropped while all other local settings remain out of
    /// scope for this normalization.
    public func normalized() -> Self {
        guard schemaVersion == Self.currentSchemaVersion else { return .resetForUnknownSchema() }
        var value = self
        value.completedSteps = value.completedSteps.intersection(Set(Self.steps))
        if value.lifecycle == .notStarted { value.step = .first }
        if value.lifecycle == .completed {
            value.completedSteps = Set(Self.steps)
            value.step = .last
        }
        if value.lifecycle == .active || value.lifecycle == .deferred,
           value.completedSteps.count == Self.steps.count {
            value.lifecycle = .completed
            value.step = .last
        }
        return value
    }

    public mutating func reduce(_ action: AtlasOnboardingAction) {
        self = AtlasOnboardingReducer.reduce(self, action: action)
    }

    public func reducing(_ action: AtlasOnboardingAction) -> Self {
        AtlasOnboardingReducer.reduce(self, action: action)
    }

    public mutating func start() { reduce(.start) }
    public mutating func back() { reduce(.back) }
    public mutating func next() { reduce(.next) }
    public mutating func skip() { reduce(.skip) }
    public mutating func resume() { reduce(.resume) }
    public mutating func complete() { reduce(.complete) }

    public var status: AtlasOnboardingLifecycle { lifecycle }
    public var currentStep: AtlasOnboardingStep { step }
    public var completedStepIDs: Set<AtlasOnboardingStep> {
        get { completedSteps }
        set { completedSteps = newValue }
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, lifecycle, step, completedSteps }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        lifecycle = try values.decodeIfPresent(AtlasOnboardingLifecycle.self, forKey: .lifecycle) ?? .notStarted
        step = try values.decodeIfPresent(AtlasOnboardingStep.self, forKey: .step) ?? .first
        completedSteps = try values.decodeIfPresent(Set<AtlasOnboardingStep>.self, forKey: .completedSteps) ?? []
    }
}

public enum AtlasOnboardingReducer {
    public static func reduce(_ input: AtlasOnboardingState, action: AtlasOnboardingAction) -> AtlasOnboardingState {
        var state = input.normalized()
        switch action {
        case .start:
            guard state.lifecycle == .notStarted || state.lifecycle == .deferred else { return state }
            state.lifecycle = state.allStepsCompleted ? .completed : .active
            if state.lifecycle == .active { state.step = firstIncomplete(from: state) }
        case .back:
            guard state.lifecycle == .active, state.step.rawValue > AtlasOnboardingStep.first.rawValue else { return state }
            state.step = AtlasOnboardingStep(rawValue: state.step.rawValue - 1) ?? .first
        case .next:
            guard state.lifecycle == .active else { return state }
            state.completedSteps.insert(state.step)
            if state.allStepsCompleted {
                state.lifecycle = .completed
                state.step = .last
            } else {
                state.step = firstIncomplete(from: state)
            }
        case .skip:
            guard state.lifecycle != .completed else { return state }
            state.lifecycle = .deferred
        case .resume:
            guard state.lifecycle == .deferred else { return state }
            if state.allStepsCompleted {
                state.lifecycle = .completed
                state.step = .last
            } else {
                state.lifecycle = .active
                state.step = firstIncomplete(from: state)
            }
        case .complete:
            guard state.lifecycle != .completed, state.allStepsCompleted else { return state }
            // Complete is intentionally a no-op until every step has been
            // acknowledged by Next.  This prevents a premature skip from
            // claiming that education was completed.
        }
        return state.normalized()
    }

    private static func firstIncomplete(from state: AtlasOnboardingState) -> AtlasOnboardingStep {
        AtlasOnboardingStep.allCases.first(where: { !state.completedSteps.contains($0) }) ?? .last
    }
}

public typealias AtlasOnboarding = AtlasOnboardingState
public typealias AtlasOnboardingStatus = AtlasOnboardingLifecycle
