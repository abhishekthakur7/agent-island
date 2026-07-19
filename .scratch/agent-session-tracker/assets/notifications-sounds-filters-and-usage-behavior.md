# Notifications, sounds, filters, and usage behavior

**Decision date:** 2026-07-18  
**Scope:** local presentation of validated Agent Session events: island reveal
and glow, macOS notifications, sound, filtering, and optional provider usage.
It does not grant Agent Product action authority, change Agent Session
lifecycle, or define overlay mechanics.

## Decision

Agent Island turns one validated, current, relevant source change into at most
one durable **Alert Candidate** and evaluates it once through one local
**Notification Policy**. The resulting signal bundle is coordinated rather
than independently emitted: a focused island reveal or collapsed glow, one
sound, and one macOS notification all carry the same candidate identity. This
prevents duplicate delivery from replayed hooks, parallel observation modes,
or competing presentation timers.

A candidate is eligible only after the lifecycle reducer has accepted its
source fact, deduplicated it, and determined a current Agent Session, Turn,
or Attention Request owner. A candidate never supplies lifecycle truth or
action authority. Missing continuity, stale/replayed evidence, an unknown
owner, or an unsupported capability produces no user-facing alert; the
reducer/Adapter instead retains a redacted diagnostic reason.

The policy is local, capability-aware, and privacy-preserving. It evaluates,
in order: source/currentness and deduplication; hard filtering; a **Quiet
Scene**; quiet hours for sound; exact foreground relevance; event settings;
and the currently available notification permission. A later suppression does
not erase the candidate's canonical event, the owning Agent Session, or an
open Attention Request.

This specifies behavior and preference semantics, not a source-product sound,
pixel art, or default sound pack. Source evidence establishes the available
controls and observed short reveal ranges, but not a preferred initial choice
of sound or per-event enablement. The initial configuration must make its
enabled routes visible and reversible; an unavailable macOS permission or
usage capability is always represented as unavailable rather than silently
substituted.

## Candidate identity and coalescing

- Candidate identity is `(Product namespace, native Agent Session ID, native
  Turn/request ID when supplied, semantic event class, source event/revision
  identity)`. It is never derived from title, prompt, command, path, model,
  Host Context, receipt time, or text similarity.
- Replayed or duplicate source evidence may update presentation only when the
  source declares a higher revision; it does not play another sound, show a
  second macOS notification, restart dwell, or create another glow.
- For an event class without a stable native event ID, the Adapter's documented
  weak deduplication key may suppress only an exact duplicate delivery. A
  collision or continuity gap is ambiguous and produces no alert.
- A candidate has one current **primary presentation**: `focusedReveal`,
  `collapsedGlow`, `inlineOnly`, `suppressed`, or `coalesced`. When eligible,
  one sound and one macOS notification are optional facets of that same
  candidate, never separately generated alerts. `coalesced` links a
  lower-priority event to an existing eligible visible candidate instead of
  creating another interruption.
- A newly arriving higher-priority candidate retargets the existing island
  transition from its current geometry. It cancels any lower-priority dwell;
  it does not stack panels, timers, sounds, or macOS notifications. Lower
  priority candidates update their owned row/count and remain available from
  the expanded list.
- Automatic presentation is non-activating: it never takes keyboard focus,
  reserves an Action Lease, or changes selection. Its visible and hit regions
  always collapse together.

## Event classes and presentation rules

