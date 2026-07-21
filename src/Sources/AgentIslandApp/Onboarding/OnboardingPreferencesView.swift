import SwiftUI

/// AB-167 §2.4 "A few preferences" (ref #6). Fourth and last of the four
/// onboarding screens (welcome → agents → connect → **preferences**).
///
/// AC-2.4-a: circular back button top-left; centered title + subtitle.
/// AC-2.4-b: two full-width dark rows — "Notifications" (green toggle, ON by
/// default) and "Launch at login" (gray toggle, OFF by default) — each a
/// leading label + a trailing `OnboardingToggle`.
/// AC-2.4-c: glossy white "Continue" pill that **completes onboarding**
/// (`model.complete()`, not `model.advance()` — `advance()` is already a
/// no-op on `.preferences`; this is the screen that ends the flow).
///
/// Unlike AB-165/166's "Continue" (gated on selection/install progress),
/// this one has no invented gating condition: every preference here is
/// optional (the subtitle's literal promise), so it is always enabled.
struct OnboardingPreferencesView: View {
    @ObservedObject var model: OnboardingFlowModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingBackground()

            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    OnboardingTitleText(text: "A few preferences")
                    OnboardingSubtitleText(text: "All optional. You can change these later in Settings.")
                }

                VStack(spacing: 12) {
                    OnboardingPreferenceRow(
                        label: "Notifications",
                        isOn: model.notificationsEnabled,
                        action: model.toggleNotifications
                    )
                    OnboardingPreferenceRow(
                        label: "Launch at login",
                        isOn: model.launchAtLoginEnabled,
                        action: model.toggleLaunchAtLogin
                    )
                }

                Spacer(minLength: 8)

                OnboardingPrimaryButton(title: "Continue", action: model.complete)
            }
            .padding(.horizontal, 48)
            .padding(.top, 74)
            .padding(.bottom, 32)

            // AC-2.4-a: circular back button, top-left — same placement and
            // extra safe-area padding as every other non-welcome screen
            // (clears the real traffic lights; see `OnboardingAgentsView`'s
            // identical comment).
            OnboardingBackButton(action: model.back)
                .padding(.leading, 24)
                .padding(.top, 20)
        }
    }
}

// MARK: - Preference row (AC-2.4-b)

/// One full-width dark row: a leading label + a trailing `OnboardingToggle`.
/// The whole row is the tap target — same "generous hit target over a small
/// nested control" call `OnboardingAgentsView`'s `OnboardingAgentCard` doc
/// comment makes — rather than only the small toggle knob reacting, and
/// rather than nesting a second `Button` inside this one (which would fire
/// both handlers per tap and toggle twice). `OnboardingToggle` below is
/// therefore a pure, state-driven visual, not itself interactive.
private struct OnboardingPreferenceRow: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(IslandOnboardingTheme.title)

                Spacer(minLength: 12)

                OnboardingToggle(isOn: isOn)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: IslandOnboardingTheme.cardRadius, style: .continuous)
                    .fill(IslandOnboardingTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IslandOnboardingTheme.cardRadius, style: .continuous)
                    .strokeBorder(IslandOnboardingTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(OnboardingPreferenceRowButtonStyle())
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// Press feedback for a full-width row — a subtler scale than the smaller
/// agent/connect cards (`OnboardingCardButtonStyle`'s 0.97): a wide row
/// scaling down as aggressively would read as an odd squish rather than a
/// crisp press. Same instant, ~120ms easeOut timing (emil-design-eng:
/// buttons must feel responsive on press, not just on release).
private struct OnboardingPreferenceRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - OnboardingToggle (AC-2.4-b)

/// The reusable green/gray toggle: green (`IslandOnboardingTheme.toggleOn`,
/// `#34C759`) when `isOn`, gray (`toggleOff`) otherwise, with the knob
/// sliding to the corresponding side. A pure, state-driven view bound to
/// `isOn` — see `OnboardingPreferenceRow`'s doc comment above for why the
/// tap target lives on the embedding row instead of here.
///
/// Motion: a single critically-damped spring (`dampingFraction: 1.0`, no
/// overshoot) drives both the knob's slide and the track's color crossfade
/// together, settling in well under emil-design-eng's 300ms UI ceiling.
/// apple-design's guidance reserves bounce/overshoot for gesture-driven,
/// momentum-carrying motion (a flick, a drag release) — a discrete on/off
/// tap carries no momentum to hand off, so this deliberately does not
/// bounce; the row's own press-scale (above) is what supplies the tap's
/// instant feedback.
struct OnboardingToggle: View {
    let isOn: Bool

    private let width: CGFloat = 38
    private let height: CGFloat = 22
    private let knobDiameter: CGFloat = 18
    private let knobInset: CGFloat = 2

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? IslandOnboardingTheme.toggleOn : IslandOnboardingTheme.toggleOff)

            Circle()
                .fill(Color.white)
                .frame(width: knobDiameter, height: knobDiameter)
                .shadow(color: Color.black.opacity(0.25), radius: 1.5, x: 0, y: 1)
                .padding(knobInset)
        }
        .frame(width: width, height: height)
        .animation(.spring(response: 0.26, dampingFraction: 1.0), value: isOn)
        // The embedding row already carries this toggle's accessibility
        // label/value/traits; exposing this inner view too would announce
        // the same control twice.
        .accessibilityHidden(true)
    }
}

// NOTE: no `#Preview` block here — this machine's command-line toolchain has
// no `PreviewsMacros` plugin (only Xcode supplies it; see the same note in
// `OnboardingAgentsView.swift` / `OnboardingRootView.swift`), so
// `#Preview { ... }` fails `swift build` here even though it works fine from
// Xcode's canvas.
