# Canonical event and Agent Session lifecycle

**Decision date:** 2026-07-18  
**Scope:** canonical local facts and derived lifecycle state for Agent Sessions,
Turns, and Subagent Runs. Attention Request state and action dispatch remain
specified by their dedicated downstream contract.

## Decision

Agent Island retains a validated, immutable sequence of **accepted normalized
event facts** and derives a replaceable current projection from those facts.
The fact sequence is audit and recovery evidence; the projection is the only
place where a card becomes `working`, `needsAttention`, `completed`,
`stopped`, `failed`, or `unresolved`. Neither receipt order, a Host's lifetime,
nor a lost transport creates a Product lifecycle fact.

An Agent Adapter may report only the evidence its negotiated capability and
documented Product surface supply. Absence of evidence is not a negative
event. The core therefore favors `unresolved` over a false completion and
preserves historical source facts even when a rewind or compaction changes the
current Turn lineage.

## Accepted event fact

Every accepted fact has the validated envelope required by the Normalized
Agent Adapter and Capability Contract, plus a core-assigned immutable receipt
ordinal. Its identity is, in priority order:

1. `(Product namespace, stable source-event ID)` when the Product supplies an
   event ID; or
2. `(integration instance, Adapter weak-deduplication key)` only when the
   Adapter declares that no stable event ID exists.

The second form is explicitly weaker: it may suppress an exact documented
replay of the same delivery, but never proves two independently observed
Product events are one event. Its construction and retention window are
Adapter-versioned diagnostic evidence. It includes the named owner IDs,
Product event kind, documented source cursor or occurrence time when present,
and a classification-safe payload digest; it must not use Interaction Content
similarity. A weak-key collision is retained as an ambiguity/gap fact rather
than silently discarded.

Accepted facts retain their original negotiation snapshot, integration mode,
source kind/variant, Product occurrence time, local receipt time, source
cursor/sequence/revision evidence, continuity evidence, and payload
classification. Later reconciliation or capability changes add facts; they do
not rewrite an accepted fact or its provenance.

## Canonical taxonomy

The semantic family is deliberately narrower than Product event names. Each
fact has one family and a namespaced source variant. Unsupported variants are
historical, non-actionable evidence only.

| Family | Required owner and meaning | May change current lifecycle? |
| --- | --- | --- |
| `observationBoundary` | Integration instance; start, stop, reconnect, contract change, transport health, or kill-switch boundary. | Only to `unresolved`; never to terminal. |
| `reconciliation` | Integration instance and stated scope; a documented list/read/replay/probe result, cursor, or authoritative snapshot. | Yes, only within its declared authority. |
| `continuityGap` | Integration instance and affected source scope; a known sequence hole, unsupported replay, malformed rejected range, or unknown continuity. | Marks affected current truth unresolved. |
| `sessionDeclared` | One Agent Session; source has identified it or supplied authoritative session attributes. | Establishes/reconciles the record, not completion. |
| `sessionActivity` | One Agent Session and, when known, a Turn; source observed work, waiting, idle, resume, interruption, archive, or session-end evidence. | Yes, according to source-specific transition mapping. |
| `turnDeclared` | One Agent Session and Turn; creation, selection, lineage, or source revision evidence. | Establishes current/historical Turn lineage. |
| `turnActivity` | One Agent Session and Turn; start, work, wait, complete, fail, interrupt, or stop evidence. | Yes, for that Turn and its parent projection. |
| `lineageChanged` | One Agent Session and explicit old/new Turn or checkpoint relation. | Changes which Turn path is current; never deletes history. |
| `compactionObserved` | One Agent Session and, when supplied, Turn/checkpoint; Product context compaction or summary boundary. | Never terminal; current work remains current. |
| `subagentRunDeclared` | One Agent Session and Subagent Run, with named parent Turn when supplied. | Establishes the child record. |
| `subagentRunActivity` | One Agent Session and Subagent Run; start, work, wait, complete, fail, interrupt, or stop evidence. | Yes, for that child and parent projection. |
| `attentionObserved` | Agent Session plus native request identity and Turn/item when supplied. | Adds/removes the `needsAttention` overlay only; it does not complete work. |
| `sourceFault` | Source-owned session, Turn, child, or request when proven. | May produce a sourced `failed`/`stopped` outcome; transport failure cannot. |

`sessionDeclared`, `turnDeclared`, and `subagentRunDeclared` are upserts only
when their Product-native identities and ownership chain validate. Events with
missing or ambiguous owner IDs remain quarantined diagnostic evidence. They
must not create a guessed Agent Session, Turn, Subagent Run, or cross-session
association.

## Ownership invariants

