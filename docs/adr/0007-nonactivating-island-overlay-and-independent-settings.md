# Non-activating Island Overlay and independent Settings window

Agent Island uses a non-modal, normally non-activating Island Overlay for automatic and pointer-driven top-edge presentation, while Settings is a separate standard activating macOS window. This boundary preserves the person's Host focus during ambient monitoring yet permits intentional keyboard/accessibility interaction and durable configuration without relying on floating-window defaults; it also makes display loss, Spaces, full screen, sleep/wake, and termination safe to model independently.

## Consequences

- Automatic presentation, hover, and collapse never activate a Host or Agent Island, and the visible Overlay region is always its only interactive/accessibility region.
- Settings has normal window-level and restoration behavior rather than inheriting Overlay display ownership or level.
- Direct Overlay keyboard engagement is bounded and explicit; navigation and Agent Product actions remain governed by their own capability and live-lease contracts.
