Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Terra-quality
Blocked by: 12-define-canonical-event-and-session-lifecycle.md, 13-define-attention-request-and-action-routing-semantics.md, 14-define-host-context-identity-navigation-and-fallback.md, 15-define-persistence-history-recovery-and-retention.md, 16-define-notifications-sounds-filters-and-usage-behavior.md, 17-define-overlay-window-display-input-and-accessibility-behavior.md, 18-define-integration-setup-reconciliation-and-uninstall.md, 19-prototype-onboarding-settings-and-diagnostics-information-architecture.md
Blocks: 21-research-native-macos-implementation-stacks.md, 22-select-application-architecture-and-component-boundaries.md, 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Define quality attributes and failure invariants

## Question

What measurable performance, scale, startup, latency, memory, energy, reliability, security, privacy, accessibility, diagnostics, compatibility, and graceful-degradation requirements—and which forbidden failure invariants—must the implementation satisfy to qualify as a proper parity application?

## Comments

### Resolution — 2026-07-18

The [quality attributes and failure invariants decision](../assets/quality-attributes-and-failure-invariants.md)
sets evidence-bearing release gates for local event and action latency, warm
and cold launch, the 30-Agent-Session working set and safe overflow,
resource observation, recovery, local privacy, accessibility, diagnostics,
version degradation, display/sleep/wake, and adapter/action/navigation safety.
It uses the approved sub-250 ms, sub-150 ms, sub-one-second warm, and
sub-two-second cold targets; it deliberately defers only stack-specific
memory/energy numbers to measured native-stack research. The decision makes
false Product truth, cross-owner state/action, stale control, unsafe navigation,
active-work loss, duplicate/disruptive presentation, privacy/configuration
overreach, dishonest health, and inaccessible fallback release-blocking.
