# Data, event, action, and extension contracts

**Decision date:** 2026-07-18  
**Scope:** implementation-neutral contracts for the local core, Agent Adapters,
Hosts, helpers, configuration, diagnostics, user export, and future outbound
services. These are internal versioned contracts, not a public plug-in API or a
choice of wire format, IPC framework, or storage schema.

## Decision

Agent Island's sole canonical input is a protected local ledger of validated,
immutable **Normalized Event Facts**. The deterministic SessionDomain reducer
derives current state from that ledger; no Product, Adapter, Host, helper, UI,
configuration editor, exporter, or future service may directly write a
projection or canonical record.

Every boundary message is a typed, classified, versioned envelope carrying its
owner tuple, source provenance, and correlation ID. Unknown input fails closed:
an unknown required version is incompatible; an unknown optional field is
ignored only when its known container declares its classification; and an
unknown extension is non-actionable Interaction Content. Product-specific
extensions may retain faithful detail but cannot bypass identity, action-lease,
configuration, privacy, or degradation rules.

The structures below specify semantic fields and constraints only. A later
implementation may select a compatible serialization, storage layout, and IPC
technology without changing these contracts.

## Common values, identifiers, and provenance

A contract version has major and minor components plus a capability-catalog
revision. A major change alters required meaning and requires explicit mutual
support. A minor change only adds optional fields, optional variants, stable
reason codes, or extension schemas. All identifiers and Host locators are
opaque outside their issuing boundary. Product-supplied time, local observation
time, and commit time retain their source and precision; none is an identity or
a substitute for a documented cursor.

| Value | Authority and rule |
| --- | --- |
| Product Namespace | Stable Agent-Adapter namespace for one Agent Product; prefixes every native owner ID. |
| Native Session, Turn, Subagent Run, Request, and Item IDs | Owned by the Product and carried with their asserted parent identities. They are never derived from text, title, path, model, process, Host, time, or local data. |
| Integration Installation ID | Random local identity for one explicit Integration Installation. It is setup/routing provenance, not Product identity. |
| Negotiation Snapshot ID | Immutable local record of one contract/Product/interface/capability negotiation. Every fact, capability, locator, lease, and attempt that relies on it retains it. |
| Source Event ID | Preferred Product-provided event identity. The stable deduplication key is Product Namespace plus this value. |
| Weak Deduplication Key | Adapter-versioned fallback only when no stable source ID exists. It is scoped to the Installation, marked weak, retains its window and documented callback/cursor/owner evidence, and never uses content similarity. |
| Fact ID and Commit Ordinal | Local store IDs. Fact ID identifies one accepted fact; ordinal gives deterministic local audit/replay order, never a fabricated Product order. |
| Host Context/Incarnation ID | Local historical identity only. It cannot make a Host locator live. |
| Attempt ID and Action Lease nonce | Attempt ID is durable local audit identity. A nonce is authenticated, single-use, live Product authority and is never persisted. |
| Correlation ID | Locally generated redacted trace value; not a Product ID, service identity, or action authority. |

The owner tuple is:

    OwnerTuple {
      productNamespace, nativeSessionID,
      nativeTurnID?, nativeSubagentRunID?, nativeRequestID?, nativeItemID?
    }

It is valid only when the Adapter validates Product-provided parentage. A child
whose Turn is unknown remains a session child; it is never attached to the
most recent Turn. Conflicting owner claims quarantine the smallest affected
intake scope.

Every accepted fact retains:

    Provenance {
      productNamespace, integrationInstallationID, integrationMode,
      adapterKindAndBuild, negotiationSnapshotID,
      sourceKind, sourceVariant, sourceEventID? | weakDeduplicationKey?,
      sourceCursor? { stream, epochOrRevision?, position? },
      productTime?, observedAt, receivedVia, continuityEvidence,
      classification, correlationID
    }

Received-via names the documented Product interface or application-owned
receiver, never a generic process scrape. Provenance is append-only; a later
probe or reconciliation adds a new fact and does not rewrite the source claim.

## Normalized event contract

### Envelope, intake, and taxonomy

