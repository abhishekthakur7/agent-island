# Quality attributes and failure invariants

**Decision date:** 2026-07-18
**Scope:** release-quality requirements for the personal, local-first Agent
Island baseline. These requirements constrain implementation outcomes, not an
implementation stack or UI technology.

## Decision

Agent Island qualifies for the [Parity Baseline](parity-baseline-inventory.md)
only when it preserves safe ownership, conservative state, local privacy, and
non-disruptive macOS behavior under the representative 30-Agent-Session
working set as well as ordinary failure conditions. A responsive rendering of
incorrect, stale, cross-session, or privacy-unsafe data is a release failure.

The confirmed product targets are local event-to-presentation below **250 ms**,
local action-dispatch below **150 ms**, usable warm launch below **one second**,
and usable cold launch below **two seconds** on supported Apple Silicon
hardware. The source research establishes why sleep/wake, duplicate events,
large lists, hit testing, compatibility changes, and input/accessibility need
release gates, but does not evidence further timing or resource constants.
Accordingly, this decision does not invent frame-rate, memory, CPU, battery,
or percentile thresholds. The native-stack decision must set those numeric
resource budgets from measured supported-hardware evidence before an
implementation is accepted.

## Measurement contract

Every result below is recorded in the parity matrix with application, macOS,
Agent Product, Agent Adapter, Host, integration mode, and relevant schema or
capability version. The record identifies the device class and power/display
conditions, test fixture, input/event trace, timestamps, diagnostic trace,
and capture or accessibility inspection as appropriate.

- **Supported environment:** macOS 14+ on Apple Silicon, with every applicable
  first-class Agent Product and Host capability cell. A result from a simulator,
  mock, or unsupported version may supplement, but cannot replace, the needed
  real or faithful controllable Adapter evidence.
- **Local event-to-presentation:** measure from acceptance of a validated local
  Adapter event at the Agent Island intake boundary to the first rendered,
  accessible presentation of its resulting current state. Product transport
  time before local receipt is reported separately and never used to hide a
  local delay.
- **Local action dispatch:** measure from completion of the explicit
  confirmation/revalidation gesture to exactly one handoff attempt at the
  negotiated Agent Adapter boundary. It does not include Agent Product
  processing or falsely claim that the action was applied.
- **Usable launch:** measure to a responsive collapsed Island Overlay or an
  explicit selected-display-unavailable state, with the local store checked,
  no stale Action Lease enabled, and Settings/menu access available. A cold
  run starts with no Agent Island process; a warm run follows a prior usable
  run with the same protected local data. Neither condition authorizes clearing
  history, bypassing integrity checks, or delaying recovery work invisibly.
- **30-session workload:** include up to 30 independently owned active and
  inactive Agent Sessions across the supported Product/Host combinations,
  with a mix of parent/child work, current terminal states, Attention
  Requests, completion recaps, history, selection, scrolling, and ordinary
  event delivery. Exercise duplicate, delayed, reordered, gap, reconnect,
  rewind, compaction, and concurrent-attention traces. A 31st safely inactive
  session tests archival; an all-active/all-attention set tests permitted
  overflow.
- **Resource observation:** record idle and loaded CPU activity, memory,
  wakeups/energy impact, disk use, open handles, timer/task count, and sound
  resource lifetime during the workload, extended idle, display changes, and
  repeated sleep/wake. Until numeric budgets are set, evidence must show a
  stable steady state: no continuously retained growth, busy polling loop,
  repeated background presentation, leaked sound/output handle, or resource
  accumulation across equivalent repetitions.

The timing targets apply to every measured standard-condition sample in the
release evidence. An over-target sample is a failure unless the matrix shows a
reproducible measurement fault; a slower upstream Product response is not an
exception to a local target.

## Required quality outcomes

