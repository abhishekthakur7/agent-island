# Overlay, window, display, input, and accessibility behavior

**Decision date:** 2026-07-18  
**Scope:** the Agent Island top-edge presentation surface, its independent
Settings window, and the display, input, accessibility, and process-lifecycle
rules that make those surfaces non-disruptive. Notification eligibility,
sounds, and dwell-policy values remain owned by the notifications decision.

## Decision

Agent Island has two deliberately different presentation surfaces:

1. the **Island Overlay**, a non-modal, normally non-activating top-edge
   companion surface on one explicitly selected display; and
2. a conventional, independently activating **Settings window** for durable
   configuration and maintenance.

Pointer activity and automatic presentation never activate Agent Island or
take the key window from the person's Host. A person may deliberately engage
the Overlay with its configured global shortcut or an explicit accessible
control; it may then receive keyboard focus only for that interaction and
releases it on collapse. This is not Host activation, Host navigation, or
authority to send Agent Product input. Jump Back and Product actions retain
their separately negotiated capability and lease requirements.

The [Horizon visual system](island-interaction-visual-system.md) supplies the
surface hierarchy and geometry. This decision supplies the platform behavior
that makes that geometry safe on built-in and external displays. It implements
the baseline outcome rather than treating a notch, a title, a Space, or an
Accessibility element as a durable identity.

## Surface roles and boundaries

| Surface | Role | Activation and level | Never does |
| --- | --- | --- | --- |
| Island Overlay | Compact status, focused reveal, expanded Horizon list, and in-island interactions. | Non-modal and non-activating for automatic and pointer presentation. It may become key only during a deliberate keyboard/accessibility engagement, then relinquishes that engagement when collapsed. It stays above the selected display's ordinary Host content only while visible. | Dim or block the desktop; activate a Host; cross a Space; keep an invisible expanded hit region; imply a Jump Back or Product action succeeded. |
| Settings window | Full configuration, integration health/recovery, diagnostics, and maintenance surface. | Standard independent macOS window, explicitly activated by Settings/Open Settings. Normal app window level; no floating-overlay level and no child/attached-sheet relationship to the Overlay. | Be created or made key by an event, hover, prewarm, display transition, or automatic reveal. |
| System menu/termination command | Explicit access to Settings and Quit when the Overlay is collapsed or unavailable. | Invoked by the person; it must remain operable even when the selected display is disconnected. | Create a second Overlay or revive a stale display selection. |

The Island Overlay is the sole display-owned surface. A Settings window is
not assigned to, attached to, or restored inside an Overlay. Its restored
frame is clamped to a currently visible display's usable frame; if its saved
display is absent, use the display containing the invoking pointer/window, or
the main display when there is none. It must never reopen wholly off-screen.

## Presentation state machine

### State

`overlayPresentation` is exactly one of:

| State | Visible result | Entry conditions | Exit conditions |
| --- | --- | --- | --- |
| `withdrawn` | No Overlay window or hit region. | User disables the Overlay; no selected display is available; application is terminating. | A selected display becomes available and Overlay visibility is enabled. |
| `collapsed` | Clean or detailed top-edge island in the selected display's safe frame. | Initial usable state; auto-reveal expiry; explicit collapse; display restoration. | Valid reveal intent, hover expansion when enabled, explicit expand, or keyboard engagement. |
| `focused` | Horizon panel focused on one Agent Session or Attention Request, with compact neighboring context. | Accepted auto-reveal; explicit focus; highest-priority Attention Request. | Show all; explicit collapse; policy expiry only while no manual engagement is present. |
| `expanded` | Full Horizon list, optionally with inline selected detail. | Explicit expand/show-all; hover expansion; keyboard engagement. | Explicit collapse/Escape; enabled pointer-exit collapse only when the interaction guard is clear. |

`keyboardEngaged` and `interactionGuard` are orthogonal state, not additional
visual states:

- `keyboardEngaged` begins only from a configured shortcut or a deliberate
  accessible/keyable Overlay control. It gives the panel a visible focus
  target and keyboard routing for that engagement. It ends on Escape,
  collapse, explicit focus transfer, display loss, sleep, or termination.
- `interactionGuard` is set while the person is interacting with a control,
  scrolling, editing an in-island field, using VoiceOver focus, or completing
  a supported Attention Request. It suppresses automatic collapse and never
  times out an active request or draft.
- Neither state changes Agent Session lifecycle, Attention Request state,
  Action Lease validity, or Host Context validity.

