# 27 — Display sourced Usage Snapshots

**Status:** ready-for-agent

## What to build

Add a display-only Usage Snapshot to the expanded Island header and Usage settings when a live Agent Adapter exposes a negotiated `usageObservation` Capability. The person can turn visibility on/off, choose used versus remaining, select a preferred provider, or follow the currently selected active Agent Session’s provider; every displayed value remains sourced, timed, and honest about reset, staleness, or absence.

## Context and constraints

Usage is not billing state, an estimate, identity, ordering signal, notification trigger, or health substitute. Cursor Hooks, Cursor ACP, and other unsupported modes must remain unavailable unless a future negotiated capability proves otherwise; never fabricate a token/remaining/reset value. A reversible Claude Status Line bridge may be enabled only as an explicit Integration Installation that preserves the person's existing visible output and exact-entry ownership; it has no implied counterpart for other products.

## Acceptance criteria

- [ ] The Usage settings and expanded header are available only when a live `usageObservation` Capability supplies a compatible sourced snapshot for the selected adapter mode; an older observation remains visibly stale rather than disappearing or being refreshed by estimate.
- [ ] An eligible snapshot identifies its provider, observation time, reset information when supplied, and whether it is fresh, stale, missing, disabled, or unavailable; absent fields stay absent rather than estimated.
- [ ] The person can reversibly configure visibility, used-versus-remaining presentation, preferred provider, and following of the selected active Agent Session provider without changing session identity, ordering, queue state, filtering, actions, or notifications.
- [ ] Provider following changes only the displayed eligible source; a selected session without an eligible provider produces an explicit unavailable/absent state rather than a substitute estimate.
- [ ] Cursor Hook and ACP usage is explicitly unavailable under the current capability profile and does not expose a placeholder figure or inferred source.
- [ ] Where a Claude Status Line bridge is supported, it is a separately enabled/reversible Integration Installation with a fresh ownership plan, exact-entry verification, existing-output preservation, and clean disconnect/revert behavior.
- [ ] Missing/stale/disabled/reverted capability or bridge evidence leaves monitoring, the Attention Request queue, and Jump Back unchanged and produces inspectable degraded/unavailable state.
- [ ] Usage values and related diagnostics remain local and bounded; no telemetry, cloud relay, secret export, or macOS notification payload is introduced.

## Required evidence

- [ ] A live or faithful Claude/direct-Codex capability fixture demonstrates fresh usage, stale usage, missing reset data, provider selection, and selected-session following in the header and Usage settings.
- [ ] A Cursor Hook/ACP fixture demonstrates explicit unavailable usage with no estimated value.
- [ ] Status Line bridge plan/apply/verify/revert evidence proves exact ownership, output preservation, clean disconnect, and no unrelated configuration mutation.
- [ ] Regression evidence shows usage changes do not alter monitoring, filtering, notifications, queues, actions, or Jump Back.

## Blocked by

- #06 — Deliver resumable onboarding and the Atlas Settings shell
- #11 — Coordinate reveals, notifications, sounds, filters, and quiet policy
- #17 — Observe Claude Code sessions through a managed Integration Installation
- #20 — Monitor and control direct Codex app-server sessions
