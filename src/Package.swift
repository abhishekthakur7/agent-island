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
        .library(name: "CodexCLIAdapter", targets: ["CodexCLIAdapter"]),
        .library(name: "CodexAppServerAdapter", targets: ["CodexAppServerAdapter"]),
        .library(name: "CursorHooksAdapter", targets: ["CursorHooksAdapter"]),
        .library(name: "CursorACPAdapter", targets: ["CursorACPAdapter"]),
        .library(name: "ITerm2HostAdapter", targets: ["ITerm2HostAdapter"]),
        .library(name: "CursorHostAdapter", targets: ["CursorHostAdapter"]),
        .library(name: "WarpHostAdapter", targets: ["WarpHostAdapter"]),
        .library(name: "OrcaHostAdapter", targets: ["OrcaHostAdapter"]),
        .library(name: "ClaudeActionRouting", targets: ["ClaudeActionRouting"]),
        .library(name: "LocalProductDiscovery", targets: ["LocalProductDiscovery"]),
        .executable(name: "ClaudeHookHelper", targets: ["ClaudeHookHelper"]),
        .executable(name: "CodexHookHelper", targets: ["CodexHookHelper"]),
        .executable(name: "CursorHookHelper", targets: ["CursorHookHelper"]),
        .executable(name: "AB138SelfCheck", targets: ["AB138SelfCheck"]),
        .executable(name: "AB139SelfCheck", targets: ["AB139SelfCheck"]),
        .executable(name: "AB140SelfCheck", targets: ["AB140SelfCheck"]),
        .executable(name: "AB141SelfCheck", targets: ["AB141SelfCheck"]),
        .executable(name: "AB142SelfCheck", targets: ["AB142SelfCheck"]),
        .executable(name: "AB143SelfCheck", targets: ["AB143SelfCheck"]),
        .executable(name: "AB144SelfCheck", targets: ["AB144SelfCheck"]),
        .executable(name: "AB145SelfCheck", targets: ["AB145SelfCheck"]),
        .executable(name: "AB146SelfCheck", targets: ["AB146SelfCheck"]),
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

        // Codex CLI documented-hook observation is a separate Product
        // boundary. It reuses only the authenticated one-way hook transport
        // and exact-entry ownership primitives, never Claude action routing.
        .target(name: "CodexCLIAdapter", dependencies: ["SessionDomain", "AdapterPort", "ClaudeCodeAdapter"]),

        // AB-137 is a deliberately separate, child-process stdio boundary.
        // It has no dependency on Hooks or Claude action routing.
        .target(name: "CodexAppServerAdapter", dependencies: ["SessionDomain", "AdapterPort", "SessionStore", "LocalProductDiscovery"]),

        // Cursor's documented v1 command hooks are observation-only here.
        // The shared lossless JSON/JSONC editor and one-way IPC primitives are
        // reused without importing an action-routing target.
        .target(name: "CursorHooksAdapter", dependencies: ["SessionDomain", "AdapterPort", "ClaudeCodeAdapter"]),

        // AB-139's ACP client has only the typed inward port. In particular,
        // it cannot import SessionStore or ProtectedStore.
        .target(name: "CursorACPAdapter", dependencies: ["SessionDomain", "AdapterPort"]),

        // iTerm2 navigation is a Host-only outer boundary. It talks only to
        // the documented iTerm2 Python API bridge and exposes the typed
        // HostNavigationPort; it has no Product action or store dependency.
        .target(
            name: "ITerm2HostAdapter",
            dependencies: ["SessionDomain"],
            resources: [.process("Resources")]
        ),

        // Cursor exact navigation is available only through the connected
        // extension-owned live-terminal endpoint; no terminal metadata or UI
        // automation enters this Host boundary.
        .target(name: "CursorHostAdapter", dependencies: ["SessionDomain"]),

        // Warp provides only NSWorkspace application activation plus an
        // explicit, transient Accessibility best-effort window election.
        // It has no Product action, store, URL grammar, or input dependency.
        .target(name: "WarpHostAdapter", dependencies: ["SessionDomain"]),

        // Orca navigation uses only the documented CLI runtime's typed JSON
        // status/show/switch and independently proven worktree/file routes.
        // It cannot send input or perform terminal lifecycle/Product actions.
        .target(name: "OrcaHostAdapter", dependencies: ["SessionDomain"]),

        // Composition bridge; the adapter itself remains unable to reach the
        // canonical store or keep callback data durably.
        .target(name: "ClaudeActionRouting", dependencies: ["ClaudeCodeAdapter", "SessionDomain", "SessionStore"]),

        // Read-only local evidence for documented Agent Product CLI locations.
        // This target has no store, adapter, or presentation dependency.
        .target(name: "LocalProductDiscovery"),

        // Application-owned documented-hook helper. It has no Product action,
        // transcript, or store dependency; it only validates stdin and sends
        // authenticated bounded frames through the local IPC abstraction.
        .executableTarget(name: "ClaudeHookHelper", dependencies: ["ClaudeCodeAdapter", "SessionDomain"]),

        // Codex has a separate executable so its observation launcher cannot
        // reach Claude's synchronous action/callback branch.
        .executableTarget(name: "CodexHookHelper", dependencies: ["CodexCLIAdapter", "ClaudeCodeAdapter", "SessionDomain"]),

        .executableTarget(name: "CursorHookHelper", dependencies: ["CursorHooksAdapter", "ClaudeCodeAdapter", "SessionDomain"]),
        .executableTarget(name: "AB138SelfCheck", dependencies: ["CursorHooksAdapter", "ClaudeCodeAdapter", "ApplicationRuntime", "SessionStore", "SessionDomain"]),
        .executableTarget(name: "AB139SelfCheck", dependencies: ["CursorACPAdapter", "ApplicationRuntime", "SessionStore", "SessionDomain", "ProtectedStore"]),
        .executableTarget(name: "AB140SelfCheck", dependencies: ["ITerm2HostAdapter", "SessionDomain"]),
        .executableTarget(name: "AB141SelfCheck", dependencies: ["CursorHostAdapter", "SessionDomain"]),
        .executableTarget(name: "AB142SelfCheck", dependencies: ["WarpHostAdapter", "SessionDomain"]),
        .executableTarget(name: "AB143SelfCheck", dependencies: ["OrcaHostAdapter", "SessionDomain"]),
        .executableTarget(name: "AB144SelfCheck", dependencies: ["SessionDomain", "ClaudeCodeAdapter"]),
        .executableTarget(name: "AB145SelfCheck", dependencies: ["SessionDomain", "ApplicationRuntime", "SessionStore", "ProtectedStore", "AdapterFixtureKit"]),
        .executableTarget(name: "AB146SelfCheck", dependencies: ["SessionDomain", "ApplicationRuntime", "SessionStore", "PresentationRuntime"]),

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
                "ClaudeActionRouting",
                "ClaudeCodeAdapter",
                "CodexCLIAdapter",
                "CursorHooksAdapter",
                "LocalProductDiscovery",
                "CursorACPAdapter",
                "ITerm2HostAdapter",
                "CursorHostAdapter",
                "WarpHostAdapter",
                "OrcaHostAdapter",
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
            name: "AB146WorkloadTests",
            dependencies: ["SessionDomain", "SessionStore", "ApplicationRuntime"]
        ),
        .testTarget(
            name: "AgentIslandAppTests",
            dependencies: ["AgentIslandApp", "SessionDomain", "SessionStore", "ClaudeActionRouting", "ClaudeCodeAdapter", "CodexCLIAdapter", "CursorHooksAdapter"]
        ),
        .testTarget(
            name: "ClaudeCodeAdapterTests",
            dependencies: ["ClaudeCodeAdapter", "SessionDomain", "AdapterPort", "SessionStore", "ApplicationRuntime"]
        ),
        .testTarget(name: "CodexCLIAdapterTests", dependencies: ["CodexCLIAdapter", "SessionDomain", "AdapterPort", "ClaudeCodeAdapter"]),
        .testTarget(name: "CodexAppServerAdapterTests", dependencies: ["CodexAppServerAdapter", "SessionDomain", "AdapterPort", "SessionStore"]),
        .testTarget(name: "CursorHooksAdapterTests", dependencies: ["CursorHooksAdapter", "SessionDomain", "AdapterPort", "SessionStore", "ApplicationRuntime", "ClaudeCodeAdapter"]),
        .testTarget(name: "CursorACPAdapterTests", dependencies: ["CursorACPAdapter", "SessionDomain", "AdapterPort", "SessionStore", "ApplicationRuntime"]),
        .testTarget(name: "ITerm2HostAdapterTests", dependencies: ["ITerm2HostAdapter", "SessionDomain"]),
        .testTarget(name: "CursorHostAdapterTests", dependencies: ["CursorHostAdapter", "SessionDomain"]),
        .testTarget(name: "WarpHostAdapterTests", dependencies: ["WarpHostAdapter", "SessionDomain"]),
        .testTarget(name: "OrcaHostAdapterTests", dependencies: ["OrcaHostAdapter", "SessionDomain"]),
        .testTarget(name: "ClaudeActionRoutingTests", dependencies: ["ClaudeActionRouting", "ClaudeCodeAdapter", "SessionDomain", "SessionStore"]),
        .testTarget(name: "LocalProductDiscoveryTests", dependencies: ["LocalProductDiscovery"]),
    ]
)