An Adapter, Host receiver, or reconciliation operation submits this logical
envelope to the single intake path:

    NormalizedEventEnvelope {
      envelopeVersion, catalogRevision, provenance,
      owner: OwnerTuple | IntegrationScopedOwner,
      family: EventFamily, variant: NamespacedVariant,
      ordering: SourceOrderingEvidence,
      body: Classified<CommonEventBody>,
      extensions: [ClassifiedExtension],
      transport: { messageID?, authenticated?, sizeBytes, receivedAt }
    }

    AcceptedNormalizedFact {
      factID, commitOrdinal, acceptedAt, originalEnvelope,
      acceptance: { acceptedVersion, validationSummary, deduplicationStrength },
      authorityScope
    }

The core validates version, authentication when applicable, size,
classification, ownership, negotiated mode, semantic shape, and source
evidence before appending. Intake returns exactly accepted, duplicate,
quarantined, or rejected with a redacted reason. Duplicate delivery produces a
diagnostic but does not run the reducer twice. Quarantined/rejected input may
not create an Agent Session, request, association, action route, or lifecycle.

| Family | Required ownership and effect |
| --- | --- |
| observationBoundary | Installation scope; changes observation/health only and never terminal lifecycle. |
| reconciliation | Installation plus named native source scope; may update only explicitly documented authoritative fields. |
| continuityGap | Installation plus affected stream/entity scope; marks current truth unresolved and never fills the missing interval. |
| sessionDeclared and sessionActivity | Agent Session and Turn where supplied; establishes sourced identity/activity only. |
| turnDeclared, turnActivity, lineageChanged, compactionObserved | Agent Session and named Turn/checkpoint; preserves current/historical lineage without deleting history. |
| subagentRunDeclared and subagentRunActivity | Agent Session and native child, with parent Turn where supplied; child status never completes its parent. |
| attentionObserved | Agent Session and native request; creates/updates durable source-attributed Attention Request state only. |
| sourceFault | Proven affected owner; can establish sourced failed/stopped evidence, not transport failure. |
| hostContextObserved and hostLocatorInvalidated | Host Context/incarnation plus proven association when available; affects navigation evidence, never Product lifecycle. |
| usageObserved, configurationObserved, healthObserved | Named Installation/capability scope; display/configuration/health evidence only. |

Common bodies declare every field as Operational Metadata or Interaction
Content. Credentials/secrets are redacted before this contract and never
persisted. Any undeclared or unknown extension field defaults to Interaction
Content, cannot be diagnostic/telemetry input, and is non-actionable.

### Ordering, deduplication, corrections, and gaps

There is no global Product order. A source cursor compares events only inside
the documented stream and epoch/revision. Within a comparable stream, reduce
by documented cursor/revision. Otherwise preserve incomparable status and use
commit ordinal only to replay deterministically; an older local observation
cannot overwrite a newer authority frontier.

Stable deduplication is Product Namespace plus Source Event ID. With no source
ID, Installation plus Weak Deduplication Key is a weaker documented-replay
suppression only. A collision or ambiguous replay is retained as ambiguity/gap
evidence, never silently merged. Text, timestamp, title, path, and payload
similarity are not deduplication input.

A correction must name its documented revision relation and may supersede only
the entity/field it authoritatively reports; both facts remain. Cursor holes,
unproven replay, source reset, rejected malformed range, interface change, or
unknown continuity append a gap. Later evidence repairs only what it proves.
Conflicting incomparable terminal facts are unresolved.

## Record model and invariants

The implementation may choose tables/documents, but these logical records have
schema version, classification manifest, immutable creation provenance, and
logical deletion boundary where needed.

