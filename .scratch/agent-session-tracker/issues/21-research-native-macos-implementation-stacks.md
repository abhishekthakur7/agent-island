Status: closed
Type: research
Label: wayfinder:research
Parent: ../MAP.md
Assignee: Terra-macos-stack
Blocked by: 04-define-local-first-privacy-security-and-future-service-boundaries.md, 08-research-host-navigation-and-control-capabilities.md, 17-define-overlay-window-display-input-and-accessibility-behavior.md, 20-define-quality-attributes-and-failure-invariants.md
Blocks: 22-select-application-architecture-and-component-boundaries.md
Resolution: answered

# Research native macOS implementation stacks

## Question

Which viable macOS application stacks and system APIs best satisfy the settled overlay, Accessibility, window control, persistence, integration, performance, testability, packaging, and future-extension requirements, and what trade-offs or technical spikes remain before selection?

## Comments

### Resolution — 2026-07-18

The [native macOS implementation stacks research](../assets/native-macos-implementation-stacks.md) keeps two native candidates for downstream selection: an AppKit-first shell with SwiftUI hosted content/settings (ranked first) and a SwiftUI lifecycle with an AppKit-owned Overlay bridge. Both can satisfy the local-first persistence, Adapter/service seams, Developer ID/notarization, and tested macOS requirements, but the AppKit-first form most directly owns the non-activating Overlay, display/Space/full-screen, accessibility, shortcut, sleep/wake, and termination mechanics.

Mac Catalyst is not viable for the specified `NSPanel`-class Overlay contract; Electron and Tauri are honest cross-platform alternatives but would require native bridges for the decisive features and add avoidable runtime/privacy surface. Two bounded gates remain: a native Overlay behavior spike and a signed/notarized encrypted-SQLite/Keychain recovery spike. The asset links primary Apple/framework evidence, the settled requirement inputs, a requirements matrix, risks, and the future boundary seams. No architecture ADR or production implementation was created.
