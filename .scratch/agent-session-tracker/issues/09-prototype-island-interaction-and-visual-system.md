Status: closed
Type: prototype
Label: wayfinder:prototype
Parent: ../MAP.md
Assignee: Codex
Blocked by: 01-establish-authoritative-parity-inventory.md, 02-define-parity-acceptance-standard.md
Blocks: 16-define-notifications-sounds-filters-and-usage-behavior.md, 17-define-overlay-window-display-input-and-accessibility-behavior.md, 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Prototype the island interaction and visual system

## Question

What original Agent Island visual language, dimensions, hierarchy, density variants, animation principles, and state transitions should govern the clean and detailed collapsed island, focused auto-reveals, expanded session list, selected detail, and large-session behavior while meeting the Parity Baseline?

## Comments

### Prototype ready for live review — 2026-07-18

The switchable throwaway prototype explored three structurally different
directions across the clean, detailed,
focused auto-reveal, expanded list, selected detail, and 30-session states:

- **Horizon** uses a chronological status rail and expands selected detail in
  place without displacing ownership metadata.
- **Current** makes one Agent Session the primary stage while retaining a
  compact adjacent queue.
- **Ledger** favors a dense operational table with a persistent inspector for
  keyboard-heavy and large-session use.

All directions preserve the protected built-in-notch region, provide an
external-display form, separate attention count from total count, keep global
controls outside the scrolling region, bound long content, use original
diamond/shoreline status marks rather than source pixel art, and expose
reduced-motion, reduced-transparency, increased-contrast, and increased-text
treatments. The motion proposal uses a critically damped, top-anchored
materialization with no decorative bounce; state remains understandable when
motion is removed.

The human review subsequently approved the current design as an adaptive
synthesis. Its durable dimensions, hierarchy, density, and transition
decisions are recorded in the resolution below; the prototype implementation
and temporary review record were removed, then restored at the human owner's
request for a second review.

### Resolution — 2026-07-18

The human owner finalized **Horizon (Variant A)**, with later tuning allowed if
implementation evidence requires it. The durable
[Agent Island interaction and visual system](../assets/island-interaction-visual-system.md)
uses its chronological flow, inline selection, nested TODO task/Subagent Run
hierarchy, and progressive compact-row behavior across every presentation
state. Current and Ledger remain review history, not approved policies.

The decision sets starting dimensions, protected-notch geometry, hierarchy,
density and truncation priorities, original diamond/shoreline state marks,
semantic state treatment, critically damped and interruptible motion,
large-session switching, transition precedence, and accessibility adaptations.
It covers Parity Baseline items I1–I8 and P1–P5 while leaving notification
dwell/suppression and native overlay mechanics to their owning downstream
decisions. The throwaway prototype code was removed after this answer was
captured and has since been restored for a second review. The approved durable
decision remains current unless that review supersedes it.

### Second-review prototype addition — 2026-07-18

At the human owner's request, the restored prototype now includes a dedicated
**Subagent Runs** state in all three directions. Horizon nests task progress
and Subagent Runs under the owning Agent Session, Current summarizes them
inside the focused parent stage while retaining the adjacent queue, and Ledger
uses an indented parent/child group suitable for high density. Every direction
now separates an explicit five-item TODO list (three complete, one in progress,
one pending) from three Subagent Runs. It also shows authoritative task count,
parent-child ownership, role/task, elapsed time, current activity, and
independent run state only when supplied by the Agent Adapter. The durable
approved specification remains unchanged pending the second-review verdict.

### Final visual-direction verdict — 2026-07-18

The human owner finalized **Horizon (Variant A)**. It now governs focused
reveals, normal expansion, inline selection, explicit TODO tasks, nested
Subagent Runs, and progressive compact-row behavior for large Agent Session
counts. Current and Ledger are rejected as final directions. The durable
visual-system asset and Wayfinder map were updated accordingly, and the losing
prototype variants and switcher were removed while preserving Horizon as the
approved runnable reference.