| Record | Canonical content and invariant |
| --- | --- |
| Agent Session | Native root owner tuple, sourced attributes, fact references, selected lineage. Lifecycle is derived; Host/model/path are never identity. |
| Turn | Parent session, native ID, explicit lineage/checkpoint and fact references. Rewind preserves historical Turns in the same session. |
| Subagent Run | Parent session, native child ID, supplied parent Turn, facts. Unknown child prevents confident terminal parent. |
| Attention Request | Native request key, owner tuple, semantic variant/constraints, source state, draft, local presentation, facts. Routing exists only with a live Action Lease. |
| Action Attempt | Durable explicit user intent, owner tuple, capability/snapshot/lease version, submitted content reference, outcome evidence. It never itself proves Product lifecycle. |
| Action Lease | Exact owner/action/response constraints, native fingerprint, deadline, nonce, issuance snapshot. Volatile; revoke on use, deadline, restart/wake, reconnect, source change, negotiation change, or action-gate closure. |
| Host Context, association, and incarnation | Historical Host identity/native key when any, opaque locator provenance, association state, invalidation history. Associations are many-to-many and live validity never survives launch/wake. |
| Integration Installation and Ownership Manifest | Explicit scope/intent, exact owned entry/artifact selector, plan/verification, compatibility and health evidence. It owns no whole config file or Product data. |
| Negotiation Snapshot and Capability | Immutable contract/Product/interface/probe evidence, extension namespaces, scoped claims/constraints/freshness. Runtime availability may narrow but cannot rewrite a snapshot. |
| Diagnostic Event | Redacted component/operation/owner-or-capability scope, reason, time, correlation, recovery hint; no content, secret, raw token/ID, title, path, command line, or locator. |
| Projection Snapshot | Ledger revision and deterministic presentation projection. It is replaceable and may publish only at its matching committed revision. |

An Agent Session's lifecycle is the independent execution, attention,
observation, and lineage tuple established by the canonical lifecycle decision.
Unresolved is required after a gap, contradiction, restart/wake without fresh
reconciliation, or unproven ownership. Archive and the 30-session working set
are local presentation/storage tiers, not Product lifecycle states.

## Commands, typed actions, attempts, leases, and acknowledgements

Every UI gesture and port request is a typed command, never source evidence:

    Command<Target, Payload> {
      commandID, correlationID, issuedAt,
      actor: LocalPerson | SystemRecovery,
      kind, target, payload, expectedLedgerRevision?,
      confirmationEvidence?, reliedOn: { snapshotID?, capabilityID?, revision? }
    }

    CommandResult {
      commandID, outcome: completed | rejected | pending | unavailable,
      redactedReason?, ledgerRevision?, safeNextStep?
    }

System recovery can only reconcile, withdraw, or restore local evidence; it
cannot dispatch Product actions, Jump Back, mutate configuration, export, or
delete. A stale revision must revalidate or safely reject.

| Command | Required target/guard | Permitted result |
| --- | --- | --- |
| IngestNormalizedEvent | Valid authenticated Adapter/receiver envelope. | Accept, deduplicate, quarantine, or reject one fact. |
| Reconcile | Installation/source scope and documented negotiated read/list/replay/probe. | Append reconciliation/gap facts only; never scrape private state or launch Product work. |
| RespondToAttention | Exact open native request, typed response schema, live one-use lease, capability, required confirmation. | One durable attempt and at most one native dispatch. |
| InterruptTurn | Exact live Session/Turn, separately negotiated capability/lease, confirmation unless Product documents harmless. | One typed attempt; Product acceptance is not completion. |
| JumpBack | Agent Session and proven association/capability candidate. | One Navigation Attempt with actual achieved level; never Product input. |
| PlanConfiguration / ApplyConfigurationPlan | Installation; apply needs fresh approved plan, exact ownership proof, and configuration gate. | Read-only plan or lossless plan/apply/verify with residual result. |
| DisableInstallation / RemoveSetup / DeleteLocalData / CompleteCleanup | Explicit scope and consequential confirmation. | Their distinct lifecycle/deletion boundary only. |
| CreateUserDataExport / CreateDiagnosticBundle | Explicit local destination and classified selected scope. | Local artifact only; content export requires additional confirmation. |

The common Product action catalog is intentionally distinct:

    ProductAction =
      AllowOnce | DenyOnce | ApplyOfferedPersistentPermission |
      SubmitStructuredAnswer | AcceptPlan | RejectPlanWithReason |
      SubmitDocumentedTurnInput | InterruptNamedTurn |
      ProductExtensionAction { namespace, actionKind, schemaRevision }

There is no generic execute, raw command, terminal-key injection, or
reply-by-text fallback. Turn input is not plan approval. Observation is not
authority to act.

