# 16 — Implement shortcuts, keyboard engagement, and adaptive accessibility

## What to build

Let a person operate the visible Island Overlay and Settings completely by keyboard and VoiceOver, with configurable safe shortcuts and equal-quality adaptive presentation. This includes a master global-shortcut switch; physical-key bindings for opening/toggling the Island, switching sessions, and expressly configured safe actions; deliberate visible Overlay keyboard engagement; and accessible, honest fallbacks for unavailable navigation and actions.

## Context and constraints

The Overlay is normally non-activating. Automatic reveals, hover, ordinary inspect/expand clicks, redraw, display transitions, and attention arrivals must retain the Host’s active/key state. Keyboard engagement begins only through a configured global shortcut or explicit accessible/keyable Overlay control, has a visible focus target, and ends on Escape, collapse, display loss, sleep, termination, or explicit focus transfer.

Bindings use a physical macOS key plus modifiers and display its current input-source equivalent; they do not match typed text. A shortcut can never bypass an Attention Request’s confirmation, typed action validation, live one-use Action Lease, capability gate, or Host fallback. Accessibility permission is not required for Island accessibility and is never used to simulate Host input.

## Acceptance criteria

- [ ] The person can configure and persist global bindings for Overlay open/toggle, session switching, and only explicitly configured safe actions; the master disable switch unregisters all bindings without erasing mappings.
- [ ] Binding capture records a physical key and modifiers, renders input-source equivalent labels, rejects in-app duplicates, reserved/system shortcuts, and currently registered collisions before saving, and leaves the prior valid binding intact when rejected.
- [ ] Non-QWERTY and CJK/IME input work safely: marked-text composition never invokes ordinary shortcut characters, while enable/disable/rebind and focused option navigation remain operable.
- [ ] Direct keyboard engagement provides a visible initial focus target, predictable forward/reverse traversal, session navigation, inspection, Show All/collapse, and Escape. Focus order follows the visible Horizon hierarchy and cannot traverse clipped, withdrawn, or hidden rows.
- [ ] Escape first applies normal local-edit cancellation where appropriate; otherwise it collapses the Overlay, ends keyboard engagement, and returns key handling only to the immediately preceding eligible macOS key window with no delayed Host reactivation.
- [ ] The collapsed Island has one concise changing text equivalent with session/attention status and only currently available labelled actions. Protected notch/breathing space has no focus stop or action.
- [ ] Expanded/focused rows expose native semantic roles and source-proven state, owner context, time, selection/attention status, nested Subagent Run hierarchy, disabled/unavailable reasons, and disclosed shortcuts without confusing decorative animation for content.
- [ ] New/higher-priority Attention Requests are announced once with owner context, preserve current VoiceOver focus and safe draft, and never use an accessibility-modal container that blocks the Host.
- [ ] All visible controls distinguish enabled, disabled, unavailable, and destructive/consequential state through labels and semantics, not color alone. Jump Back announces its achieved qualifier; unsupported response routes expose the native-Host fallback.
- [ ] Reduce Motion uses the approved short cross-fade; Reduce Transparency supplies opaque defined surfaces; Increase Contrast strengthens text/boundaries; increased text reflows or compacts optional metadata before clipping owner/action labels or introducing horizontal overflow.
- [ ] Collapse, display loss, fullscreen suppression, sleep, and termination remove hidden Overlay elements from keyboard/VoiceOver navigation and move focus to a surviving labelled control or normal macOS destination.
- [ ] Every consequential shortcut—persistent permission change, denial, cancellation/interruption, content submission, or destructive maintenance—requires the same confirmation, owner/capability validation, and live lease check as its visible control; held/repeated keys dispatch at most once.

## Required evidence

- Keyboard-only and VoiceOver recordings across collapsed, focused, expanded, attention, unavailable-action, Settings, built-in display, and external display states.
- Binding-collision, master-disable, non-QWERTY, and CJK/IME composition fixtures, including no accidental action during text entry.
- Negative traces proving non-activation during automatic/pointer behavior and zero duplicate/stale action dispatch from shortcut repeat.
- Adaptation captures for Reduce Motion, Reduce Transparency, Increase Contrast, and increased text, including accessible focus-tree inspection after withdrawal/collapse.
- Parity-matrix records for I3, P4–P5, A3, O6, and affected H cells.

## Blocked by

- 05 — Harden the native Island Overlay boundary
- 06 — Deliver resumable onboarding and the Atlas Settings shell
- 09 — Handle Attention Requests through the Guided workflow
- 10 — Navigate through the capability-honest Jump Back ladder
- 15 — Implement General and Display settings
