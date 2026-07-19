Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Terra-notifications
Blocked by: 01-establish-authoritative-parity-inventory.md, 09-prototype-island-interaction-and-visual-system.md, 12-define-canonical-event-and-session-lifecycle.md, 13-define-attention-request-and-action-routing-semantics.md
Blocks: 19-prototype-onboarding-settings-and-diagnostics-information-architecture.md, 20-define-quality-attributes-and-failure-invariants.md, 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Define notifications, sounds, filters, and usage behavior

## Question

What event-specific notification, automatic reveal, glow, sound, mute, quiet-scene, quiet-hours, foreground-suppression, spam, probe, directory, prompt, launcher, subagent, idle-reminder, and provider-usage rules reproduce the Parity Baseline without duplicate or disruptive signals?

## Comments

### Resolution — 2026-07-18

The [notifications, sounds, filters, and usage behavior](../assets/notifications-sounds-filters-and-usage-behavior.md)
defines a single deduplicated, source-proven Alert Candidate and coordinated
signal bundle so island reveal/glow, sound, and macOS notifications cannot
multiply from replayed, stale, filtered, quiet-scene, or already foreground
work. It specifies event priority and dwell, per-event sound/mute/quiet-hours
semantics, probe and custom filtering, privacy-safe foreground suppression,
and optional capability-gated provider usage without making a usage bridge
mandatory. It also adds the resolved Notification Policy, Quiet Scene, and
Usage Snapshot terms to the domain glossary. No ADR is warranted because these
are reversible local presentation and preference rules, not a durable
architecture boundary.
