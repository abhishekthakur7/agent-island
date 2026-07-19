// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AgentIsland",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SessionDomain", targets: ["SessionDomain"]),
        .library(name: "AdapterPort", targets: ["AdapterPort"]),
        .library(name: "PresentationPort", targets: ["PresentationPort"]),
        .library(name: "SessionStore", targets: ["SessionStore"]),
        .library(name: "ApplicationRuntime", targets: ["ApplicationRuntime"]),
        .library(name: "AdapterFixtureKit", targets: ["AdapterFixtureKit"]),
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

        // Single-writer canonical fact ledger and deterministic projection
        // cache. Depends only on the domain; no port or UI may reach it.
        .target(name: "SessionStore", dependencies: ["SessionDomain"]),

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
            ]
        ),

        .testTarget(name: "SessionDomainTests", dependencies: ["SessionDomain"]),
        .testTarget(name: "SessionStoreTests", dependencies: ["SessionDomain", "SessionStore"]),
        .testTarget(
            name: "ApplicationRuntimeTests",
            dependencies: ["SessionDomain", "AdapterPort", "PresentationPort", "SessionStore", "ApplicationRuntime", "AdapterFixtureKit"]
        ),
        .testTarget(
            name: "PresentationRuntimeTests",
            dependencies: ["SessionDomain", "PresentationPort", "PresentationRuntime"]
        ),
    ]
)