| Source-derived class | Required eligibility and presentation | Automatic routes |
| --- | --- | --- |
| `attention` (approval, structured question, plan review, or other source-attributed Attention Request) | The current open request is highest priority. Outside suppression, promote its owning Agent Session to focused Horizon without stealing focus; retain the compact attention count and queue. The focused view remains until source resolution, explicit collapse/navigation, or a higher-priority current request. | Eligible for one configured sound and macOS notification only when the owning work is not already foreground-relevant. |
| `error` | A source-proven current failure/error is below attention and above completion. It may receive the configured short focused reveal; manual interaction suspends automatic dismissal. A transport loss, Host closure, unconfirmed action result, or generic process exit is not an error candidate. | One configured sound/notification when background; otherwise inline/collapsed visual only. |
| `contextLimit` | Only a documented Product context-limit or equivalent Adapter capability may create it. If it also creates an Attention Request, the attention candidate owns presentation; otherwise it uses the error-level route. | One configured sound/notification when background. |
| `completion` | Only a source-proven terminal completion for the current lineage with no pending attention or active/waiting Subagent Run may create it. Show a focused bounded recap for **3–4 seconds** when configured and unsuppressed; interaction makes it persistent until explicit collapse/navigation. | One configured sound/notification when background; otherwise collapsed completion glow/inline recap only. |
| `sessionStart` | A newly declared, currently active parent Agent Session may receive a focused reveal for **2–3 seconds** when configured and unsuppressed. It preserves compact neighboring context and is not a manual selection. | Per-event sound is allowed; macOS notification is off for this class to avoid announcing ordinary work commencement. |
| `acknowledgement` | A local acknowledgement or a source-proven acknowledgement updates only the owning candidate/card. It must not imply Product application or resolve an Attention Request. | No auto-reveal or macOS notification; optional configured acknowledgement sound only. |
| `idleReminder` | Requires a source-proven idle/waiting state or a documented Adapter reminder capability. Silence, missing events, sleep, reconnect, and unresolved observation never create it. At most one unacknowledged reminder may be active per Agent Session. | No focused reveal; optional sound and background macOS notification, subject to policy. |
| `spam` | On three or more user-prompt submissions for the same native Agent Session in a rolling ten-second window, produce one coalesced `spam` candidate. Further qualifying prompts extend the same candidate/window rather than multiplying alerts. | No focused reveal or macOS notification; optional configured spam sound once per rolling window. |
| `subagentCompletion` | A Subagent Run remains under its owning Agent Session. Its completion never makes a parent complete. It may use a separately configured completion timing/sound treatment only when the Adapter supplied the child identity and terminal evidence. | Never a separate top-level macOS notification; it can update or coalesce with its parent’s completion candidate. |

`attention` outranks `error`/`contextLimit`, which outrank `completion`, then
`sessionStart`, `idleReminder`, and `acknowledgement`/`spam`. This extends the
approved Horizon priority of attention over completion and ordinary activity
without changing the attention queue's own source/expiry order. A user may
turn configured reveal classes off; this changes presentation only and does
not suppress an open Attention Request from the queue or its Host fallback.

## Quiet scenes, foreground suppression, and privacy

### Quiet Scene

Focus mode, locked/asleep display, and active screen recording or sharing are
Quiet Scenes. While one is active, Agent Island does not start an automatic
reveal, play sound, or deliver a macOS notification for any candidate,
including attention. It retains the source state and shows only the compact,
content-free island status/appropriate subtle glow when the island itself is
visible. When the scene ends, it does not replay a backlog; current open
attention remains in the queue and current completion/error state remains
inspectable.

Quiet hours are a separate local sound schedule, with a start/end in local
time and an across-midnight interval when end precedes start. Quiet hours mute
only Agent Island sound; they do not alter lifecycle, filtering, macOS
notification permission, or an otherwise permitted visual presentation.
The header mute control immediately applies the master sound state but does
not dismiss cards, cancel a focused reveal, or change event preferences.

### Foreground relevance

When the exact owning Host Context has been revalidated and is the foreground
surface, or the person is already inspecting that exact Agent Session in Agent
Island, the event is `inlineOnly`: no auto-reveal, sound, or macOS
notification. The state/card updates in place. A same-title window, a nearby
tab, an application-only Jump Back capability, or an unrevalidated historical
Host Context is not sufficient proof to suppress an alert.

This is session-scoped. Viewing one Agent Session cannot suppress another
session's attention, error, or completion. Notification payloads contain only
state and a bounded user-configured label; they never contain prompts,
commands, files, diffs, response text, or secret-looking values.

## Filters and probe traffic

Filtering is evaluated before candidate creation and has visible scope,
reason, and preview. It never causes a Product action, modifies an external
configuration file, or deletes canonical history.

| Filter | Rule |
| --- | --- |
| Launcher/probe application | A user-selected launcher/helper/probe app drops its sessions before island presentation. Application-owned health probes are marked at their source and are always dropped. Dropped sessions create no card, count, sound, notification, glow, or usage follow target; diagnostics retain only a redacted reason. |
| Built-in internal-work preset | The enabled, reviewable presets cover only in-scope first-class work: Codex memory-writing under `/.codex/memories`, Codex memory-writer first-prompt patterns, and Claude-Mem compression under `/.claude-mem`. Source presets for out-of-scope Products are not imported as product behavior. A preset may be disabled individually. |
| Directory rule | A user-created local substring rule can suppress presentation for Agent Sessions whose supplied Worktree/path context matches it. The Settings preview shows the live matching session count and names only to the person locally. |
| First-prompt rule | A user-created rule can suppress presentation based on the first supplied prompt. Its named match type, case behavior, and pattern are shown before saving, and its preview shows the number of currently matching sessions. Prompt content remains Interaction Content and is never copied to diagnostics or a macOS notification. |
| Subagent visibility | A user may hide/summarize Subagent Runs only when their owning relationship is source-proven. This changes island presentation; it cannot hide an independent parent Attention Request or fabricate parent completion. |

