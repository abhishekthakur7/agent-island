import SwiftUI

/// AB-165 §2.2 "Which agents do you use?" (ref #4). Second of the four
/// onboarding screens (welcome → **agents** → connect → preferences).
///
/// AC-2.2-a: circular back button top-left; centered title + subtitle.
/// AC-2.2-b: 3-column grid of agent cards, in `OnboardingAgent`'s declared
/// order (Claude, Codex, Cursor / Grok, Kimi, Hermes / OpenCode, GitHub
/// Copilot, Kilo Code / Droid, Antigravity, Pi) — each card brand icon +
/// name + trailing checkbox, dark card token; tapping toggles selection.
/// AC-2.2-c: footer helper text (gear glyph) + glossy white "Continue" pill,
/// disabled until at least one agent is selected.
struct OnboardingAgentsView: View {
    @ObservedObject var model: OnboardingFlowModel

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingBackground()

            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    OnboardingTitleText(text: "Which agents do you use?")
                    OnboardingSubtitleText(text: "Select the agents Agent Island should set up now.")
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(OnboardingAgent.allCases, id: \.self) { agent in
                        OnboardingAgentCard(
                            agent: agent,
                            isSelected: model.selectedAgents.contains(agent),
                            action: { model.toggleAgentSelection(agent) }
                        )
                    }
                }

                Spacer(minLength: 8)

                HStack(alignment: .center) {
                    Label("Select at least one agent to continue.", systemImage: "gearshape")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(IslandOnboardingTheme.subtitle)

                    Spacer(minLength: 16)

                    OnboardingPrimaryButton(
                        title: "Continue",
                        enabled: !model.selectedAgents.isEmpty,
                        minWidth: 140,
                        action: model.advance
                    )
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 74)
            .padding(.bottom, 32)

            // AC-2.2-a: circular back button, top-left. Extra top/leading
            // padding (vs. a bare corner pin) clears the real macOS traffic
            // lights `OnboardingWindowCoordinator` renders behind this
            // content — see that file's `.fullSizeContentView` doc comment.
            OnboardingBackButton(action: model.back)
                .padding(.leading, 24)
                .padding(.top, 20)
        }
    }
}

// MARK: - Agent card (AC-2.2-b)

/// One 3-column grid cell: brand icon tile + name + trailing checkbox on a
/// dark card token. The whole card is the tap target — tapping anywhere
/// toggles selection, not just the checkbox — which is the friendlier hit
/// target for a card this size (apple-design: hysteresis/hit-padding, not a
/// tiny checkbox-only target).
private struct OnboardingAgentCard: View {
    let agent: OnboardingAgent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                OnboardingAgentIconTile(agent: agent, size: 28)

                Text(agent.displayName)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(IslandOnboardingTheme.title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                OnboardingAgentCheckbox(isSelected: isSelected, tint: agent.iconTint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: IslandOnboardingTheme.cardRadius, style: .continuous)
                    .fill(IslandOnboardingTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IslandOnboardingTheme.cardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? agent.iconTint.opacity(0.55) : IslandOnboardingTheme.cardBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(OnboardingCardButtonStyle())
        .accessibilityLabel(agent.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Press feedback for the agent card — instant, subtle scale on press
/// (emil-design-eng: buttons must feel responsive; ~0.97 scale, ~120ms —
/// matching `OnboardingCircularButtonStyle`'s existing feel in
/// `OnboardingChrome.swift` rather than inventing a different one here).
private struct OnboardingCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Trailing checkbox: empty (just a hairline square) when unselected, filled
/// with the agent's tint + a checkmark when selected — AC-2.2-b's "trailing
/// empty checkbox" that fills in on selection.
private struct OnboardingAgentCheckbox: View {
    let isSelected: Bool
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? tint : Color.clear)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isSelected ? tint : Color.white.opacity(0.24), lineWidth: 1.4)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(IslandOnboardingTheme.primaryButtonText)
            }
        }
        .frame(width: 18, height: 18)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

// MARK: - Shared brand icon tile (reusable — AB-166's Connect cards too)

/// Uniform rounded-square brand icon tile: a tinted fill/border with either a
/// literal character mark or an SF Symbol centered inside. Every one of the
/// 12 agents renders through this single component (only `mark`/`tint`
/// differ) so the grid reads as one consistent icon system rather than a mix
/// of ad hoc styles — and so AB-166's 2-column "Connect an agent" cards
/// (AC-2.3-b: "brand icon + name") can reuse this exact tile instead of
/// redrawing agent brand icons a second time.
struct OnboardingAgentIconTile: View {
    let mark: OnboardingAgentIconMark
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(tint.opacity(0.34), lineWidth: 1)
            )
            .overlay(markView)
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .character(let text):
            Text(text)
                .font(.system(size: size * 0.46, weight: .semibold, design: .default))
                .foregroundStyle(tint)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

/// Convenience initializer so call sites that already have an `OnboardingAgent`
/// (this screen's cards) don't have to spell out `agent.iconMark`/`agent.iconTint`
/// themselves.
extension OnboardingAgentIconTile {
    init(agent: OnboardingAgent, size: CGFloat = 28) {
        self.init(mark: agent.iconMark, tint: agent.iconTint, size: size)
    }
}

// NOTE: no `#Preview` block here — this machine's command-line toolchain has
// no `PreviewsMacros` plugin (only Xcode supplies it; see the same note in
// `OnboardingRootView.swift` / `IslandGlyphs.swift`), so `#Preview { ... }`
// fails `swift build` here even though it works fine from Xcode's canvas.
