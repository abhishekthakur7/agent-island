import SwiftUI

/// AB-166 §2.3 "Connect an agent" (ref #5). Third of the four onboarding
/// screens (welcome → agents → **connect** → preferences).
///
/// AC-2.3-a: back button top-left; centered title + subtitle.
/// AC-2.3-b: 2-column grid, **only** `model.orderedSelectedAgents` (the
/// agents chosen on the previous screen, in that same fixed order) — each
/// card: brand icon + name, a top-right spinner while installing, and a
/// second "Installing X hooks…" line — settling to a check + "Connected"
/// once `model.installStates` resolves (`OnboardingFlowModel.swift`'s
/// `beginAgentInstalls()` drives this; kicked off from `.onAppear` below).
/// AC-2.3-c: footer shield glyph + the exact credentials copy.
///
/// No AC names an explicit forward control for this screen. Per the
/// ticket's own forward-nav judgment call, this reuses the house
/// `OnboardingPrimaryButton` "Continue" pattern (AB-165's screen), enabled
/// once the subtitle's own promise — "One is enough to finish" — is met:
/// see `continueEnabled`'s doc comment for the exact condition and why it
/// is not simply "≥1 connected".
struct OnboardingConnectView: View {
    @ObservedObject var model: OnboardingFlowModel

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    /// Enabled once ≥1 chosen agent has actually connected (the subtitle's
    /// literal promise), **or** once every chosen agent's install has
    /// otherwise settled (none remain `.idle`/`.installing`). The second
    /// clause exists so a person who only picked agents with nothing
    /// installable in this codebase (AC-2.2-b's other nine — e.g. only
    /// "Grok") is never trapped on this screen waiting for a `.connected`
    /// that can never arrive; apple-design's wayfinding principle: never
    /// trap the user with no way forward.
    private var continueEnabled: Bool {
        let states = model.orderedSelectedAgents.map { model.installStates[$0] ?? .idle }
        guard !states.isEmpty else { return false }
        let anyConnected = states.contains(.connected)
        let allSettled = states.allSatisfy { $0 != .idle && $0 != .installing }
        return anyConnected || allSettled
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingBackground()

            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    OnboardingTitleText(text: "Connect an agent")
                    OnboardingSubtitleText(text: "One is enough to finish.")
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.orderedSelectedAgents, id: \.self) { agent in
                        OnboardingConnectCard(
                            agent: agent,
                            state: model.installStates[agent] ?? .idle
                        )
                    }
                }

                Spacer(minLength: 8)

                HStack(alignment: .center) {
                    // AC-2.3-c: shield glyph + exact credentials copy.
                    Label("Agent Island never receives agent provider credentials.", systemImage: "lock.shield")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(IslandOnboardingTheme.subtitle)

                    Spacer(minLength: 16)

                    OnboardingPrimaryButton(
                        title: "Continue",
                        enabled: continueEnabled,
                        minWidth: 140,
                        action: model.advance
                    )
                }
                .animation(.easeOut(duration: 0.2), value: continueEnabled)
            }
            .padding(.horizontal, 48)
            .padding(.top, 74)
            .padding(.bottom, 32)

            // AC-2.3-a: circular back button, top-left — same placement and
            // extra safe-area padding as AB-165's screen (clears the real
            // traffic lights; see `OnboardingAgentsView`'s identical comment).
            OnboardingBackButton(action: model.back)
                .padding(.leading, 24)
                .padding(.top, 20)
        }
        .onAppear { model.beginAgentInstalls() }
    }
}

// MARK: - Connect card (AC-2.3-b)

/// One 2-column grid cell: brand icon tile + name, a top-right status glyph
/// (spinner while installing, check/exclamation once settled), and a second
/// status line beneath the name ("Installing X hooks…" → "Connected", or the
/// failed/skipped read). Unlike `OnboardingAgentCard` (AB-165) this card is
/// not tappable — install progress here is system-driven, not a selection
/// toggle.
private struct OnboardingConnectCard: View {
    let agent: OnboardingAgent
    let state: OnboardingAgentInstallState

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 10) {
                OnboardingAgentIconTile(agent: agent, size: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.displayName)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(IslandOnboardingTheme.title)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    statusLine
                }

                Spacer(minLength: 18)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: IslandOnboardingTheme.cardRadius, style: .continuous)
                    .fill(IslandOnboardingTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IslandOnboardingTheme.cardRadius, style: .continuous)
                    .strokeBorder(borderTint, lineWidth: state == .connected ? 1.4 : 1)
            )

            // Top-right status glyph: spinner while installing, settled
            // check/failure mark once resolved — never both at once.
            statusGlyph
                .padding(.top, 11)
                .padding(.trailing, 12)
        }
        .animation(.easeOut(duration: 0.2), value: state)
    }

    private var borderTint: Color {
        switch state {
        case .connected: return IslandTheme.allowGreen.opacity(0.5)
        case .failed: return IslandTheme.denyRed.opacity(0.4)
        default: return IslandOnboardingTheme.cardBorder
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state {
        case .idle:
            // Only visible for the one frame before `.onAppear` fires;
            // reserves the line's height so settling in doesn't reflow the
            // card.
            Text(" ").font(.system(size: 11.5)).hidden()
        case .installing:
            // AC-2.3-b's exact copy, X = this agent's real installable hook
            // count (`OnboardingAgent.installableHookCount`) — always
            // non-nil here, since `.installing` is only ever set for an
            // agent with a real `integrationKind`.
            Text("Installing \(agent.installableHookCount ?? 0) hooks…")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(IslandOnboardingTheme.subtitle)
                .lineLimit(1)
        case .connected:
            Text("Connected")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(IslandTheme.allowGreen)
        case .failed(let message):
            Text(message)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(IslandTheme.denyRed)
                .lineLimit(2)
        case .skipped:
            // AB-166 wiring note (`OnboardingAgent.integrationKind`'s doc
            // comment): a `nil` kind has nothing installable in this
            // codebase — acknowledged, not a broken install action.
            Text("Nothing to install")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(IslandOnboardingTheme.subtitle)
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch state {
        case .idle, .skipped:
            EmptyView()
        case .installing:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .frame(width: 14, height: 14)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IslandTheme.allowGreen)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IslandTheme.denyRed)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }
}

// NOTE: no `#Preview` block here — this machine's command-line toolchain has
// no `PreviewsMacros` plugin (only Xcode supplies it; see the same note in
// `OnboardingAgentsView.swift` / `OnboardingRootView.swift`), so
// `#Preview { ... }` fails `swift build` here even though it works fine from
// Xcode's canvas.
