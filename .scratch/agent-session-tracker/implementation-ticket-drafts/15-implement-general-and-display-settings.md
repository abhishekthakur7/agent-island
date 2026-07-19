# 15 — Implement General and Display settings

## What to build

Make General and Display durable Settings destinations that let a person configure everyday Island behavior and see a local read-only preview before saving. General controls launch-at-login, hover/reveal/collapse, exact-Host foreground suppression, fullscreen/no-active-session hiding, completion/attention reveal, and labelled click behavior. Display controls selected display, clean/detailed collapsed layout, content size, panel bounds, completion-card height, optional sourced metadata, and safe notch/pill geometry.

## Context and constraints

Settings is a normal independently activating macOS window; the Island Overlay remains the single normally non-activating selected-display surface. Settings previews are local and read-only: they must not emit an alert, move the live Overlay, create a second Overlay, mutate an Integration Installation, or change an Agent Product.

There is one explicit display selection. If it becomes unavailable, all Overlay visible, hit-testing, and accessibility regions withdraw and the person must deliberately reselect; it never silently migrates. Host foreground suppression requires an exact currently revalidated Host Context, while click-to-Jump-Back must follow the separately proven navigation ladder. No custom Jump Back rule is offered without a documented Host destination grammar.

## Acceptance criteria

- [ ] General persists and applies launch-at-login, hover expansion, pointer-exit collapse, completion and attention reveal, fullscreen/no-active-session hiding, exact-Host foreground suppression, and a clearly labelled inspect/expand versus Jump Back click choice.
- [ ] A General preference changes local presentation policy only. It cannot change Product lifecycle, filter canonical facts, delete/Archive a session, reserve an Action Lease, mutate integration configuration, or invent foreground relevance.
- [ ] Foreground suppression activates only for the exact revalidated owning Host Context; a same title, path, nearby tab, app-only result, historical locator, or unrevalidated Host never suppresses an eligible event.
- [ ] Disabled click-to-Jump-Back performs no navigation. An enabled Jump Back click revalidates before navigation and reports its actual achieved level rather than claiming exact success.
- [ ] Display has one selected display identity and only one live Overlay. Choosing another display atomically ends engagement and withdraws/collapses the old presentation before creating the new one.
- [ ] Selected-display disconnect or inability to host the Overlay withdraws all visible, hit-testing, and accessibility regions and records selection-unavailable. Reconnection restores only a collapsed Overlay after revalidation; no stale focus, reveal, timer, or frame is replayed.
- [ ] Saved Display controls apply clean/detailed collapsed layout, content size, maximum panel width/height, completion-card height, optional project/worktree/model/Subagent Run/activity metadata, and geometry clamped to current visible/safe bounds.
- [ ] Built-in display geometry keeps content and targets outside the protected notch; external display geometry uses an honest floating-pill form and never pretends hardware notch semantics.
- [ ] A local preview beside each relevant control reflects pending General/Display values, labels unavailable display state, and preserves readable hierarchy across text/contrast/transparency/motion adaptations.
- [ ] Preview creates no Alert Candidate, sound, notification, Product action, configuration write, Integration Installation mutation, live-Overlay relocation, or hidden input/accessibility region.
- [ ] Fullscreen/no-active-session policies withdraw only local presentation when configured, preserve Settings/menu access, do not cross Spaces or activate a Host, and never conceal active canonical work or its History.
- [ ] No custom Jump Back destination/rule is shown for an in-scope Host lacking a documented user-defined destination grammar, including a bare URL scheme; the available lower fallback remains labelled.

## Required evidence

- Saved-preference and restart traces for every General control, including exact-foreground and disabled-click negative cases.
- Built-in-notch and external-display preview/saved captures, with geometry/hit/accessibility inspection, disconnect/reconnect/reselection, fullscreen, and no-active-session behavior.
- Proof that preview causes no alert, sound, live-Overlay move, Product action, or Integration Installation mutation.
- Jump Back capture showing achieved exact/lower/unavailable levels and no custom-rule offering.
- Parity-matrix records for O3, O4, O5, I1–I5, P4–P5, and applicable H cells.

## Blocked by

- 05 — Harden the native Island Overlay boundary
- 06 — Deliver resumable onboarding and the Atlas Settings shell
- 11 — Implement coordinated Notification Policy
- 12 — Implement protected Session History
