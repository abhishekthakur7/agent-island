# Native macOS implementation stacks

**Research date:** 2026-07-18
**Scope:** feasibility for the personal, local-first macOS 14+ Apple Silicon baseline. This is a shortlist and risk assessment, not an architecture selection or ADR.

## Decision inputs

The candidate must implement the independently activating Settings window and normally non-activating **Island Overlay** as different native surfaces; it must not approximate the latter with a conventional floating web window. This follows the settled [overlay behavior](overlay-window-display-input-accessibility.md), [quality requirements](quality-attributes-and-failure-invariants.md), [local-first boundary](local-first-privacy-security-boundary.md), and [Host-navigation contract](host-navigation-capabilities.md).

The frozen [Parity Baseline inventory](parity-baseline-inventory.md) and its [original evidence](../../../VIBE_ISLAND_FUNCTIONALITY.md) make this a native window-management problem as well as a UI problem. The release history includes focus theft, hover loops, wrong-display behavior, Settings-level errors, Accessibility crashes, CJK shortcut failures, and repeated sleep/wake crashes. The [product defaults](product-direction-defaults.md) also set direct Developer ID/notarized distribution and permit a constrained application-owned helper/background item only where it is needed.

## Platform findings

- [NSPanel](https://developer.apple.com/documentation/appkit/nspanel), its [nonactivating panel style](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel), [window levels](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct), and explicit [collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) give AppKit the required overlay control. The [can-join-all-Spaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces) and [full-screen auxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary) flags are presentation choices, not public Space identity or targeting APIs.
- [NSScreen](https://developer.apple.com/documentation/appkit/nsscreen) and [screen-parameter change notification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification) cover display observation. Product policy still requires selected-display loss to withdraw, not migrate, the Overlay.
- [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement) supports only the explicitly optional, best-effort Host-window fallback. AX labels, geometry, and Spaces cannot become durable Host Context identity. Agent Island's own standard AppKit accessibility tree does not require this permission.
- A registered global shortcut is narrower than global keyboard observation. Apple's [event-monitoring guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) distinguishes local and global monitors. Request input monitoring only for a separately justified capability, never ordinary shortcuts, content capture, keylogging, simulated input, or clipboard monitoring.
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) is the supported macOS 13+ launch-at-login/helper registration surface. [XPC](https://developer.apple.com/documentation/foundation/xpc) is suitable for an authenticated local process boundary when a helper materially reduces Adapter blast radius. It is not a privileged helper.
- [Keychain Services](https://developer.apple.com/documentation/security/keychain-services) can retain the per-installation encryption key. SQLite is appropriate for the canonical local store, but Apple SQLite is not encrypted: use application-layer authenticated encryption or a vetted [SQLCipher](https://www.zetetic.net/sqlcipher/) build. Key, ciphertext, schema, and classification failure must fail closed.
- [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) covers notification authorization/delivery. [NSWorkspace sleep](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification) and [wake](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification) notifications support the cold-resume boundary: revalidate, do not replay.
- [XCTest](https://developer.apple.com/documentation/xctest) is the native unit/UI-test substrate. Direct distribution is feasible with Developer ID, hardened runtime, and notarization under Apple's [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). TCC grants remain person-controlled and must be tested in the signed/notarized build.

## Requirements matrix

**Strong** means a direct, supported fit. **Conditional** means native bridge/custom work or a material compromise. **Weak** means a poor fit for this baseline. Every cell assumes the settled privacy and capability gates.

| Requirement | SwiftUI app + AppKit Overlay bridge | AppKit-first shell + SwiftUI views | Mac Catalyst | Electron / Tauri web wrapper |
| --- | --- | --- | --- | --- |
| Non-activating Overlay, levels, visible-only hit/AX region | **Strong**, but an AppKit-owned panel must supply the behavior. SwiftUI alone is insufficient. | **Strong**; window delegate and hit-test lifecycle are first-class. | **Weak**; UIKit/Catalyst does not expose the necessary AppKit panel/level model. | **Conditional**; window-level APIs or native extensions do not provide the required panel behavior without an AppKit shell. |
| Multi-display, notch, Spaces, full screen | **Strong** through AppKit; implement selected-display withdrawal. | **Strong**; clearest control of screen, collection behavior, and restoration. | **Conditional** for ordinary scenes; weak for the specified Overlay policy. | **Conditional**; browser abstractions do not remove the macOS-specific lifecycle work. |
| Agent Island AX and optional AX Host fallback | **Strong** for native controls and AX APIs. | **Strong**; direct AX tree/focus control is safest. | **Conditional**; UIKit AX is sound, but Host AX/window semantics remain platform-specific. | **Conditional**; web accessibility is not a substitute for macOS AX/window behavior. |
| Global shortcuts and input monitoring | **Strong** with AppKit/Carbon/Core Graphics, TCC- and capability-gated. | **Strong**; same APIs with less bridge lifecycle. | **Conditional**; standard shortcuts work, but input/overlay integration is awkward. | **Conditional**; Electron [globalShortcut](https://www.electronjs.org/docs/latest/api/global-shortcut) and Tauri native integration still require TCC/IME validation. |
| Hooks, local helper, authenticated IPC | **Strong** via Swift actors plus optional XPC/local socket. | **Strong**; natural owner for helper lifecycle and Adapter isolation. | **Conditional**; possible, without a benefit over AppKit. | **Conditional**; Node/Rust sidecars add a content-bearing IPC/runtime boundary. |
| SQLite, encryption, Keychain, migrations | **Strong** with a Swift repository and proven encrypted store. | **Strong**; same implementation. | **Strong** technically, but no offsetting windowing benefit. | **Conditional**; plug-ins can do it, but bridge serialization expands classification/test surface. |
| Login item, notifications, sound, sleep/wake | **Strong** via ServiceManagement, UserNotifications, AVFoundation/AppKit, and NSWorkspace. | **Strong**; direct delegate ownership simplifies termination ordering. | **Conditional**; basic support exists, difficult lifecycle remains indirect. | **Conditional**; basic APIs exist, but lifecycle and permissions cross runtime bridges. |
| Deterministic core and UI/AX testing | **Strong** if core reducers/store/adapters are pure Swift. | **Strong**; injected screen/AX/permission ports and panel tests are most direct. | **Conditional**; does not test the intended panel mechanism. | **Conditional**; web tests do not prove native focus, TCC, Spaces, or AX without a second macOS suite. |
| Developer ID signing and notarization | **Strong**; standard Xcode path. | **Strong**; standard Xcode path. | **Strong**, but it does not solve the product gap. | **Conditional**; helpers/addons and WebView/Node/Rust supply chains add signing/notarization surface. |
| Idle memory, energy, launch targets | **Strong** in principle; measure under the 30-session workload. | **Strong** and lowest-runtime-overhead candidate; measure. | **Conditional**; UIKit compatibility layer adds indirection. | Electron is **Weak** because Chromium/Node is mismatched to the idle budget; Tauri is **Conditional** but still adds web runtime/rendering. |
| Future Adapter/service seams | **Strong** using versioned Swift protocols/actors and classified ports. | **Strong**; clear UI/core/Adapter/store/service boundaries. | **Conditional**; technically possible, no benefit. | **Conditional**; RPC isolation risks untyped content copying and does not solve the native overlay. |

## Viable shortlist

### 1. AppKit-first shell with SwiftUI hosted content/settings

An AppKit application delegate/coordinator owns the Island Overlay panel, display selection, level/collection behavior, hit testing, keyboard engagement, menu/termination, sleep/wake, global-shortcut lifecycle, and optional AX/XPC boundaries. SwiftUI is hosted for Horizon rows, focused/expanded content, and the Settings sidebar/content; use an AppKit control only when a SwiftUI abstraction cannot prove focus or AX behavior.

This is the strongest fit: it isolates hard macOS behavior from visual implementation while retaining SwiftUI productivity. Its cost is explicit responder-chain and state synchronization work. The core must not live in views; it should expose typed main-actor projections from a non-UI event/store domain.

### 2. SwiftUI application with an AppKit-owned Overlay bridge

SwiftUI owns application lifecycle, Settings, and most presentation, while an AppKit coordinator owns a panel that hosts a SwiftUI root view. It is viable only if that bridge—not SwiftUI scene defaults—owns panel activation, collection behavior, display withdrawal, visible-shape hit testing, and AX/focus cleanup.

It reduces AppKit surface area but makes the bridge critical infrastructure. Keep it in the shortlist only if the Overlay spike passes its required behavior matrix.

### 3. Mac Catalyst: technically native, not viable here

[Mac Catalyst](https://developer.apple.com/documentation/uikit/mac_catalyst) is a good route for conventional UIKit applications. This product's differentiator is a macOS-specific non-activating auxiliary panel, not cross-platform UI reuse. Catalyst would compromise the Overlay contract or need an AppKit bridge large enough to erase its value. Do not shortlist it.

### 4. Electron or Tauri: honest alternatives, not recommended

Electron [BrowserWindow](https://www.electronjs.org/docs/latest/api/browser-window) can be always-on-top, and Tauri offers [window customization](https://v2.tauri.app/learn/window-customization/) and [Rust invocation](https://v2.tauri.app/develop/calling-rust/). They suit cross-platform or web-first products, but do not make the required AppKit panel, Host AX, TCC, display/Space, and cold-resume behaviors first-class. Achieving the requirements needs native code for every hard case and duplicates state/privacy boundaries across runtimes. Electron also conflicts with the idle memory/energy posture; Tauri is lighter but provides no benefit once AppKit owns the Overlay and sensitive integration work. Neither belongs on the shortlist.

## Stack-independent seams

Preserve these boundaries whichever native candidate is selected:

- **Core/store:** pure replay-safe reducer and versioned SQLite repository; opaque identifiers, immutable facts, classified projections, and encrypted material behind a storage port.
- **Agent Adapter:** per-Product capability negotiation, hook/app-server intake, health, Action Lease dispatch, and reconciliation behind typed local ports. Parse/classify before records cross into core.
- **Host:** independently revalidated Host Context locator and Jump Back result; never a view-model title or AX frame. Accessibility is a capability-local fallback.
- **Presentation:** a main-actor projection emits Overlay intents; the panel can render, suppress, or withdraw them but cannot create Product truth or replay an action.
- **Process/egress:** optional application-owned XPC helper only for a measured isolation/reliability need. Future service ports remain classified, explicit, local-first, and outbound-only under [ADR 0001](../../../docs/adr/0001-local-canonical-state-and-consent-gated-egress.md).

These preserve the capability-local degradation and live-locator boundaries in [ADR 0002](../../../docs/adr/0002-versioned-capability-scoped-adapter-boundary.md), [ADR 0004](../../../docs/adr/0004-live-host-context-locators-and-honest-navigation.md), and [ADR 0007](../../../docs/adr/0007-nonactivating-island-overlay-and-independent-settings.md).

## Necessary technical spikes

Only two spikes are warranted; the rest is ordinary implementation/release verification.

1. **Native Overlay behavior spike — selection gate.** Build a disposable AppKit panel with a hosted SwiftUI view and run OW-1, OW-3/4, OW-8–10, OW-12–15 on built-in and external displays. Prove no Host focus theft, visible-shape-only hit and AX regions, deliberate keyboard engagement/release, selected-display withdrawal, full-screen/Space behavior without a Space claim, and cold wake recovery. This discriminates the two native variants.
2. **Protected-store distribution spike — release-feasibility gate.** In a Developer-ID-signed, hardened, notarized test app, create/migrate/reopen a small encrypted SQLite store whose key is in Keychain. Exercise absent key, corrupt ciphertext, schema migration failure, and redacted diagnostics. Prove fail-closed recovery and no sensitive logs. This closes the uncertainty Keychain alone cannot solve.

No Catalyst, Electron, or Tauri prototype is justified: their mismatch is architectural, not unanswered feasibility. Global shortcuts, login item, notifications, optional helper/XPC, and Host AX belong in the native acceptance suite; add a helper only after an Adapter proves a real reliability or security need.

## Recommendation for downstream selection

Carry **AppKit-first shell with SwiftUI hosted content/settings** and **SwiftUI lifecycle with an AppKit-owned Overlay bridge** as the only two native candidates. Rank the AppKit-first form first because it directly owns the difficult window/input/AX lifecycle. Reject Mac Catalyst and web wrappers for this baseline; revisit only if the destination expands to cross-platform clients. The downstream selection ticket should choose between the two native variants after the Overlay spike, set measured memory/energy budgets from the 30-session workload, and record its durable choice in its own ADR.
