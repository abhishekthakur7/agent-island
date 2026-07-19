# 07 — Negotiate Adapter capabilities and expose honest integration health

## What to build

Make Agent Adapter support explicit, versioned, and inspectable. For a first real integration mode, implement read-only discovery, immutable Negotiation Snapshots, capability records, independently scoped observation/action/configuration/navigation gates, and a truthful health vector surfaced through Atlas. The person must see what this Integration Installation can currently do and why it is degraded, without assuming capability from Product name, an enabled preference, or a prior version.

The slice establishes the reusable contract for Claude Code, Codex CLI direct/hooks, and Cursor Hooks/ACP modes; it does not yet mutate Product configuration or expose unsupported actions as if they existed.

## Context and constraints

- A capability carries semantic ID/revision, scope, direction, availability, maturity, constraints, provenance, freshness, and safe fallback. Observation never implies action; Host navigation is independently negotiated.
- Contract major incompatibility accepts no events/actions/configuration mutation. Product/interface change triggers fresh read-only reprobe and capability-local narrowing, not optimistic compatibility.
- Discovery is side-effect free and uses documented/selectable surfaces only—no arbitrary home-directory scan, private transcripts, terminal scrollback, or competing resume process.
- Health dimensions include intent, exact ownership/configured state, load/policy, reachability, delivery freshness/gaps, action readiness, and Host-navigation readiness. Healthy needs enabled intent, manifest-proven loaded configuration, and verified delivery.
- All negotiation/health evidence is local, immutable/provenance-bearing where required, and redacted in diagnostics.

## Acceptance criteria

- [ ] Read-only discovery returns zero or more explicitly selectable integration candidates with Product/version evidence, available modes, compatibility/probe state, setup evidence, required permissions, and a non-mutating probe plan; discovery itself changes no configuration or enabled intent.
- [ ] Activating a supported test integration creates an immutable Negotiation Snapshot that records contract/catalog revision, Adapter/Product/interface versions, mode, probe evidence/time, resulting capabilities, and health dimensions.
- [ ] The effective capability model separately represents observe, act, configure, and navigate directions and preserves Product-specific semantics/constraints; it cannot reduce them to a generic interactive/support boolean.
- [ ] Unknown/incompatible contract major refuses events, actions, and configuration writes. Unknown or changed Product/interface evidence triggers reprobe and narrows only unproven capabilities while preserving independently safe observation where applicable.
- [ ] Ingestion accepts only facts whose current integration/mode/capability provenance validates. An unavailable or stale action capability never receives a fabricated alternative; the UI explains the unavailable reason and safe fallback.
- [ ] Atlas displays enabled intent separately from Disabled, Setup required, Healthy, Degraded, Unavailable, and Incompatible summaries, with evidence time, affected capability, and a non-destructive next step.
- [ ] Per-installation observation, action, and configuration kill switches fail closed and narrow the affected capability without altering Product lifecycle or silently removing configuration.

## Required evidence

- Negotiation/probe captures for compatible, unknown/changed interface, and incompatible-major fixtures, including snapshot/provenance and resulting capability/health presentation.
- Contract tests for malformed/oversized/cross-owner input, unknown minor fields/variants, version change, permission loss, kill-switch closure, and capability-local degradation.
- Atlas capture demonstrating intent and all compact health summaries are separate from detection/configuration/delivery/action readiness.
- Redacted diagnostic sample showing a health/capability failure without Interaction Content, credentials, full paths, raw callback tokens, or raw external IDs.

## Blocked by

- 03 — Derive conservative Agent Session lifecycle from immutable facts
- 06 — Deliver resumable onboarding and the Atlas Settings shell