Before lease reservation, ApplicationRuntime and the owning Adapter both
validate the same owner tuple, source state/current lineage, integration
mode/snapshot, capability/scope, response constraints, native fingerprint and
deadline, nonce liveness, action gate, and deliberate confirmed gesture.
Reservation atomically persists one Action Attempt with its submitted payload
reference, changes routing to reserved, and consumes the volatile lease. The
Adapter then makes exactly one dispatch attempt.

    ActionAttemptResult {
      attemptID,
      outcome: rejected | acceptedByProduct | applied | superseded | indeterminate,
      observedAt, provenance, redactedReason?, productEvidenceReference?
    }

Rejected proves no native dispatch. Accepted-by-Product is not application.
Applied needs documented synchronous or later sourced proof. Superseded means
the native Product resolved/replaced it first. Indeterminate means dispatch may
have happened and must never automatically retry. Retry is a new attempt and
new lease only when documented Product idempotency and current liveness allow
it. Native expiry wins over local timers; recovery/reconnect and all gate/source
changes revoke every lease while durable request/draft history remains visible.

## Persistence, snapshots, migrations, and deletion

SessionStore is the sole persistence port and single logical writer. An
accepted fact atomically commits identity/provenance, ordering, deduplication
and authority-frontier updates, plus the matching projection or sufficient
facts to rebuild it. An Action Attempt is durable before its dispatch. A crash
shows the prior complete commit or no commit, never a ghost session, duplicate
fact, half-attempt, or projection without its fact.

Facts are logically append-only. Correction, reconciliation, gap, migration,
and deletion boundary are new records. Physical compaction, re-encryption,
index rebuilding, and snapshot replacement must preserve Fact ID, commit order,
classification, provenance, deletion boundaries, and deterministic replay.

| Boundary | Required contract |
| --- | --- |
| Snapshot/rebuild | Snapshot has ledger and projection/schema revision; rebuild from verified facts only, never presentation/cache/path/title/transcript resemblance. |
| Migration | Preflight without changing the only readable copy; stage encrypted replacement; verify IDs/order/classification/provenance/deletion boundaries and deterministic projection; atomically promote or fail closed. |
| Key/schema/ciphertext/corruption | Preserve protected bytes and redacted fault; affected state is unavailable/unresolved; offer verified local export or separately confirmed purge. Never reset or revive a lease. |
| Session History deletion | After confirmation remove only selected inactive session facts, received content, dependent request/draft/attempt and local Host evidence; retain minimum non-content native owner/source-range boundary to suppress old replay. Never affect Product data/configuration. |
| Active local-history deletion | First stop only local observation scope; never claim Product stopped or retain stale authority. Fresh documented source evidence may create fresh local history. |
| Installation cleanup | Separately remove selected diagnostics/preferences/generated schema/cache/manifests under setup/removal rules. Forgetting a manifest never authorizes external deletion. |

Interaction Content, redacted operational records, and replaceable projections
remain separate. Leases, callback handles, and raw response tokens never
persist. No Adapter, helper, UI, Host, or service receives a store handle or
Keychain key.

## Required outer ports

The core owns typed inward-facing ports. Implementations use the common
envelopes and error result below, cannot import presentation state, and cannot
write the store directly.

| Port | Operations and constraints |
| --- | --- |
| AgentAdapterPort | Discover, negotiate, start/stop observation, reconcile, dispatch typed Product Action, inspect/plan/apply/verify configuration, health. One actor owns one Installation's transport, health, and volatile leases. |
| HostNavigationPort | Negotiate, revalidate opaque locator, Jump Back candidate/level, health. It returns actual exactSurface, exactTab, workspaceOrFile, windowBestEffort, appOnly, or unavailable—not intended success. |
| IntegrationReceiverPort | Accepts only versioned, size-limited, authenticated documented local input; classifies/parses then submits an event envelope. Signed helper/extension has no store/key/UI/config access and cannot dispatch alone. |
| ConfigurationPort | Read-only discovery/reconciliation plus exact-entry plan/apply/verify/remove. Each write is installation-locked, freshly approved, lossless, verified, and residual-reporting. |
| DiagnosticsPort | Accepts only redacted Diagnostic Events and creates user-initiated local bundle. It rejects Interaction Content, credentials, raw IDs/tokens, titles, paths, command lines, and locators. |
| UserDataExportPort | Writes person-selected verified local data plus schema/integrity manifest. Interaction Content is separately confirmed; secrets, leases, callback tokens, raw config, and unselected sessions are excluded. |
| ServiceEgressPort | Absent by default. Consumes only classified purpose-consented outbound change sets from a local outbox; outbound-only, no direct store read, no remote merge, no blocked local commit, and no Product/Host/configuration action. |

