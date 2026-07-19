# Application architecture and component boundaries

**Decision date:** 2026-07-18  
**Scope:** the native macOS implementation architecture for the personal,
local-first Agent Island baseline. This selects a production architecture; it
does not authorize production implementation.

## Decision

Agent Island is an **AppKit-first Swift application with SwiftUI hosted
content and Settings**. The AppKit application shell owns the normally
non-activating Island Overlay and the macOS lifecycle that makes that contract
safe. SwiftUI owns Horizon and Atlas presentation content only; it does not
own Product state, panel policy, or application lifecycle. Distribution is a
Developer-ID-signed, hardened, notarized macOS 14+ Apple Silicon application.

The local stack is Swift with structured concurrency, AppKit, SwiftUI,
XCTest/UI tests, Keychain Services, SQLCipher-backed SQLite, and an optional
application-owned XPC helper/receiver where a selected Adapter mode needs it.
SQLite is the protected local canonical-store engine: its database key is
per-installation Keychain material, and ciphertext, schema, migration, and
integrity failure fail closed. `SMAppService`, `UNUserNotificationCenter`, and
documented AppKit/ApplicationServices APIs are used only behind their own
platform ports. No Catalyst, Electron, Tauri, web renderer, public Adapter
plug-in loader, general command executor, or cloud service is in the v1
runtime.

This choice applies the [native macOS implementation-stack research](native-macos-implementation-stacks.md), the [non-activating Overlay ADR](../../../docs/adr/0007-nonactivating-island-overlay-and-independent-settings.md), and the approved [product-direction defaults](product-direction-defaults.md). It preserves the independently selected [Adapter contract](normalized-adapter-capability-contract.md), [persistence boundary](persistence-history-recovery-and-retention.md), [Integration Installation lifecycle](integration-setup-reconciliation-and-uninstall.md), and [quality invariants](quality-attributes-and-failure-invariants.md).

## Process model and trust boundaries

The normal runtime is one application process. It contains the AppKit shell,
SwiftUI views, deterministic domain code, the protected store, and the
orchestration actors described below. It has no elevated privilege. A login or
background item is not an assumed second process; it is introduced only for a
selected integration mode whose measured delivery requirement cannot be met
while the app is not frontmost.

An Adapter may require a narrowly scoped **Integration Receiver** helper or a
Host extension. Such code is application-owned, versioned, signed, and
manifest-proven for its Integration Installation. The receiver parses only its
documented external protocol, applies size/authentication/source checks, and
sends a versioned classified envelope over authenticated local XPC to the app.
It has no direct SQLite/Keychain access, cannot render UI, cannot mutate
configuration, cannot decide lifecycle, and cannot dispatch an action without
a request from the app's Adapter runtime. A helper exit, XPC failure, or
extension crash is transport degradation, not Product completion or an app
restart.

The boundary is intentionally not a general IPC or plug-in API. First-party
Adapters are compiled and shipped with the app. A later third-party Adapter
mechanism must be a separate architecture decision and satisfy the same
identity, classification, capability, and failure-isolation rules.

## Modules and dependency direction

The codebase is organized as acyclic modules. Ports point inward; platform,
Product, and service implementations point outward.

| Module | Owns | May depend on | Must not depend on |
| --- | --- | --- | --- |
| `SessionDomain` | opaque owner tuples, normalized-fact validation rules, pure reducer, deterministic projection functions, typed domain commands/results | value types and deterministic utilities only | SwiftUI, AppKit, SQLite, XPC, clocks, random IDs, Adapter/Host implementations |
| `SessionStore` | append-only canonical ledger, commit ordinal, encrypted SQLCipher repository, migration/checkpoint/rebuild, durable Action Attempts, manifests, preferences, redacted diagnostics | `SessionDomain`, Keychain/storage implementation port | UI, Adapter/Host runtime, Product/Host SDKs |
| `ApplicationRuntime` | intake orchestration, projection publication, policy coordination, lifecycle recovery, port invocation | `SessionDomain`, store and typed ports | concrete UI panels or Product-specific parsing |
| `AdapterRuntime` | one actor per Integration Installation: negotiation, capabilities, health, reconciliation, event intake, volatile Action Leases, typed Product dispatch | Adapter contract and `ApplicationRuntime` ports | views, direct store writes, Host targeting, configuration writes |
| `HostRuntime` | one actor per Host endpoint: locator revalidation and typed Jump Back attempts | Host port and `ApplicationRuntime` ports | Agent Product action dispatch, lifecycle reduction, direct UI mutation |
| `ConfigurationRuntime` | manifest-backed discovery, plan, approval freshness, exact-entry apply/verify, repair/removal residuals | configuration port, `SessionStore`, Adapter discovery surface | live session reduction, arbitrary file rewriting, UI-owned mutation |
| `PresentationRuntime` | main-actor projection subscription, notification policy, Overlay intents, Settings state and accessibility presentation | immutable presentation snapshots and typed UI-command ports | SQLite, raw Adapter/Host input, Action Leases, configuration files |
| `MacOSInfrastructure` | AppKit shell/panel, SwiftUI hosting, Keychain, SQLCipher, XPC, ServiceManagement, notifications, AX, filesystem and Product/Host clients | outward port protocols | domain decisions or canonical records |

