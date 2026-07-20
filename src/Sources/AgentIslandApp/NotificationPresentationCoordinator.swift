import Foundation
import Combine
import SessionDomain

public struct NotificationPresentationResult: Sendable, Equatable {
    public let decision: AlertPresentationDecision
    public let retargetedExistingPresentation: Bool
    public let bannerPosted: Bool
    public let soundPlayed: Bool

    public init(decision: AlertPresentationDecision, retargetedExistingPresentation: Bool, bannerPosted: Bool, soundPlayed: Bool) {
        self.decision = decision
        self.retargetedExistingPresentation = retargetedExistingPresentation
        self.bannerPosted = bannerPosted
        self.soundPlayed = soundPlayed
    }
}

/// Inward-facing banner boundary used by the coordinator. Tests and the shell
/// can provide a deterministic adapter without giving it Product authority.
@MainActor
public protocol NotificationBannerPort: AnyObject {
    func post(_ facet: NotificationBannerFacet) async -> Bool
}

@MainActor
extension MacNotificationAdapter: NotificationBannerPort {}

/// One coordinator owns all automatic presentation facets. There is one
/// current primary decision, one sound lease per candidate, and one banner per
/// candidate; arrivals retarget/coalesce rather than create stacks.
@MainActor
public final class NotificationPresentationCoordinator: ObservableObject {
    @Published public private(set) var currentDecision: AlertPresentationDecision?
    @Published public private(set) var currentCandidate: AlertCandidate?

    public private(set) var policy: NotificationPolicy
    public private(set) var lastEvaluation: AlertPresentationDecision?

    private weak var bannerPort: (any NotificationBannerPort)?
    private let soundAdapter: LocalSoundAdapter?
    private let clock: () -> Date
    private var latestRevisionByCandidate: [AlertCandidateID: Int64] = [:]
    private var bannersDelivered: Set<AlertCandidateID> = []
    private var soundsDelivered: Set<AlertCandidateID> = []
    private var leases: [AlertCandidateID: SoundPlaybackLease] = [:]
    private var dwellWork: DispatchWorkItem?
    private var restoredBoundary = false
    private var guardedCandidateID: AlertCandidateID?

    public init(
        policy: NotificationPolicy = .default,
        bannerPort: (any NotificationBannerPort)? = nil,
        soundAdapter: LocalSoundAdapter? = nil,
        clock: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.bannerPort = bannerPort
        self.soundAdapter = soundAdapter
        self.clock = clock
    }

    public func update(policy: NotificationPolicy) { self.policy = policy }

    public func beginInteraction(for candidateID: AlertCandidateID) {
        guardedCandidateID = candidateID
    }

    public func endInteraction() {
        guardedCandidateID = nil
    }

    /// Mark restored durable state as already observed.  This boundary is
    /// intentionally sticky until a fresh source revision arrives.
    public func restore(_ candidates: [AlertCandidate]) {
        restoredBoundary = true
        for candidate in candidates { latestRevisionByCandidate[candidate.id] = max(latestRevisionByCandidate[candidate.id] ?? 0, candidate.sourceRevision) }
    }

    public func clearRestartBoundary() { restoredBoundary = false }

    @discardableResult
    public func submit(
        _ candidate: AlertCandidate,
        quietScene: QuietScene = .inactive,
        exactForeground: ExactForegroundRelevance = .none,
        currentRevision: Int64? = nil
    ) async -> NotificationPresentationResult {
        let hadCurrent = currentDecision != nil
        let priorityGuard = currentCandidate?.semanticClass == .attention ? currentCandidate?.id : nil
        let restoredCandidate = restoredBoundary && latestRevisionByCandidate[candidate.id] == candidate.sourceRevision
        let context = AlertEvaluationContext(
            policy: policy,
            quietScene: quietScene,
            exactForeground: exactForeground,
            currentRevision: currentRevision ?? candidate.sourceRevision,
            latestRevisionByCandidate: latestRevisionByCandidate,
            now: clock(),
            interactionGuardedCandidateID: guardedCandidateID ?? priorityGuard,
            restoredFromRestart: restoredCandidate
        )
        let decision = NotificationPolicyEvaluator.evaluate(candidate, context: context)
        lastEvaluation = decision
        latestRevisionByCandidate[candidate.id] = max(latestRevisionByCandidate[candidate.id] ?? 0, candidate.sourceRevision)
        // A genuinely fresh event after restart is eligible; restored
        // candidates remain suppressed by the per-candidate boundary.

        guard decision.reason == .eligible else {
            // Quiet Scene and filtering intentionally do not retain a replay
            // queue. The durable candidate remains available to inspection.
            return NotificationPresentationResult(decision: decision, retargetedExistingPresentation: false, bannerPosted: false, soundPlayed: false)
        }

        // Child completion is represented inside its parent card. It remains
        // observable as a policy decision but never becomes a top-level
        // primary, banner, or sound facet.
        if candidate.semanticClass == .childCompletion {
            return NotificationPresentationResult(decision: decision, retargetedExistingPresentation: false, bannerPosted: false, soundPlayed: false)
        }

        let retargeted = hadCurrent && currentCandidate?.id != candidate.id
        currentCandidate = candidate
        currentDecision = decision

        var playedSound = false
        if !hadCurrent, let sound = decision.sound, !soundsDelivered.contains(candidate.id), let lease = soundAdapter?.play(sound, now: clock()) {
            soundsDelivered.insert(candidate.id)
            leases[candidate.id] = lease
            let candidateID = candidate.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.releaseSound(for: candidateID)
            }
            playedSound = true
        }

        var postedBanner = false
        if !hadCurrent, let banner = decision.banner, !bannersDelivered.contains(candidate.id), let bannerPort {
            postedBanner = await bannerPort.post(banner)
            if postedBanner { bannersDelivered.insert(candidate.id) }
        }

        scheduleDwell(for: candidate, decision: decision)
        return NotificationPresentationResult(decision: decision, retargetedExistingPresentation: retargeted, bannerPosted: postedBanner, soundPlayed: playedSound)
    }

    public func releaseSound(for candidateID: AlertCandidateID) {
        guard let lease = leases.removeValue(forKey: candidateID) else { return }
        soundAdapter?.release(lease)
    }

    public func dismissCurrent() {
        dwellWork?.cancel()
        dwellWork = nil
        currentDecision = nil
        currentCandidate = nil
    }

    private func scheduleDwell(for candidate: AlertCandidate, decision: AlertPresentationDecision) {
        dwellWork?.cancel()
        guard decision.primary.presentation == .focusedReveal,
              guardedCandidateID != candidate.id,
              candidate.semanticClass != .attention,
              let dwell = candidate.dwell
        else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.guardedCandidateID == nil, self.currentCandidate?.id == candidate.id else { return }
            self.currentDecision = AlertPresentationDecision(candidateID: candidate.id, primary: AlertPrimaryFacet(candidateID: candidate.id, presentation: .collapsedGlow), sound: nil, banner: nil, reason: .eligible, steps: decision.steps)
        }
        dwellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell.maximum, execute: work)
    }
}

public typealias AlertPresentationCoordinator = NotificationPresentationCoordinator