| ID | Attribute | Release requirement and observable evidence |
| --- | --- | --- |
| Q1 | Responsiveness | Each validated current event reaches its correct local visual and accessibility state in under 250 ms. A valid explicit action reaches one Adapter dispatch attempt in under 150 ms, with its separate `rejected`, `acceptedByProduct`, `applied`, `superseded`, or `indeterminate` outcome shown honestly. Trace timestamps prove both boundaries. |
| Q2 | Startup and recovery | Warm launch is under one second and cold launch under two seconds. Both restore verified local evidence without duplicate cards, a recovered live claim, a live Host locator, or an enabled stale Action Lease. A failed store/key/schema check is a visible unavailable/recovery state rather than a faster silent reset. |
| Q3 | Thirty-session scale | The 30-session workload remains legible, keyboard-operable, accessible, independently scrollable, and responsive enough to satisfy Q1. It retains all current work, request ownership, histories, and diagnostics. The 31st safely inactive session moves to Session History without data loss; if no safely inactive session exists, the working set visibly exceeds 30 rather than evicting active, unresolved, child-active, or attention-requiring work. |
| Q4 | Memory and energy | At idle and through the scale, display, and sleep/wake workloads, resource evidence demonstrates the stable steady state defined above. The release record includes the measured resource series and the later stack-specific numeric budget. No idle relaunch, cleanup timer, or resource mitigation may delete, conceal, or reclassify Agent Session evidence. |
| Q5 | Reliability and correctness | The required lifecycle, routing, overlay, setup, and recovery fixtures complete with no crash, hang, ghost session, duplicate current fact, stuck hidden request, false terminal state, or lost durable record. Transient transport/Host failure is diagnosed and capability-local where possible; it becomes `unresolved`, degraded, or unavailable rather than completed or healthy. |
| Q6 | Security and privacy | Protected local state is authenticated and encrypted at rest; invalid ciphertext, key loss, malformed input, or schema/migration failure contributes no state or action authority. Seeded Interaction Content and credentials must be absent from Diagnostic Bundles, notifications, unapproved logs, and future-service paths. Only an explicitly confirmed user-data export may include selected Interaction Content, and it remains local unless a separately approved Service Egress exists. |
| Q7 | Accessibility | Every supported Overlay and Settings job is complete with keyboard and VoiceOver: visible focus only, semantic roles/names/state/reason, text equivalents for compact status, once-only attention announcement, usable increased text, Reduce Motion, Reduce Transparency, and Increase Contrast. Evidence includes keyboard traversal, accessibility-tree inspection, and VoiceOver operation on built-in and external display forms. |
| Q8 | Diagnostics | Each accepted, filtered, deduplicated, quarantined, downgraded, rejected, unavailable, degraded, or failed operation has retained redacted operational evidence sufficient to identify its owner, capability/health condition, time, and safe recovery path. Diagnostics never promote unproven state, expose Interaction Content, or report a fallback as exact success. |
| Q9 | Compatibility and degradation | A changed, unsupported, ambiguous, disconnected, permission-denied, or unknown Agent Product/Host/Adapter/schema version narrows only the affected Capability. The application shows Disabled, Setup required, Healthy, Degraded, Unavailable, or Incompatible with evidence and non-destructive next action; it does not guess version semantics, broaden permissions, auto-repair configuration, or silently enable a new integration. |
| Q10 | Display, sleep, and wake | Built-in notch and selected external-display behavior preserve safe geometry, visible-only hit/accessibility regions, and one Overlay. Display loss withdraws the Overlay rather than migrating it. Sleep/wake and restart are cold-resume boundaries: they cancel timers/engagement, invalidate live locators and Action Leases, rebuild conservatively, and never replay input, focus, reveal, or an Action Attempt. Repeated cycles must complete without a crash. |
| Q11 | Adapter, action, and navigation safety | Every event, request, action, shortcut, configuration mutation, and Jump Back is validated against exact owner identity, negotiated Capability, and current liveness. A response is dispatched once only with its live one-use Action Lease; navigation reports the actual ladder level. Fixtures prove a same-looking session, pane, title, path, callback, or stale route cannot receive another owner's action or become an inferred exact target. |

## Failure invariants

The following are forbidden in every applicable capability cell. One observed
violation is a release-blocking failure; a fallback may reduce capability but
cannot waive an invariant.

1. **No invented Product truth.** Silence, timer expiry, Host closure,
   transport loss, action acceptance, local cache, or presentation metadata
   must not create completion, failure, identity, lineage, or request
   resolution. Gaps and contradictions remain conservatively unresolved.
2. **No ownership crossing.** Agent Session, Turn, Subagent Run, Attention
   Request, Integration Installation, Host Context, and Action Attempt data
   must not merge, disappear, or act across native owner tuples—even when
   titles, prompts, paths, models, panes, or timestamps look the same.
3. **No stale or duplicate control.** No restart, reconnect, timeout, double
   gesture, shortcut repeat, callback loss, or indeterminate dispatch can
   reuse an Action Lease, replay an action, or present Product application as
   confirmed without Product evidence.
