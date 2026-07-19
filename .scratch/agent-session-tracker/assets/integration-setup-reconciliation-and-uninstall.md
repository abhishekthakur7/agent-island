# Integration setup, reconciliation, and uninstall

**Decision date:** 2026-07-18  
**Applies to:** explicit local setup and removal of first-class Claude Code,
Codex CLI, Cursor, and Host integration surfaces.  
**Does not authorize:** editing a repository or Worktree by default, scanning a
home directory, altering Product security/permission settings, changing
unrelated extensions or hooks, or deleting Agent Product data.

## Decision

An **Integration Installation** is one explicit, reversible configuration of
one Agent Adapter integration mode at one selected configuration scope. Agent
Island discovers possible setup surfaces read-only, but never enables a
discovered Agent Product or modifies configuration without a person approving a
concrete plan.

Every write is backed by an **Ownership Manifest** created before mutation. It
proves the exact logical configuration entry and application-owned artifact
Agent Island created. The manifest is evidence for precise repair, migration,
and removal; it is not a claim over a whole configuration file, directory,
Product, profile, or repository. A configuration entry is removable
automatically only when the manifest, selected source, and a lossless current
parse prove it is the same application-owned entry. A change, collision,
unsupported version, policy override, or lossy syntax is a non-destructive
review/manual-remedy state, never an invitation to rewrite or delete nearby
material.

## Installation boundaries

### Scopes and discovery

The default is one user-level personal configuration scope. Project, Worktree,
profile, or repository-shared setup is a separately labelled advanced choice
that names the exact path and sharing consequence before any plan. Custom
executable paths, Product homes, and alternate installations are also advanced
choices; Agent Island does not infer them by recursively scanning the disk.

Discovery uses only selected Product-documented configuration locations, a
person-selected path, and already-authorized bookmarks. It resolves the
selected path's symlink chain for inspection while retaining both entered
logical path and final canonical target as sensitive local installation facts.
It never replaces a symlink with a regular file, retargets it, changes its
ownership or permissions, or follows a path outside the granted scope to write.

Read-only discovery reports each selected mode as one of:

| State | Meaning and next step |
| --- | --- |
| Not configured | No candidate owned entry was found. Enable can prepare a plan. |
| Owned intact | Manifest and current lossless parse prove the exact entry/artifact is present. Health validation may proceed. |
| Owned drifted | A manifest-proven location remains, but entry, artifact, source path, or version differs. Show a repair/removal plan; do not apply it automatically. |
| External candidate | A similar helper, hook, extension, or config entry exists without manifest proof. Describe it without claiming ownership; leave it untouched. |
| Shadowed or managed | A documented higher-precedence source, policy, trust state, or Product mode prevents loading. Explain it; never write around it. |
| Unsupported | Product/schema/configuration representation cannot be safely understood. Keep it read-only and offer compatible upgrade or manual instructions. |
| Unavailable | Product, selected source, permission, helper, or Host endpoint cannot be inspected. Preserve last facts and explain missing evidence. |

Discovery is not health: finding an executable, candidate entry, or enabled
toggle does not prove that the mode is loaded, reachable, or delivering events.

### Exact ownership and manifest

An Installation receives a random local installation ID. A configuration entry
uses an Adapter-specific uniquely recognizable semantic marker tied to that
ID: for example, an absolute Agent Island helper command with an
installation-ID argument, or an extension/launcher identifier whose package
receipt and installation ID are recorded. The marker is not a credential and
cannot grant control by itself. It lets a lossless editor identify one entry
without claiming a neighbouring hook that invokes the same program.

Before an approved write, Agent Island atomically persists an intent record.
After successful verification, it commits an Ownership Manifest containing:

- local installation ID; Agent Adapter kind, mode, selected scope, and Product
  namespace;
- logical selected path, symlink-aware canonical target, source format/schema
  version, and filesystem identity where available;
- a precise selector for each owned entry, generated marker, entry-local
  secret-free fingerprint, and before/after validation facts;
- every application-owned helper, extension, launcher, or receiver artifact:
  logical/canonical path or Product receipt identity, expected
  code/content fingerprint, install version, and removal dependency order;
- Product/interface/extension versions, capability-negotiation snapshot,
  creation and latest verification timestamps; and
- lifecycle status: active, disabled, drifted, removal pending, or removed,
  plus only redacted reconciliation reasons.

The manifest stores no whole configuration file, arbitrary command line,
credential, prompt, source text, or unredacted external identifier. Full paths
are protected local configuration data and are redacted from a Diagnostic
Bundle. If intent survives a crash without verified completion, reconciliation
shows incomplete setup/removal and uses the same exact-entry rules; it never
guesses that a write succeeded.

### Plan, approve, apply, verify

Enable, repair, migrate, disable, and remove are all plan-producing actions.
The plan names selected scope, logical/canonical location, each exact
entry/artifact to add/change/remove, expected Product/version compatibility,
permissions, affected Capability, current drift/conflict, and rollback/manual
remedy. It also says what it will not touch: Product permission mode and rules,
status lines, telemetry, credentials, unrelated hooks/extensions,
session/transcript data, and repository configuration unless that scope was
explicitly selected.