### Events, priority, and timing contract

The notifications policy produces a typed `revealIntent` containing an owned
Agent Session/Attention Request identity, reason, priority, eligibility,
and optional dwell interval. The Overlay consumes an intent only when it can
show it safely. It does not decide which events deserve sound, glow, reveal,
or suppression.

Priority is `attention` > `explicit person action` > `completion` > `new
activity`. A higher-priority intent may update the focused item, but it cannot
discard an in-progress response, selection, draft, or keyboard focus: the
new Attention Request is announced and promoted in the list, while the
existing guarded interaction remains available. Resolving or withdrawing an
intent removes only that intent's presentation; it never collapses an
unrelated guarded interaction.

For eligible automatic reveals, the policy supplies a configurable short
dwell. Baseline evidence constrains the starting/default ranges to **2–3
seconds for a new-session reveal** and **3–4 seconds for a completion recap**;
an implementation may expose a value within those ranges but must not treat a
source screenshot's value as an invariant. Attention has no automatic expiry.
Any pointer, keyboard, VoiceOver, scroll, selection, or row/control
interaction sets `interactionGuard` and cancels automatic dismissal. A
manual collapse is always immediate and reversible.

On a competing event, retarget from the currently presented geometry. The
Horizon motion rules apply; reduced motion uses a short cross-fade. No event
may cause a transient full-screen/expanded input region, focus transfer, or
timer-driven deletion of an Agent Session.

### Hover, pointer, and hit testing

- Hover expansion and pointer-exit collapse are independently persisted
  General preferences. Their dwell/debounce values are policy parameters, not
  inferred from the visual animation duration.
- Enter is recognized only when the pointer enters the **currently rendered
  visible island bounds**. A pointer at a display's top edge outside those
  bounds is ordinary macOS/Host input; there is no hidden screen-edge trigger.
- While expanding or collapsing, hit testing follows the presented shape on
  every frame. At the collapse commit, the panel hit and accessibility region
  is removed before or atomically with the panel no longer being visible; the
  remaining collapsed hit region is exactly the visible island silhouette.
- Pointer exit schedules collapse only when enabled and `interactionGuard` is
  clear. Re-entry cancels that one pending exit rather than starting a second
  competing transition. Repeated enter/exit events are coalesced, so they
  cannot form an expand/collapse loop or flicker.
- The built-in protected-notch region is neither content nor an action target.
  Its visual reserve is not a transparent bridge between the two visible
  wings. On an external display, the corresponding breathing space follows
  the visual geometry but does not pretend that hardware exists.
- The visible collapsed surface is one coherent control only where its
  configured action is unambiguous. Its accessible name describes that action
  (for example, “Show Agent Sessions” or “Jump Back to selected session”),
  rather than universally claiming that a click expands the panel. Session-row
  clicks use the same configured expand/inspect versus Jump Back semantics.
  A context menu exposes Settings and Quit without requiring a hidden hit area.

## Focus and keyboard behavior

### Non-activation invariant

The following must preserve the pre-existing Host application's active/key
state: session events, Attention Requests, automatic reveal/collapse, hover,
pointer click that only expands/inspects, display/Space/full-screen changes,
screen-recording state changes, and Overlay redraw/recreation. They must not
emit keystrokes, use Accessibility UI automation, or make a Host frontmost.

A direct Overlay keyboard engagement is an intentional exception: it provides
an explicit, visible focus target inside Agent Island. Escape first cancels an
in-progress non-consequential local edit when that is standard macOS behavior;
otherwise it collapses the Overlay, ends `keyboardEngaged`, and returns key
handling to the immediately preceding key window only if macOS still considers
that window eligible. No delayed restoration may reactivate an application the
person changed away from meanwhile.

Opening Settings is also explicit. It activates the Settings window, not the
Overlay, and pauses no Agent Product lifecycle. Closing Settings restores only
normal macOS focus behavior; it does not force a Host to frontmost.

### Keyboard contract

