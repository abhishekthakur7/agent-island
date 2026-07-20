import AppKit
import SwiftUI
import SessionDomain

struct AtlasSettingsDetail: View {
    @ObservedObject var model: AtlasSettingsModel
    @ObservedObject var notificationSettings: NotificationPolicySettingsModel
    let destination: AtlasSettingsDestination
    let liveDisplayControls: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            switch destination {
            case .general: AtlasGeneralSection(model: model)
            case .integrations: AtlasIntegrationsSection(model: model)
            case .notifications: AtlasNotificationsSection(preview: model.preview, send: model.sendPreview)
            case .display: AtlasDisplaySection(model: model, preview: model.preview, send: model.sendPreview, liveDisplayControls: liveDisplayControls)
            case .sound: AtlasSoundSection(model: notificationSettings)
            case .usage: AtlasPlaceholderSection(title: "Usage", icon: "chart.bar", message: "Usage Snapshots are display-only source evidence. Agent Island never estimates unavailable usage.")
            case .shortcuts: AtlasShortcutsSection(model: model)
            case .labs: AtlasPlaceholderSection(title: "Labs", icon: "flask", message: "Experimental capabilities remain opt-in and clearly separate from stable settings.")
            case .diagnostics: AtlasDiagnosticsSection(integrations: model.integrations)
            case .maintenance: AtlasMaintenanceSection()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(destination.title).font(.largeTitle.bold())
            Text(destination.subtitle).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AtlasGeneralSection: View {
    @ObservedObject var model: AtlasSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AtlasOnboardingCard(model: model)
            AtlasCard(title: "Launch and presentation") {
                Picker("Launch behavior", selection: generalBinding(\.launchBehavior)) {
                    Text("Open manually").tag(AtlasLaunchBehavior.manual)
                    Text("Launch at login").tag(AtlasLaunchBehavior.atLogin)
                }
                .accessibilityIdentifier("atlas.general.launchBehavior")
                if model.launchAtLoginState == .unavailable {
                    Label("Launch-at-login is unavailable in this app/OS context; intent remains saved.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                AtlasToggle("Expand on hover", detail: "Only visible Island bounds respond.", value: generalBinding(\.expandOnHover), id: "hoverExpansion")
                AtlasToggle("Collapse on pointer exit", detail: "Interaction and keyboard engagement still keep the Island open.", value: generalBinding(\.collapseOnPointerExit), id: "pointerExitCollapse")
                AtlasToggle("Suppress for exact foreground Host", detail: "Only a currently revalidated exact Host Context qualifies.", value: generalBinding(\.suppressWhenExactHostForeground), id: "exactHostSuppression")
                AtlasToggle("Hide in full screen", detail: "Withdraw without moving to another display.", value: generalBinding(\.hideInFullScreen), id: "hideFullScreen")
                AtlasToggle("Hide with no active Agent Session", detail: "Settings and retained local evidence remain available.", value: generalBinding(\.hideWhenNoActiveSession), id: "hideNoActiveSession")
            }
            AtlasCard(title: "Reveal and click behavior") {
                AtlasToggle("Reveal on completion", detail: "A short local presentation; open Attention Requests never expire.", value: generalBinding(\.revealOnCompletion), id: "revealCompletion")
                AtlasToggle("Reveal on attention", detail: "Presentation only; it does not answer or approve anything.", value: generalBinding(\.revealOnAttention), id: "revealAttention")
                Picker("Click behavior", selection: generalBinding(\.clickBehavior)) {
                    Text("Inspect or expand").tag(AtlasClickBehavior.inspectExpand)
                    Text("Jump Back when evidence-backed").tag(AtlasClickBehavior.jumpBack)
                }
                .accessibilityIdentifier("atlas.general.clickBehavior")
                Text("Jump Back always revalidates the live Host Context and reports the achieved fallback. This setting performs no navigation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func generalBinding<Value>(_ keyPath: WritableKeyPath<AtlasGeneralPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.general[keyPath: keyPath] },
            set: { value in model.updateGeneral { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct AtlasOnboardingCard: View {
    @ObservedObject var model: AtlasSettingsModel

    var body: some View {
        if model.onboarding.lifecycle != .completed {
            AtlasCard(title: onboardingTitle) {
                if model.onboarding.lifecycle == .notStarted {
                    Text("Monitor concurrent Agent Sessions locally, learn honest Host fallback, and choose what to enable at your pace.")
                        .foregroundStyle(.secondary)
                    Button("Get started") { model.startOnboarding() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("atlas.onboarding.start")
                } else if model.onboarding.lifecycle == .deferred {
                    Text("Your completed education is saved. Resume at the first unfinished concept.")
                        .foregroundStyle(.secondary)
                    Button("Resume onboarding") { model.resumeOnboarding() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("atlas.onboarding.resume")
                } else {
                    ProgressView(value: onboardingProgress)
                        .accessibilityLabel("Onboarding progress")
                    Text(model.onboarding.step.title).font(.title3.bold())
                    Text(model.onboarding.step.explanation).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack { onboardingButtons }
                        VStack(alignment: .leading) { onboardingButtons }
                    }
                }
            }
            .accessibilityIdentifier("atlas.onboarding.card")
        }
    }

    private var onboardingTitle: String {
        switch model.onboarding.lifecycle {
        case .notStarted: "Welcome to Agent Island"
        case .active: "Getting started"
        case .deferred: "Onboarding paused"
        case .completed: "Onboarding complete"
        }
    }

    private var onboardingProgress: Double {
        Double(model.onboarding.step.rawValue + 1) / Double(AtlasOnboardingStep.allCases.count)
    }

    @ViewBuilder private var onboardingButtons: some View {
        Button("Back") { model.backOnboarding() }
            .disabled(model.onboarding.step == .first)
            .accessibilityIdentifier("atlas.onboarding.back")
        Button(model.onboarding.step == .last ? "Finish" : "Next") { model.nextOnboarding() }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("atlas.onboarding.next")
        Button("Skip for now") { model.skipOnboarding() }
            .accessibilityIdentifier("atlas.onboarding.skip")
    }
}

private struct AtlasIntegrationsSection: View {
    @ObservedObject var model: AtlasSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enabled intent and observed health are independent. Discovery never enables or configures an Integration Installation.")
                .foregroundStyle(.secondary)
            ForEach(model.integrations, id: \.kind) { integration in
                AtlasCard(title: integration.kind.title) {
                    Toggle("Enabled intent", isOn: Binding(
                        get: { integration.enabledIntent },
                        set: { model.setIntegrationIntent(integration.kind, enabled: $0) }
                    ))
                    .accessibilityIdentifier("atlas.integration.\(integration.kind.rawValue).intent")
                    LabeledContent("Intent and readiness", value: integration.summary.title)
                    LabeledContent("Observed health", value: integration.health.title)
                    LabeledContent("Evidence freshness", value: integration.freshness.title)
                    LabeledContent("Evidence time", value: integration.evidence?.observedAt?.formatted(date: .abbreviated, time: .shortened) ?? "No evidence")
                    LabeledContent("Affected capability", value: integration.affectedCapability?.title ?? "None reported")
                    LabeledContent("Safe next step", value: integration.safeNextStep.title)
                    Text("Changing enabled intent does not write Agent Product configuration. Setup and repair require a later reviewable plan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("atlas.integration.\(integration.kind.rawValue)")
            }
        }
    }
}

private struct AtlasNotificationsSection: View {
    let preview: AtlasPreviewState
    let send: (AtlasPreviewAction) -> Void

    var body: some View {
        AtlasCard(title: "Read-only filter preview") {
            Text("These controls update only the local preview. They cannot emit an alert or sound.")
                .foregroundStyle(.secondary)
            Toggle("Completion", isOn: Binding(
                get: { preview.includesCompletion },
                set: { _ in send(.toggleCompletionFilter) }
            ))
                .accessibilityIdentifier("atlas.notifications.preview.completionFilter")
            Toggle("Attention", isOn: Binding(
                get: { preview.includesAttention },
                set: { _ in send(.toggleAttentionFilter) }
            ))
                .accessibilityIdentifier("atlas.notifications.preview.attentionFilter")
            ViewThatFits(in: .horizontal) {
                HStack { notificationButtons }
                VStack(alignment: .leading) { notificationButtons }
            }
            AtlasPreviewSurface(preview: preview)
        }
    }

    @ViewBuilder private var notificationButtons: some View {
        Button("Preview completion") { send(.revealCompletion) }
        Button("Preview attention") { send(.revealAttention) }
        Button("Clear preview") { send(.hide) }
    }
}

private struct AtlasDisplaySection: View {
    @ObservedObject var model: AtlasSettingsModel
    let preview: AtlasPreviewState
    let send: (AtlasPreviewAction) -> Void
    let liveDisplayControls: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AtlasCard(title: "Display assignment") {
                liveDisplayControls
            }
            AtlasCard(title: "Collapsed layout and content") {
                Picker("Collapsed layout", selection: Binding(
                    get: { model.display.collapsedLayout },
                    set: { value in model.updateDisplay { $0.collapsedLayout = value } }
                )) {
                    Text("Clean").tag(AtlasCollapsedLayout.clean)
                    Text("Detailed metadata").tag(AtlasCollapsedLayout.detailed)
                }
                .accessibilityIdentifier("atlas.display.collapsedLayout")
                Picker("Content size", selection: Binding(
                    get: { model.display.contentSize },
                    set: { value in model.updateDisplay { $0.contentSize = value } }
                )) {
                    Text("Small").tag(AtlasDisplayContentSize.small)
                    Text("Medium").tag(AtlasDisplayContentSize.medium)
                    Text("Large").tag(AtlasDisplayContentSize.large)
                }
                .accessibilityIdentifier("atlas.display.contentSize")
                Slider(value: Binding(
                    get: { model.display.maximumPanelWidth },
                    set: { value in model.updateDisplay { $0.maximumPanelWidth = value } }
                ), in: 240...1_600, step: 10) { Text("Maximum panel width") }
                Slider(value: Binding(
                    get: { model.display.maximumPanelHeight },
                    set: { value in model.updateDisplay { $0.maximumPanelHeight = value } }
                ), in: 80...1_000, step: 10) { Text("Maximum panel height") }
                Slider(value: Binding(
                    get: { model.display.completionCardHeight },
                    set: { value in model.updateDisplay { $0.completionCardHeight = value } }
                ), in: 80...700, step: 10) { Text("Completion-card height") }
                Toggle("Project metadata", isOn: displayBinding(\.showProjectMetadata))
                Toggle("Worktree metadata", isOn: displayBinding(\.showWorktreeMetadata))
                Toggle("Model metadata", isOn: displayBinding(\.showModelMetadata))
                Toggle("Subagent Run metadata", isOn: displayBinding(\.showSubagentRunMetadata))
                Toggle("Activity metadata", isOn: displayBinding(\.showActivityMetadata))
                Text("Only source-proven metadata appears; missing values stay absent. Dimensions clamp to the selected display’s current safe visible bounds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            AtlasCard(title: "Read-only Island preview") {
                Text("The preview is local and read-only. It does not move, recreate, or resize the live Island Overlay.")
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { displayPreviewButtons }
                    VStack(alignment: .leading) { displayPreviewButtons }
                }
                .accessibilityIdentifier("atlas.display.preview.controls")
                AtlasPreviewSurface(preview: preview)
                if let unavailable = preview.unavailableDisplayLabel {
                    Label("Selected display unavailable: \(unavailable)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("atlas.display.preview.unavailable")
                }
            }
        }
    }

    @ViewBuilder private var displayPreviewButtons: some View {
        Button("Pointer enters") { send(.hoverEntered) }
        Button("Pointer exits") { send(.hoverExited) }
        Button("Reset") { send(.reset) }
    }

    private func displayBinding<Value>(_ keyPath: WritableKeyPath<AtlasDisplayPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.display[keyPath: keyPath] },
            set: { value in model.updateDisplay { $0[keyPath: keyPath] = value } }
        )
    }
}

private struct AtlasPreviewSurface: View {
    let preview: AtlasPreviewState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var contentScale: CGFloat { CGFloat(preview.presentationMetrics.contentScale) }

    var body: some View {
        HStack(spacing: 8 * contentScale) {
            Image(systemName: preview.isVisible ? "sparkles" : "circle.hexagongrid")
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.isExpanded ? "Expanded local preview" : "Compact local preview")
                Text(preview.display.collapsedLayout == .detailed ? "Detailed sourced metadata" : "Clean summary")
                    .font(.system(size: 11 * contentScale))
                    .foregroundStyle(.secondary)
                Text("Completion card \(Int(preview.presentationMetrics.completionCardHeight))pt · \(String(format: "%.2f×", preview.presentationMetrics.contentScale)) content")
                    .font(.system(size: 11 * contentScale))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(preview.selectedDisplayAvailable ? (preview.isVisible ? "Visible" : "Idle") : "Unavailable")
                .font(.system(size: 13 * contentScale))
                .foregroundStyle(preview.selectedDisplayAvailable ? Color.secondary : Color.orange)
        }
        .padding(12 * contentScale)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("atlas.preview.surface")
    }
}

private struct AtlasDiagnosticsSection: View {
    let integrations: [AtlasIntegrationState]

    var body: some View {
        AtlasCard(title: "Redacted local evidence") {
            Text("Renderable diagnostics contain only allowlisted categories. Interaction Content, credentials, paths, raw identifiers, and commands cannot enter this view model.")
                .foregroundStyle(.secondary)
            ForEach(integrations, id: \.kind) { integration in
                let record = AtlasDiagnosticsSanitizer.render(integration: integration)
                LabeledContent(integration.kind.title, value: "\(record.outcome.title) · \(record.reason.title)")
            }
            Button("Create Diagnostic Bundle…", action: createBundle)
                .help("Choose a local folder for redacted Markdown and JSON artifacts")
        }
        .accessibilityIdentifier("atlas.diagnostics.redacted")
    }

    private func createBundle() {
        let panel = NSOpenPanel()
        panel.title = "Choose Diagnostic Bundle Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let evidence = integrations.map { AtlasDiagnosticsSanitizer.evidence(integration: $0) }
            let bundle = try DiagnosticBundle(records: evidence)
            let destination = try DiagnosticBundleDestination(directory: directory)
            let artifacts = try DiagnosticBundleWriter.write(bundle, to: destination)
            showResult(
                title: "Diagnostic Bundle Created",
                message: "Created \(artifacts.markdown.lastPathComponent) and \(artifacts.machineReadableJSON.lastPathComponent)."
            )
        } catch {
            showResult(
                title: "Diagnostic Bundle Not Created",
                message: "Choose an empty writable local folder and try again. No partial bundle was retained."
            )
        }
    }

    private func showResult(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct AtlasSoundSection: View {
    @ObservedObject var model: NotificationPolicySettingsModel

    var body: some View {
        AtlasCard(title: "Local sound policy") {
            Toggle("Sound enabled", isOn: binding(\.masterEnabled))
            Toggle("Mute now", isOn: binding(\.immediateMute))
            Toggle("Quiet hours", isOn: binding(\.quietHoursEnabled))
            Slider(value: binding(\.volume), in: 0...1) {
                Text("Volume")
            }
            LabeledContent("Volume", value: "\(Int(model.volume * 100))%")
            Text("Quiet hours and immediate mute affect sound only. Preview and imported sounds stay local and create no Alert Candidate or Agent Product action.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("atlas.sound.policy")
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<NotificationPolicySettingsModel, Value>) -> Binding<Value> {
        Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0 })
    }
}

private struct AtlasMaintenanceSection: View {
    var body: some View {
        AtlasCard(title: "Consequential maintenance") {
            Text("Every category requires a separately scoped plan, preview, and confirmation. This shell performs none of them.")
                .foregroundStyle(.secondary)
            AtlasInertAction(title: "Reset preferences", detail: "Return local presentation preferences to defaults.")
            AtlasInertAction(title: "Remove setup", detail: "Remove only manifest-proven configuration entries and owned artifacts.")
            AtlasInertAction(title: "Delete local data", detail: "Choose protected local categories separately.")
            AtlasInertAction(title: "Complete cleanup", detail: "Review a residual-aware cleanup checklist.")
        }
        .accessibilityIdentifier("atlas.maintenance.categories")
    }
}

private struct AtlasInertAction: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Button("Review…") {}.disabled(true).accessibilityHint("Planned action; unavailable in this version")
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AtlasPlaceholderSection: View {
    let title: String
    let icon: String
    let message: String
    var body: some View {
        AtlasCard(title: title) {
            Label(message, systemImage: icon).foregroundStyle(.secondary)
            Text("This destination is reserved now so its capability, privacy, and failure semantics remain distinct.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AtlasShortcutsSection: View {
    @ObservedObject var model: AtlasSettingsModel

    private var commands: [ShortcutCommand] {
        [
            .toggleOverlay, .nextSession, .previousSession, .showAll, .collapse, .inspect
        ] + ShortcutSafeAction.allCases.map(ShortcutCommand.safeAction)
    }

    var body: some View {
        AtlasCard(title: "Keyboard and global shortcuts") {
            Toggle("Enable global shortcuts", isOn: Binding(
                get: { model.shortcuts.registry.masterEnabled },
                set: { model.setShortcutsEnabled($0) }
            ))
            .accessibilityHint("Disabling unregisters every shortcut while preserving saved bindings.")
            Text("Bindings use physical keys and current input-source labels. Agent Island does not simulate Host input or require Accessibility permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(model.shortcutRegistrationStatus.shortcutStatusMessage, systemImage: model.shortcutRegistrationStatus.shortcutStatusSymbol)
                .font(.caption)
                .foregroundStyle(model.shortcutRegistrationStatus.shortcutStatusIsHealthy ? Color.secondary : Color.orange)
            Text("Input source: \(model.shortcutInputSource.localizedName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(commands, id: \.identifier) { command in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(command.shortcutTitle)
                        Text(command.shortcutDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.shortcutCaptureCommand == command {
                        ShortcutCaptureView { binding in
                            model.captureShortcut(binding, for: command)
                        } onCancel: {
                            model.cancelShortcutCapture()
                        }
                        .frame(width: 130, height: 28)
                        .accessibilityLabel("Press a physical key for \(command.shortcutTitle)")
                    } else {
                        Button(model.shortcuts.registry.bindings[command]?.renderedLabel(inputSource: model.shortcutInputSource) ?? "Set shortcut") {
                            model.beginShortcutCapture(command)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Shortcut for \(command.shortcutTitle)")
                    }
                }
                .padding(.vertical, 3)
            }
            if let feedback = model.shortcutFeedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(feedback.hasPrefix("Saved") ? Color.secondary : Color.orange)
                    .accessibilityLabel("Shortcut feedback: \(feedback)")
            }
        }
        .accessibilityIdentifier("atlas.shortcuts.section")
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onBinding: (ShortcutBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onBinding = onBinding
        view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onBinding = onBinding
        nsView.onCancel = onCancel
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onBinding: ((ShortcutBinding) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        let text = NSString(string: "Press a key")
        text.draw(at: NSPoint(x: 10, y: 7), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode != PhysicalKey.escape.rawValue else { onCancel?(); return }
        let flags = event.modifierFlags
        var modifiers: ShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.function) { modifiers.insert(.function) }
        onBinding?(ShortcutBinding(key: PhysicalKey(event.keyCode), modifiers: modifiers))
    }
}

private extension ShortcutCommand {
    var shortcutTitle: String {
        switch self {
        case .toggleOverlay: "Open / toggle Overlay"
        case .nextSession: "Next Agent Session"
        case .previousSession: "Previous Agent Session"
        case .showAll: "Show all sessions"
        case .collapse: "Collapse Overlay"
        case .inspect: "Inspect selected session"
        case let .safeAction(id): ShortcutSafeAction(rawValue: id)?.title ?? "Unavailable safe action"
        }
    }

    var shortcutDescription: String {
        switch self {
        case .toggleOverlay, .nextSession, .previousSession: "Global shortcut; physical key remains stable across input sources."
        case .showAll, .collapse, .inspect: "Focused Overlay shortcut; hidden rows are never traversed."
        case .safeAction: "Guided shortcut; focuses one eligible request and never sends a Product action directly."
        }
    }
}

private extension ShortcutBindingValidation {
    var shortcutMessage: String {
        switch self {
        case .valid: "Saved."
        case let .rejected(reason): "Not saved: \(reason.humanReadableDescription)."
        }
    }
}

private extension ShortcutRegistrationStatus {
    var shortcutStatusIsHealthy: Bool {
        switch self {
        case .active, .disabled: true
        case .unavailable: false
        }
    }

    var shortcutStatusSymbol: String {
        switch self {
        case .active: "checkmark.circle"
        case .disabled: "pause.circle"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    var shortcutStatusMessage: String {
        switch self {
        case .active: "Global registration active for eligible Overlay commands."
        case .disabled: "Global shortcuts disabled; saved mappings are retained."
        case let .unavailable(reason): "Global registration unavailable: \(reason)"
        }
    }
}

private struct AtlasToggle: View {
    let title: String
    let detail: String
    @Binding var value: Bool
    let id: String

    init(_ title: String, detail: String, value: Binding<Bool>, id: String) {
        self.title = title; self.detail = detail; _value = value; self.id = id
    }

    var body: some View {
        Toggle(isOn: $value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("atlas.general.\(id)")
    }
}

private struct AtlasCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.thinMaterial), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(contrast == .increased ? Color.primary : Color.secondary.opacity(0.2)))
    }
}

private extension AtlasSettingsDestination {
    var subtitle: String {
        switch self {
        case .general: "Local launch, presentation, reveal, and click semantics."
        case .integrations: "Intent, evidence, capability impact, and honest next steps."
        case .notifications: "Interruption policy and local filter previews."
        case .display: "Selected-display behavior and a local Island preview."
        case .sound: "Local audible presentation policy."
        case .usage: "Display-only source-supplied Usage Snapshots."
        case .shortcuts: "Keyboard engagement without bypassing capability checks."
        case .labs: "Explicitly experimental local capabilities."
        case .diagnostics: "Redacted evidence that explains behavior without Interaction Content."
        case .maintenance: "Separated, scoped, consequential categories."
        }
    }
}

private extension AtlasOnboardingStep {
    var explanation: String {
        switch self {
        case .aggregation: "Agent Island brings concurrent Agent Sessions into one calm, local-first surface."
        case .completionAwareness: "Completion and Attention Requests can surface without repeatedly checking every Host."
        case .hostFallback: "Jump Back targets only live, evidence-backed Host Contexts and degrades honestly."
        case .setupAndDisplay: "Detection is read-only and setup remains reviewable. Choose where the Island belongs; display loss withdraws it instead of silently moving."
        }
    }
}

private extension AtlasIntegrationSummary {
    var title: String { rawValue.splitBeforeUppercase.capitalized }
}
private extension AtlasIntegrationSafeNextStep {
    var title: String { rawValue.splitBeforeUppercase.capitalized }
}
private extension AtlasIntegrationCapability {
    var title: String { rawValue.capitalized }
}
private extension AtlasIntegrationHealth {
    var title: String { rawValue.splitBeforeUppercase.capitalized }
}
private extension AtlasEvidenceFreshness {
    var title: String { rawValue.capitalized }
}
private extension AtlasDiagnosticOutcome {
    var title: String { rawValue.capitalized }
}
private extension AtlasDiagnosticReason {
    var title: String { rawValue.splitBeforeUppercase.capitalized }
}
private extension String {
    var splitBeforeUppercase: String {
        reduce(into: "") { result, character in
            if character.isUppercase { result.append(" ") }
            result.append(character)
        }
    }
}
