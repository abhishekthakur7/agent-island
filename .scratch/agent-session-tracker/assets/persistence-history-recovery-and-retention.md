# Persistence, history, recovery, and retention

**Decision date:** 2026-07-18  
**Scope:** local persistence for the personal, single-user Agent Island baseline. This defines information lifetime and recovery requirements, not a database engine or a production implementation.

## Decision

Agent Island has one protected, local **canonical store**. It retains the validated normalized facts that Agent Island owns, their identity/provenance evidence, and selected Adapter-supplied Interaction Content. Current cards, queues, and working-set placement are deterministic, replaceable projections of that store. A restart therefore restores evidence and local presentation, but never restores Product truth, live locators, or authority to act.

The 30-session limit is solely a compact presentation working set. When it is exceeded, the oldest safely inactive Agent Session moves to Session History; its canonical evidence remains local. An active, waiting, unresolved, or attention-requiring Agent Session, or one with a known active/waiting Subagent Run, is never moved out merely to meet the limit. If no safely inactive session exists, the working set exceeds 30. There is no age-, launch-, or storage-timer deletion of Agent Session data. History remains until the person uses a separately confirmed local-data deletion action.

An **Archive** is a compact Session History presentation and storage tier, not a terminal lifecycle state, a claim that the Agent Product deleted a session, or a lossy transcript conversion. This implements the approved working-set and cleanup defaults while preserving the immutable-fact and local-first boundaries in the linked decisions.

## Local record classes

The logical store must make each class independently classifiable, encrypted, versioned, and removable only through the allowed lifecycle action.

| Class | Canonical / derived | Restart rule | Retention and rule |
| --- | --- | --- | --- |
| Accepted normalized event facts, identity/ownership tuples, source ordering, authority frontiers, deduplication evidence, gaps, and reconciliation evidence | Canonical | Yes | Immutable logical history, retained with its Agent Session. Do not retain raw Product event streams or privately discovered Product transcripts. |
| Agent Session, Turn, Subagent Run, and sourced lineage records | Canonical identity plus derived lifecycle | Yes | Retain historical and rewound Turns in the same Agent Session. Rebuild lifecycle from facts when necessary. |
| Current lifecycle, queue, working-set, archive, and search/index projections | Derived | A snapshot may survive for fast launch; it is always rebuildable | A snapshot never overrides accepted facts. It may be regenerated after a crash, migration, or integrity failure. |
| Attention Request ownership/state, local acknowledgement, drafts, and submitted-payload/Action Attempt evidence | Canonical local records plus derived routing state | Durable request/history and drafts: yes | Retain with the owning session. Drafts are Interaction Content. Live Action Leases, callback handles, and native response tokens are volatile. |
| Host Context associations, locator provenance, incarnations, invalidation reasons, and navigation attempts | Canonical local evidence | Yes | Preserve historical association evidence, but every locator is unvalidated after launch/wake. |
| Integration Installation intent, Ownership Manifest, health/capability observations, application-owned schema/cache state, and preferences | Canonical local configuration | Yes | Keep separate from Agent Session history so disablement, setup removal, data deletion, and complete cleanup remain distinct. |
| Diagnostics | Local diagnostic evidence / user-owned export artifact | Local records: yes | Redacted by construction. An export is not a hidden managed backup or a general data-export API. |
| Future-service consent/outbox records | Not a baseline feature | N/A | The absent service port is normal. A future copy is never canonical and cannot block local state. |

Credentials, secrets, raw native callback tokens, arbitrary Product state files, terminal scrollback, and unclassified fields are not a persistence class. Credentials and tokens are never stored in these records; an unknown Adapter field is Interaction Content until classified.

## Commit, encryption, and transcript rules

Before Agent Island acknowledges accepted observation to its presentation, one atomic durable commit must include the validated fact, required identity and provenance evidence, deduplication/authority-frontier change, and either the new projection or enough information to deterministically rebuild it. A crash must expose either the last complete commit or no commit, never a half-created Agent Session, duplicate accepted fact, or projection that lacks its fact.

Facts are logically append-only. Corrections, reconciliation, source revisions, gaps, replay boundaries, deletion markers, and migration evidence are additional records; they do not rewrite the source fact they qualify. Physical compaction, encryption rewrapping, indexing, and snapshot replacement are permitted only when they preserve the logical identity, receipt order, classification, and provenance needed to reproduce the same conservative result.