A Service Egress change set has purpose, consent version, selected scope,
schema version, service-specific pseudonyms, and classified payload. Purposes
are hosted persistence, telemetry, and support diagnostic; each future
implementation needs separate destination, authentication, retention, deletion,
and failure policy. Telemetry is allowlisted aggregate/redacted measurement.
Hosted persistence receives no raw local/Product identity. Failed or absent
egress cannot alter local monitoring, storage, Attention Requests, actions, or
Jump Back.

## Capability, error, health, and degradation contracts

    CapabilityRecord {
      capabilityID, revision, direction: observe | act | configure | navigate,
      scope, availability: available | unavailable | temporarilyUnavailable |
                          unknown | incompatible,
      maturity: documented | experimentalOptIn | diagnosticOnly,
      constraints, evidence, observedAt, expiresAt?, renegotiationConditions,
      fallbackCapability?
    }

    PortOutcome<T> {
      status: success | rejected | unavailable | incompatible | degraded |
              indeterminate | failed,
      value?, stableReasonCode, correlationID, occurredAt,
      affectedScope, capabilitySnapshot?, safeNextStep?
    }

A Port Outcome reports operation truth, never Product lifecycle. Its reason is
allowlisted plus optional redacted detail. Health is a timestamped vector:
Product/interface compatibility; configuration ownership/load; permissions;
helper/transport; protocol/schema; event freshness/gaps; action readiness; Host
navigation; and breakers. The UI may summarize only Disabled, Setup required,
Healthy, Degraded, Unavailable, or Incompatible while preserving dimensions and
a non-destructive next step.

Observation, action, and configuration gates are independent and scopeable by
global, Adapter, Installation/mode, or capability. Closing one safely rejects
new work and records evidence; it never sends approval, denial, cleanup,
keystrokes, or invented completion. An automatic breaker targets the smallest
unsafe surface and never auto-reopens action/configuration. Changed, unknown,
or disconnected Product/Host/interface evidence narrows only affected
capabilities and produces a gap/degraded/unavailable state where needed.

## Compatibility and extension evolution

1. Persist exact contract/catalog versions and Negotiation Snapshot on every
   fact, attempt, capability, and locator.
2. Decode known majors only. Unsupported major is incompatible: no intake,
   action, or configuration mutation.
3. New minor fields remain optional and classified until a later supported
   major makes their meaning required.
4. Common family/action/capability IDs never change meaning. Deprecate through
   old decoder/migrator plus a new ID/revision, never semantic mutation.
5. Every extension has namespace, schema revision, declared classification, and
   opaque payload. Namespace registration is part of Negotiation Snapshot.
   Unknown extension data may be retained as non-actionable evidence but may
   not reduce lifecycle, create routing, dispatch, or flow outward by default.
6. Migrations preserve old semantics; an ambiguous old fact remains preserved
   and its new projection field becomes unresolved.
7. Product/Host version change is read-only reprobe. Observation survival does
   not inherit a past action/configuration/navigation claim.

## Representative examples

