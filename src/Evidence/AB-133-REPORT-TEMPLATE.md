# AB-133 — Shortcuts, keyboard engagement, and adaptive accessibility

This template records evidence only. Empty rows are pending capture; this file
does not claim a recording, VoiceOver inspection, or external-display result.

| Acceptance area | Deterministic fixture / command | Capture or inspection | Result | Notes |
| --- | --- | --- | --- | --- |
| Physical key persistence and input-source labels | `ShortcutModelsTests`, `NativeShortcutInputSourceResolver` | authored | authored | TIS labels are read-only; CJK/IME sources fall back to PhysicalKey labels. No typed-text matching. |
| Duplicate/reserved/registered collision rejection | `ShortcutModelsTests`, `ShortcutRegistrationCoordinatorTests` | authored | authored | Carbon/fake registration is attempted before commit; failed replacement rolls back the prior native binding and persisted mapping. |
| Master disable and re-enable | `ShortcutRegistrationCoordinatorTests`, settings repository round-trip | authored | authored | Disable unregisters every active global binding while retaining mappings; re-enable is transactional and reports per-binding collision. |
| CJK/IME marked composition | `ShortcutKeyEventMapper` + `ShortcutInvocationGate` fixture | authored | authored | Production mapper reads `NSTextInputContext.current?.client.hasMarkedText()`; ordinary composition characters are never consumed. |
| Bounded focus and Escape | `KeyboardEngagementState`, Overlay model tests | pending | pending | Hidden/withdrawn rows are excluded; local edit cancels first. |
| Held/repeated shortcut at-most-once | `ShortcutInvocationGate`, `ShortcutRegistrationCoordinatorTests` | authored | authored | Pressed/repeated global and local events dispatch once until key-up, then permit the next physical press. |
| Attention announcement dedupe | `AccessibilityAnnouncementLedger` fixture | pending | pending | Higher priority may announce once while focus/draft survives. |
| Reduce Motion / Transparency / Contrast / text scale | `AccessibilityAdaptation` fixture | pending | pending | Capture short cross-fade, opaque surface, stronger boundaries, reflow. |
| Keyboard-only and VoiceOver Overlay/Settings | macOS manual run | pending | pending | Do not use Accessibility permission to simulate Host input. |
| Built-in notch and external display withdrawal | AppKit display fixture | pending | pending | Protected gap has no hit/focus/accessibility region. |

## Verification

- `cd src && swift build` — run result recorded by the implementing agent.
- `Scripts/self-check.sh` — run result recorded by the implementing agent.
- `swift test` — XCTest is unavailable in the current command-line-only environment when applicable; authored tests remain in source.

The native Carbon/TIS paths are source-authored and build-checked only; no
manual keyboard, VoiceOver, external-display, or OS-collision capture is
claimed by this evidence file.

## Risks / follow-up

Global registration is reported as unavailable when native registration is not
proven by the current build. Saved mappings are never silently discarded, and
Product-specific consequential actions remain behind Guided workflow and live
Action Lease gates.