- An Agent Session is keyed solely by Product namespace and native Agent
  Session ID. A Turn is keyed within that session; a Subagent Run is keyed
  within its owning session. Adapter, integration instance, Host Context,
  Worktree, model, process, title, path, and receipt time are provenance or
  attribution, never identity.
- A child association is accepted only when the Product event names the parent
  session and, if asserted, its parent Turn. A child with a proven session but
  unknown Turn remains a session child; it is never attached to the most
  recent Turn. A completion lacking the native child ID (for example an
  ambiguous concurrent Cursor Hook stop) records an unresolved completion
  observation and closes no child.
- A Turn or Subagent Run can have at most one proven owner. Conflicting owner
  claims are rejected and trip the smallest affected intake circuit breaker.
- Agent Island owns the local fact log, projections, presentation state, and
  reconciliation markers. The Agent Product owns lifecycle truth. An Adapter
  owns translation and may not promote local inference, Host state, or action
  result into a Product fact.
- A local action result such as `acceptedByProduct` is not a lifecycle event.
  Only documented synchronous proof or a later sourced event may change a
  lifecycle projection.

## Ordering, idempotency, and conflict rules

There is no fabricated global Product order. The receipt ordinal gives a
stable local audit order only. Source cursors compare facts only within the
same documented Product stream and epoch/revision; Product occurrence times
are display/diagnostic attributes, never a tie-breaker for source truth.

1. Validate identity, ownership, negotiation compatibility, classification,
   size, and event shape before appending a fact. Reject invalid input without
   mutating lifecycle state.
2. A duplicate stable event ID is idempotent: retain one accepted fact and
   record duplicate-delivery telemetry without rerunning its reducer.
3. Apply facts deterministically by their source stream cursor when comparable;
   otherwise by receipt ordinal while preserving their incomparable status.
   A late fact stays historical. It can enrich history, but cannot overwrite a
   newer authoritative current projection merely because its local receipt was
   later.
4. A higher source revision or explicit source correction supersedes a prior
   projection field only inside the same named entity and stream. Preserve the
   superseded value and source fact. Conflicting incomparable terminal facts
   produce `unresolved` with both facts visible to diagnostics, not a chosen
   winner.
5. A sequence discontinuity, replay boundary without documented replay
   semantics, integration switch, or source reset appends `continuityGap`.
   Subsequent fresh source evidence can establish new current state, but cannot
   retrospectively claim the missing interval.

The reducer keeps an **authority frontier** for each field: the source stream,
epoch/revision, cursor when available, and fact identity that last proved it.
This prevents an old `turn/started` delivered after `turn/completed` from
reactivating work, while allowing a documented higher-revision correction to
do so.

## Lifecycle projections

The visible lifecycle is a tuple, not one overloaded source status:

| Projection dimension | Values | Rule |
| --- | --- | --- |
| `execution` | `working`, `waiting`, `terminalCompleted`, `terminalFailed`, `terminalStopped`, `unresolved` | Derived only from current source evidence for the selected Turn lineage and proven children. `waiting` means the Product has explicitly reported waiting/idle; it is not inferred from silence. |
| `attention` | `none`, `pending`, `unresolved` | A derived overlay from durable native request evidence. It does not alter `execution`. |
| `observation` | `fresh`, `degraded`, `gap`, `unavailable` | Derived from Adapter health/boundaries and continuity evidence. It never asserts Product completion. |
| `lineage` | `current`, `historical`, `ambiguous` | Selects Product-proven current Turn path; historical facts remain retained. |

Presentation derives from the tuple in this priority order: `needsAttention`
when attention is pending; `unresolved` when execution is unresolved or
observation is gap/unavailable and current truth matters; `working` for
working or waiting execution; then `failed`, `stopped`, and `completed` for
fresh, terminal execution. The UI preserves a Product-specific interruption
term when one is supplied; otherwise `stopped` is neutral. `inactive` is only
a presentation/working-set classification for a terminal session with no
pending attention and no known active/waiting Subagent Run; it is not a source
lifecycle state.

An Agent Session remains non-terminal while any proven current Turn is
working/waiting, a pending Attention Request exists, or a Subagent Run is
working/waiting. A parent `Stop`/turn completion with documented background
work therefore leaves the session active. A terminal child never completes its
parent; only parent source evidence can do that. If child status is unknown
after a gap, it prevents a confident terminal parent projection and makes the
parent unresolved.

### State transitions

`unresolved` is the safe initial/recovery state for a retained record until
fresh evidence proves another execution state. The allowed transition rules
are:

