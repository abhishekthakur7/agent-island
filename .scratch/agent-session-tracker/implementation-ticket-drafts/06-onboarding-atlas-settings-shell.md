# 06 — Deliver resumable onboarding and the Atlas Settings shell

## What to build

Deliver the independently activating Atlas Settings experience and contextual, resumable onboarding. A person can understand Agent Island’s local-first promise, discover what needs setup, leave and resume onboarding, and navigate a conventional macOS sidebar to General, Integrations, Notifications, Display, Sound, Usage, Shortcuts, Labs, Diagnostics, and Maintenance—without the settings shell itself mutating Agent Products, moving the Overlay, or claiming integration health.

This ticket establishes the presentation shell and local preference semantics. Integration plan/apply/verify, detailed capability health, notification policy, and destructive maintenance mechanics remain later vertical slices.

## Context and constraints

- Settings is a normal independently activating macOS window, never an Overlay child or display-owned floating panel. It remains available when the Overlay is unavailable.
- Onboarding is contextual and resumable in General, not a permanent wizard. Completion removes progress treatment, not access to settings/diagnostics.
- Intent and health are distinct. Detection or an enabled switch cannot mean Healthy; this shell must reserve accurate state/reason/next-step presentation.
- Read-only previews are local representations. They cannot emit an alert, move/recreate the Overlay, configure an Integration Installation, or write Product configuration.
- Maintenance is visually/conceptually separated; reset preferences, remove setup, delete local data, and complete cleanup are not casual controls and require later scoped plans/confirmations.

## Acceptance criteria

- [ ] A person can start onboarding from first run, understand aggregation/Host fallback/setup/display concepts, skip it, resume it later, and reach the relevant Settings destination without repeating completed education or losing normal navigation.
- [ ] Settings is a standard independently activating/restorable macOS window with the complete Atlas sidebar grouping and one independently scrolling detail pane; it remains reachable through the menu while the Overlay is unavailable.
- [ ] General exposes local preference controls/placeholders for launch behavior, hover expansion/pointer-exit collapse, exact-Host foreground suppression, fullscreen/no-active-session hiding, completion/attention reveal, and explicitly labelled inspect/expand versus Jump Back click behavior without performing unvalidated navigation.
- [ ] Integrations can display separate enabled intent, compact health state, evidence time, affected capability, and safe next step without conflating detected/configured/loaded/reachable/delivery/action states or enabling anything by discovery alone.
- [ ] Display and notification/filter previews are visibly read-only and update locally. Test instrumentation confirms preview interaction does not emit alerts, move the live Overlay, create/configure an Integration Installation, or alter Agent Product state.
- [ ] The sidebar includes distinct Usage, Sound, Shortcuts, Labs, Diagnostics, and Maintenance destinations; Diagnostic presentation is redacted by construction and Maintenance clearly separates ordinary preferences from consequential categories.
- [ ] Keyboard, VoiceOver, increased text, reduced motion/transparency, increased contrast, and compact-window layouts preserve destination, status, action meaning, and no-horizontal-overflow behavior.

## Required evidence

- UI/AX walkthrough showing first-run, skip/resume/completion, all sidebar destinations, independent Settings activation with unavailable Overlay, and keyboard-only/VoiceOver traversal.
- Read-only preview trace proving no Overlay movement, notification emission, configuration mutation, or Product interaction.
- Accessibility/adaptation screenshots or recordings at increased text, reduced motion/transparency, and increased contrast.
- State-model review demonstrating displayed intent/health fields cannot be derived from a simple enabled toggle.

## Blocked by

- 02 — Persist and reopen one protected Agent Session