| Scope | Required behavior |
| --- | --- |
| Global shortcuts | Persist configurable bindings for opening/toggling the Overlay, session switching, and only the expressly configured safe actions. A disabled global-shortcut master switch unregisters every binding without erasing mappings. |
| Overlay keyboard mode | Provide a visible initial focus target; predictable forward/reverse focus traversal; session navigation; Show all/collapse; row inspection; and Escape collapse. Focus order follows the visible Horizon hierarchy and never traverses clipped or hidden rows. |
| Attention/Product actions | Reuse the attention-routing contract. Consequential bindings (persistent permission change, deny, cancellation, destructive maintenance) require the recorded confirmation behavior and a live one-use Action Lease. A shortcut cannot bypass an unavailable route or Jump Back fallback. |
| Binding capture and validation | Bind a physical macOS key plus modifiers and render its current input-source equivalent; do not match typed text. Reject an in-app duplicate, reserved/system shortcut, or currently registered collision before saving, show the conflict, and leave the former valid binding intact. |
| Input methods | During marked-text/IME composition, do not consume ordinary composition characters as a shortcut. Test at least a non-QWERTY layout and CJK IME, including enable/disable/rebind and the focused panel's option navigation. |

Shortcut discovery is redundant: visible focused controls include their label
and shortcut where available; a held configured modifier may reveal shortcut
hints but must not replace a labelled control. Keyboard operation must be
complete without pointer hover.

## Displays, notch geometry, Spaces, and full screen

### Selected-display state machine

`displayPlacement` is exactly one of `availableBuiltIn`,
`availableExternal`, `selectionUnavailable`, or `reselecting`. It stores a
user-selected display identity and placement preferences, never a window
title, Space identifier, frame, or display ordinal as the identity.

| Event | Required behavior |
| --- | --- |
| First usable launch / person selects a display | Resolve a currently connected display and enter `availableBuiltIn` or `availableExternal`; calculate the safe top-edge geometry from its current usable bounds and display class. |
| Selected display changes scale, safe area, notch characteristics, resolution, arrangement, or primary status | Recalculate geometry and clamp configured dimensions before showing the next frame. Preserve presentation/selection where the display identity remains valid; never let text, content, or a hit target cross the built-in protected region. |
| Selected external display disconnects or cannot host the Overlay | Immediately end `keyboardEngaged`, withdraw the Overlay and all its hit/accessibility regions, enter `selectionUnavailable`, and retain the explicit selection. Do not silently move the island to another display. Settings/menu status explains the condition and offers a deliberate display selection. |
| Selected display reconnects | Revalidate its identity and safe frame. Recreate only the collapsed Overlay; do not replay a stale reveal, restore key focus, or treat a saved frame as valid. |
| Person chooses another display | End current engagement, collapse/withdraw old presentation atomically, then create one Overlay on the new selection. There is never more than one live Island Overlay. |

Built-in geometry obeys the approved Horizon starting envelope and the actual
safe area: the 136-point protected center is a maximum starting reserve, not
a claim about every MacBook. External geometry uses the approved floating
pill form and only visual breathing space. All configured width, height,
content-size, and alignment values are clamped to the selected display's
current visible/safe frame before rendering or hit testing.

### Spaces and full screen

Spaces and full-screen placement are presentation conditions, not identities
or navigation targets. Agent Island does not save a Space identifier, switch
Spaces, leave full screen, or activate a Host for presentation. A full-screen
or Space transition recomputes Overlay eligibility and geometry for the
selected display only.

The Display preference supplies a persisted `hideInFullscreen` policy. When
it is enabled and the selected display's active Space is full screen, the
Overlay becomes `withdrawn` with no residual hit/accessibility region; an
explicit global shortcut may still open Settings or report the suppressed
condition but does not cross Spaces. When disabled, the Overlay may remain a
non-activating companion on that display subject to macOS's allowed
collection behavior. A Host is never brought forward to make either result
happen. A Jump Back remains the separate explicit action and reports only its
achieved Host-navigation level, never a Space/full-screen success claim.

## Recording, sleep/wake, and termination

### Screen recording and sharing

Agent Island neither captures the screen nor infers Interaction Content from
screen pixels. Screen recording/sharing is a quiet-scene input owned by the
notifications policy. When that policy says automatic presentation is
suppressed, the Overlay declines new automatic reveal intents but keeps the
collapsed meaningful status and all explicit keyboard/pointer/accessibility
actions available. It does not hide an already person-engaged panel, change
an Attention Request's durable state, or manufacture a recording indicator.

### Sleep and wake

Sleep begins by cancelling hover/reveal timers and ending keyboard engagement;
the Overlay may be withdrawn by macOS. Wake is a cold-resume boundary:

1. recreate display placement from currently connected displays and current
   safe frames;
2. rebuild Overlay presentation from durable derived session state, initially
   collapsed if placement is available;
3. require Host Context locators, adapter connections, and Action Leases to
   revalidate through their own contracts before they can support navigation
   or actions; and