`SessionDomain` is the only component allowed to derive current Agent Session,
Turn, Subagent Run, Attention Request, and working-set state from accepted
facts. Its reducer is a pure function of an explicitly versioned canonical
ledger plus projection inputs. It receives local receipt time, generated IDs,
and ordering evidence as data; it calls no clock, UUID source, task, I/O API,
or UI API. The store serializes accepted commits and persists their commit
ordinal. Source ordering remains evidence rather than an invented global
Product order; incomparable or gapped facts reduce conservatively to
`unresolved`. A stored ledger therefore reproduces the same projection after
replay, migration, or crash recovery.

The only allowed high-level direction is:

```text
MacOSInfrastructure / Adapter / Host / future service implementations
                         -> typed ports -> ApplicationRuntime
                         -> SessionDomain + SessionStore
                         -> immutable projection -> PresentationRuntime
                         -> AppKit shell / SwiftUI views
```

UI commands reverse only through typed application ports. They cannot call a
Product or Host client directly. Product and Host implementations do not
import presentation code or write canonical state directly.

## Concurrency, ordering, and actions

`SessionStore` is a single-writer actor. It atomically commits each accepted
normalized fact with the identity/provenance/deduplication frontier and either
the corresponding projection checkpoint or the information necessary to
rebuild it. Projection work may run off the main actor, but a result is
published only if its ledger revision still matches; stale work is discarded.
Read models are immutable revisioned snapshots, so views never observe a
half-commit.

Each AdapterRuntime actor owns its own connection, receive tasks, health
state, kill switches, and volatile Action Leases. Each HostRuntime actor owns
only that endpoint's live locator state. They communicate through typed,
bounded async channels; all external bytes are parsed, size-limited,
authenticated where applicable, classified, and validated before entering the
single intake path. Backpressure pauses/quarantines the affected integration
and records redacted diagnostics rather than dropping a fact silently or
blocking the main actor.

The explicit action path is:

```text
SwiftUI/AppKit intent -> ApplicationRuntime validation -> durable Action Attempt
  -> AdapterRuntime revalidates owner + capability + live one-use lease
  -> exactly one typed Adapter dispatch -> result fact/diagnostic -> store
```

Only Product evidence can change Product lifecycle or prove an action applied.
The local dispatch result can update Action Attempt state but cannot create
completion, approval, or request resolution. Restart, wake, reconnect, source
change, and Adapter actor replacement clear every volatile Action Lease and
force fresh negotiation/reconciliation. A HostRuntime is never an action
fallback.

## Local storage, configuration, diagnostics, and extension ports

`SessionStore` is the sole local-storage boundary. It exposes typed repository
operations, not SQL, database handles, or file paths. It separates canonical
facts and protected selected Interaction Content from replaceable card, queue,
search, and working-set projections; it also keeps Integration Installation
manifests/preferences and redacted operational diagnostics separately from
Agent Session history. No Adapter, helper, extension, UI, or future service
port receives a database handle or Keychain key.

Configuration mutation has a single **ConfigurationRuntime** boundary. A
Settings command requests discovery or a fresh plan; only an explicit approved
plan that is still valid may pass to an Adapter-specific lossless editor or
documented installer. The configuration kill switch defaults to deny. The
actor takes an Installation-scoped mutation lock, commits intent/manifest
evidence around the mutation, re-reads to verify it, and reports residuals.
Helpers and extensions cannot change Product configuration, and normal Adapter
event delivery cannot implicitly enable, repair, migrate, or uninstall an
Integration Installation.

