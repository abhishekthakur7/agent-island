import SwiftUI

struct OverlayContentView: View {
    let presentation: OverlayPresentation
    let geometry: OverlayGeometry
    let sessions: [FixtureSession]
    let keyboardEngaged: Bool
    let onExpand: () -> Void
    let onCollapse: () -> Void
    let onSettings: () -> Void
    let onEngageKeyboard: () -> Void

    private var attentionCount: Int { sessions.filter { $0.state == .attention }.count }

    var body: some View {
        ZStack(alignment: .top) {
            if geometry.isBuiltIn {
                HStack(spacing: geometry.protectedGap) {
                    if presentation == .collapsed {
                        builtInCollapsedStatus
                        builtInCollapsedAction
                    } else {
                        expandedSurface(
                            Array(sessions.prefix(15)),
                            title: presentation == .focused ? "Focused session" : "Agent Sessions",
                            detail: "Sessions 1–15",
                            includesControls: true
                        )
                        expandedSurface(
                            Array(sessions.dropFirst(15)),
                            title: "More sessions",
                            detail: "Sessions 16–30",
                            includesControls: false
                        )
                    }
                }
            } else {
                surface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var surface: some View {
        Group {
            if presentation == .collapsed {
                collapsedSurface
            } else {
                expandedSurface(sessions, title: presentation == .focused ? "Focused session" : "Agent Sessions", detail: "30-session fixture • selected display only", includesControls: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var builtInCollapsedStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: attentionCount > 0 ? "exclamationmark.circle.fill" : "sparkles")
                .foregroundStyle(attentionCount > 0 ? .orange : .cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("Agent Sessions").font(.system(size: 13, weight: .semibold))
                Text("\(sessions.count) working • \(attentionCount) attention")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .modifier(IslandSurface())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Working; \(sessions.count) Agent Sessions; \(attentionCount) need attention")
    }

    private var builtInCollapsedAction: some View {
        Button(action: onExpand) {
            HStack(spacing: 7) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Show sessions").font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.plain)
        .modifier(IslandSurface())
        .accessibilityLabel("Show Agent Sessions")
    }

    private var collapsedSurface: some View {
        HStack(spacing: 8) {
            Image(systemName: attentionCount > 0 ? "exclamationmark.circle.fill" : "sparkles")
                .foregroundStyle(attentionCount > 0 ? .orange : .cyan)
            Text(attentionCount > 0 ? "\(attentionCount) need attention" : "\(sessions.count) sessions")
                .font(.system(size: 13, weight: .semibold))
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Button("Show Agent Sessions", action: onExpand)
                .buttonStyle(.plain)
                .accessibilityLabel("Show Agent Sessions")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .modifier(IslandSurface())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Working; \(sessions.count) Agent Sessions; \(attentionCount) need attention. Show Agent Sessions")
    }

    private func expandedSurface(_ visibleSessions: [FixtureSession], title: String, detail: String, includesControls: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if includesControls {
                    VStack(alignment: .trailing, spacing: 5) {
                        Button("Keyboard", action: onEngageKeyboard)
                            .keyboardShortcut("k", modifiers: [.command, .shift])
                            .accessibilityHint("Engage keyboard navigation in the Island Overlay")
                        HStack(spacing: 8) {
                            Button("Settings", action: onSettings)
                            Button("Collapse", action: onCollapse)
                                .keyboardShortcut(.escape, modifiers: [])
                        }
                    }
                }
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(visibleSessions) { session in
                        SessionRow(session: session)
                    }
                }
                .padding(10)
            }
        }
        .frame(height: 500)
        .modifier(IslandSurface())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), non-modal Agent Sessions region")
        .overlay(alignment: .bottomTrailing) {
            if keyboardEngaged && includesControls {
                Text("Keyboard engaged • Escape collapses")
                    .font(.caption2)
                    .padding(7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
                    .accessibilityLabel("Keyboard engagement active. Escape collapses the overlay.")
            }
        }
    }

    private var accessibilityLabel: String {
        presentation == .collapsed
            ? "Working; \(sessions.count) Agent Sessions; \(attentionCount) need attention"
            : "Agent Sessions overlay"
    }
}

private struct IslandSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
}

private struct SessionRow: View {
    let session: FixtureSession

    var body: some View {
        Button {
            // Fixture deliberately has no Agent Product navigation or action route.
        } label: {
            HStack(spacing: 10) {
                Image(systemName: session.state.symbol)
                    .foregroundStyle(session.state.tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(.system(size: 13, weight: .medium))
                    Text("\(session.project) • \(session.product) • \(session.host) • \(session.elapsed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.childRuns > 0 {
                    Text("\(session.childRuns) subagent \(session.childRuns == 1 ? "run" : "runs")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(session.state.rawValue)
                    .font(.caption)
                    .foregroundStyle(session.state.tint)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(session.state.rawValue); \(session.project); \(session.title); \(session.product); \(session.host); \(session.elapsed)\(session.childRuns > 0 ? "; \(session.childRuns) child runs" : "")")
        .accessibilityHint("Fixture row. Product actions are unavailable in this spike.")
    }
}

struct SettingsView: View {
    @ObservedObject var controller: OverlayController

    var body: some View {
        Form {
            Section("Overlay placement") {
                Picker("Selected display", selection: $controller.selectedDisplayID) {
                    ForEach(controller.displays) { display in
                        Text(display.name).tag(Optional(display.id))
                    }
                }
                .onChange(of: controller.selectedDisplayID) { _, newValue in
                    controller.selectDisplay(id: newValue)
                }
                Text(controller.displayStatus)
                    .font(.caption)
                    .foregroundStyle(controller.selectedScreen == nil ? .orange : .secondary)
            }
            Section("Presentation") {
                Toggle("Hide in full screen", isOn: $controller.hideInFullscreen)
                    .onChange(of: controller.hideInFullscreen) { _, _ in controller.reconcilePresentation() }
                Toggle("Simulate active full-screen Space", isOn: $controller.simulateFullscreen)
                    .onChange(of: controller.simulateFullscreen) { _, _ in controller.reconcilePresentation() }
                Toggle("Hover expands overlay", isOn: $controller.hoverExpansionEnabled)
            }
            Section("Spike controls") {
                HStack {
                    Button("Auto reveal") { controller.autoReveal() }
                    Button("Withdraw") { controller.withdraw() }
                    Button("Wake rebuild") { controller.handleWake() }
                }
                Text("This disposable fixture intentionally stores no preferences, session data, adapters, or action routes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 360)
    }
}