4. do not replay pre-sleep input, auto-reveal, focus restoration, Hover state,
   or Action Attempts.

Failure to restore a display or integration becomes an explicit unavailable or
degraded state, not completion, dismissal, or a crash. Repeated sleep/wake
cycles are a required regression case.

### Application and window termination

Closing Settings closes Settings only. Explicit Quit is the only normal path
that terminates Agent Island. On termination, in this order, Agent Island
must stop accepting global input and remove all Overlay hit/accessibility
regions; cancel presentation timers and local animations; invalidate in-memory
keyboard engagement and Action Leases; persist durable state through its
separate lifecycle/persistence contracts; stop only application-owned helper
work; then close the Overlay and Settings windows. It must not send a pending
approval, denial, answer, cancellation, terminal input, or Jump Back merely
because it is quitting. Durable Attention Requests survive for later native
resolution; their routes are unavailable/stale after restart until proven
live again. No global shortcut, monitor, window, or invisible overlay may
remain after process exit.

## Accessibility requirements

The Overlay must be fully operable with VoiceOver and keyboard even though it
normally does not activate the application. Accessibility support for the
Overlay itself uses standard application accessibility; macOS Accessibility
permission is requested only when the person elects an optional
`windowBestEffort` Jump Back fallback, never to make the Overlay interactive
or to automate a Host.

| Surface/content | Required semantics |
| --- | --- |
| Collapsed Island | One concise status group with a combined, changing textual equivalent such as “Working; 12 Agent Sessions; 1 needs attention.” The visual diamond/shoreline animation and frame-by-frame activity are hidden from the accessibility tree. The group exposes only currently available labelled actions. |
| Protected notch/breathing space | No accessible content, action, or spurious focus stop. |
| Expanded/focused list | A named non-modal region with structured session rows. Each row names state, Project/task/title, Agent Product, Host, relative time, and available attention/selection state; optional Model/activity and decorative marks do not obscure ownership. Subagent Runs remain announced as children of their parent Agent Session. |
| Controls and actions | Native semantic roles, stable visible labels, enabled/disabled state and reason, selected/expanded value, and shortcut disclosure. A disabled/unavailable action remains discoverable with its reason; it cannot masquerade as success. Jump Back announces its achieved qualifier and reason. |
| Attention and dynamic updates | Announce a new or higher-priority Attention Request once, with owning session context, without repeatedly announcing animation, timer ticks, or every list refresh. Preserve the current VoiceOver focus and draft when safe; never use an accessibility-modal container that blocks the Host. |
| Motion and display adaptations | Reduce Motion uses the Horizon cross-fade; Reduce Transparency makes surfaces opaque with defined borders; Increase Contrast strengthens text/boundaries; increased text reflows/compacts optional detail before clipping ownership or action labels. Built-in and external display forms keep the same text and action semantics. |
| Settings | Standard titled window semantics, conventional sidebar/content grouping, stable tab order, accessible live preview labels, and explicit ordinary/warning/destructive action distinctions. It must be reachable from the menu even when the Overlay is unavailable. |

Accessible focus is always limited to visible controls and content. Collapse,
display loss, full-screen suppression, sleep, and termination remove hidden
Overlay elements from navigation and move focus to a surviving labelled
control or normal macOS focus—not to a stale row.

## Acceptance matrix

The implementation-ready parity matrix must include these evidence-bearing
scenarios for every applicable supported macOS/display/Host cell. Each row
requires appropriate automated state/hit-test evidence plus a capture,
accessibility inspection, and diagnostic trace where applicable.

