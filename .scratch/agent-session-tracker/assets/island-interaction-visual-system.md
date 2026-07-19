# Agent Island interaction and visual system

**Decision date:** 2026-07-18  
**Review:** Human-approved Variant A (Horizon) as the final baseline; values may
be tuned during implementation when accessibility, device, or live-use
evidence requires it.

## Design intent

Agent Island should feel calm, precise, and locally present: a compact top-edge
instrument that communicates ownership and urgency without becoming another
application window. It uses a near-black native-macOS surface, restrained
system typography, compact monospaced operational text, and original nested
diamond/shoreline marks. The marks may animate internally without changing
their frame or surrounding layout. They are decorative when equivalent state
text is already exposed.

The approved design is **Horizon (prototype Variant A)** across every state.
Agent Sessions remain in one chronological flow; focused content is promoted
within that flow, selected detail expands in place, TODO tasks and Subagent
Runs remain nested beneath their owning Agent Session, and large-session
density progressively compacts the same hierarchy. Current and Ledger were
review candidates only and are not part of the final system.

## Geometry

All values are implementation starting points in logical points, subject to
safe-area and available-screen constraints.

| Surface | Starting geometry | Behavior |
| --- | --- | --- |
| Built-in clean | 390 × 38 maximum envelope | Flush to top edge; 136-point protected center region; rounded lower corners only. |
| Built-in detailed | 520 × 38 maximum envelope | Same baseline and protected region; label width is reserved to prevent jitter. |
| External clean/detailed | Same content envelope, 10 points below top edge, 42 points high | Floating pill with 18-point top and 26-point lower radii; protected center reduces to visual breathing space rather than simulating hardware. |
| Focused or normal panel | 760 points wide | Top-attached, up to 690 points or screen height minus 26 points, whichever is smaller. |
| Large-session panel | 760 points wide | Uses compact Horizon rows; same height bound and fixed global header. |
| Normal panel corners | 26-point lower radius | No modal scrim; restrained shadow only. |

The visible surface and actual hit region must always agree. A visually
collapsed island cannot retain an expanded invisible hit target. The built-in
protected center never contains text, a badge, progress, or an action.

## Hierarchy and state

### Collapsed

The clean state shows one status mark and the total Agent Session count. The
detailed state adds one short state phrase, such as **Working** or **1 needs
you**, without changing the outer height. Leading status, protected center,
and trailing count are three stable zones. Attention count and total count are
distinct facts and never replace one another.

Accessible status combines the meaningful state and total, for example:
“Working; 12 Agent Sessions.” Animation frames and decorative marks are not
announced.

### Focused auto-reveal — Horizon policy

The relevant Agent Session is promoted to the first rich row within the same
chronological surface. Its title, abbreviated original prompt, current state,
Agent Product, Model when available, Host, and age remain together. One or more
compact neighboring rows preserve concurrent-work context without creating a
separate stage or side queue.

Attention outranks completion, which outranks ordinary new activity. A focused
reveal does not mutate list selection. Manual interaction suspends its
automatic dismissal; **Show all Agent Sessions** moves to the normal expanded
view without losing the focused or selected detail.

### Expanded list and selected detail

The list is chronological with urgent unresolved Attention Requests promoted
ahead of ordinary activity. Each full row has:

1. a leading state mark and continuity rail;
2. a strong Project/task title;
3. abbreviated **You:** prompt;
4. optional current activity or result supplied by the Agent Adapter; and
5. trailing Agent Product, Model when available, Host, and relative time.

Older or less relevant rows collapse to one line with only essential ownership
and time. Rows are separated by spacing and subtle rules, not a stack of
bordered cards. Hover or selection may add a single charcoal row surface.

Selected completion detail expands inline at its owning row. It includes the
original prompt, explicit done state, response recap, and independent scrolling
within a default 164-point maximum height. Opening it does not reorder adjacent
Agent Sessions or erase the active focused-reveal identity.

### Large-session behavior

Horizon progressively compacts older or less relevant rows while preserving
the same chronological structure and inline-selection model. It never switches
to a table or separate inspector. The header stays fixed; rows virtualize in
the production implementation; selection remains inline without changing
ownership or list order. At least one non-color status cue remains visible in
every row. Increased text or a narrow display may compact descriptive fields
earlier, but ownership remains visible.

## Density rules

