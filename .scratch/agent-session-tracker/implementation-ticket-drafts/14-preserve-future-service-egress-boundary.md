# 14 — Preserve the future Service Egress boundary

## What to build

Make the absence of network services a tested product capability while preserving one typed future Service Egress seam. Agent Island continues to monitor, persist local facts, present Attention Requests, and perform Jump Back when every service implementation is absent or fails. A future implementation can receive only a classified, versioned, purpose-consented outbound copy; it can never become canonical state or send Product, Host, configuration, or presentation commands inward.

## Context and constraints

The local encrypted canonical store is the sole source of truth. Interaction Content is sensitive by default; unknown Adapter fields remain Interaction Content. Baseline scope excludes accounts, cloud sync, hosted storage, telemetry, analytics, automatic diagnostic upload, remote access, network listeners, and network identity.

This ticket creates a boundary, not a hosted feature, endpoint, account, queue, retry loop, service credential, or network request. Future purposes are limited to hosted persistence, telemetry, and support diagnostic, each requiring a separate future decision for destination, authentication, retention, deletion, and failure behavior.

## Acceptance criteria

- [ ] The application runs all baseline local behavior with no Service Egress implementation attached; absent, disabled, failed, or revoked service paths cannot delay or replace a local fact commit, recovery, monitoring, attention queue, action attempt, or Jump Back.
- [ ] The only future-service interface accepts a classified, schema-versioned outbound snapshot/change set from a local outbox, with selected scope, purpose, consent version/time, and service-specific pseudonyms.
- [ ] There is no inbound service read, remote merge, migration source, lifecycle reconciliation source, action route, configuration route, presentation route, or direct store access through the boundary.
- [ ] A future consent gate is opt-in, purpose-granular, user-visible, revocable, and checked at dispatch. It records the result without retaining the sensitive payload and supports purpose-specific disable/delete.
- [ ] Classification occurs before the boundary using allowlisted projections. Interaction Content, credentials, raw local/Product identifiers, full paths, command lines, raw diagnostics, callback tokens, and unknown/unclassified extensions cannot enter telemetry or an outbound copy by default.
- [ ] Hosted-persistence payloads never use raw reusable local identity; telemetry is aggregate/redacted and allowlisted; support diagnostic remains an explicit separately redacted artifact rather than an automatic upload.
- [ ] The normal baseline exposes no endpoint, account, network identity, background retry loop, remote listener, cloud replica, analytics event, or outbound traffic.
- [ ] Egress failure or a rejected consent check yields a local redacted diagnostic and leaves local state and visible behavior unchanged; it does not retry a Product action, change a permission mode, or claim data was delivered.
- [ ] Contract tests reject attempts by helpers, Adapters, UI, or future-service implementations to receive a database/key handle, raw Adapter record, unclassified extension, or a capability to initiate non-egress actions.

## Required evidence

- Offline/absent-port and failed-port traces proving local commits, recovery, monitoring, Attention Requests, and Jump Back remain usable with no outbound request.
- Boundary contract tests seeded with Interaction Content, credentials, paths, raw IDs, tokens, locators, command lines, unknown fields, and raw diagnostics.
- Consent/revocation and purpose-isolation fixtures demonstrating only redacted local operational evidence after a blocked dispatch.
- Architecture review evidence showing the one-way boundary and no inbound merge/action capability.
- Parity-matrix records for H and applicable privacy/egress acceptance scenarios.

## Blocked by

- 02 — Persist and reopen one protected Agent Session
- 07 — Negotiate Adapter capabilities and expose honest integration health
- 13 — Implement redacted diagnostics, local export, and scoped maintenance