A person approves the fresh plan immediately before mutation. It expires if
source fingerprint, symlink target, Product version, policy, or configuration
state changes. Revalidation occurs again under the write lock; a stale plan is
discarded and regenerated, never optimistically applied.

Supported file formats require a tested lossless, structure-preserving editor:

- JSONC editing retains comments, whitespace, ordering, and unknown keys.
- TOML and every other supported format retain untouched token ranges,
  comments, ordering, and unknown syntax.
- An extension or launcher uses its documented installer/remover only when it
  identifies the exact installed receipt or application-owned artifact.

Parsing to an object and serializing a whole document is forbidden. If current
syntax cannot be parsed and round-tripped losslessly, has duplicate or
ambiguous matching entries, has a changed symlink target, is policy-owned, or
requires unsupported schema migration, Agent Island makes no mutation. It
shows the redacted location, reason, and narrow manual instructions.

For a supported mutation, Agent Island alters the smallest token/entry range,
writes a same-directory temporary file to the resolved target, preserves file
metadata where supported, atomically replaces that target, and re-reads it to
verify exact entry identity and unchanged unrelated ranges. It does not replace
the logical symlink. Multi-artifact plans stage application-owned helpers before
their references and validate Product load/probe before retiring an old owned
reference. If a later step fails, Agent Island rolls back only
still-provably-owned steps; otherwise it retains the manifest and reports a
recoverable partial state.

## Product and Host setup rules

| Surface | Explicit setup rule | Verification and safe removal |
| --- | --- | --- |
| Claude Code hooks | Default only to selected user settings. Add one marked absolute command-hook entry for the local helper. A project/local scope needs shared-config consent. | Re-read exact settings entry, probe no-action helper, check version, and observe documented reload/config-change evidence. Remove only manifest-matched hook; never change permissions, status lines, OTel, or managed settings. |
| Codex CLI hooks | Add one marked owned hook only in selected documented user/config/profile source; project source needs consent. | Re-read exact definition and validate trust/load state plus no-action receiver probe. Remove only it and owned receiver state—never CODEX_HOME, credentials, sessions, skills, or another hook. |
| Codex app-server | No Product configuration write is required for local stdio mode. Generate version-pinned schema only in application-private storage after explicit enablement. | Run version/schema/initialize probes and retain redacted results. Removal stops connection and deletes only Agent Island generated schema/cache/manifest; it never changes Codex Threads or state. |
| Cursor IDE Hooks | Add a marked Hook at selected user or explicitly chosen project location. Keep an Agent Island extension/receiver separate from person-installed extensions unless its exact receipt is manifest-proven. | Re-read exact Hook and validate local delivery. Remove only manifest-matched Hook and owned receiver/receipt; never modify run modes, credentials, existing Agent Sessions, or person-installed extensions. |
| Cursor ACP | Starting an Agent Island-owned ACP session is runtime setup, not discovery or configuration of an existing Cursor Agent Session. | Negotiate ACP capability per connection. Disable/removal ends Agent Island transport state; it cannot remove or adopt native Cursor sessions. |
| iTerm2, Cursor terminal, Warp, Orca Host endpoints | Request documented access or extension endpoint only when its exact navigation/control Capability is selected. | Health-check endpoint independently from Agent Adapter. Removing it deletes only an Agent Island-owned endpoint/launcher or manifest-matched extension receipt; it never changes profiles, tabs, panes, Worktrees, or Host preferences. |

## Health and reconciliation

Reconciliation is read-only by default. It runs at launch, return from
sleep/wake, explicit Refresh, Product/Host version change, safe source-file
change notification, helper/extension reconnect, and after failed delivery or
probe. It reads only selected source and manifest, coalesces repeated
notifications, and records a timestamped health vector:

- enabled intent and lifecycle state;
- source existence, exact ownership, load/preference/policy result, and current
  Product/schema compatibility;
- required filesystem, Accessibility, extension, and local-IPC permission;
- helper/extension/launcher and authenticated local transport reachability;
- delivery freshness, declared/reconciled gaps, and last safe no-action probe;
  and
- per-Capability action readiness and independent Host navigation readiness.

Healthy requires an enabled mode, manifest-proven loaded configuration, and
verified delivery. An installed helper, present entry, running process, opened
socket, or absence of recent events does not prove delivery; lack of event
evidence remains unknown unless a documented heartbeat/probe proves failure.
The compact UI derives only Disabled, Setup required, Healthy, Degraded,
Unavailable, or Incompatible, while Settings shows reason, evidence time,
affected Capability, and non-destructive next action.

On a source change, restart, reconnect, or Product update, Agent Island
revalidates source identity, version/schema, manifest selector, and documented
load/probe surfaces. It may reconcile Agent Session state only through the
Agent Adapter's documented read/list/replay/probe surface. It never derives
current work from configuration, terminal scrollback, private transcripts, or
state files; it does not synthesize completion, replay stale Attention Requests,
restore expired action leases, or use a Host as an action fallback.