4. **No unsafe navigation claim.** A stale/ambiguous locator must not receive
   simulated input or an exact-success label. Jump Back may only take the
   independently revalidated `exactSurface`, `exactTab`,
   `workspaceOrFile`, `windowBestEffort`, `appOnly`, or `unavailable` path and
   must name the achieved result.
5. **No active-work loss.** The 30-session presentation cap, idle/resource
   management, filter, collapse, history transition, crash recovery, or
   display change must not delete, hide as terminal, or stop monitoring an
   active, waiting, unresolved, child-active, or attention-requiring Agent
   Session.
6. **No duplicate or disruptive presentation.** Duplicate/replayed events,
   parallel observation, hover races, or wake recovery must not produce extra
   cards, sounds, notifications, timers, focus theft, flicker loops, or an
   invisible input/accessibility region.
7. **No privacy or configuration overreach.** Agent Island must not expose
   Interaction Content or credentials through diagnostics/notifications, make
   unconsented egress, read private Product state to infer truth, overwrite a
   configuration file, adopt an unproven external entry, or remove anything
   not proved by its Ownership Manifest.
8. **No dishonest health or degradation.** Enabled intent, discovery, loaded
   configuration, endpoint reachability, delivery, action readiness, and Host
   navigation must remain distinct. Unknown/unsupported versions and denied
   permissions fail closed with an inspectable degraded state.
9. **No accessibility regression as a fallback.** Reduced motion, display
   adaptation, unavailable navigation, disabled action, or non-activating
   behavior must preserve a labelled, keyboard/VoiceOver-operable and honest
   alternative; hidden controls must not retain focus.

## Release gates and evidence

The final parity review cannot mark an applicable cell passed until all of the
following evidence is linked from its parity record:

| Gate | Required evidence |
| --- | --- |
| Timing and launch | Q1/Q2 timestamp traces for standard local events/actions and cold/warm launches, including the measured conditions and target comparison. |
| Scale and resources | Q3/Q4 30-session, 31st-history, all-active-overflow, extended-idle, sound-release, and measured-resource records. The stack-specific resource budget must be present before release. |
| Lifecycle and recovery | Deterministic fixtures for duplicate/reordered/gap/rewind/compaction/reconnect/restart and repeated sleep/wake, plus captured state and redacted diagnostic evidence. |
| Safety and privacy | Negative tests for ownership collision, stale lease, indeterminate dispatch, ambiguous Jump Back, manifest drift, malformed/encrypted-store input, permission denial, and seeded-content redaction. |
| Overlay, accessibility, and compatibility | The OW-1 through OW-16 matrix, keyboard/VoiceOver/adaptation inspection, built-in/external display and Space/full-screen cases, and affected-version degradation records. |
| Human parity review | The applicable functional, interaction, visual-quality, and approved-deviation records required by the [parity acceptance standard](parity-acceptance-standard.md). Automated evidence cannot self-certify this gate. |

These gates refine, and do not replace, the canonical lifecycle,
Attention-Request routing, Host Context, persistence, notification, Overlay,
Integration Installation, and Settings decisions. Production implementation,
benchmark harness choice, and stack-specific numeric resource budgets remain
for the downstream architecture and implementation work.

## Evidence and rationale

The numeric targets and 30-session posture are the confirmed
[product-direction defaults](product-direction-defaults.md). The relevant
failure modes come from the frozen [local product research](../../../VIBE_ISLAND_FUNCTIONALITY.md), especially its release-history reliability findings and minimum regression suite (lines 618–784). The detailed dependent contracts are the [canonical lifecycle](canonical-event-session-lifecycle.md), [action-routing](attention-request-action-routing-semantics.md), [Host Context navigation](host-context-identity-navigation-fallback.md), [persistence and recovery](persistence-history-recovery-and-retention.md), [notifications](notifications-sounds-filters-and-usage-behavior.md), [Overlay behavior](overlay-window-display-input-accessibility.md), [Integration Installation lifecycle](integration-setup-reconciliation-and-uninstall.md), and [Settings/diagnostics decision](settings-onboarding-diagnostics-information-architecture.md).

No glossary term is added: release gate, metric, and invariant are general
quality-assurance terms rather than Agent Island domain concepts. No ADR is
warranted because this decision establishes acceptance requirements without
selecting a hard-to-reverse architectural mechanism; the durable architecture
boundaries it enforces are already recorded in the linked ADRs.