| From | Evidence | To |
| --- | --- | --- |
| any | named current Turn/session/subagent start or activity | `working` |
| `working` | explicit Product waiting/idle state, with no contrary active child | `waiting` |
| `working` or `waiting` | named current Turn/session completion proof, all known current children terminal, and no pending attention | `terminalCompleted` |
| `working` or `waiting` | named Product failure proof | `terminalFailed` |
| `working` or `waiting` | named Product interruption/abort/cancel/stop proof | `terminalStopped` |
| any nonterminal or terminal | gap, Adapter restart/reconnect without reconciliation, conflicting incomparable facts, or loss of a required owner relationship | `unresolved` |
| `unresolved` | later named, authoritative source evidence | the evidenced state only |

An explicit current-lineage selection applies its rule before reducing Turn
activity. A terminal event for a historical Turn remains historical and may
not alter the selected current path. Product capabilities decide which
source-event variants satisfy each transition; an Adapter must not map a
generic EOF, process exit, hook return, window closure, session cleanup, tool
finish, notification, or action request acceptance to completion.

## Rewind, compaction, restart, sleep, and closure

**Rewind/fork/retry.** An explicit Product lineage event changes the selected
Turn path in the same Agent Session. It marks displaced Turns and their facts
historical, records the parent/selected/replaced native IDs, and does not
reuse a Turn or Subagent Run ID. A fork that receives a different native Agent
Session ID is a different Agent Session, linked only as sourced lineage
metadata. Late events for a displaced Turn never change the new current state.

**Compaction.** A Product compaction, summary checkpoint, or context-window
reset is `compactionObserved`. It may update sourced context attribution and
the current-lineage checkpoint but creates neither a new Agent Session nor a
completion. Pre-compaction Turns remain historical; a Product-created post-
compaction Turn must carry its own native ID.

**Agent Island restart or Mac sleep.** Persist facts, authority frontiers,
deduplication records, and projections before acknowledging presentation. On
launch/wake, retain every previously active session but set its live
observation to degraded/unavailable and its execution to `unresolved` unless a
documented durable reconciliation result re-establishes current truth. Expire
all local action leases; a durable Attention Request remains as history but
its routing becomes stale/unavailable until a live native request proves it
again.

**Adapter reconnect or Product update.** Append an observation boundary and
re-negotiate capabilities. Reuse source identities and cursor continuity only
when the Product documents them. A changed/unknown interface version narrows
capabilities pending reprobe. Loss of one integration mode may leave facts
from another mode observable, but their provenance and authority frontiers do
not merge without the same Product-native owner IDs and documented continuity.

**Host closure.** Host termination, terminal EOF, IDE window/tab closure,
Host Context rebinding failure, or lost navigation capability affects Host
Context/observation only. It never changes a Product lifecycle state. A
documented Product session-end or termination event may be reduced according
to that Product's mapping, but cleanup alone is not successful completion.

## Reconciliation and recovery

Reconciliation is a named source operation, never an inference pass. It may
use only a negotiated, documented Product read/list/replay/status/probe
surface. Each result records its native query/result identity, scope, snapshot
or cursor boundary, and whether that scope is exhaustive.

- Reconcile by the native identifiers already held, or create a record only
  when the returned native identity is new. Never discover continuity from
  local files, terminal scrollback, a transcript, title, path, model, or
  timestamp.
- A documented replay may backfill events and use the ordinary deduplication
  rules. A documented authoritative read may set fields it explicitly reports
  and supplies authority for. A list's absence proves neither deletion nor
  completion unless the Product documents the exact scope as exhaustive and
  declares absence semantics.
- If current state cannot be read, preserve historical facts, append a gap or
  unavailable observation boundary, retire unsafe actions, and leave current
  execution unresolved. Do not relaunch/resume a Product conversation merely
  to learn its state.
- A later source event repairs only the field and entity it proves. It does
  not erase the gap, rewrite history, or revive expired native requests.

## Required conformance fixtures

The lifecycle reducer is first-class only when fixtures demonstrate: stable
event-ID and weak-key duplicate delivery; out-of-order and equal-time events;
cursor gaps and source resets; conflicting terminal evidence; late events on a
rewound Turn; compaction without a false completion; concurrent children with
an unidentifiable child-stop; parent completion with background work; app
restart/sleep and stale action leases; reconnect with and without documented
replay; authoritative and non-exhaustive reconciliation; adapter/Host/process
closure; and preservation of Interaction Content boundaries in facts and
diagnostics.

The fixtures must prove that no path creates an identity from presentation
metadata, treats transport loss as completion, closes a child from an ambiguous
event, routes an action after a restart/reconnect without a live native lease,
or loses an active/attention-requiring Agent Session to the 30-session
presentation cap.
