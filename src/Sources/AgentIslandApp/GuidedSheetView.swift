import SwiftUI
import SessionDomain

/// Compact, non-modal Guided surface.  Its labels keep stage, owner,
/// consequence, and Host fallback available to VoiceOver and high-contrast
/// users without relying on color or animation.
public struct GuidedSheetView: View {
    @ObservedObject private var model: GuidedSheetModel
    private let onAdvance: () -> Void
    private let onCollapse: () -> Void
    private let onContinueInHost: () -> Void

    public init(
        model: GuidedSheetModel,
        onAdvance: @escaping () -> Void = {},
        onCollapse: @escaping () -> Void = {},
        onContinueInHost: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onAdvance = onAdvance
        self.onCollapse = onCollapse
        self.onContinueInHost = onContinueInHost
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !model.isCollapsed {
                stageBar
                queue
                detail
            }
        }
        .padding(16)
        .frame(minWidth: 360, idealWidth: 520, maxWidth: 620)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Guided Attention Request sheet")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Guided workflow").font(.headline)
                Text("\(model.pendingCount) pending Attention Requests")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Collapse", action: onCollapse)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityHint("Hides the sheet without resolving the source request")
        }
    }

    private var stageBar: some View {
        HStack(spacing: 6) {
            ForEach(GuidedAttentionStage.allCases, id: \.self) { stage in
                Text(stage.title)
                    .font(.caption.weight(stage == model.selectedStage ? .bold : .regular))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 7)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(stage == model.selectedStage ? Color.accentColor : .secondary))
                    .accessibilityLabel("Stage \(stage.title)\(stage == model.selectedStage ? ", current" : "")")
            }
        }
    }

    private var queue: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.requests) { request in
                    Button {
                        model.select(request.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.displayTitle ?? "Attention Request")
                                .lineLimit(1)
                            Text(request.priority == .urgent ? "Urgent" : request.sourceVariant)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(request.id == model.selectedRequestID ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attention Request from \(request.owner.productNamespace.rawValue), \(request.stage.title)")
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let request = model.selectedRequest {
            VStack(alignment: .leading, spacing: 10) {
                Text(request.displayTitle ?? "Attention Request")
                    .font(.title3.weight(.semibold))
                Text("Owner: \(request.owner.productNamespace.rawValue) • Session \(request.owner.nativeSessionID.rawValue)")
                    .font(.caption)
                    .accessibilityLabel("Owning Agent Product \(request.owner.productNamespace.rawValue), Agent Session \(request.owner.nativeSessionID.rawValue)")
                if let host = request.hostLabel { Text("Host: \(host)").font(.caption) }

                if request.sourceOutcome != .pending || !request.canRouteAction {
                    Text("Source: \(request.sourceOutcome == .resolvedElsewhere ? "Resolved elsewhere" : "Unavailable")")
                        .foregroundStyle(.secondary)
                    if request.sourceOutcome == .pending {
                        Text(request.routingAvailability == .observationOnly ? "This integration can observe but cannot answer from Agent Island." : "The Action capability is stale or unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Continue in Host / Jump Back", action: onContinueInHost)
                        .accessibilityHint("No action is sent from Agent Island")
                } else {
                    responseShape(request)
                    Button(model.selectedStage == .respond ? "Acknowledge" : "Next", action: onAdvance)
                        .disabled(!model.canAdvance)
                        .accessibilityLabel(model.selectedStage == .respond ? "Acknowledge without resolving the Product request" : "Next stage")
                }
            }
        } else {
            Text("No Attention Request selected").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func responseShape(_ request: GuidedAttentionRequest) -> some View {
        switch request.semanticShape.kind {
        case .structuredChoice:
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose a response")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(request.semanticShape.choices.enumerated()), id: \.element.id) { index, choice in
                    Button {
                        model.handleNumberShortcut(index + 1)
                    } label: {
                        HStack {
                            Text("\(index + 1). \(choice.label)")
                            if choice.recommended { Text("Recommended").font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            if request.draft.selectedChoiceIDs.contains(choice.id) { Image(systemName: "checkmark") }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choice \(index + 1), \(choice.label)\(choice.recommended ? ", recommended but not selected" : "")")
                }
            }
        case .allowDeny:
            HStack {
                Text("Source-provided allow or deny")
                Spacer()
                Text("No default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .persistentSuggestion:
            Text("Source-provided persistent suggestion")
        case .planReview:
            Text("Review the Product plan, then accept or reject with reason.")
        case .turnInput, .interruption:
            Text("Continue in Host / Jump Back for this Product-native action.")
        case .productExtension:
            Text("Product-specific response")
        }
    }
}
