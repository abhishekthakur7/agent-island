import SwiftUI

// MARK: - OnboardingChrome — AB-164
//
// Shared SwiftUI chrome for the onboarding flow (welcome → agents → connect
// → preferences). Every screen — this ticket's `OnboardingWelcomeView` and
// AB-165/166/167's screens after it — composes itself out of these pieces
// instead of redrawing background/buttons/type per screen.
//
// Onboarding is deliberately SF Pro **sans**, never `IslandFont` (mono) —
// see IslandTheme.swift's `IslandOnboardingTheme` doc comment. Every color
// below comes from that enum; nothing here invents a new token.

// MARK: - Background

/// Radial warm-charcoal background, glow biased top-right, per the spec
/// doc's onboarding token table. Sized off its own container via
/// `GeometryReader` (rather than a fixed window-size constant) so it drops
/// into any screen — and any future preview or resized container — without
/// looking clipped or under-scaled.
struct OnboardingBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let diagonal = (proxy.size.width * proxy.size.width + proxy.size.height * proxy.size.height).squareRoot()
            ZStack {
                IslandOnboardingTheme.backgroundOuter
                RadialGradient(
                    colors: [IslandOnboardingTheme.backgroundInner, IslandOnboardingTheme.backgroundOuter],
                    center: .center,
                    startRadius: 0,
                    endRadius: diagonal * 0.6
                )
                // Faint blue glow, biased toward the top-right corner per
                // IslandOnboardingTheme.backgroundGlow's doc comment.
                RadialGradient(
                    colors: [IslandOnboardingTheme.backgroundGlow, .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: diagonal * 0.5
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Typography

/// Sans title/subtitle sizes shared across onboarding screens. Colors always
/// come from `IslandOnboardingTheme`; only the sizes live here.
enum OnboardingTypography {
    /// AC-2.1-a's ~56pt welcome-only title — larger than every other
    /// screen's header, so it gets its own size rather than overloading
    /// `IslandOnboardingTheme.titleFont`.
    static let welcomeTitleFont = Font.system(size: 56, weight: .bold, design: .default)
    /// Standard header size for the non-welcome screens (2.2–2.4). Reuses
    /// the 48pt bold token already defined in `IslandTheme.swift` rather
    /// than duplicating a size value.
    static let headerTitleFont = IslandOnboardingTheme.titleFont
    static let subtitleFont = Font.system(size: 17, weight: .regular, design: .default)
}

/// Title text style. Apple's optical-sizing guidance (see apple-design
/// skill: large display type wants negative tracking) is applied via a
/// size-appropriate `.tracking()` — tighter at the welcome screen's 56pt
/// than at the 48pt header size.
struct OnboardingTitleText: View {
    let text: String
    var font: Font = OnboardingTypography.headerTitleFont
    /// Negative tracking scaled to size; only the welcome screen's larger
    /// font needs to opt into the tighter value.
    var tracking: CGFloat = -0.5

    var body: some View {
        Text(text)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(IslandOnboardingTheme.title)
            .multilineTextAlignment(.center)
    }
}

struct OnboardingSubtitleText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OnboardingTypography.subtitleFont)
            .foregroundStyle(IslandOnboardingTheme.subtitle)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Glossy white primary pill

/// The glossy white "Get started" / "Continue" pill (AC-2.1-a and every
/// later screen's primary action). `enabled` is exposed now even though
/// this ticket's own "Get started" is always enabled, because AB-165's
/// "Continue" (disabled until ≥1 agent picked, AC-2.2-c) and AB-167's
/// completing "Continue" both need it.
struct OnboardingPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    /// Pill hugs its text plus this floor, matching the reference's
    /// wide-relative-to-label "Get started" / "Continue" pill.
    var minWidth: CGFloat = 220
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .default))
                .tracking(-0.1)
                .foregroundStyle(IslandOnboardingTheme.primaryButtonText)
                .frame(minWidth: minWidth)
                .padding(.vertical, 14)
                .padding(.horizontal, 28)
        }
        .buttonStyle(OnboardingGlossyPillButtonStyle(enabled: enabled))
        .disabled(!enabled)
    }
}

/// Draws the pill fill + top highlight ("glossy" read) and the press
/// feedback. Split out as a `ButtonStyle` (rather than baked into the view
/// body) so `configuration.isPressed` drives the scale — emil-design-eng:
/// pressable elements need instant, subtle feedback (~0.97 scale, ~150ms).
private struct OnboardingGlossyPillButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(IslandOnboardingTheme.primaryButtonFill)
            )
            .overlay(
                // Subtle top highlight — the specular read that makes a flat
                // white fill look "glossy" instead of matte.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [IslandOnboardingTheme.primaryButtonTopHighlight, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.4)
            .shadow(color: Color.black.opacity(enabled ? 0.28 : 0), radius: 14, x: 0, y: 6)
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Circular back button

/// Top-left circular back button. AC-2.1-b: the welcome screen has none —
/// this exists purely so AB-165/166/167's screens (2.2–2.4, each specifying
/// "Back button top-left") have it ready without redefining it three times.
/// Placement (top-left, safe-area padding) is each screen's own call, not
/// baked into this component.
struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IslandOnboardingTheme.title)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(OnboardingCircularButtonStyle())
        .accessibilityLabel("Back")
    }
}

private struct OnboardingCircularButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(IslandOnboardingTheme.cardFill))
            .overlay(Circle().strokeBorder(IslandOnboardingTheme.cardBorder, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
