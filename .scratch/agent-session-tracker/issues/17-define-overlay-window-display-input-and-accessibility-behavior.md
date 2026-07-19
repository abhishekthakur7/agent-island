Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Terra-overlay
Blocked by: 01-establish-authoritative-parity-inventory.md, 08-research-host-navigation-and-control-capabilities.md, 09-prototype-island-interaction-and-visual-system.md, 14-define-host-context-identity-navigation-and-fallback.md
Blocks: 19-prototype-onboarding-settings-and-diagnostics-information-architecture.md, 20-define-quality-attributes-and-failure-invariants.md, 21-research-native-macos-implementation-stacks.md, 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Define overlay, window, display, input, and accessibility behavior

## Question

What explicit state machines and acceptance behavior govern non-activating overlay focus, click and hover, hit regions, auto-reveal and collapse, keyboard navigation, configurable shortcuts, accessibility semantics, multiple displays, notch geometry, Spaces, fullscreen, screen recording, sleep and wake, Settings windows, and app termination?

## Comments

### Resolution — 2026-07-18

The complete [overlay, window, display, input, and accessibility decision](../assets/overlay-window-display-input-accessibility.md) defines the non-activating Island Overlay and independently activating Settings window, explicit presentation/display states, precise visible hit-region and hover rules, focused keyboard engagement and safe configurable shortcuts, accessibility semantics, display/notch/Space/full-screen behavior, screen-recording policy boundary, cold wake/restart recovery, and termination ordering.

It turns the parity and changelog evidence into a 16-scenario acceptance matrix while retaining the notifications ticket's authority over notification eligibility and exact dwell-policy selection. It also records [ADR 0007](../../../docs/adr/0007-nonactivating-island-overlay-and-independent-settings.md) for the durable activation/window boundary and adds **Island Overlay** to the shared glossary.