| Drift | Result |
| --- | --- |
| Exact owned entry was deleted | Setup required; offer a fresh explicit enable plan, never recreate it automatically. |
| Owned entry changed but remains uniquely identifiable | Degraded; show field-level review and a repair, preserve, or removal plan. No automatic repair. |
| Entry became ambiguous, duplicated, moved, source was symlink-retargeted, or format is lossy | Degraded or unavailable; no write. Retain manifest evidence and give manual instructions. |
| Product/Host update changes supported interface or extension version | Incompatible or capability-local degraded; reprobe/regenerate only after approval where it writes. Do not assume a compatible minor version. |
| Higher-precedence config, policy, trust, safe/bare mode, or disabled hook prevents load | Unavailable; identify blocker and do not evade it with a second entry elsewhere. |
| Helper, extension, IPC, or delivery probe fails | Degraded; keep independently safe capabilities, record a gap, and offer repair/Jump Back as appropriate. |

Repair is an explicit plan that restores a manifest-proven losslessly editable
entry or replaces it only after the person accepts the transition. Migration
retains old manifest evidence, stages compatible owned artifacts, verifies
target version and delivery, then removes prior entry/artifact only when still
manifest-proven. If this would duplicate event delivery or make removal
ambiguous, migration stops with manual steps. Neither action silently broadens
scope, changes a custom path, adopts a similar external entry, or overrides
policy.

## Disablement, removal, and cleanup

| Action | Effect | Retained by default |
| --- | --- | --- |
| Runtime pause / safety kill switch | Stops applicable event, action, or configuration gate; does not change intent or files. | Configuration and manifest records. |
| Disable Integration Installation | Sets enabled intent off and stops runtime I/O; does not write Product configuration. | Owned entry/artifacts, manifest, history, preferences, diagnostics. Re-enable is revalidated and explicit. |
| Remove setup | Deletes only current manifest-proven exact entries and application-owned helper/extension/launcher/receiver artifacts, then stops runtime. | Agent Session history, presentation preferences, and diagnostics unless separately selected. |
| Delete local data | Separately confirmed per-Installation deletion of selected Agent Island history, preferences, diagnostics, generated schema/cache, and manifest after setup removal. | Product configuration and all Agent Product data. |
| Complete cleanup | Checklist combining every manifest-proven setup artifact with independently confirmed local-data categories. | External/ambiguous residual remains preserved and reported, never falsely labelled removed. |

Removal has a fresh plan and final verification. It removes configuration
entries before deleting helpers they invoke, then verifies no manifest-proven
entry remains loaded. It removes app-private generated caches/receivers and an
extension/launcher only when its exact receipt/path and dependency rules still
validate. It never deletes an entire Product root, Claude or Cursor home,
CODEX_HOME, project config directory, sessions, transcripts, credentials,
permissions, non-Agent-Island extensions, or a person's similarly named script.

If an owned-looking entry was externally edited, removal may remove only a
still-exact marked subentry when a lossless selector proves it preserves that
edit. Otherwise it leaves the entry, marks removal pending, and gives precise
manual instructions. It may forget its manifest only after the person
acknowledges that residual; forgetting evidence never authorizes deletion. The
final result distinguishes removed, partially removed with residual, and not
removed, so complete cleanup never overclaims success.

## Safety and acceptance requirements

- Plans, mutations, verification outcomes, drift reasons, and removal residuals
  are auditable locally without Interaction Content or credentials.
- Configuration mutation has a default-deny kill switch. Closing it prevents
  enable/repair/migration/removal writes but does not represent existing
  configuration as absent.
- A Product configuration change, external edit, or failed probe never silently
  enables an Integration Installation, dismisses an Attention Request,
  dispatches an action, or changes Product permission behavior.
- Contract fixtures cover comments/JSONC, TOML, unknown fields, custom paths,
  symlink targets, duplicate and external edits, malformed/lossy syntax, policy
  precedence, Product upgrades, partial migration, crash recovery,
  exact-entry removal, and every residual outcome.
- Product × Host parity review records selected scope, integration mode,
  Product/Host version, manifest/health evidence, achieved Capability, and safe
  deviation. It proves disabled, configured, loaded, reachable,
  delivery-verified, and action-verified remain distinct states.

## Consequences

This approach deliberately stops some setup, repair, migration, and cleanup
flows for review instead of fixing configuration. That is the trade-off needed
to preserve comments, unknown upstream syntax, custom/symlinked paths,
externally maintained entries, and Product policy. It gives Settings a truthful
lifecycle: discovery is useful without claiming ownership; removal is complete
for what Agent Island proves it owns without deleting what it cannot safely
identify.

The persistence, application architecture, extension contract, Settings, and
quality decisions must use the Integration Installation, Ownership Manifest,
health-vector, and residual-removal terms and preserve these exact-entry
boundaries.

