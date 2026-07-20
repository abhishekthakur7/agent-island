import Foundation
import SwiftUI
import SessionDomain

/// Presentation state for one Guided sheet.  Selection is stable by native
/// request identity: arrivals update the queue indicator but never replace a
/// focused item or discard its draft.
@MainActor
public final class GuidedSheetModel: ObservableObject {
    @Published public private(set) var requests: [GuidedAttentionRequest] = []
    @Published public private(set) var selectedRequestID: GuidedAttentionRequestID?
    @Published public private(set) var isCollapsed = false
    @Published public private(set) var isTextEntryFocused = false
    @Published public private(set) var announcement: String?
    private var announcementLedger = AccessibilityAnnouncementLedger()

    public init(requests: [GuidedAttentionRequest] = []) {
        apply(requests: requests)
    }

    public var selectedRequest: GuidedAttentionRequest? {
        guard let selectedRequestID else { return nil }
        return requests.first { $0.id == selectedRequestID }
    }

    public var pendingCount: Int { requests.filter { $0.sourceOutcome == .pending }.count }

    public var selectedStage: GuidedAttentionStage { selectedRequest?.stage ?? .arrived }

    public var canAdvance: Bool {
        guard let request = selectedRequest else { return false }
        switch request.stage {
        case .arrived: return true
        case .review: return true
        case .respond:
            guard request.sourceOutcome == .pending else { return false }
            switch request.semanticShape.kind {
            case .structuredChoice:
                if case .success = request.draft.validating(against: request.semanticShape) { return true }
                return false
            case .turnInput, .interruption:
                return request.draft.freeText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            case .allowDeny, .persistentSuggestion, .planReview, .productExtension:
                return true
            }
        case .acknowledged: return false
        }
    }

    /// Applies a durable snapshot while preserving the current selection and
    /// text-entry focus when that native request remains present.
    public func apply(requests newRequests: [GuidedAttentionRequest]) {
        let prior = selectedRequestID
        let priorByID = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0) })
        requests = newRequests.map { incoming in
            guard let previous = priorByID[incoming.id] else { return incoming }
            var retained = incoming
            if retained.draft == .empty, previous.draft != .empty { retained.draft = previous.draft }
            if previous.stage != .arrived, retained.stage == .arrived { retained.stage = previous.stage }
            if previous.localPresentation != .queued, retained.localPresentation == .queued { retained.localPresentation = previous.localPresentation }
            return retained
        }.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
            if lhs.sourceObservedAt != rhs.sourceObservedAt { return lhs.sourceObservedAt < rhs.sourceObservedAt }
            return lhs.id.id < rhs.id.id
        }
        let candidates = requests.filter { incoming in
            guard let previous = priorByID[incoming.id] else { return incoming.sourceOutcome == .pending }
            return incoming.priority.rawValue > previous.priority.rawValue
        }
        if let candidate = candidates.first,
           let text = announcementLedger.announce(
               requestID: candidate.id.id,
               priority: candidate.priority.rawValue,
               owner: candidate.owner.productNamespace.rawValue + " / " + candidate.owner.nativeSessionID.rawValue
           ) {
            announcement = text
        }
        if let prior, requests.contains(where: { $0.id == prior }) {
            selectedRequestID = prior
        } else if selectedRequestID == nil, let first = requests.first(where: { $0.sourceOutcome == .pending }) ?? requests.first {
            selectedRequestID = first.id
        } else if selectedRequestID != nil, !requests.contains(where: { $0.id == selectedRequestID }) {
            selectedRequestID = requests.first?.id
            isTextEntryFocused = false
        }
    }

    public func select(_ id: GuidedAttentionRequestID) {
        guard requests.contains(where: { $0.id == id }) else { return }
        selectedRequestID = id
        announcement = "Selected Attention Request from \(id.productNamespace.rawValue)"
    }

    public func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        if collapsed { isTextEntryFocused = false }
    }

    public func setTextEntryFocused(_ focused: Bool) { isTextEntryFocused = focused }

    public func advance() {
        guard canAdvance, let id = selectedRequestID, let index = requests.firstIndex(where: { $0.id == id }) else { return }
        var request = requests[index]
        switch request.stage {
        case .arrived: request.stage = .review
        case .review: request.stage = .respond
        case .respond: request.stage = .acknowledged; request.localPresentation = .acknowledged
        case .acknowledged: return
        }
        requests[index] = request
    }

    public func toggleChoice(_ choiceID: String) {
        guard !isTextEntryFocused, let id = selectedRequestID, let index = requests.firstIndex(where: { $0.id == id }) else { return }
        var request = requests[index]
        guard request.semanticShape.choices.contains(where: { $0.id == choiceID }) else { return }
        if request.semanticShape.allowsMultipleSelection {
            if request.draft.selectedChoiceIDs.contains(choiceID) {
                request.draft = GuidedAttentionDraft(selectedChoiceIDs: request.draft.selectedChoiceIDs.filter { $0 != choiceID }, freeText: request.draft.freeText, questionIndex: request.draft.questionIndex)
            } else {
                request.draft = GuidedAttentionDraft(selectedChoiceIDs: request.draft.selectedChoiceIDs + [choiceID], freeText: request.draft.freeText, questionIndex: request.draft.questionIndex)
            }
        } else {
            request.draft = GuidedAttentionDraft(selectedChoiceIDs: request.draft.selectedChoiceIDs == [choiceID] ? [] : [choiceID], freeText: request.draft.freeText, questionIndex: request.draft.questionIndex)
        }
        requests[index] = request
    }

    /// Number shortcuts are intentionally ignored while a text editor has
    /// focus, preventing accidental selection while entering a draft.
    @discardableResult
    public func handleNumberShortcut(_ number: Int) -> Bool {
        guard !isTextEntryFocused, let request = selectedRequest, number > 0,
              request.semanticShape.choices.indices.contains(number - 1)
        else { return false }
        toggleChoice(request.semanticShape.choices[number - 1].id)
        return true
    }
}