| ID | Setup and action | Must observe | Must not observe |
| --- | --- | --- | --- |
| OW-1 | Automatic new-session and completion reveal while an editor/terminal is key. | Focused Horizon reveal obeys policy dwell; Host remains key. | App activation, typed-input loss, visible/hit-region mismatch. |
| OW-2 | Attention arrives during completion reveal and during an active response. | Attention is prominent and announced once; existing guarded response/draft survives. | Timer dismissal, cross-session replacement, duplicated announcement. |
| OW-3 | Rapid pointer enter/exit at the top edge and on the visible island. | Only visible bounds trigger; one debounced reversible transition. | Edge-wide trigger, flicker/loop, invisible expanded hit area. |
| OW-4 | Collapse during pointer, keyboard, VoiceOver, and animated states. | Visible and AX/hit regions contract together; Escape works as specified. | Stranded focus, retained panel hit region, Host activation. |
| OW-5 | Exercise each click configuration on collapsed island and a session row. | Visible/accessibility label describes expand/inspect or Jump Back action; Jump Back reports achieved level. | Universal hard-coded click meaning or navigation-success claim from app activation. |
| OW-6 | Register, rebind, disable, and invoke global/focused shortcuts. | Collision rejection, retained prior binding on failure, disabled-master preservation, focus order, and shortcut labels. | Silent collision, consumed IME composition, unsafe Product action without confirmation/lease. |
| OW-7 | Non-QWERTY and CJK/IME shortcut tests. | Physical binding stays recognizable and normal text composition works. | Layout-specific accidental invocation or input delay/loss. |
| OW-8 | Built-in notch at different safe-area/scale configurations. | Content and hit testing stay outside the protected center and inside safe frame. | Text, badge, or action target across notch; clipped wings. |
| OW-9 | External selected display disconnect/reconnect and deliberate display change. | One Overlay only; withdrawal removes input/AX region; explicit reselection and safe collapsed restore. | Silent display migration, stale focus/reveal replay, off-screen window. |
| OW-10 | Space/full-screen transitions with `hideInFullscreen` both enabled and disabled. | Configured presentation result with no Space claim; explicit Jump Back retains honest level. | Automatic Space crossing, Host activation, residual hidden input region. |
| OW-11 | Screen recording/sharing quiet-scene signal. | Automatic reveal follows notification policy; manual controls and durable state remain available. | Screen capture, forced panel dismissal, altered ownership/action state. |
| OW-12 | Repeated sleep/wake and application restart while Overlay is visible and while attention is pending. | Cold-resume rebuild, stale locator/lease invalidation, no crash; Agent Sessions remain conservatively represented. | Replayed input/focus/reveal, false completion, stale action route. |
| OW-13 | Open/close Settings from each display, while Overlay is visible/unavailable, and after its saved display disappears. | One normal-level, on-screen, independently activating Settings window; Overlay does not become parent/key by side effect. | Flash/prewarm creation, floating-level Settings, off-screen or duplicate window. |
| OW-14 | Quit while collapsed, expanded, keyboard-engaged, and with an Attention Request/draft. | Hit regions/shortcuts/helpers terminate; durable request remains for native fallback. | Dispatch of pending action, leaked monitor/window, ghost global shortcut. |
| OW-15 | VoiceOver, keyboard-only, Reduce Motion, Reduce Transparency, Increase Contrast, and increased text on built-in/external forms. | Coherent collapsed text, meaningful structured rows/control states, once-only attention notice, complete operation. | Decorative animation chatter, hidden focus stop, color-only state, clipped ownership/actions. |
| OW-16 | Exact, best-effort, app-only, and unavailable Jump Back results from the Overlay. | Spoken/visual result names achieved level and reason. | Space/window/thread exactness claim unsupported by the Host contract or simulated Host input. |

## Traceability and durable boundary

- [Parity Baseline inventory](parity-baseline-inventory.md): I1–I7, P1–P5,
  J1–J4, and the overlay/accessibility recovery row.
- [Horizon visual system](island-interaction-visual-system.md): approved
  geometry, hierarchy, motion, and accessibility adaptations; this decision
  owns the platform mechanics it intentionally left open.
- [Host navigation capabilities](host-navigation-capabilities.md) and
  [Host Context identity/navigation fallback](host-context-identity-navigation-fallback.md): no Space identity, no guessed target, and achieved-level feedback.
- [Product direction defaults](product-direction-defaults.md): explicit
  selected display/Settings behavior, complete keyboard and accessibility
  operation, contextual Accessibility consent, and safe cold resume.
- [Parity acceptance standard](parity-acceptance-standard.md): requires the
  listed scenarios to enter the final matrix rather than self-certifying this
  decision.
- [ADR 0007](../../../docs/adr/0007-nonactivating-island-overlay-and-independent-settings.md): records the durable presentation/activation boundary.

## Evidence

This decision is grounded in the frozen local [Parity Baseline research](../../../VIBE_ISLAND_FUNCTIONALITY.md): detailed non-blocking collapsed island and protected-notch observations (lines 173–224), focused reveal/collapse behavior (lines 293–367), display/shortcut/non-activating-overlay controls (lines 590–602), and the release-history failures and regression matrix for hover, displays, Spaces/full screen, sleep/wake, Settings level, Accessibility, and CJK input (lines 628–647 and 735–784). It does not reproduce source branding, assets, or unobserved pixel-level details.
