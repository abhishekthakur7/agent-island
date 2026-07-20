// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AgentIsland",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SessionDomain", targets: ["SessionDomain"]),
        .library(name: "AdapterPort", targets: ["AdapterPort"]),
        .library(name: "ServiceEgressPort", targets: ["ServiceEgressPort"]),
        .library(name: "PresentationPort", targets: ["PresentationPort"]),
        .library(name: "SessionStore", targets: ["SessionStore"]),
        .library(name: "ProtectedStore", targets: ["ProtectedStore"]),
        .library(name: "ApplicationRuntime", targets: ["ApplicationRuntime"]),
        .library(name: "AdapterFixtureKit", targets: ["AdapterFixtureKit"]),
        .library(name: "ClaudeCodeAdapter", targets: ["ClaudeCodeAdapter"]),
        .library(name: "ClaudeActionRouting", targets: ["ClaudeActionRouting"]),
        .executable(name: "ClaudeHookHelper", targets: ["ClaudeHookHelper"]),
        .library(name: "PresentationRuntime", targets: ["PresentationRuntime"]),
        .executable(name: "AgentIslandApp", targets: ["AgentIslandApp"]),
    ],
    targets: [
        // Pure domain: identity, envelope validation, negotiation rules, the
        // replay-safe reducer, and projection types. No SwiftUI, AppKit,
        // SQLite, XPC, clocks, random IDs, or Adapter/Host implementations.
        .target(name: "SessionDomain"),

        // Typed inward port an Adapter (or fixture) enters through. It never
        // exposes the canonical store or a database/key handle.
        .target(name: "AdapterPort", dependencies: ["SessionDomain"]),

        // Typed port the UI subscribes through for revisioned projections.
        .target(name: "PresentationPort", dependencies: ["SessionDomain"]),

        // One-way, future-only Service Egress boundary.  It deliberately
        // depends on the classified domain contract only; it cannot import
        // SessionStore, ProtectedStore, AdapterPort, or presentation code.
        .target(name: "ServiceEgressPort", dependencies: ["SessionDomain"]),

        // Single-writer canonical fact ledger and deterministic projection
        // cache. Depends only on the domain; no port or UI may reach it.
        .target(name: "SessionStore", dependencies: ["SessionDomain", "ProtectedStore"]),

        // Deliberately supplied by Homebrew/pkg-config rather than silently
        // falling back to Apple's unencrypted libsqlite3 (AB-119/ADR 0008).
        .systemLibrary(
            name: "SQLCipher",
            pkgConfig: "sqlcipher",
            providers: [.brew(["sqlcipher"])]
        ),

        // The encrypted, per-installation-Keychain-keyed canonical store.
        // Only `SessionStore` may hold a `ProtectedStore` handle; it is the
        // single writer per ADR 0008/0001.
        .target(name: "ProtectedStore", dependencies: ["SessionDomain", "SQLCipher"]),

        // Intake orchestration: implements AdapterPort inbound and
        // PresentationPort outbound, the only component allowed to hold the
        // SessionStore reference.
        .target(
            name: "ApplicationRuntime",
            dependencies: ["SessionDomain", "AdapterPort", "PresentationPort", "SessionStore"]
        ),

        // Controllable first-party Adapter fixture. Deliberately depends on
        // AdapterPort + SessionDomain only, so it cannot hold a store/key
        // handle or bypass validation even if misused.
        .target(name: "AdapterFixtureKit", dependencies: ["SessionDomain", "AdapterPort"]),

        // Documented Claude Code Hooks observation boundary. The adapter is
        // deliberately outer-only: it may enter through AdapterPort but never
        // receives a SessionStore, ProtectedStore, Product action client, or
        // transcript reader.
        .target(name: "ClaudeCodeAdapter", dependencies: ["SessionDomain", "AdapterPort"]),

        // Composition bridge; the adapter itself remains unable to reach the
        // canonical store or keep callback data durably.
        .target(name: "ClaudeActionRouting", dependencies: ["ClaudeCodeAdapter", "SessionDomain", "SessionStore"]),

        // Application-owned documented-hook helper. It has no Product action,
        // transcript, or store dependency; it only validates stdin and sends
        // authenticated bounded frames through the local IPC abstraction.
        .executableTarget(name: "ClaudeHookHelper", dependencies: ["ClaudeCodeAdapter", "SessionDomain"]),

        // Main-actor projection subscriber. Depends on PresentationPort +
        // SessionDomain only, so it cannot call an Adapter/Product client or
        // the canonical store directly.
        .target(name: "PresentationRuntime", dependencies: ["SessionDomain", "PresentationPort"]),

        // AppKit-first shell hosting SwiftUI presentation content. The
        // composition root wires concrete ApplicationRuntime instances; the
        // views themselves only ever see PresentationRuntime and the fixture
        // controller's typed AdapterPort-scoped surface.
        .executableTarget(
            name: "AgentIslandApp",
            dependencies: [
                "SessionDomain",
                "AdapterPort",
                "ApplicationRuntime",
                "AdapterFixtureKit",
                "PresentationRuntime",
                "ProtectedStore",
            ]
        ),

        .testTarget(name: "SessionDomainTests", dependencies: ["SessionDomain"]),
        .testTarget(name: "ServiceEgressPortTests", dependencies: ["SessionDomain", "ServiceEgressPort"]),
        .testTarget(name: "SessionStoreTests", dependencies: ["SessionDomain", "SessionStore", "ProtectedStore"]),
        .testTarget(name: "ProtectedStoreTests", dependencies: ["SessionDomain", "ProtectedStore"]),
        .testTarget(
            name: "ApplicationRuntimeTests",
            dependencies: ["SessionDomain", "AdapterPort", "PresentationPort", "SessionStore", "ApplicationRuntime", "AdapterFixtureKit"]
        ),
        .testTarget(
            name: "PresentationRuntimeTests",
            dependencies: ["SessionDomain", "PresentationPort", "PresentationRuntime"]
        ),
        .testTarget(
            name: "AgentIslandAppTests",
            dependencies: ["AgentIslandApp", "SessionStore"]
        ),
        .testTarget(
            name: "ClaudeCodeAdapterTests",
            dependencies: ["ClaudeCodeAdapter", "SessionDomain", "AdapterPort", "SessionStore", "ApplicationRuntime"]
        ),
        .testTarget(name: "ClaudeActionRoutingTests", dependencies: ["ClaudeActionRouting", "ClaudeCodeAdapter", "SessionDomain", "SessionStore"]),
    ]
)
