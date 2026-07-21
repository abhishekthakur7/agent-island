import SwiftUI

/// AB-164 §2.1 Welcome (ref #3). First of the four onboarding screens.
///
/// AC-2.1-a: centered app icon → "Agent Island" (~56pt bold sans) → subtitle
/// → glossy white "Get started" pill.
/// AC-2.1-b: warm charcoal radial background, real macOS traffic lights
/// top-left (that's the window's job — see `OnboardingWindowCoordinator`),
/// and no back button on this screen.
struct OnboardingWelcomeView: View {
    @ObservedObject var model: OnboardingFlowModel

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 28) {
                OnboardingAppIconMascot()
                    .frame(width: 120, height: 120)

                VStack(spacing: 12) {
                    OnboardingTitleText(
                        text: "Agent Island",
                        font: OnboardingTypography.welcomeTitleFont,
                        tracking: -1.0
                    )
                    OnboardingSubtitleText(text: "Your coding agents, in the Mac notch")
                }

                OnboardingPrimaryButton(title: "Get started") {
                    model.advance()
                }
                .padding(.top, 12)
            }
            .padding(48)
        }
        // AC-2.1-b: deliberately no `OnboardingBackButton` here — this is
        // the first screen in the flow, so there's nothing to go back to.
    }
}

/// AC-2.1-a's "rounded-square blue-gradient mascot with the notch face".
///
/// `IslandGlyphs.swift` (AB-152) has a mascot vocabulary, but it's the
/// overlay's own brand mark: an orange, monospaced pixel-art walking crab
/// meant for the notch's *activity* indicator — a different surface with a
/// different palette (see that file's header comment on why it's tinted
/// orange/blue-violet for Claude/Codex specifically). Nothing there is a
/// blue-gradient app-icon tile, so per this ticket's fallback instruction,
/// this draws an original, simple notch-face motif instead: a dark pill
/// (the MacBook notch) with two dot "eyes", set into a blue-gradient
/// rounded-square tile.
private struct OnboardingAppIconMascot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0x5B / 255, green: 0x9C / 255, blue: 0xF2 / 255),
                        Color(red: 0x2B / 255, green: 0x55 / 255, blue: 0xC7 / 255),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(notchFace)
            .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 10)
    }

    /// The "notch face": a rounded black pill standing in for the MacBook
    /// notch, with two small dots read as eyes.
    private var notchFace: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            RoundedRectangle(cornerRadius: h * 0.16, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .frame(width: w * 0.46, height: h * 0.24)
                .overlay(
                    HStack(spacing: w * 0.07) {
                        Circle().frame(width: w * 0.05, height: w * 0.05)
                        Circle().frame(width: w * 0.05, height: w * 0.05)
                    }
                    .foregroundStyle(Color.white.opacity(0.9))
                )
                .position(x: w / 2, y: h * 0.32)
        }
    }
}

// NOTE: no `#Preview` block here — this machine's command-line toolchain has
// no `PreviewsMacros` plugin (only Xcode supplies it; see the same note in
// `IslandGlyphs.swift`), so `#Preview { ... }` fails `swift build` here even
// though it works fine from Xcode's canvas. `OnboardingWelcomeView(model:
// OnboardingFlowModel())` is already a plain, previewable `View` — add a
// `#Preview` for it directly in Xcode if desired.
