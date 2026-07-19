# AppKit-first application architecture with a deterministic local core

Agent Island uses an AppKit-first Swift application shell with SwiftUI hosted
Overlay/Settings content, a pure replay-safe session reducer, a single-writer
encrypted local canonical store, and typed inward-facing Adapter, Host,
configuration, diagnostics, and future-egress ports. AppKit owns the
non-activating Overlay and macOS lifecycle because those requirements cannot
safely be delegated to SwiftUI scene defaults; Product/Host integrations,
optional signed helpers, and future services remain capability-scoped outer
implementations so their failure or evolution cannot manufacture Product truth
or compromise local-first recovery.

## Consequences

- The selected stack is Swift, AppKit, SwiftUI, Swift concurrency, and
  SQLCipher SQLite with a Keychain-held per-installation key. Developer ID
  signing and notarization are outside the personal-use local baseline;
  full-Xcode-only XCTest/UI execution is not a prerequisite to implementation.
- UI, helpers, extensions, and external integrations may only use typed ports;
  none receives a direct database/key handle or bypasses live action,
  configuration-ownership, or classification gates.
- The AppKit Overlay and encrypted-store spike architectures were accepted by
  the owner on 2026-07-19. Unrun validation remains explicit implementation
  risk and must not be represented as passing evidence.
