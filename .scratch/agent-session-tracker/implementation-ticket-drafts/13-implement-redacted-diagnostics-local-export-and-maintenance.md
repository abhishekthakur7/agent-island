# 13 — Implement redacted diagnostics, local export, and scoped maintenance

## What to build

Let a person inspect integration and capability problems, create a safe redacted Diagnostic Bundle, export selected verified local data, and perform clearly scoped maintenance. Each outcome is a local, explicit, reviewable operation: diagnostics explain without exposing Interaction Content; user-data export can include selected content only after extra confirmation; maintenance keeps preferences, setup, local data, and complete cleanup separate.

## Context and constraints

Diagnostics are Operational Metadata only. They may identify component/owner-or-capability scope, timestamp, allowlisted reason, correlation ID, health condition, and safe recovery step. They must never contain Interaction Content, credentials, raw callback tokens, raw external identifiers, titles, full paths, raw command lines, Host locators, or copied export contents. Redaction is structural: allowlisted typed projections enter diagnostics; pattern scanning is defense in depth.

User-data export and Diagnostic Bundle are different foreground local file operations. The local canonical store remains authoritative. Every consequential maintenance operation requires scope preview and confirmation; manifest-proven removal is the only setup mutation scope and never conveys ownership of an entire external configuration file.

## Acceptance criteria

- [ ] Accepted, filtered, deduplicated, quarantined, downgraded, rejected, unavailable, degraded, and failed operations retain redacted diagnostic evidence sufficient to identify the affected capability/owner scope, time, reason, correlation, and safe next step.
- [ ] Diagnostics distinguish enabled intent, configuration load, interface compatibility, permissions, transport, event freshness, action readiness, and Host navigation; a summary state never overclaims Healthy or an exact fallback.
- [ ] Diagnostic Bundle generation is person-initiated and produces redacted human-readable and machine-readable local artifacts only. It is not an upload, remote support channel, hidden backup, or generic raw-event export.
- [ ] Seeded prompts, response/plan text, commands, tool data, paths, titles, model/project/worktree labels, credentials, identifiers, callback tokens, locators, and secret-like strings are absent from diagnostic records and bundles.
- [ ] A user-data export requires a destination and preview of selected sessions/date scope, data classes, schema/format, and whether Interaction Content is included. It writes only selected verified local records and an integrity manifest.
- [ ] Including Interaction Content requires a separate explicit confirmation; credentials, Action Leases, callback tokens, raw Product configuration, unselected sessions, and hidden duplicate copies are always excluded.
- [ ] Neither export is opened, uploaded, network-sent, or retained as a hidden second local copy. A Diagnostic Bundle does not include user-data-export content or export destination.
- [ ] Maintenance presents separate, directly labelled flows for resetting presentation preferences, deleting selected diagnostics/preferences/generated schema/cache/manifests, removing manifest-proven setup, deleting selected inactive Session History, deleting active local history, and complete cleanup.
- [ ] Every maintenance flow shows exact local categories and external-manifest scope before confirmation, changes only its selected category, reports residual/ambiguous external entries honestly, and never treats setup removal as Product/session deletion.
- [ ] Store/key/schema/ciphertext/migration failure exposes the affected category, preserves verifiable protected bytes, offers redacted diagnostics and verified selected export where possible, and never silently resets, auto-exports, uploads, or claims Product repair.
- [ ] Keyboard, VoiceOver, increased text, contrast/reduced-transparency, and reduced-motion use expose ordinary, warning, and destructive maintenance actions with visible labels and no color-only distinction.

## Required evidence

- Seeded-data redaction tests for Diagnostic Bundles, logs, notification-adjacent diagnostics, user-data exports, and maintenance previews.
- Local export captures proving scope/confirmation differentiation and absence of egress, hidden copies, unselected content, credentials, and volatile authority.
- Maintenance scope-confirmation and negative mutation traces covering manifest drift, ambiguous ownership, integrity failure, selected history deletion, and complete-cleanup residuals.
- Accessibility traversal and VoiceOver capture for Diagnostics and Maintenance.
- Parity-matrix records for O7, O8, S5, and H with correlation to the relevant degradation fixtures.

## Blocked by

- 02 — Persist and reopen one protected Agent Session
- 06 — Deliver resumable onboarding and the Atlas Settings shell
- 07 — Negotiate Adapter capabilities and expose honest integration health
- 08 — Manage Integration Installations without owning external configuration
- 12 — Implement protected Session History
