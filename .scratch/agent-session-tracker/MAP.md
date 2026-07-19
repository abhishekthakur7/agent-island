Label: wayfinder:map
Status: complete
Completed: 2026-07-18

# Specify complete personal-use Agent Island parity

## Destination

An implementation-ready, evidence-backed product requirements and architecture specification for Agent Island: a native macOS 14+ Apple Silicon application that meets or exceeds the in-scope functional behavior and visual quality of the Parity Baseline for Claude Code, Codex CLI, and Cursor across iTerm2, Cursor's integrated terminal and IDE, Warp, and Orca, while remaining extensible to future adapters and hosted services.

## Notes

- The Parity Baseline is Vibe Island v1.0.42 and public product materials as observed on July 18, 2026; later releases require a new effort.
- [Approved downstream product defaults](assets/product-direction-defaults.md) set the 30-session working-set behavior and recommended lifecycle, attention, navigation, setup, health, runtime, schema, and quality posture; downstream issues must turn them into evidence-backed requirements and surface only genuine conflicts.
- This is a personal, single-user, local-first application. State, configuration, transcripts, and diagnostics remain local in this baseline.
- The architecture must leave explicit extension seams for future telemetry, analytics, hosted persistence, and additional adapters, but those services are not implemented here.
- Functional and interaction parity is a floor. Visual quality must also meet the baseline while using original Agent Island branding and assets.
- First-class Agent Adapters: Claude Code, Codex CLI, and Cursor. First-class Hosts: iTerm2, Cursor's integrated terminal and IDE, Warp, and Orca.
- Consult `../../../VIBE_ISLAND_FUNCTIONALITY.md`, `../../../CONTEXT.md`, and relevant material under `../../../docs/adr/` before working a ticket.
- Use the `domain-modeling` skill for terminology and durable architectural decisions. Prototype tickets require live human review; research and task tickets may be driven AFK.
- This map may produce research assets, interaction prototypes, the glossary, ADRs, and the final specification. Production implementation is outside the map.
- Never resolve more than one child ticket in one Wayfinder session.

## Decisions so far