These examples demonstrate meaning, not serialization syntax.

    // Interaction Content remains in the protected request body.
    NormalizedEventEnvelope {
      version: 1.0,
      provenance: { productNamespace: codex, integrationMode: appServer,
        sourceEventID: opaqueEvent91, sourceCursor: { stream: thread8, position: 42 },
        negotiationSnapshotID: snapshot7, classification: mixed },
      owner: { productNamespace: codex, nativeSessionID: thread8,
        nativeTurnID: turn4, nativeRequestID: approval2 },
      family: attentionObserved, variant: codex.approval.requested,
      body: { requestVariant: permission, choices: [allowOnce, denyOnce],
        prompt: InteractionContent }
    }

    Command {
      kind: RespondToAttention, actor: LocalPerson, commandID: attempt15,
      target: owner tuple above, payload: allowOnce,
      reliedOn: { snapshotID: snapshot7, capabilityID: permission.allowOnce }
    }

    ActionAttemptResult { attemptID: attempt15, outcome: acceptedByProduct }

    PortOutcome<NavigationAttempt> {
      status: success, stableReasonCode: host.revalidated,
      value: { hostKind: iTerm2, achievedLevel: exactSurface,
        capabilitySnapshot: hostSnapshot3 }
    }

## Contract conformance tests

| Area | Minimum proof |
| --- | --- |
| Identity/provenance | Same-looking sessions, Turns, requests, and panes never merge; conflicting ownership quarantines; facts retain original snapshot/mode/source evidence. |
| Version/extensions | Unknown minor optional field is safe; unknown major is incompatible; unknown extension is non-actionable and excluded from diagnostics/egress; deprecated schema replays equivalently or explicitly unresolved. |
| Intake/order | Stable duplicate reduces once; weak-key collision remains ambiguous; reorder/reset/gap/conflicting terminal facts preserve history and project conservatively. |
| Lifecycle/recovery | Rewind/compaction retain history; Host/helper/transport loss never completes work; restart/wake clears leases and live locators while restoring verified records. |
| Actions | Cross-owner, expired, rewound, double-click, shortcut-repeat, killed, disconnected, and indeterminate paths dispatch zero or one time as required; applied needs Product proof; retry has new lease. |
| Navigation | Locator cannot cross Host/incarnation; exact requires revalidation; ambiguity chooses/downgrades; feedback matches achieved ladder level. |
| Store/migration/deletion | Crash has no half commit; snapshots rebuild deterministically; migration retains canonical evidence; corruption fails closed; deletion affects only declared local category. |
| Configuration | Stale, ambiguous, lossy, or externally changed plan writes nothing; approved exact plan preserves unrelated material; verification/residual is durable. |
| Privacy/egress | Seeded content, secrets, paths, raw IDs/tokens, locators, and command lines cannot enter diagnostics/telemetry; content export is explicitly scoped; failed egress leaves core unchanged. |
| Degradation | Capability-local loss narrows only affected claims and exposes redacted reason/recovery; health never conflates configured, loaded, reachable, delivered, action-ready, and navigable. |

## Decision dependencies

This asset implements the contracts required by the [Normalized Agent Adapter
and Capability Contract](normalized-adapter-capability-contract.md), [canonical
lifecycle](canonical-event-session-lifecycle.md), [Attention Request routing](attention-request-action-routing-semantics.md), [Host Context navigation](host-context-identity-navigation-fallback.md), [persistence and recovery](persistence-history-recovery-and-retention.md), [Integration Installation lifecycle](integration-setup-reconciliation-and-uninstall.md), [local-first privacy boundary](local-first-privacy-security-boundary.md), [quality invariants](quality-attributes-and-failure-invariants.md), and [selected application architecture](application-architecture-and-component-boundaries.md).

It preserves [ADR 0001: local canonical state](../../../docs/adr/0001-local-canonical-state-and-consent-gated-egress.md), [ADR 0001: stable Product identity](../../../docs/adr/0001-stable-identity-at-product-boundary.md), [ADR 0002: versioned Adapter boundary](../../../docs/adr/0002-versioned-capability-scoped-adapter-boundary.md), [ADR 0003: immutable facts](../../../docs/adr/0003-immutable-event-facts-and-conservative-lifecycle-projection.md), [ADR 0004: live action leases](../../../docs/adr/0004-live-action-leases-for-attention-routing.md), [ADR 0004: live Host locators](../../../docs/adr/0004-live-host-context-locators-and-honest-navigation.md), and [ADR 0008: AppKit-first architecture](../../../docs/adr/0008-appkit-first-application-architecture.md).

No ADR is warranted: this asset specifies implementation-facing interfaces
inside already accepted architectural boundaries and selects no new durable
technology or trade-off. Filename 0009 remains unreserved.

