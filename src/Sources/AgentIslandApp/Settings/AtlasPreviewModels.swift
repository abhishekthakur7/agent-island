import Foundation

public struct AtlasPreviewState: Equatable, Hashable, Sendable {
    public var general: AtlasGeneralPreferences
    public var isVisible: Bool
    public var isExpanded: Bool
    public var isHovered: Bool
    public var includesCompletion: Bool
    public var includesAttention: Bool

    public init(
        general: AtlasGeneralPreferences = .default,
        isVisible: Bool = false,
        isExpanded: Bool = false,
        isHovered: Bool = false,
        includesCompletion: Bool = true,
        includesAttention: Bool = true
    ) {
        self.general = general
        self.isVisible = isVisible
        self.isExpanded = isExpanded
        self.isHovered = isHovered
        self.includesCompletion = includesCompletion
        self.includesAttention = includesAttention
    }
}

public enum AtlasPreviewAction: Equatable, Sendable {
    case setGeneral(AtlasGeneralPreferences)
    case hoverEntered
    case hoverExited
    case revealCompletion
    case revealAttention
    case toggleCompletionFilter
    case toggleAttentionFilter
    case hide
    case reset
}

/// The trace is intentionally closed.  There is no alert, Overlay, Product,
/// configuration, or service event that a preview can emit.
public enum AtlasPreviewTrace: Equatable, Sendable {
    case previewStateChanged
}

public enum AtlasPreviewReducer {
    public static func reduce(_ input: AtlasPreviewState, action: AtlasPreviewAction) -> AtlasPreviewState {
        var state = input
        switch action {
        case let .setGeneral(general):
            state.general = general
        case .hoverEntered:
            state.isHovered = true
            if state.general.expandOnHover { state.isExpanded = true }
        case .hoverExited:
            state.isHovered = false
            if state.general.collapseOnPointerExit { state.isExpanded = false }
        case .revealCompletion:
            if state.includesCompletion && state.general.revealOnCompletion { state.isVisible = true }
        case .revealAttention:
            if state.includesAttention && state.general.revealOnAttention { state.isVisible = true }
        case .toggleCompletionFilter:
            state.includesCompletion.toggle()
        case .toggleAttentionFilter:
            state.includesAttention.toggle()
        case .hide:
            state.isVisible = false
        case .reset:
            state = AtlasPreviewState(general: state.general)
        }
        return state
    }
}

public protocol AtlasPreviewActionSink: AnyObject {
    func send(_ action: AtlasPreviewAction)
}

public final class AtlasPreviewRouter: AtlasPreviewActionSink {
    public private(set) var state: AtlasPreviewState
    public private(set) var trace: [AtlasPreviewTrace] = []

    public init(initialState: AtlasPreviewState = AtlasPreviewState()) {
        self.state = initialState
    }

    public func send(_ action: AtlasPreviewAction) {
        let next = AtlasPreviewReducer.reduce(state, action: action)
        guard next != state else { return }
        state = next
        trace.append(.previewStateChanged)
    }
}

public typealias AtlasPreviewActionRouter = AtlasPreviewRouter
