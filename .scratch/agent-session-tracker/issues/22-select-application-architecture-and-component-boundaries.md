Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Terra-architecture
Blocked by: 11-define-normalized-adapter-and-capability-contract.md, 15-define-persistence-history-recovery-and-retention.md, 18-define-integration-setup-reconciliation-and-uninstall.md, 20-define-quality-attributes-and-failure-invariants.md, 21-research-native-macos-implementation-stacks.md
Blocks: 23-specify-data-event-action-and-extension-contracts.md, 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Select the application architecture and component boundaries

## Question

Which implementation stack, process model, module boundaries, dependency direction, concurrency model, and failure isolation should Agent Island adopt so the core session engine remains deterministic while adapters, Hosts, UI, persistence, diagnostics, and future service ports evolve independently?

## Comments

### Resolution — 2026-07-18

Agent Island will use the [AppKit-first application architecture and component
boundaries](../assets/application-architecture-and-component-boundaries.md): a
Developer-ID-notarized Swift macOS application where AppKit owns the
non-activating Island Overlay and lifecycle, SwiftUI hosts presentation,
`SessionDomain` remains a pure deterministic/replay-safe reducer, and a
single-writer encrypted local store commits canonical facts before revisioned
projections reach the main-actor UI. Typed ports and per-installation actors
isolate Agent Adapters, Hosts, configuration mutation, diagnostics, optional
signed helpers/extensions, and future consented outbound services; none can
write the store directly, invent Product truth, or bypass owner/capability/live
lease gates.

The decision selects SQLCipher-backed SQLite with a Keychain-held
per-installation key, rejects Catalyst/web wrappers/public plug-ins for the
baseline, and makes both the native AppKit Overlay matrix and signed encrypted
store recovery spike mandatory pre-implementation gates. They validate the
selected architecture rather than leave its component boundaries unresolved.
The durable choice is recorded in [ADR
0008](../../../docs/adr/0008-appkit-first-application-architecture.md). No
glossary term was added because the resolved module, process, port, actor, and
storage terms are implementation concepts rather than Agent Island domain
language.