- [Establish the authoritative parity inventory](issues/01-establish-authoritative-parity-inventory.md): Freeze Vibe Island v1.0.42 evidence to the in-scope personal, local-first Claude Code/Codex CLI/Cursor and iTerm2/Cursor/Warp/Orca surface; preserve unknowns for downstream decisions.
- [Define local-first privacy, security, and future-service boundaries](issues/04-define-local-first-privacy-security-and-future-service-boundaries.md): Keep classified session data local and protected; use least-privilege macOS access, redacted explicit exports, and consent-gated outbound-only future-service seams.
- [Define the parity acceptance standard](issues/02-define-parity-acceptance-standard.md): Require capability-aware, evidence-backed outcome parity and live visual review; allow only documented safe deviations while preserving original Agent Island identity.
- [Define domain language and identity boundaries](issues/03-define-domain-language-and-identity-boundaries.md): Product-native identifiers, namespaced by Agent Adapter, are authoritative; labels, models, paths, and Host Contexts never silently merge work.
- [Research the Cursor adapter surface](issues/07-research-cursor-adapter-surface.md): Use Hook observation only for new local IDE Agent Sessions and reserve approval, question, plan, and cancellation routing for ACP sessions Agent Island itself starts; Cursor's IDE remains a separate Host surface.
- [Research Host navigation and control capabilities](issues/08-research-host-navigation-and-control-capabilities.md): Treat exact Host targeting as a live, host-specific capability; iTerm2 and Orca have supported runtime locators, Cursor requires a live extension endpoint, Warp is app-only, and Spaces are never an exact target.
- [Research the Claude Code adapter surface](issues/05-research-claude-code-adapter-surface.md): Use consented, capability-gated hooks and a local helper for structured lifecycle and attention; retain native Host Context fallback for unsupported controls and usage.
- [Research the Codex CLI adapter surface](issues/06-research-codex-cli-adapter-surface.md): Use version-pinned app-server for direct Codex control and opt-in hooks for observation-only terminal sessions; private persisted state is diagnostic-only.
- [Prototype the island interaction and visual system](issues/09-prototype-island-interaction-and-visual-system.md): Use Horizon for every state, promoting focused content and progressively compacting the same chronological, nested hierarchy at scale.
- [Define the normalized adapter and capability contract](issues/11-define-normalized-adapter-and-capability-contract.md): Negotiate evidence-backed capabilities per integration mode and live native scope through independent, fail-closed discovery, ingestion, action, configuration, health, degradation, and kill-switch surfaces.
- [Define integration setup, reconciliation, and uninstall](issues/18-define-integration-setup-reconciliation-and-uninstall.md): Manage each explicit Integration Installation through a manifest-proven, lossless exact-entry plan/apply/verify lifecycle; preserve drift and report residuals rather than rewriting or deleting ambiguous external material.
- [Define the canonical event and Agent Session lifecycle](issues/12-define-canonical-event-and-session-lifecycle.md): Retain immutable, source-proven event facts and derive conservative current state; gaps, restart, and Host loss are unresolved rather than completion, while rewinds and compaction preserve history within the same Agent Session.
- [Prototype attention, completion, plan, and question workflows](issues/10-prototype-attention-completion-plan-and-question-workflows.md): Use one capability-aware Guided sheet with Arrived → Review → Respond → Acknowledged progression, a preserved compact queue, and explicit Jump Back whenever an action cannot safely route in Agent Island.
- [Define Host Context identity, navigation, and fallback](issues/14-define-host-context-identity-navigation-and-fallback.md): Keep Agent Session–Host Context associations historical and provenance-bearing; navigate only with revalidated Host-specific locators and report the achieved explicit fallback level.
- [Define Attention Request and action-routing semantics](issues/13-define-attention-request-and-action-routing-semantics.md): Retain source-attributed requests and local drafts durably, but require a live one-use lease and typed attempt for each exact Product action; stale or ambiguous routes never replay and fall back to the Host.
- [Define persistence, history, recovery, and retention](issues/15-define-persistence-history-recovery-and-retention.md): Retain protected local canonical history until explicit deletion; rebuild derived views safely, fail closed on recovery, and keep future service copies outbound-only.
- [Define notifications, sounds, filters, and usage behavior](issues/16-define-notifications-sounds-filters-and-usage-behavior.md): Coordinate source-proven alerts through one deduplicated policy with quiet/foreground/filter suppression and optional capability-gated usage.
- [Define overlay, window, display, input, and accessibility behavior](issues/17-define-overlay-window-display-input-and-accessibility-behavior.md): Use a non-activating, display-selected Island Overlay with explicit presentation/input/accessibility/recovery state machines and a separate standard Settings window; preserve Host focus, visible-only hit regions, capability-honest navigation, and cold-resume safety.
- [Prototype onboarding, Settings, and diagnostics information architecture](issues/19-prototype-onboarding-settings-and-diagnostics-information-architecture.md): Use the Atlas macOS Settings sidebar with contextual onboarding, separate integration intent and health, owner-local previews, redacted diagnostics, and isolated consequential maintenance.
- [Define quality attributes and failure invariants](issues/20-define-quality-attributes-and-failure-invariants.md): Require evidence-gated local responsiveness, 30-session safe scale, conservative recovery, privacy/accessibility/diagnostics, capability-local degradation, and zero tolerance for unsafe state, action, navigation, or presentation failures.
- [Research native macOS implementation stacks](issues/21-research-native-macos-implementation-stacks.md): Keep AppKit-first with SwiftUI hosted views first and SwiftUI lifecycle with an AppKit Overlay bridge second; reject Catalyst and web wrappers pending two bounded native feasibility spikes.
- [Select the application architecture and component boundaries](issues/22-select-application-architecture-and-component-boundaries.md): Adopt an AppKit-first Swift shell with hosted SwiftUI, a deterministic replay-safe local core and isolated typed ports; gate production work on native Overlay and protected-store feasibility.
- [Specify data, event, action, and extension contracts](issues/23-specify-data-event-action-and-extension-contracts.md): Define versioned, fail-closed canonical facts, typed actions and ports, persistence boundaries, and extension evolution for replay-safe local-first operation.
- [Assemble the implementation-ready product and architecture specification](issues/24-assemble-implementation-ready-product-and-architecture-specification.md): Publish `SPEC.md` as the ready-for-agent, evidence-backed implementation baseline covering product behavior, contracts, architecture, quality gates, and feasibility spikes.
- [Close explicit attention, usage, and Settings parity requirement gaps](issues/27-close-explicit-attention-usage-and-settings-parity-gaps.md): Make A3, N5, O3, O4, and O5 explicit and testable, recording the approved no-timer cleanup improvement and capability-honest fallbacks.
- [Complete parity acceptance matrix and deviation register](issues/28-complete-parity-acceptance-matrix-and-deviation-register.md): Publish the complete normative parity record, including approved capability-scoped action, navigation, and usage deviations.
- [Audit parity traceability and requirements completeness](issues/25-audit-parity-traceability-and-requirements-completeness.md): Verify explicit inventory-by-capability acceptance records, approved deviations, and complete requirements coverage for the frozen baseline.
- [Approve the implementation baseline and exceptions](issues/26-approve-the-implementation-baseline-and-exceptions.md): Human owner approved `SPEC.md` as the frozen implementation baseline, including DR-01–DR-05 for their stated cells; production and visual evidence remain gated.

## Not yet specified

None currently.

## Out of scope

- Pricing, purchases, passes, licensing, device-seat management, and commercial entitlement flows.
- SSH Remote, remote-host setup, remote session monitoring, tunnels, bastions, and multi-Mac fan-out.
- Accounts, teams, collaboration, multi-user administration, cloud sync, and hosted-service implementation.
- Telemetry and analytics implementation; only an extensible boundary is required.
- Agent Products other than Claude Code, Codex CLI, and Cursor, and Hosts other than iTerm2, Cursor, Warp, and Orca, except as extension-contract test cases.
- Intel Macs, macOS versions earlier than 14, Windows, Linux, iOS, Android, and web clients.
- Copying Vibe Island branding, proprietary assets, or proprietary source code.
- Production implementation and implementation tickets; those begin only after this requirements map is complete.
- Feature changes released after the Parity Baseline.
