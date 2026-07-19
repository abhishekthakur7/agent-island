# 05 — Harden the native Island Overlay boundary

## What to build

Implement the native AppKit Island Overlay mechanics for Horizon: a single selected-display, non-modal, normally non-activating top-edge presentation surface whose visible geometry, input region, and accessibility tree always agree. It must coexist with the independently activating Settings window and survive display, Space, fullscreen, screen-sharing, sleep/wake, and quit conditions without stealing Host focus or leaving ghost interaction regions.

This ticket completes the required native Overlay feasibility gate. It supplies native panel/lifecycle behavior for the Horizon content, not notification-policy eligibility or Product action authority.

## Context and constraints

- Automatic reveal/collapse, pointer hover, redraw, and inspect/expand clicks must preserve the current Host key state. Deliberate keyboard/accessibility engagement is bounded, visible, and released on collapse.
- There is one live Overlay on one explicitly selected display. Display loss withdraws it and all hit/accessibility regions; it never silently migrates. Settings remains independently usable.
- Built-in displays reserve the physical-notch area for no content or hit target; external displays use an equivalent floating top-edge form without pretending hardware exists.
- The Overlay is non-modal, never dims/blocks the desktop, crosses no Space, stores no Space identity, and never treats presentation activation as Jump Back or Product-action success.
- The currently rendered silhouette is the entire hit/AX region. No screen-edge trigger, invisible expanded panel, or hidden focus stop is permitted.

## Acceptance criteria

- [ ] Native automatic focused/collapsed/expanded presentation hosts Horizon while preserving the previously active Host application/key window under event delivery, hover, ordinary inspect/expand click, display change, and redraw.
- [ ] A configured shortcut or explicit accessible control can begin keyboard engagement with a visible initial focus target and predictable traversal; Escape/collapse, display loss, sleep, and termination end engagement and remove hidden focusable content.
- [ ] Hover expansion and pointer-exit collapse operate only inside currently visible bounds, are independently configurable/debounced, honor interaction guards, coalesce races without flicker, and update hit testing/AX geometry on every presented frame.
- [ ] Built-in-notch and external-display layouts recompute from current selected-display safe bounds. Protected notch reserve has no content/action/AX node; configured dimensions clamp before rendering and do not cross safe bounds.
- [ ] Disconnecting an explicitly selected display atomically withdraws the Overlay, its hit region, and AX elements without migration; reconnection recreates only a collapsed safe presentation and does not restore stale focus/reveal/input.
- [ ] Fullscreen/Space and screen-sharing quiet-scene conditions follow configured presentation policy without crossing Spaces, activating a Host, collecting screen data, or leaving residual interaction regions.
- [ ] Sleep/wake and explicit Quit cancel timers/engagement, invalidate volatile UI authority, withdraw the Overlay safely, preserve durable session state through its own boundary, and never dispatch a pending Product action or Jump Back.
- [ ] The conventional Settings window is independently activatable/restorable and reachable from the system menu even if the Overlay is withdrawn or the selected display is unavailable.

## Required evidence

- Native Overlay feasibility matrix across built-in notch and selected external display, including focus/key-window observations, visible-region hit testing, AX inspection, display disconnect/reconnect, fullscreen/Spaces, screen sharing, keyboard engagement, repeated sleep/wake, and quit.
- Negative captures proving no focus theft, no invisible hit/AX region, no automatic display migration, no notch collision, and no pending action/navigation on termination.
- Accessibility evidence for collapsed aggregate, expanded structured rows, visible-only traversal, VoiceOver labels, and reduced-motion/transparency/contrast/increased-text adaptations.

## Blocked by

- 04 — Deliver the Horizon session-monitoring experience
