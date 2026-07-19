Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Codex
Blocked by: 03-define-domain-language-and-identity-boundaries.md, 08-research-host-navigation-and-control-capabilities.md, 11-define-normalized-adapter-and-capability-contract.md, 12-define-canonical-event-and-session-lifecycle.md
Blocks: 15-define-persistence-history-recovery-and-retention.md, 17-define-overlay-window-display-input-and-accessibility-behavior.md, 20-define-quality-attributes-and-failure-invariants.md, 23-specify-data-event-action-and-extension-contracts.md
Resolution: answered

# Define Host Context identity, navigation, and fallback

## Question

How is a Host Context captured, persisted, invalidated, reconciled, and activated across Spaces, fullscreen, multiple similar windows, tabs and panes, recreated contexts, and missing permissions, and what capability ladder and user feedback govern every Jump Back fallback?

## Comments

### Resolution — 2026-07-18

The [Host Context identity, navigation, and fallback decision](../assets/host-context-identity-navigation-fallback.md)
separates historical Agent Session–Host Context associations from
Product-owned identity; ties exact navigation to revalidated, Host-specific
live locators; and records context incarnation, invalidation, provenance, and
the achieved—not intended—Jump Back result. It forbids continuity inference
from similar panes, titles, paths, Spaces, full-screen state, or Accessibility
data; recreated contexts are distinct until the source proves continuity.

Jump Back follows the explicit `exactSurface` → `exactTab` →
`workspaceOrFile` → `windowBestEffort` → `appOnly` → `unavailable` ladder,
with contextual permission handling and feedback that names the actual result
and limitation. [ADR 0004](../../../docs/adr/0004-live-host-context-locators-and-honest-navigation.md)
records the durable boundary.
