# AB-133 — Shortcuts, keyboard engagement, and adaptive accessibility

This template records evidence only. Empty rows are pending capture; this file
does not claim a recording, VoiceOver inspection, or external-display result.

| Acceptance area | Deterministic fixture / command | Capture or inspection | Result | Notes |
| --- | --- | --- | --- | --- |
| Physical key persistence and input-source labels | `ShortcutModelsTests` | pending | pending | Include non-QWERTY source label mapping. |
| Duplicate/reserved/registered collision rejection | `ShortcutModelsTests` | pending | pending | Prior valid binding must remain after rejection. |
| Master disable and re-enable | `ShortcutModelsTests`, settings repository round-trip | pending | pending | Mappings remain while active registry is empty. |
| CJK/IME marked composition | `ShortcutInvocationGate` fixture | pending | pending | Ordinary composition characters are never consumed. |
| Bounded focus and Escape | `KeyboardEngagementState`, Overlay model tests | pending | pending | Hidden/withdrawn rows are excluded; local edit cancels first. |
| Held/repeated shortcut at-most-once | `ShortcutInvocationGate` fixture | pending | pending | Include key-up reset trace. |
| Attention announcement dedupe | `AccessibilityAnnouncementLedger` fixture | pending | pending | Higher priority may announce once while focus/draft survives. |
| Reduce Motion / Transparency / Contrast / text scale | `AccessibilityAdaptation` fixture | pending | pending | Capture short cross-fade, opaque surface, stronger boundaries, reflow. |
| Keyboard-only and VoiceOver Overlay/Settings | macOS manual run | pending | pending | Do not use Accessibility permission to simulate Host input. |
| Built-in notch and external display withdrawal | AppKit display fixture | pending | pending | Protected gap has no hit/focus/accessibility region. |

## Verification

- `cd src && swift build` — run result recorded by the implementing agent.
- `Scripts/self-check.sh` — run result recorded by the implementing agent.
- `swift test` — XCTest is unavailable in the current command-line-only environment when applicable; authored tests remain in source.

## Risks / follow-up

Global registration is reported as unavailable when native registration is not
proven by the current build. Saved mappings are never silently discarded, and
Product-specific consequential actions remain behind Guided workflow and live
Action Lease gates.
