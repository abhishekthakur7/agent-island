# Normalized Agent Adapter and Capability Contract

**Decision date:** 2026-07-18  
**Scope:** the implementation-neutral boundary between Agent Island and every
Agent Adapter. Exact serialized schemas and concrete process boundaries remain
for the later data/event/action contract and architecture decisions.

## Decision

Every Agent Adapter implements one version-negotiated, fail-closed contract
with seven independent surfaces:

1. discovery and compatibility inspection;
2. normalized event ingestion;
3. capability negotiation;
4. typed action routing;
5. owned-configuration planning and reconciliation;
6. multidimensional health and degradation reporting; and
7. independent observation, action, and configuration kill switches.

An Agent Adapter may expose more than one **integration mode** for the same
Agent Product. Capabilities are negotiated for the concrete configured
integration instance and, where the Product surface differs, for each Agent
Session or outstanding native request. They are never inferred from the
Product name, an enabled preference, or a previously observed version.

The contract normalizes identity, provenance, lifecycle evidence, action
outcomes, health, and ownership. It does not flatten Product-specific meaning.
Every normalized fact retains its Product namespace, native identity,
integration mode, source event kind, compatibility evidence, and semantic
variant. Unsupported semantics remain explicit, namespaced extensions or
unavailable capabilities; an Adapter must not approximate them with a
different common action.

## Contract negotiation and identity

At activation, Agent Island and the Agent Adapter choose the highest mutually
supported contract version and record a new immutable negotiation snapshot.
The snapshot contains:

- contract major/minor version and capability-catalog revision;
- Adapter kind and build version;
- configured Product namespace and integration-instance identity;
- integration mode, Product executable/build/version and interface/schema
  version where observable;
- declared extension namespaces;
- discovery and probe evidence with its observation time; and
- the resulting capability records and health dimensions.

Contract versions use major/minor compatibility rules. A major change may
alter meaning or required fields and requires an explicit Adapter update. A
minor change may add optional fields, event variants, health reasons, or
capabilities; receivers ignore unknown optional minor-version fields but must
not treat an unknown event or capability as a known one. A capability-catalog
revision changes the known vocabulary without changing the envelope.

An unsupported contract major makes the instance `incompatible`: Agent Island
accepts no events, sends no actions, and performs no configuration mutation.
An unknown or changed Product/interface version triggers a fresh read-only
probe. Until it succeeds, only capabilities proved safe independently of the
changed surface remain available. Product upgrades never inherit a rich action
claim merely because observation still works.

The Product namespace plus Product-native identifier remains authoritative for
Agent Sessions, Turns, Subagent Runs, and Attention Requests. The integration
instance and mode are routing provenance, not replacement identity. An Adapter
reports `identityUnresolved` when native evidence is absent or ambiguous; it
must not synthesize continuity from titles, prompts, paths, timestamps,
processes, models, or Host Contexts.

## 1. Discovery surface

Discovery is read-only and side-effect free. It returns zero or more
installation candidates rather than silently selecting or configuring one.
Each candidate reports:

| Field | Requirement |
| --- | --- |
| Product evidence | Product kind, Product namespace proposal, executable/application identity, version, and evidence source. |
| Integration modes | Independently selectable documented surfaces, such as observation hooks or a directly controlled protocol. |
| Compatibility | `compatible`, `incompatible`, `unknown`, or `probeRequired`, with a stable reason and supported version/interface bounds. |
| Setup evidence | Whether an owned entry is absent, present, externally changed, shadowed, invalid, or blocked by policy/trust. |
| Permissions | Required filesystem, Accessibility, extension, or local-IPC access, including whether each has actually been granted. |
| Probe plan | The exact non-mutating probe available and the sensitive-data class of its result. |

Discovery must use documented Product locations and interfaces or paths the
person selected. It may not scan arbitrary home-directory contents, parse
terminal scrollback, launch a competing resume process, or treat private
transcripts/state stores as an authoritative feed. Finding a Product is not
proof that setup, delivery, or actions work.

## 2. Event-ingestion surface

The Adapter projects every accepted Product event into a validated normalized
envelope before it reaches the core. The envelope carries:

- negotiation-snapshot ID and integration instance/mode;
- Product namespace and all available native owner IDs;
- stable source-event ID, or an Adapter-scoped deduplication key explicitly
  marked as weaker evidence;
