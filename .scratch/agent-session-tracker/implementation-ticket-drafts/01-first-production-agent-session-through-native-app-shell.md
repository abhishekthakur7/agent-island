# 01 — First production Agent Session through native app shell

## What to build

Deliver the smallest end-to-end Agent Island slice: a local macOS application can accept one validated, source-proven Agent Session observation from a controllable first-party Adapter fixture, commit it as a Normalized Event Fact, derive a revisioned read model, and show its Product-native identity and sourced status in a native application surface. The slice establishes the AppKit-first shell, SwiftUI-hosted presentation content, typed inward ports, and one-way fact-to-screen flow without treating presentation metadata as identity.

This is deliberately an observation-only vertical slice. It must not claim live Product control, configuration ownership, host navigation, cloud connectivity, or action routing. It creates the production-shaped seam on which later Product modes can land, while keeping all baseline data local.

## Context and constraints

- Agent Session identity is the Product namespace plus stable Product-native identifier only. A title, prompt, path, worktree, model, Host Context, local record ID, or timestamp can enrich display but cannot create or merge identity.
- The application is AppKit-first on supported macOS, with SwiftUI used only for hosted presentation content. The main/UI actor receives immutable revisioned projections; it must not decide Product truth.
- An Adapter or fixture enters through typed ports. It cannot hold the canonical-store/key handle, mutate a card directly, or bypass validation/classification.
- Validate contract/version compatibility, source and owner identity, payload size/shape, capability provenance, and classification before a fact is accepted. Invalid or ambiguous input must produce redacted diagnostic evidence and no card.
- Commit an accepted immutable fact before publishing its projection. Unknown Interaction Content remains protected local content; no telemetry, remote listener, account, or Service Egress is introduced.
- Preserve Agent Island’s original identity and terminology; do not copy baseline product assets, wording, sounds, or visual arrangement.

## Acceptance criteria

- [ ] A controllable, faithful first-party Adapter fixture can negotiate an explicitly compatible observation capability and deliver one source-proven session declaration/activity observation through the same typed intake boundary intended for real integrations.
- [ ] The app validates the envelope before accepting it, including Product namespace, stable native session ID, Adapter/integration provenance, negotiation snapshot, event identity or declared weak deduplication evidence, classification, and supported event shape.
- [ ] A valid observation is atomically committed as an immutable Normalized Event Fact before a derived projection becomes visible; the visible read model is tagged with the committed ledger revision.
- [ ] The native application shell renders one Agent Session from the projection, visibly distinguishing sourced Product/Host/status metadata from identity and omitting unavailable metadata rather than inventing it.
- [ ] Repeated delivery of a stable source-event ID does not create a second fact or card; an input with missing/ambiguous owner identity, incompatible contract major, malformed shape, or excessive size produces no Agent Session and no lifecycle claim.
- [ ] The UI cannot call an Adapter/Product client or canonical store directly, and fixture transport loss/exit cannot mark the Agent Session completed, stopped, or failed.
- [ ] The slice operates with all external-service ports absent and does not emit Interaction Content, credentials, raw identifiers, paths, or payloads into diagnostics or presentation outside the protected view.

## Required evidence

- A recorded positive fixture trace from negotiation through validated fact commit, projection revision, and visible native rendering, with redacted diagnostic correlation.
- Negative captures for duplicate stable delivery, invalid/ambiguous ownership, incompatible contract, and transport loss; each demonstrates no duplicate card and no invented lifecycle change.
- An architecture-boundary review showing AppKit shell/SwiftUI hosted content, typed port entry, immutable projection publication, and no direct UI/store/Adapter shortcuts.
- A short local privacy check showing no network egress and no Interaction Content in the diagnostic capture.

## Blocked by

None — can start immediately.