Every suppression is explainable in the owning Agent Session/Integration
diagnostics as `filtered`, `quietScene`, `quietHours`, `foregroundRelevant`,
`duplicate`, `coalesced`, `capabilityUnavailable`, or `notificationDenied`,
with event class and time but without Interaction Content. Filter previews are
read-only and do not create candidates or play previews.

## Sound and macOS notification controls

The fixed expanded-panel header provides the immediate master mute/unmute
control. Settings provide master sound, volume, an Off-or-sound selection and
safe local preview for every class in the table, imported local sounds, quiet
hours, and probe muting. Preview is explicitly invoked, uses the selected
class's volume, creates no Alert Candidate or macOS notification, and cannot
change an Agent Product state. Imported sounds remain local and do not imply a
network/service integration.

macOS notifications are separately permission- and event-setting-controlled.
They may be used only for eligible background `attention`, `error`,
`contextLimit`, `completion`, and `idleReminder` candidates. One candidate
updates/replaces its own notification when the OS supports that operation;
otherwise a later source revision is coalesced and must not post a second
banner. Agent Island never reissues a notification after restart merely
because it restored a durable Agent Session or Attention Request.

## Optional provider usage

A **Usage Snapshot** is display-only, source-proven provider limit/usage and
reset information supplied by an available `usageObservation` Capability. The
expanded-panel header may show it only when that capability is available and
the person has enabled usage visibility. It offers used-versus-remaining,
preferred-provider selection, or following the current selected Agent
Session's provider. A snapshot always identifies its provider, observation
time, and reset information when supplied; stale/missing data is visibly stale
or absent, never estimated.

Usage is not required for any Agent Adapter, does not alter an Agent Session's
identity or ordering, and cannot cause sound, alerts, or filtering. A Claude
Status Line bridge is allowed only as an explicitly enabled, reversible
Integration Installation: it must preserve the person's existing visible
status-line output, retain exact-entry ownership, and disconnect cleanly.
There is no mandatory bridge for Codex CLI, Cursor, or another unsupported
surface, and no telemetry or external usage relay in this baseline.

## Required acceptance scenarios

- A duplicate completion event, replay, or source revision produces one recap,
  one sound at most, and one macOS notification at most; it never restarts a
  dismissed dwell.
- A new completion arriving while an attention card is focused updates its
  owning row but cannot displace the attention request or steal focus.
- Focus mode, a locked/asleep display, and screen sharing each suppress an
  approval reveal, sound, and macOS notification; ending the scene does not
  replay them.
- With the exact owning terminal pane foreground, a completion updates inline
  with no sound or notification. A same-titled but unrevalidated pane does not
  falsely suppress an eligible background candidate.
- A Codex memory writer, Claude-Mem compression, selected launcher, and
  application-owned probe produce no phantom card, count, sound, notification,
  or usage target; Settings previews their filter effect without emitting an
  alert.
- Three prompts in ten seconds for one Agent Session produce one coalesced
  spam sound at most; two simultaneous Agent Sessions never share a spam
  counter.
- Restart, sleep/wake, reconnect, Host closure, a stale Action Lease, or a
  non-exhaustive reconciliation result cannot emit a completion, error, idle,
  or attention notification without fresh eligible source evidence.
- A hidden Subagent Run never appears as a top-level completion or completes
  its parent; a source-proven parent completion remains independently
  presentable.
- Denied macOS notification permission, disabled sound, unavailable usage
  capability, and a failed/reverted Status Line bridge each leave monitoring,
  the local queue, and Jump Back usable with an explicit degraded/unavailable
  indication.

## Evidence and dependencies

This decision implements inventory items N1–N5, P1–P3, and the notification
parts of O3/O5 from the [Parity Baseline inventory](parity-baseline-inventory.md).
The 2–3 second start and 3–4 second completion intervals, quiet scenes,
filters, sound taxonomy, and usage controls are observed in the frozen
[local product research](../../../VIBE_ISLAND_FUNCTIONALITY.md). It relies on
the [Horizon visual system](island-interaction-visual-system.md) for focused
reveal priority/transition behavior, the [canonical lifecycle](canonical-event-session-lifecycle.md)
for current source truth, and [Attention Request routing](attention-request-action-routing-semantics.md)
for presentation-only controls and Action Lease safety. Content handling is
bounded by the [local-first privacy boundary](local-first-privacy-security-boundary.md),
and optional Claude usage follows the [Claude Code Adapter surface](claude-code-adapter-surface.md).