- Product event kind and normalized semantic family/variant;
- Product occurrence time when supplied and local receipt time;
- source ordering/cursor evidence when the Product supplies it;
- payload classification as Operational Metadata or Interaction Content;
- normalized facts, plus an optional versioned Product-namespaced extension;
- validation, redaction, and continuity/gap evidence.

The initial semantic families are identity/discovery evidence, Agent Session
and Turn activity, Attention Request evidence, tool activity, plan state,
Subagent Run activity, usage/context evidence, Product error, configuration
change, and transport/reconciliation evidence. This list is routing vocabulary,
not a canonical lifecycle state machine; that decision belongs to the session
lifecycle issue.

Ingestion obeys these invariants:

- validate contract version, size, type, source identity, ownership, and
  payload classification before accepting an event;
- deduplicate by stable source evidence and make duplicate acceptance
  idempotent; never deduplicate Interaction Content by textual similarity;
- preserve Product ordering evidence but tolerate out-of-order delivery;
  sequence gaps become explicit gap evidence, not invented intermediate events;
- unknown variants are retained only as safely classified, non-actionable
  evidence and never advance lifecycle or satisfy an Attention Request;
- reconnect/replay is accepted only when the Product documents it; a private
  transcript or state file cannot silently fill a gap;
- Adapter transport EOF, helper exit, or disconnection is degradation, never
  Product completion; and
- malformed, unauthenticated, oversized, mismatched, or cross-session input is
  rejected with a redacted diagnostic reason and no Product action.

Interaction Content is admitted only when a declared capability requires it
and the source is documented. Raw input is not copied into diagnostics or
generic extension logs. Product-specific extensions are versioned and
classified at their Adapter boundary; the core defaults an unknown extension
field to Interaction Content.

## 3. Capability-negotiation surface

A capability is a structured claim, not a boolean. Each record contains:

| Dimension | Required meaning |
| --- | --- |
| ID and revision | Stable semantic ID from the common catalog or a Product-namespaced extension. |
| Scope | Integration instance, integration mode, Agent Session, Turn, or one outstanding native request. |
| Direction | `observe`, `act`, `configure`, or `navigate`; observing a request never implies authority to answer it. |
| Availability | `available`, `unavailable`, `temporarilyUnavailable`, `unknown`, or `incompatible`. |
| Maturity | `documented`, `experimentalOptIn`, or `diagnosticOnly`; experimental support is never enabled merely for parity. |
| Constraints | Supported variants, option cardinality, response forms, permission choices, timeouts, content limits, and Product policy restrictions. |
| Evidence | Product/interface version, probe result, native method/event, source date, and negotiation snapshot. |
| Freshness | Observation time, optional expiry, and conditions that require renegotiation. |
| Fallback | Another independently available capability, usually Jump Back; never a fabricated equivalent action. |

The common catalog must keep materially different behavior separate. At
minimum it distinguishes lifecycle observation, completion evidence, failure
evidence, structured single/multiple-choice questions, free-text response,
plan observation, plan approval, plan feedback, permission allow, permission
deny, persistent Product-provided permission suggestion, arbitrary Turn input,
Turn steering, Turn interruption, Subagent Run observation/control, usage
observation, and exact Host navigation. A generic `interactive` or
`supportsAttention` capability is insufficient.

Capability snapshots are immutable audit evidence. A newer snapshot supersedes
one for future routing but does not rewrite the facts under which an earlier
event or action was accepted. The effective capability may narrow at runtime
because a particular Agent Session is observation-only, a native request has
expired, Product policy disallows an offered choice, or a kill switch is open.

## 4. Typed action surface

There is no generic `execute`, terminal-keystroke, or raw Product-command
method. Each action type has its own validated request and result. A request
contains:

- action type/version and unique attempt ID;
- exact Product namespace and native Agent Session/Turn/item/request IDs;
- integration instance and mode selected from the event provenance;
- capability record and negotiation snapshot being relied on;
- Product-native response token or live request lease where required;
- expected current-state/native-input fingerprint and expiry/deadline;
- one semantic choice permitted by the negotiated constraints; and
- user intent and local correlation ID, without credentials in durable logs.

