import SwiftUI

/// AB-164 — the root of the onboarding flow. Owns nothing about window
/// chrome itself (the real traffic lights are a window-level concern —
/// see `OnboardingWindowCoordinator`); this view's only job is switching on
/// `model.screen` and handing off to the right screen view.
///
/// All four screens are real now: `.welcome` (AB-164), `.agents` (AB-165),
/// `.connect` (AB-166), and `.preferences` (AB-167 — "A few preferences",
/// §2.4, ref #6; its "Continue" calls `model.complete()`, ending the flow,
/// rather than `model.advance()`).
struct OnboardingRootView: View {
    @ObservedObject var model: OnboardingFlowModel

    var body: some View {
        Group {
            switch model.screen {
            case .welcome:
                OnboardingWelcomeView(model: model)

            case .agents:
                OnboardingAgentsView(model: model)

            case .connect:
                OnboardingConnectView(model: model)

            case .preferences:
                OnboardingPreferencesView(model: model)
            }
        }
        .frame(width: 720, height: 560)
    }
}

// NOTE: no `#Preview` block here — see the same note in
// `OnboardingWelcomeView.swift` / `IslandGlyphs.swift`: this machine's
// command-line toolchain lacks the `PreviewsMacros` plugin that only Xcode
// supplies, so `#Preview { ... }` fails `swift build` here.
