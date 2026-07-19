# 20 — Implement Codex app-server observation and control

## What to build

Deliver the version-pinned direct Codex app-server Agent Adapter mode for Codex Threads Agent Island starts or explicitly resumes through that connection. The person can monitor native Thread/Turn/item state and protected activity, handle only live typed approval/question capabilities, submit documented Turn controls, and see truthful result/degradation states. Independently launched Codex terminal work remains Hooks-only; no mode is silently upgraded or merged.

## Context and constraints

Direct mode uses the documented local app-server protocol over the default child-process standard-input/output transport. During setup and after each CLI update, record the executable version and regenerate/validate the version-specific schema; initialize then initialized is mandatory. Only documented generated-schema methods and negotiated capabilities are used. Experimental fields/methods, experimental API opt-in, WebSocket transport, and private Codex state are not baseline control paths.

Thread ID, Turn ID, item ID, outstanding server-request identity, and opaque approval ID where supplied form exact native ownership. A live request-scoped Action Lease is valid only while the connection and capability remain live. Disconnect, reconnect, restart, wake, source change, schema/capability change, or request resolution retires routes; local state never recreates authority.

## Acceptance criteria

- [ ] Setup detects the local Codex executable, records compatible version/schema/negotiation evidence, starts the documented local standard-input/output connection, completes initialize/initialized once, and exposes each negotiated observation/action capability with maturity and constraints.
- [ ] Unknown/incompatible version, failed schema generation, duplicate/failed initialization, unavailable required stable method, oversized/malformed protocol input, or unsupported major contract disables only the affected mode/capability with an inspectable reason; it never falls back to private files, terminal injection, or an experimental claim.
- [ ] Native Thread/Turn/item notifications and documented read/list/reconciliation create immutable facts using exact native identity. Reconnect reconciles by native ID through documented protocol reads/lists; missing/gapped/non-exhaustive evidence remains unresolved and never merges by title, cwd, model, or Host pane.
- [ ] Direct-mode presentation renders only protected data received on the active connection. Diffs, tool output, agent messages, and progress remain Interaction Content/activity rather than completion proof; token/context/usage display is source-proven, optional, and unavailable rather than estimated.
- [ ] Command, file-change, and permissions approval server requests create one durable Attention Request per exact outstanding JSON-RPC/native owner tuple. A response routes only through that live request identity and supplied native IDs, never by a guessed session or stale callback.
- [ ] Structured/multi-question UI appears only if the generated schema and negotiated capability support it. Otherwise prose remains content and any later input uses an explicitly documented scoped Turn action; choice IDs are never invented.
- [ ] Completed plan state may be displayed from documented plan updates. There is no fictional plan accept/reject control; any documented review comment is typed scoped Turn input/steer and must not masquerade as plan approval.
- [ ] Turn start/steer/interrupt, thread resume/fork/archive controls are offered only for an explicitly selected directly connected Thread and separately negotiated capability. An accepted interruption is not completion; only later lifecycle evidence can prove work stopped.
- [ ] Before every action, core and Adapter revalidate exact owner/current lineage, request state/fingerprint, negotiated capability/scope, response schema, deadline, live one-use lease, and required confirmation. Reservation creates one durable Action Attempt; dispatch occurs at most once and result is truthfully rejected, accepted-by-Product, applied, superseded, or indeterminate.
- [ ] Disconnect invalidates every outstanding response route. Reconnect does not replay a response or recreate a lease; only newly documented live request evidence for the same authoritative tuple can make routing available again.
- [ ] Subagent activity lacking a separately documented stable app-server child identity remains capability-limited activity. It is not assigned a stable Subagent Run identity, individual control, or inferred parent/child continuity from private rollout data.
- [ ] The mode remains distinct from Codex Hooks: observed terminal sessions cannot gain app-server action authority merely because labels/working directories look alike, and direct Threads do not rely on Hooks or terminal input as a fallback.

## Required evidence

- Version/schema/initialize negotiation captures, including update reprobe, incompatible schema, malformed message, and failed-handshake degradation.
- Faithful/live Thread/Turn/item streams covering start/activity/completion, reconnect/gap reconciliation, approval requests, structured-question capability present/absent, plan update, usage present/absent, and subagent limitation.
- Typed-action traces for approval, supported Turn input/steer, interrupt, and thread control, with cross-owner/stale/disconnect/double-submit/indeterminate zero-or-one dispatch proof.
- Mode-separation fixtures proving independently launched Hooks sessions cannot receive app-server control and no private-state or terminal-input fallback occurs.
- Parity-matrix evidence for applicable D-mode S1–S6, A1–A7, N5, and degradation/fallback cells.

## Blocked by

- 04 — Deliver the Horizon session-monitoring experience
- 07 — Negotiate Adapter capabilities and expose honest integration health
- 08 — Manage Integration Installations without owning external configuration
- 09 — Handle Attention Requests through the Guided workflow