All persisted baseline data remains application-private and encrypted at rest with a per-installation key in the macOS Keychain. File permissions and FileVault complement but do not replace that protection. Storage validation must authenticate ciphertext and verify record/schema integrity before a record contributes to a projection. The physical engine remains for the application-architecture decision, but it must provide atomic commit, crash consistency, authenticated encryption, ordered reads, and verified migration.

Agent Island does not create a generic raw Product-transcript archive. It may retain only Interaction Content supplied through a supported Agent Adapter and needed for the in-scope session, request, completion, or history experience. That content remains owned by its Agent Session/Turn/request and its original classification. Product compaction or a received Product summary is sourced evidence; it neither authorizes reading private Product history nor deletes previously received historical evidence.

## History, archive, and cleanup

An Agent Session enters Session History only when it is safely inactive: terminal by current Product evidence, no pending Attention Request, and no known active/waiting Subagent Run. Unresolved is not safely inactive. History ordering uses Product-sourced creation time when available, with local first-observed time as the explicit fallback. Archiving changes neither Product lifecycle nor monitoring eligibility, and a later authoritative event can return the session to the working set.

For working-set overflow, choose the oldest safely inactive session first. If it becomes active or needs attention during the transition, abort the move or return it to the working set; do not discard its state. An inactive session's recap and inspectable historical facts remain available in History without consuming compact-island space.

The following actions are deliberately separate and each requires a clear scope preview and consequential confirmation:

| Action | Effect | Must not do |
| --- | --- | --- |
| Move to History | Changes local presentation/storage tier for a safely inactive session. | Delete facts, drafts, requests, diagnostics, or Product data. |
| Delete selected Session History | Permanently removes the selected inactive Agent Session's local facts, received content, dependent Attention Request/draft/Action Attempt records, and local Host association evidence. | Send a Product action, delete a Product transcript/session, alter setup, or silently delete another session. |
| Stop monitoring and delete active local history | A separately named stronger action: first stops the selected local observation scope, then removes selected active-session local records. | Pretend the Product stopped, use a stale action route, or allow old replay to recreate deleted history without fresh documented source evidence. |
| Delete diagnostics, preferences, generated schema/cache, or manifests | Removes only the independently selected local category. | Imply that Integration Installation setup or Product data was removed. |
| Remove setup / complete cleanup | Follows the manifest-proven setup/removal decision, then offers separately confirmed local-data categories. | Delete non-owned Product configuration, credentials, sessions, or ambiguous external material. |

Deletion of historical facts creates the minimum protected, non-content deletion boundary needed to suppress an old documented replay of the same source range. It is scoped to the known Product namespace/native owner and source cursor or epoch when available. A newer authoritative Product observation may create fresh local evidence; a timer, local label, or similar text cannot. A deletion boundary is removed with the corresponding Integration Installation local-data cleanup.

No automatic retention period, idle cleanup, quota eviction, or timer may delete or conceal active work. Storage management may compact verified physical representations and show the person exact local usage, but it must ask the person to select history or diagnostic data for deletion rather than silently sacrificing evidence. This follows the approved defaults: 30 is a working set, history deletion is distinct from cleanup, and active work cannot be lost to a timer.

## Restart, wake, and reconciliation

Launch and wake follow this sequence:

1. Open and integrity-check the canonical store, Keychain key, schema, and last committed checkpoint. Load a verified projection or rebuild it from accepted facts.
2. Preserve all prior Agent Sessions and historical records. Every formerly active/waiting session becomes unresolved with degraded or unavailable observation until documented fresh Product evidence proves current state. Retain it in the working set even if this exceeds 30.
3. Preserve a durable Attention Request and unsent draft, but expire every Action Lease and make routing stale/unavailable. A request can become routable only when a live Product surface proves the same authoritative ownership tuple again.
4. Mark every persisted Host locator unvalidated. Preserve its historical association/invalidation evidence, but require a read-only documented Host probe before exact Jump Back; otherwise use only a separately proven lower fallback.
5. Append the observation/recovery boundary and reconcile only through the negotiated Product read, list, replay, status, or probe surface. Absence from a non-exhaustive result, a Host closure, helper exit, or a transport loss never completes a session, resolves a request, or recreates a lease.

A later authoritative fact repairs only the entity and field it proves. Recovery never reads private Product transcripts/state files, guesses continuity from paths/titles/timestamps, launches/resumes a Product to inspect it, or merges local records on presentation similarity.

## Schema migration and corruption recovery

The store schema and every serialized record/projection contract are internal, explicitly versioned contracts. Migrations must preserve canonical fact IDs, receipt order, classification, source provenance, deletion boundaries, and the ability to rebuild the conservative projection. A migration must:

