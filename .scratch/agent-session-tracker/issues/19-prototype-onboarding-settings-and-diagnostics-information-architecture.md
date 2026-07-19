Status: closed
Type: prototype
Label: wayfinder:prototype
Parent: ../MAP.md
Assignee: Terra-settings-prototype
Blocked by: 01-establish-authoritative-parity-inventory.md, 04-define-local-first-privacy-security-and-future-service-boundaries.md, 11-define-normalized-adapter-and-capability-contract.md, 16-define-notifications-sounds-filters-and-usage-behavior.md, 17-define-overlay-window-display-input-and-accessibility-behavior.md, 18-define-integration-setup-reconciliation-and-uninstall.md
Blocks: 20-define-quality-attributes-and-failure-invariants.md, 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Prototype onboarding, Settings, and diagnostics information architecture

## Question

How should first-run education and detection, integration intent versus health, General, Integrations, Notifications, Display, Sound, Usage, Shortcuts, Labs-equivalent controls, About and maintenance actions, live previews, filter previews, diagnostics, export, reset, and uninstall be organized and visually presented for the personal build?

## Comments

### Prototype ready for live review — 2026-07-18

The dependency-free, throwaway review artifact is
[settings information architecture prototype](../assets/settings-information-architecture-prototype/README.md).
It uses representative local-only data and in-memory visual controls only; no
control mutates a Product, configuration, permission, file, or stored state.

Run from the repository root:

```sh
python3 -m http.server 4184 --directory .scratch/agent-session-tracker/assets/settings-information-architecture-prototype
```

Open <http://localhost:4184/?variant=atlas>. The fixed bottom review switcher
and left/right keys (outside inputs) preserve the shareable URL parameter.

- `atlas` — conventional Settings sidebar with contextual first-run education.
- `flight` — progressive setup journey organized around the person's next outcome.
- `workbench` — operational lanes separating daily preferences, integration evidence, and consequential care.

Review prompts: Which organization makes integration **intent** versus verified
**health** clearest? Where should live display/filter previews and everyday
notification controls live? Does maintenance feel sufficiently separate from
ordinary preferences?

Live human direction is required before resolving this ticket. Status remains
open and Resolution remains unresolved.

### Apple Design redesign ready for live review — 2026-07-18

The three prototype directions retain their distinct information architecture
but now share an Apple-informed macOS presentation foundation: layered
translucent materials, familiar window chrome and grouped preferences,
restrained system typography, immediate press feedback, spatially consistent
materialization, semantic health states, and explicit reduced-motion,
reduced-transparency, increased-contrast, focus, and compact-layout behavior.

Browser validation covered Atlas, Flight, and Workbench at 1440×1000, plus
Flight at 760×900. All routes returned successfully, keyboard variant switching
remained URL-stable, the compact viewport had no horizontal overflow, and the
page console had no errors or warnings. This is still a throwaway prototype;
the ticket remains open until the human owner selects or combines a direction.

### Resolution — 2026-07-18

The human owner selected **Atlas (Option A)** as the final direction. The
[Settings, onboarding, and diagnostics information architecture](../assets/settings-onboarding-diagnostics-information-architecture.md)
uses a conventional persistent macOS Settings sidebar, contextual and resumable
first-run education, explicit separation between integration intent and
observed health, owner-local live previews, redacted diagnostics, and a
visually and behaviorally isolated Maintenance destination.

The Apple-informed material, typography, feedback, motion, and accessibility
foundation is retained. Flight and Workbench are rejected as final structures;
the active prototype is reduced to an Atlas-only reference because production
implementation remains outside this map. No ADR is warranted for this
revisable presentation decision.