Before dispatch, both core and Adapter independently validate target ownership,
live capability, constraints, native lease, expected state, deadline, and kill
switches. Action tokens and synchronous leases are single-use, scoped to their
native request, kept only as long as required, and never guessed, replayed, or
matched by command text.

Action results distinguish:

| Result | Meaning |
| --- | --- |
| `rejected` | Validation failed before Product dispatch; includes stale, mismatched, unsupported, policy-blocked, killed, and invalid-choice reasons. |
| `acceptedByProduct` | The Product accepted the command/request; this is not proof of its eventual effect. |
| `applied` | A documented synchronous response or later Product event proves the requested effect. |
| `superseded` | The Product or its native UI resolved the request first. |
| `indeterminate` | Dispatch may have occurred but no documented evidence can prove the outcome; never retry automatically. |

Timeout, disconnect, or Adapter crash never becomes `applied`. Retry is allowed
only when the Product documents idempotency for the same native request and the
request is still live; otherwise the person receives a stale/indeterminate
result and the native Host fallback. An Adapter must not translate failure to
reach Agent Island into Product approval or denial unless that exact fallback
is defined by the Product's hook protocol and shown during setup.

## 5. Configuration-ownership surface

Configuration is a plan/apply/verify/reconcile contract, separate from
discovery and event delivery. The Adapter maintains a local ownership manifest
for every entry or artifact it created, including scope, exact semantic entry,
canonical and symlink-aware location, install version, before/after validation
facts, and a secret-free fingerprint sufficient to detect external change.

The surface provides read-only inspection, an explicit enable/repair/migrate
plan, application of an approved plan, post-write verification, disable, and
uninstall planning. Every mutation must:

- be atomic and limited to the exact application-owned entry;
- preserve unrelated keys, comments, formatting, ordering, symlinks, custom
  paths, permissions, and external edits;
- refuse a lossy round trip, ambiguous ownership, managed-policy override, or
  unsupported schema and explain the non-destructive manual remedy;
- never alter Product permission mode, unrelated hooks/extensions, telemetry,
  status lines, or repository-shared configuration without a separate explicit
  decision; and
- remove only manifest-proven owned material during disable/uninstall.

`enabledIntent`, `configured`, `loaded`, `reachable`, `deliveryVerified`, and
`actionVerified` are separate facts. Reconciliation reports drift and a repair
plan; it does not silently repair external edits or relocate itself around
policy. Kill switching or disabling runtime I/O does not uninstall anything.

## 6. Health and degradation surface

Health is a timestamped vector with stable reason codes, not one green/red
boolean. It reports at least:

- Product discovery/version compatibility;
- configuration ownership and load state;
- required local permission state;
- helper/extension/process and authenticated transport reachability;
- protocol/schema negotiation;
- event-delivery freshness and known gaps;
- per-action-family round-trip readiness;
- capability-level restrictions or circuit breakers; and
- last successful probe, last failure, and recommended non-destructive repair.

The UI may derive a concise summary—`disabled`, `setupRequired`, `healthy`,
`degraded`, `unavailable`, or `incompatible`—but must retain and display the
underlying dimensions. `healthy` requires verified delivery for the enabled
mode; a present executable, installed entry, enabled toggle, or connected
transport alone is insufficient. Lack of recent events is `unknown` unless a
documented heartbeat or probe proves failure.

Degradation is capability-local. Loss of an action lease disables that action,
not lifecycle observation. Loss of the rich control transport may leave a
separately configured observation mode or Jump Back available. Conversely,
seeing an Attention Request through a hook does not make its response action
available. Every downgrade records the affected capability, reason, start
time, evidence gap, user-visible consequence, and safe fallback.

On a gap, restart, reconnect, or Product update the Adapter may reconcile only
through a documented read/list/replay/probe surface. Otherwise it preserves
last-known historical facts, marks current truth unresolved, retires unsafe
actions, and waits for new source evidence. It never synthesizes completion,
replays stale attention, scrapes a private store, broadens permissions, or
silently drives the Host.

## 7. Kill switches and circuit breakers

Agent Island has independent, default-deny dispatch gates for:

1. event intake/observation;
2. Product action issuance; and
3. configuration mutation.

Each gate can be closed globally, per Adapter kind, per configured integration
instance/mode, and per capability/action family. Persistent user disablement,
an emergency runtime kill switch, and an automatic safety circuit breaker are
distinct states with distinct reasons. A global action kill switch can stop
all Product actions while observation and Jump Back continue; a configuration
kill switch prevents install/repair/uninstall writes without misreporting the
existing runtime as removed.