1. preflight the source schema, available protected storage, and Keychain access without mutating the only readable copy;
2. stage a new encrypted representation, validate its integrity and a deterministic projection against the old verified facts; and
3. atomically promote the verified result, retaining only the recovery material needed to finish or roll back that migration inside protected application storage.

An unknown schema, failed validation, missing key, or interrupted migration is a visible unavailable/recovery state, never a silent reset, downgrade, or best-effort rewrite. Valid independent records may remain available. Affected sessions remain historical or unresolved, as appropriate, and no unsafe action becomes available.

On ciphertext, record, index, or projection corruption, preserve the unreadable protected bytes and record a redacted local fault. Rebuild a projection only from verified facts; never fill a hole from a title, transcript, cache, Host Context, or local Action Attempt. The recovery UI must name the affected local category, offer a redacted Diagnostic Bundle, and allow the person to export verified selected data or separately confirm purge of irrecoverable local data. It must not upload, auto-export, erase, or claim that the Agent Product's data was repaired. After a purge, fresh documented reconciliation may establish new current evidence, but the missing interval remains a continuity gap.

## Export and future-service boundary

A **user-data export** is a foreground, user-selected local file operation. Before writing it, show the destination, selected sessions/date scope, data classes, whether Interaction Content is included, and export format/schema version. Include only selected, verified local records and an integrity manifest; never include credentials, Action Leases, callback tokens, raw Product configuration, or another session's content. Interaction Content requires an additional explicit confirmation. Agent Island neither opens, uploads, nor retains a hidden second copy of the export.

A **Diagnostic Bundle** remains a separate explicit export: redacted human-readable Markdown plus machine-readable JSON, without Interaction Content, credentials, raw command lines, titles, full paths, raw external identifiers, or user-data-export contents. Failed integrity/decryption checks are reported only as redacted categories and correlation IDs.

The local canonical store remains the only baseline source of truth. Future hosted persistence or telemetry, if separately approved, consumes a classified, versioned, purpose-consented outbound snapshot/change set through the existing local outbox seam. It cannot supply a migration source, replace local recovery, merge remote state into lifecycle, bypass local deletion, or initiate Product actions. Its own retention, deletion, authentication, and conflict policy require a future decision.

## Required acceptance scenarios

- A 31st safely inactive session moves to History while all retained facts and recap remain inspectable; if all 30 are active or need attention, the working set visibly exceeds 30 and nothing is evicted.
- A late event revives an archived session only through its proven native identity; a similar title/path/transcript never does. Rewound and compacted Turns remain historical within the same Agent Session.
- A crash between intake and presentation leaves no ghost card or duplicate fact. Restart restores the last verified state, marks prior active work unresolved, preserves requests/drafts, and provides no lease-backed action.
- Host restart or a persisted locator does not make exact navigation live; revalidation or the honest fallback ladder is required.
- Missing Keychain material, corrupt ciphertext, a corrupt projection, and an interrupted migration each fail closed, retain verifiable history, produce a redacted diagnostic path, and never silently reset or infer lifecycle.
- Deleting selected inactive history removes its local Interaction Content and dependent local records only after confirmation; it does not affect Product sessions, configuration, diagnostics, another Integration Installation, or a native request.
- A selected user-data export can include confirmed Interaction Content; the corresponding Diagnostic Bundle cannot. Neither operation causes network egress or creates a service replica.
- Reconciliation after recovery uses only documented Adapter surfaces. A missing session from a non-exhaustive list, source disconnect, or Host closure leaves current truth unresolved rather than completed.

## Evidence and consequences

This decision applies the approved [product-direction defaults](product-direction-defaults.md), especially the 30-session working set, retained restart state, separate cleanup actions, local-only baseline, internal versioned schemas, and no post-restart action authority. It concretizes the [local-first privacy, security, and future-service boundary](local-first-privacy-security-boundary.md), [canonical event and Agent Session lifecycle](canonical-event-session-lifecycle.md), [Attention Request and action-routing semantics](attention-request-action-routing-semantics.md), and [Host Context identity, navigation, and fallback](host-context-identity-navigation-fallback.md). It is also consistent with [integration setup, reconciliation, and uninstall](integration-setup-reconciliation-and-uninstall.md).

No additional ADR is needed: the durable architectural choices—local canonical state, immutable facts, live action leases, and live Host locators—are already recorded in ADRs 0001, 0003, and 0004. This asset defines their required local retention and recovery behavior for the final specification.

