# 02 — Persist and reopen one protected Agent Session

## What to build

Make the first Agent Session durable and safely recoverable. A committed source-proven Agent Session and its immutable fact evidence must survive application restart, reopen through the protected local canonical store, and reappear from a deterministic projection without restoring unsafe live authority or fabricating current Product truth.

The slice proves the protected-store feasibility boundary for this first real record: encrypted local storage, per-installation Keychain material, atomic fact/projection durability, integrity-aware reopen, and fail-closed recovery. It retains local evidence, not a Product transcript or a cloud backup.

## Context and constraints

- The sole canonical store is local, single-writer, encrypted SQLCipher SQLite protected by a per-installation Keychain-held key. UI, Adapter, helper, and Host code never receive its key or database handle.
- Canonical facts and identity/provenance evidence are durable; cards, queues, working-set placement, and search views are replaceable deterministic projections.
- On restart/wake, retain durable facts and local drafts/history but expire all Action Leases, invalidate all persisted Host locators, and mark formerly live current work unresolved until documented reconciliation proves otherwise.
- Missing key material, corrupt ciphertext, bad integrity state, or migration failure must fail closed. Preserve verifiable protected bytes and give a person-led recovery/purge choice; never reset silently or infer completion.
- Do not add timer/idle data deletion. Session History is an Archive tier, not lifecycle completion or Product deletion.

## Acceptance criteria

- [ ] A valid fact and the information required to reproduce its projection are committed atomically, so a crash between intake and presentation cannot create a ghost card, partial identity, or duplicate fact after reopen.
- [ ] After a clean restart, the app opens the protected store using per-installation Keychain material, verifies integrity, rebuilds or validates the projection, and renders the same Product-native Agent Session without creating a replacement from display metadata.
- [ ] A restart of previously active work retains the session and immutable evidence but presents current execution as unresolved/degraded until a later documented source observation proves a state; it does not restore a live lease, callback token, or exact Host locator.
- [ ] Reopen preserves classification boundaries: selected durable local content remains protected, while redacted diagnostics and ordinary presentation never expose credentials, raw callback material, or unrestricted Product data.
- [ ] A missing key, corrupt ciphertext/integrity failure, invalid projection snapshot, and interrupted migration each prevent normal authoritative reopen, preserve protected evidence for recovery, and surface a redacted, actionable unavailable/recovery state rather than silently deleting or recreating data.
- [ ] The app can deterministically rebuild the visible record from verified facts when a projection snapshot is unusable; the snapshot never overrides canonical evidence.
- [ ] The implementation does not add any remote copy, telemetry export, unencrypted fallback store, or automatic Agent Session cleanup.

## Required evidence

- Restart capture showing encrypted-store creation, durable fact commit, termination, reopen, integrity check, deterministic projection reconstruction, and the same native identity on screen.
- Fault-injection traces for crash-between-intake-and-presentation, missing Keychain material, corrupt ciphertext, corrupt projection, and interrupted migration, with redacted diagnostics and fail-closed outcome.
- A test trace confirming all volatile Action Leases and Host locators are invalid after restart while durable session evidence remains inspectable.
- Storage-boundary review confirming one writer, no store/key access from UI/Adapter/Host code, and no egress.

## Blocked by

- 01 — First production Agent Session through native app shell