- Preserve ownership before descriptive detail. Agent Product and Host outrank
  Model, activity parameters, and long prompts when space is constrained.
- Truncate titles and prompts on compact rows; never push ownership badges out
  of alignment.
- Wrap recap content only inside its bounded detail surface.
- Show rich task and Subagent Run blocks only when the Agent Adapter supplies
  authoritative structure. A Subagent Run remains visibly attached to its
  owning Agent Session.
- Global usage, mute, and Settings controls stay fixed above the scrolling
  region. They do not enter collapsed presentation.

## Semantic appearance

| State | Color role | Required redundant cue |
| --- | --- | --- |
| Active | cool blue | activity label plus internally changing diamond mark |
| Completed/healthy | mint green | done label plus settled diamond mark |
| Attention/setup | warm amber | explicit “needs you” or setup label plus open diamond mark |
| Error/destructive | coral red | error label plus broken/alert diamond form |
| Idle/history | neutral gray | quiet dot/diamond plus age or idle label where needed |

Color never carries state alone. Solid color is used sparingly on a stable
layer; translucent text receives sufficient contrast and weight. System type
is the default; operational labels may use SF Mono or the platform monospace.

## Motion and interruption

- Expansion originates at the top edge and follows the same path in reverse.
- Default transitions use a critically damped spring: damping ratio `1.0`,
  response `0.36s`, with no decorative overshoot.
- Material arrival coordinates scale, opacity, and blur. Text and metadata do
  not animate independently or reflow mid-transition.
- Retargeting begins from the current presented geometry and preserves current
  velocity; input is never locked during a transition.
- Collapsed activity may breathe within the fixed mark frame on a roughly
  1.6-second cycle. It cannot move adjacent labels or counts.
- Automatic reveal dwell remains policy-controlled by the notifications
  decision. This visual system fixes priority and interruption behavior, not a
  copied source duration.
- Reduced Motion replaces movement and blur with a short cross-fade and static
  geometry. No meaning depends on motion.

## Transition policy

| Event | From | To | Rule |
| --- | --- | --- | --- |
| Activity begins | clean | detailed | Update in the fixed collapsed envelope; do not open the panel solely for ordinary activity unless notification policy requests a reveal. |
| New Agent Session reveal | collapsed | focused Horizon | Promote the new session while retaining compact neighboring rows; return when policy dwell expires unless interrupted. |
| Completion reveal | any non-attention state | focused Horizon | Show bounded inline recap; interaction makes the reveal persistent until explicit collapse or navigation. |
| Attention Request | any state | focused Horizon | Outranks activity and completion; preserve separate attention and total counts. |
| Show all | focused | expanded Horizon | Preserve focused identity and any selected detail. |
| Select row | expanded | selected inline/inspector | Selection is independent from reveal state and list ordering. |
| Scale/space threshold crossed | rich Horizon | compact Horizon | Preserve scroll anchor, selection, and focused identity. |
| Pointer exit | expanded | collapsed | Only when enabled and no interaction, keyboard focus, or unresolved modal action requires persistence. |
| Manual collapse/Escape | expanded/focused | collapsed | Immediate and reversible; visual and hit regions shrink together. |

Click cannot universally mean expand because click-to-Jump-Back is
configurable. Hover expansion, click behavior, keyboard focus, and exact window
activation are capability- and setting-aware; the overlay decision owns their
macOS implementation details.

## Accessibility and adaptability

- Full keyboard operation preserves a visible focus indicator and stable
  navigation order.
- VoiceOver receives one coherent collapsed status and structured row labels;
  decorative animation is hidden.
- Increased text scales layout and compacts optional descriptive fields sooner.
  It never clips essential ownership or actions.
- Reduce Transparency uses opaque surfaces and defined borders.
- Increase Contrast strengthens boundaries and muted text while retaining the
  same hierarchy.
- Built-in and external-display forms preserve the same semantics rather than
  pretending an external display has a physical notch.

## Parity traceability

This decision covers inventory items I1–I8 and P1–P5. It preserves the Parity
Baseline’s compact top-edge hierarchy, focused and full-list distinction,
bounded recaps, density variants, state priority, and non-blocking overlay
quality while using original Agent Island marks and an adaptive arrangement.
Notification dwell and suppression remain for the notifications decision;
window level, displays, hit testing, focus, Spaces, and platform accessibility
mechanics remain for the overlay decision.