Closing an action gate atomically rejects new requests and revokes pending
local leases. It does not emit approval, denial, cancellation, keystrokes, or
cleanup to the Product. The Adapter follows the Product's already-declared
native timeout/fallback behavior and marks the Island Attention Request stale
or native-only as evidence arrives. Closing observation records a gap boundary,
stops accepting new Adapter events, and does not mark active work complete.

Malformed or unauthenticated input, repeated identity/lease mismatches,
protocol/schema violation, or an unsafe unknown Product version may trip an
automatic circuit breaker only for the smallest affected surface. Observation
may continue when safely separable. Automatic reset is forbidden for an
action or configuration breaker; explicit successful revalidation and user
reenablement are required. Every gate change is local, auditable without
Interaction Content, immediately visible in health, and testable without the
Agent Product running.

## Preserving Product-specific semantics

The core consumes common outcomes only where their meaning truly agrees. The
following are deliberately not interchangeable:

- Claude Code hook observation/control, Codex hook observation, Codex
  app-server control, Cursor Hook observation, and Cursor ACP control;
- a Product permission suggestion and a session-only allow;
- notification that input is needed and a live request that may be answered;
- plan Markdown approval, a plan-state update, and free-form plan feedback;
- request acceptance, Turn interruption, and observed Turn completion; and
- context-window usage, Product subscription limits, and cost/token usage.

A Product-namespaced semantic extension can add faithfully sourced detail, but
cannot bypass common identity, classification, health, action, or kill-switch
invariants. UI and policy code branch on negotiated semantic capability and
variant, never on `isClaude`, `isCodex`, or `isCursor` conditionals standing in
for evidence.

## Required baseline mode mapping

| Agent Product integration mode | Observation | Direct actions | Required honest degradation |
| --- | --- | --- | --- |
| Claude Code documented hooks | Session/Turn, completion/failure, attention, plan/question/tool and Subagent Run evidence, subject to version gates. | Only live synchronous documented hook decisions; arbitrary input, cancellation, and plan-revision text are unavailable. | Expired/unreachable hook falls back to native prompt and Jump Back; never replay. |
| Codex CLI hooks | Independently launched CLI lifecycle, Turn, permission/tool and limited subagent evidence. | None for the terminal-owned prompt. | Notify and Jump Back; do not simulate terminal input. |
| Codex app-server | Directly connected Thread/Turn stream, approvals, plan, usage, and schema-gated optional events. | Typed native server responses and documented Thread/Turn actions while connected. | Disconnect retires outstanding request routing; reconcile by native ID and mark gaps. |
| Cursor IDE Hooks | New local IDE Agent Session observation, activity, compaction, and partial subagent evidence. | No documented approval/question/plan response channel. | Observe/notify and use separately negotiated Host navigation only. |
| Cursor ACP controlled session | ACP session stream, permissions, questions, plans/todos and terminal status. | ACP request responses and cancellation for Agent Island-started sessions only. | EOF/error/child exit is transport degradation, never completion. |

## Conformance requirements

An Agent Adapter is not first-class until automated contract fixtures prove:

- version negotiation, unknown minor fields, incompatible majors, and Product
  upgrade reprobe behavior;
- native-identity preservation, duplicate/out-of-order events, explicit gaps,
  malformed/oversized input, and reconnect without invented lifecycle facts;
- independent capability variants and scopes, including observation-only and
  rich-control modes for one Product;
- successful, stale, mismatched, expired, duplicate, killed, disconnected, and
  indeterminate action paths with no cross-session routing;
- configuration drift, external edits, lossy syntax, policy precedence,
  custom/symlinked paths, and exact-entry uninstall;
- health-vector derivation without equating enabled/configured/connected with
  delivery or action readiness;
- global and scoped kill switches plus non-automatic circuit-breaker recovery;
  and
- diagnostic output free of Interaction Content, credentials, raw external
  identifiers, full paths, and unrelated configuration.

Parity acceptance records cite the exact negotiation snapshot and capability
evidence used in each Product × Host scenario. An unavailable or unsafe
capability is an explicit inapplicability/deviation input, never a silent pass.