Diagnostics are emitted as a typed redacted operational event before crossing
the diagnostics port. Classification/redaction occurs at the Adapter, Host,
storage, and configuration boundaries, not in a final export filter. The
diagnostic repository and Diagnostic Bundle formatter accept no Interaction
Content, credentials, raw callback tokens, raw external identifiers, full
paths, or arbitrary command lines. Correlation IDs link a failure across
actors without granting data access.

Future outbound functionality is represented by internal `ServiceEgressPort`
implementations. They consume only a classified, versioned, purpose-consented
snapshot/change set from a local outbox. The port is absent by default, has no
inbound read/merge interface, cannot delay or replace a local commit, and
cannot initiate Product/Host/configuration actions. Telemetry, analytics, and
hosted persistence must each define their own implementation and consent
policy before an implementation is attached.

## UI projection and macOS shell

`PresentationRuntime` observes revisioned derived snapshots, applies local
Notification Policy and presentation state, and emits an Overlay intent. The
AppKit shell decides only native display/panel mechanics: selected display,
`NSPanel` non-activation, collection/level behavior, visible-shape hit and
accessibility regions, deliberate keyboard engagement/release, screen change,
sleep/wake, and safe withdrawal. It hosts SwiftUI content for the Island
Overlay and an independently activating standard Settings window. It cannot
advance lifecycle, make a locator live, dispatch a Product action, or retain
hidden interaction regions. Display loss withdraws the Overlay rather than
migrating it; Settings remains independent.

This makes the core-to-screen flow one way:

```text
accepted fact -> atomic canonical commit -> deterministic projection
  -> revisioned presentation snapshot -> policy/Overlay intent
  -> AppKit panel mechanics -> hosted SwiftUI rendering and AX tree
```

An action, Jump Back, setup, or deletion gesture returns through a separate
typed command port and its required confirmation/revalidation flow. A view
model, card title, selection, timer, notification, or panel callback is never
source evidence.

## Failure isolation and recovery

An Adapter/Host/helper/extension failure narrows only its negotiated
capabilities and health dimensions. It cannot corrupt the ledger, block other
installations, affect the Overlay process model, or make another Product
unavailable. A malformed or excessive message is rejected before the core;
an unknown classified extension is retained only as non-actionable evidence.
Circuit breakers are per capability/installation and require explicit safe
recovery rather than automatic reopening. The app must retain redacted
diagnostics for each boundary failure.

Store/key/schema/ciphertext/migration failure is contained before projection or
action routing. The app enters visible recovery/unavailable state for the
affected data, preserves verifiable protected bytes, and does not reset,
invent lifecycle, or enable a lease. UI/panel failure must withdraw the
affected presentation safely without changing canonical state; restart
reopens the verified store, rebuilds projections, marks formerly live state
unresolved, invalidates Host locators and Action Leases, and reconciles only
through documented Adapter/Host ports.

## Required gates before production implementation

The two research spikes do not leave the architecture choice open; AppKit-first
is selected because it directly owns the decisive panel lifecycle. They are
mandatory pre-implementation gates because failure would prevent this selected
architecture from satisfying a settled invariant:

1. **Overlay gate:** the AppKit `NSPanel` hosting a SwiftUI view must pass the
   stated built-in/external-display matrix for non-activation, visible-only hit
   and accessibility regions, explicit keyboard engagement/release,
   selected-display withdrawal, full-screen/Space behavior, and cold
   sleep/wake recovery. Failure stops production work and records the failed
   condition; it does not silently substitute a SwiftUI scene or web window.
2. **Protected-store gate:** a Developer-ID-signed, hardened, notarized test
   app must create, migrate, reopen, and fail closed with a Keychain-held key
   and SQLCipher SQLite store. It must cover missing key, corrupt ciphertext,
   migration failure, deterministic rebuild, and redacted diagnostics. Failure
   stops production work; selecting an alternative storage engine or encryption
   design would require a new ADR and a new equivalent gate.

The gates also establish the stack-specific memory and energy budget from the
30-Agent-Session workload before release, as required by the quality decision.
They are intentionally bounded feasibility work, not a reason to defer module,
process, or dependency selection.

## Consequences

AppKit responder-chain and panel lifecycle work is explicit and testable,
while SwiftUI remains productive for presentation. The single protected-store
writer and pure reducer make replay/recovery reviewable, at the cost of
explicit asynchronous ports and revisioned projections. Optional helpers and
extensions add signed IPC and manifest obligations but cannot become an
unbounded plug-in or database boundary. Future services can be added outward
without weakening the local-first core.
