import AppKit
import SwiftUI
import CursorACPAdapter
import SessionDomain

/// A deliberately small production Settings seam. It starts a fresh ACP
/// child only after a person selects an executable and presses Start; it has
/// no discovery/list/adoption control for any existing Cursor surface.
@MainActor
struct CursorACPSettingsControls: View {
    let composition: CursorACPApplicationComposition
    @ObservedObject private var model: CursorACPSettingsModel

    init(composition: CursorACPApplicationComposition) {
        self.composition = composition
        self.model = composition.settingsModel
    }

    var body: some View {
        GroupBox("Cursor ACP controlled sessions") {
            Text("Agent Island starts a fresh Cursor ACP child only. It never scans, adopts, or controls existing Cursor IDE, CLI, SDK, or headless sessions.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Cursor executable", text: $model.executablePath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Cursor ACP executable path")
                Button("Choose…", action: chooseExecutable)
                    .accessibilityHint("Select the Cursor executable to use for one new ACP session")
            }
            Button("Start new controlled Cursor session") { Task { await start() } }
                .buttonStyle(.borderedProminent)
                .disabled(!FileManager.default.isExecutableFile(atPath: model.executablePath))
                .accessibilityIdentifier("cursor-acp.start")
                .accessibilityHint("Starts a new Agent Island controlled ACP session; existing Cursor sessions are not used")
            Text(model.status).font(.caption).foregroundStyle(.secondary).accessibilityLabel("Cursor ACP status: \(model.status)")
            Divider()
            HStack {
                Text("Guided responses").font(.headline)
                Spacer()
                Button("Refresh") { Task { await reload() } }
                    .accessibilityLabel("Refresh Cursor ACP Attention Requests")
            }
            if model.requests.isEmpty {
                Text("No live Cursor ACP Attention Requests.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.requests) { request in
                    CursorACPGuidedRequest(request: request, draft: draftBinding(for: request), rejectReason: rejectReasonBinding(for: request), submit: { action in await submit(request, action: action) })
                }
            }
        }
        .task {
            // Bounded, cancellation-aware refresh while this Settings view is
            // visible. The adapter reader owns ingress; this only refreshes
            // the already-canonical Guided projection for SwiftUI.
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = "Choose the Cursor executable for a new controlled ACP session"
        if panel.runModal() == .OK, let url = panel.url { model.executablePath = url.path }
    }

    private func start() async {
        guard FileManager.default.isExecutableFile(atPath: model.executablePath) else { model.status = "The selected file is not executable."; return }
        switch await composition.start(cursorExecutable: URL(fileURLWithPath: model.executablePath), arguments: ["agent", "--acp"]) {
        case .success(let identity): model.status = "Started controlled session \(identity.nativeSessionID.rawValue)."
        case .failure(let failure): model.status = "Unavailable: \(failure.rawValue). Continue in the native Host."
        }
        await reload()
    }

    private func reload() async {
        model.requests = await composition.attentionRequests()
        for request in model.requests where model.drafts[request.id] == nil { model.drafts[request.id] = request.draft }
    }

    private func draftBinding(for request: GuidedAttentionRequest) -> Binding<GuidedAttentionDraft> {
        Binding(get: { model.drafts[request.id] ?? request.draft }, set: { next in
            model.drafts[request.id] = next
            Task { _ = await composition.updateDraft(request.id, draft: next) }
        })
    }

    private func rejectReasonBinding(for request: GuidedAttentionRequest) -> Binding<String> {
        Binding(get: { model.rejectReasons[request.id] ?? "" }, set: { model.rejectReasons[request.id] = $0 })
    }

    private func submit(_ request: GuidedAttentionRequest, action: GuidedAction) async {
        let result = await composition.submit(requestID: request.id, action: action, attemptID: UUID().uuidString, confirmed: true)
        switch result {
        case .dispatched: model.status = "Response handed off; awaiting source evidence."
        case .unavailable(let failure, _): model.status = "Unavailable: \(failure.rawValue). Continue in the native Host."
        }
        await reload()
    }
}

@MainActor
private struct CursorACPGuidedRequest: View {
    let request: GuidedAttentionRequest
    @Binding var draft: GuidedAttentionDraft
    @Binding var rejectReason: String
    let submit: (GuidedAction) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.sourceVariant).font(.subheadline.weight(.semibold))
            Text("Session \(request.owner.nativeSessionID.rawValue)").font(.caption).foregroundStyle(.secondary)
            if request.sourceOutcome != .pending { Text("Resolved or unavailable; use the native Host.").foregroundStyle(.secondary) }
            else { response }
        }
        .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cursor ACP Guided Attention Request")
    }

    @ViewBuilder private var response: some View {
        switch request.semanticShape.kind {
        case .allowDeny:
            HStack {
                if offered.contains("allow-once") { actionButton("Allow once", action: .allow, key: "a") }
                if offered.contains("allow-always") { actionButton("Allow always", action: .persistentSuggestion(allow: true), key: "l") }
                if offered.contains("reject-once") { actionButton("Reject once", action: .deny, key: "r") }
            }
        case .structuredChoice:
            VStack(alignment: .leading, spacing: 5) {
                Text("Choose one or more responses. No default is selected.").font(.caption)
                ForEach(Array(request.semanticShape.choices.enumerated()), id: \.element.id) { index, choice in
                    Toggle(choice.label, isOn: selectionBinding(choice.id))
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Choice \(index + 1): \(choice.label), not selected by default")
                        .onAppear { if !request.semanticShape.allowsMultipleSelection && draft.selectedChoiceIDs.count > 1 { draft = .empty } }
                }
                actionButton("Submit choices", action: .structuredResponse(.init(selectedChoiceIDs: draft.selectedChoiceIDs, freeText: draft.freeText)), disabled: !isValidDraft, key: .return)
            }
        case .planReview:
            HStack {
                actionButton("Accept plan", action: .planReview(.accept, reason: nil), key: "a")
                actionButton("Cancel plan review", action: .planReview(.cancel, reason: nil), key: .escape)
            }
            TextField("Reason required to reject", text: $rejectReason)
                .accessibilityLabel("Reason for rejecting plan")
            actionButton("Reject plan", action: .planReview(.reject, reason: rejectReason), disabled: rejectReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key: "r")
        default:
            Text("This source response is unavailable in Agent Island. Continue in the native Host.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var offered: Set<String> { Set((request.capability.constraints["offeredResponses"] ?? "").split(separator: ",").map(String.init)) }
    private var isValidDraft: Bool { if case .success = draft.validating(against: request.semanticShape) { return true }; return false }
    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { draft.selectedChoiceIDs.contains(id) }, set: { selected in
            var next = draft.selectedChoiceIDs.filter { $0 != id }
            if selected { next = request.semanticShape.allowsMultipleSelection ? next + [id] : [id] }
            draft = GuidedAttentionDraft(selectedChoiceIDs: next, freeText: draft.freeText, questionIndex: draft.questionIndex)
        })
    }
    @ViewBuilder private func actionButton(_ title: String, action: GuidedAction, disabled: Bool = false, key: KeyEquivalent) -> some View {
        Button(title) { Task { await submit(action) } }
            .disabled(disabled)
            .keyboardShortcut(key, modifiers: [])
            .accessibilityLabel(title)
            .accessibilityHint(disabled ? "Complete the required response first" : "Sends this exact source-offered response once")
    }
}
