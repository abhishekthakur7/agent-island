# Settings, onboarding, and diagnostics information architecture

**Decision date:** 2026-07-18  
**Approved direction:** Atlas (Option A)

## Decision

Agent Island uses a conventional macOS Settings window with a persistent
sidebar and one independently scrolling detail pane. This familiar Atlas
structure is the default information architecture for first-run education,
preferences, integration health, diagnostics, and consequential maintenance.
It retains the Apple-informed material, typography, feedback, motion, and
accessibility foundation validated in the prototype.

Onboarding is contextual and resumable rather than a separate permanent
navigation system. The first-run promise and progress appear in General during
setup, can be skipped or resumed, and hand off to the relevant Settings
destination when an integration, permission, display, or interruption choice
needs detail. Completing onboarding removes the progress treatment without
removing the underlying settings or diagnostics.

## Sidebar structure

The persistent destinations are grouped by frequency and consequence:

- **Preferences:** General, Integrations, Notifications, Display, Sound, Usage.
- **Advanced:** Shortcuts, Labs, Diagnostics, Maintenance.

General owns launch, overlay, hover, foreground-suppression, fullscreen, and
reveal defaults. Integrations owns detection, enabled intent, setup plans,
capability evidence, observed health, repair, and custom paths. Notifications
owns event delivery, quiet scenes, filters, and live filter previews. Display
owns selected-display behavior and its live Island preview. Sound and Usage
remain separate because they have distinct capability, privacy, and failure
semantics. Shortcuts and Labs remain explicitly advanced. Diagnostics explains
accepted, filtered, deduplicated, downgraded, and broken states through local
redacted evidence.

Maintenance is the final, visually differentiated destination. Resetting
presentation preferences, removing manifest-proven setup, deleting selected
local data, and complete cleanup remain separate planned actions with their own
scope preview and confirmation. They never appear as casual switches beside
ordinary preferences.

## Intent, health, and recovery

Every Integration Installation exposes enabled intent independently from its
observed delivery health. An enabled switch never doubles as a health claim.
Each row shows a compact current state—such as Healthy, Degraded, Setup
Required, Unavailable, or Incompatible—and expands into evidence, affected
capabilities, observation time, and a non-destructive next action. Detection
alone never enables or configures an integration.

Setup, repair, migration, disablement, and removal begin with reviewable plans.
Unknown syntax, external drift, missing proof of ownership, or an unsupported
Product version produces a manual-remedy/residual state rather than a false
success or destructive rewrite.

## Presentation rules

- Use a standard activating macOS Settings window, independent of the
  non-activating Island Overlay and its display ownership.
- Use a heavier translucent sidebar/titlebar material, lighter grouped detail
  surfaces, system typography, restrained system-blue primary actions, and
  semantic status colors.
- Controls respond on pointer-down and remain usable during non-gesture
  transitions. Materialization is spatially consistent and critically damped
  in character, with no decorative bounce.
- Provide explicit focus treatment plus reduced-motion,
  reduced-transparency, increased-contrast, keyboard, VoiceOver, and compact
  layout adaptations.
- Place a live preview beside the setting it explains. A preview is local and
  read-only; it never creates an alert, changes an Agent Product, or writes
  configuration.
- Consequential actions use direct labels, show scope before confirmation, and
  never rely on color alone.

## Acceptance scenarios

- A person can leave and resume onboarding without repeating completed
  education or losing access to the normal Settings destinations.
- Claude Code can be enabled and Healthy while Codex CLI is enabled but
  Degraded and Cursor is detected but not enabled; none of those states is
  visually or semantically conflated.
- Notification filter and Display previews update locally without emitting an
  alert, moving the Island Overlay, or mutating an integration.
- Diagnostics can explain a degraded capability and prepare a redacted local
  bundle without exposing Interaction Content or credentials.
- Maintenance keeps preference reset, setup removal, selected local-data
  deletion, and complete cleanup distinct through scope preview and explicit
  confirmation.
- Keyboard, VoiceOver, increased text, reduced motion/transparency, increased
  contrast, and a compact window preserve destination, state, and action
  meaning without horizontal overflow.

## Prototype disposition

The reviewed [Settings information architecture prototype](settings-information-architecture-prototype/README.md)
is retained temporarily as an Atlas-only runnable reference because no
production application scaffold exists yet. Flight and Workbench are rejected
as final structures; their active variant switcher has been removed. The
prototype remains non-production and all controls remain illustrative.

No ADR is warranted. The decision is a validated product and presentation
organization that can be revised without changing a durable system boundary.
