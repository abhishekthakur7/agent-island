Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Codex
Blocked by: 04-define-local-first-privacy-security-and-future-service-boundaries.md, 05-research-claude-code-adapter-surface.md, 06-research-codex-cli-adapter-surface.md, 07-research-cursor-adapter-surface.md, 08-research-host-navigation-and-control-capabilities.md, 11-define-normalized-adapter-and-capability-contract.md
Blocks: 19-prototype-onboarding-settings-and-diagnostics-information-architecture.md, 20-define-quality-attributes-and-failure-invariants.md, 22-select-application-architecture-and-component-boundaries.md, 23-specify-data-event-action-and-extension-contracts.md, 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Define integration setup, reconciliation, and uninstall

## Question

How should Agent Island discover, enable, configure, health-check, repair, migrate, disable, and completely remove its owned hooks, plugins, extensions, launchers, and config entries while preserving custom paths, JSONC, comments, symlinks, unrelated settings, external edits, and unknown upstream versions?

## Comments

### Resolution — 2026-07-18

The [integration setup, reconciliation, and uninstall decision](../assets/integration-setup-reconciliation-and-uninstall.md) defines an explicit, reviewable lifecycle for each Integration Installation. A local Ownership Manifest proves only exact marked entries and application-owned artifacts; discovery and reconciliation are read-only by default, and every supported configuration mutation is lossless, plan-approved, revalidated, and verified.

### Amendment — 2026-07-20

[ADR 0009](../../../docs/adr/0009-bounded-launch-time-integration-installation.md)
permits one bounded exception: a pristine, reviewed, user-scope Integration
Installation may be applied automatically after launch discovery. It retains
exact ownership, journaling, prerequisite, and zero-write refusal rules; all
repair, adoption, migration, removal, and ambiguous states remain explicitly
reviewed.

Runtime pause, disablement, setup removal, local-data deletion, and complete cleanup are distinct actions. External edits, unknown versions/syntax, policy precedence, symlink changes, and ambiguous entries cause a visible repair/manual-remedy or residual state rather than automatic repair, adoption, deletion, or a false successful-uninstall claim. The durable trade-off is recorded in [ADR 0003](../../../docs/adr/0003-manifest-proven-exact-entry-configuration-ownership.md).
