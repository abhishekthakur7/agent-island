# Attention, completion, plan, and question workflow design

## Decision

Live review on 2026-07-18 selected prototype **C — Guided sheet**. Agent Island
uses one compact, top-edge sheet that guides a person through **Arrived →
Review → Respond → Acknowledged** while keeping the owning Agent Session,
Turn, Attention Request, Agent Product, capability tier, and Host Context
visible. The sheet handles one focused item at a time; a compact queue preserves
parallel work without turning the surface into an inbox or sidebar.

This asset records the validated interaction answer. The prototype code was
throwaway and has been removed.

## Experience goals

The workflow should feel calm, local, and decisive. At every point a person
must be able to answer four questions without opening another view:

1. Which Agent Session and Turn owns this item?
2. What happened or what decision is required?
3. Can Agent Island safely act, or must the person Jump Back?
4. Has the Agent Product acknowledged the response, or has only the local
   presentation changed?

The design prioritizes safety and comprehension over minimizing clicks. It
never converts missing capability evidence into an action, never hides an
unresolved Attention Request, and never describes a local acknowledgement as
an Agent Product success.

## Guided-sheet anatomy

The sheet grows from the collapsed island and remains attached to the display's
top edge. It uses the chosen island visual system rather than a detached toast,
dialog, or notification-center treatment.

From top to bottom it contains:

1. **Collapsed-status bridge.** The leading glyph and label carry the highest
   priority state into the expansion. Unresolved-attention count and total
   Agent Session count remain separate.
2. **Global utility band.** Only durable panel utilities appear here, such as
   sound and Settings. Capability diagnostics are not normal user-facing
   chrome.
3. **Progress rail.** Text and markers show Arrived, Review, Respond, and
   Acknowledged. Completed stages use a check or completed marker; the current
   stage uses both emphasis and accessible text. Color is supplementary.
4. **Owning-session header.** Show project/session title, initial prompt
   summary, Agent Product, model when sourced, Host, elapsed time, and Jump
   Back. Long content truncates here; complete decision context belongs in the
   body.
5. **Workflow body.** One bounded card contains the question, context, inputs,
   and actions. Detail blocks and completion recaps scroll independently when
   they exceed their configured height.
6. **Compact queue.** Small state markers represent other pending or recent
   items. Every marker has an accessible label with kind, owner, and position.
   Selecting one changes the focused item without losing drafts. A separate
   action opens the full Agent Session list.

The ordinary sheet is deliberately narrower than the expanded multi-session
view. It increases height only as needed within configured bounds, after which
the body scrolls. It does not add a modal scrim or block Host input outside its
visible bounds.

## Presentation progression

The progress rail describes presentation and acknowledgement, not an invented
Agent Product state machine:

| Stage | Meaning | Exit |
| --- | --- | --- |
| Arrived | A sourced event has been attributed to its owner and is eligible for presentation. | The focused sheet becomes visible or the person selects it from the queue. |
| Review | The person can inspect complete relevant context and action availability. | A valid input is chosen, an action begins, or the item needs no response. |
| Respond | A supported, request-scoped action is being routed and controls are protected from duplicate submission. | The Agent Product acknowledges, rejects, times out, disconnects, or resolves the item elsewhere. |
| Acknowledged | The source result or the exact scope of a local acknowledgement is shown. | The person advances, collapses, or the acknowledged dwell ends. |

An Attention Request remains durable and unresolved behind this presentation
until authoritative source evidence resolves, expires, cancels, or supersedes
it. Collapsing the sheet does not advance the request. Reopening resumes at the
current stage with preserved drafts.

## Arrival, priority, and queue behavior

- New actionable Attention Requests outrank context warnings, failures,
  completions, and ordinary activity in the collapsed island and focused queue.
- Within the same urgency, preserve arrival order. Do not reorder a request
  while the person is entering an answer.
- A newly arriving higher-priority item increments the queue and updates the
  collapsed status, but does not steal keyboard focus or replace an item being
  actively reviewed.
- When no workflow is being manipulated, an actionable request may auto-reveal.
  Quiet scenes suppress automatic expansion and sound but retain a visible
  unresolved marker.
- A completion may auto-reveal as a focused sheet. Interaction pauses its dwell;
  without interaction it collapses after the configured dwell while the recap
  remains available.
- Selecting **Show all sessions** changes presentation only. The selected item,
  question page, inputs, scroll position, and request ownership remain intact.

## Capability and action rules

Every control is derived from a live, independently negotiated Capability. The
interface does not branch on Agent Product name alone.

- **Act here.** Show a specific action only while its action route, source
  request, owning Agent Session/Turn, and native response scope are live.
- **Continue in Host.** When routing is unsupported or degraded, show the
  content needed to understand the item plus a prominent Jump Back action. Say
  explicitly that Agent Island has not sent or applied a response.
- **Submitting.** After activation, preserve the chosen response, disable
  duplicate actions, and show progress without claiming success.
- **Acknowledged.** Show the source-confirmed result and its exact scope.
- **Rejected or disconnected.** Return to Review when safely retryable through
  the same live source request. Otherwise retire controls and direct the person
  to the Host.
- **Resolved elsewhere.** Atomically mark every local action stale, state that
  the owning Host resolved it first, and offer Jump Back or the next queued
  item. Never replay the response.

## Workflow-specific behavior

### Approval and denial

Review shows the requested tool/action plus complete relevant command, file,
diff, MCP, directory, and impact context supplied by the Agent Product.
Sensitive Interaction Content remains local and follows the chosen display
policy.

- Primary action is **Allow once** when supported.
- **Deny** is visually destructive but does not overpower the safe default.
- An always-allow, permission profile, directory, mode, or rule action appears
  only when the Agent Product supplied that exact choice. Its label describes
  scope; no generic broader rule is manufactured.
