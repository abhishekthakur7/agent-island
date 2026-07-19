// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SQLCipherProtectedStoreSpike",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SQLCipherProtectedStoreSpike", targets: ["SQLCipherProtectedStoreSpike"])
    ],
    targets: [
        // Deliberately supplied by Homebrew/pkg-config rather than silently
        // falling back to Apple's unencrypted libsqlite3.
        .systemLibrary(
            name: "SQLCipher",
            pkgConfig: "sqlcipher",
            providers: [.brew(["sqlcipher"])]
        ),
        .target(name: "StorageCore"),
        .target(name: "SQLCipherStore", dependencies: ["StorageCore", "SQLCipher"]),
        .executableTarget(name: "SQLCipherProtectedStoreSpike", dependencies: ["StorageCore", "SQLCipherStore"]),
        .testTarget(name: "StorageCoreTests", dependencies: ["StorageCore"])
    ]
)