- Activating a choice moves the sheet to Respond. It becomes Acknowledged only
  after the Agent Product accepts or reports the result.
- A source denial, policy block, or auto-mode denial is a sourced failure, not a
  user denial, and uses Jump Back.

### Single and multiple-choice questions

The body shows a category when supplied, the complete question, and full-width
options numbered from 1. No answer—including a recommended one—is selected by
default.

- Number keys select visible options while focus is outside text entry.
- Single-choice selection replaces the prior choice. Multi-select toggles each
  choice and requires at least one valid selection unless the source marks the
  question optional.
- Supporting explanations and recommendation text remain attached to their
  option.
- **Next** stays disabled until the current answer is valid.
- Selection remains reversible until the complete response is submitted.

### Multi-question wizard and free text

The overall progress rail remains visible; a subordinate question band shows
answered/current/future markers plus **Question n of m**.

- Previous and Next preserve all drafts and the current question when switching
  queue items, focused/full-list presentation, or collapsing.
- Free-text fields show inline validation, a character count when bounded, and
  that the draft has not been sent.
- Submit sends one answer map scoped to the source request. Respond protects it
  against duplicate submission until source acknowledgement.
- Free text, multi-select, or multi-question UI appears only when the negotiated
  schema supports that shape. Unsupported portions route to the Host while
  preserving earlier drafts locally.

### Plan review and revision

The completed plan renders as accessible Markdown in a bounded scrolling body,
with an optional source view. Partial deltas never masquerade as the completed
plan.

- Claude Code offers the documented plan-approval path. Revision or **keep
  planning** routes to the Host because the documented input has no feedback
  field.
- Cursor ACP offers accept and reject-with-reason using the source tool-call
  scope, without changing permission mode.
- Codex direct mode presents completed plan state. Written comments are scoped
  Turn input/steer, not a fictional plan rejection or approval.
- Observation-only tiers show safely observed plan content and use Jump Back
  for response.

The feedback field requires a non-trivial response before submission. The
Acknowledged stage names whether the result was plan approval,
reject-with-reason, or Turn input.

### Completion recap

Completion uses the same sheet without pretending to be an Attention Request.
It shows the original prompt, redundant Done state, sourced final recap, Agent
Product/Host metadata, and Jump Back. The recap scrolls independently inside a
bounded height.

- Interaction pauses the automatic collapse dwell.
- **Acknowledge** quiets presentation; it does not archive, delete, or end the
  Agent Session.
- **Show all sessions** preserves the recap and opens broader context.
- A source event with background work still running does not enter completion.

### Failure and error

Errors use a redundant error glyph, label, color, and accessible description.
The sheet shows source classification, last confirmed action, and safest
recovery. Nonessential technical detail is collapsed by default.

- Do not automatically retry, relax permissions, infer completion, or turn a
  transport exit into a Product failure.
- Show Retry only when a live Capability defines its exact scope and
  idempotency. Otherwise use Jump Back.
- **Acknowledge** quiets presentation while the Turn remains failed.
- Redacted diagnostic copy excludes Interaction Content by default.

### Context warning

Context health is distinct from provider usage and billing. Show only sourced
percentage, token/window counts, compaction status, and message counts supplied
by the active Capability. Never estimate missing values.

- The first material threshold may auto-reveal subject to notification rules.
- **Acknowledge warning** quiets that threshold for the owning Turn until the
  sourced value changes materially or crosses a higher threshold.
- Compaction progress is activity, not failure or completion.
- Jump Back lets the person inspect or steer the owning Agent Session where
  supported.

## Collapse, dismissal, and cleanup

Labels distinguish outcomes precisely:

- **Collapse** hides the sheet but never resolves or removes an Attention
  Request.
- **Acknowledge** records that a completion, failure, or warning presentation
  was seen; it does not mutate Agent Product work.
- **Deny**, **Cancel**, and **Dismiss request** appear only when they are actual
  Agent Product actions with documented semantics.
- A stale, expired, cancelled, or source-resolved request loses every action
  immediately and remains briefly as an Acknowledged explanation before queue
  advancement.
- An active item is never removed solely by a presentation timer. Cleanup
  requires a terminal source event, confirmed Host closure, explicit local
  history action, or the later defined recovery policy.

Escape collapses the sheet when focus is not in an essential system
interaction. It never activates Deny or discards a draft. Outside-click
collapse follows the configured preference and the same unresolved-request
rule.

## Keyboard, accessibility, and motion

- Tab order follows visual order: session/Jump Back, context disclosure,
  inputs, secondary actions, primary action, then queue.
- Every action has a specific accessible label that includes consequence and
  scope when the visible label alone is insufficient.
- Progress exposes current stage and counts as text; queue markers expose kind,
  owner, urgency, and position.
- Status, urgency, selection, completion, warning, and error use shape/glyph,
  text, and color. High contrast adds defined borders and near-solid surfaces.
- Dynamic Type may increase sheet height and wrapping; action rows wrap without
  changing logical order, and content scrolls before controls disappear.
- Expansion and stage changes use interruptible, critically damped motion around
  0.3–0.4 seconds. Enter and exit follow the same top-edge path.
- Reduced Motion replaces geometry changes with short cross-fades and retains
  state feedback.
- Focus never moves because a new queue item arrives. After source
  acknowledgement, focus moves to the explanation or next safe action.

## Downstream requirements

The action-routing specification must define durable request ownership, live
action leases, idempotency, stale rejection, acknowledgements, and draft
preservation required by this design. The final product specification must
include acceptance scenarios for each workflow in direct-action, Host-fallback,
submitting, resolved-elsewhere, degraded, reduced-motion, high-contrast,
keyboard-only, and VoiceOver states.
