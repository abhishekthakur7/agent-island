import AdapterPort
import ClaudeCodeAdapter
import CodexCLIAdapter
import CursorHooksAdapter
import Foundation
import LocalProductDiscovery
import SessionDomain

/// The bounded launch-time exception defined by ADR 0009. It may add a new,
/// exact user-scope hook installation, but never adopts, repairs, migrates, or
/// removes configuration that it cannot prove with its durable manifest.
actor LaunchIntegrationAutoInstaller {
    private let port: any AdapterIntakePort
    private let claudeActionLifecycle: ClaudeActionIntegrationLifecycle
    private let detector: any ProductInstallationIdentityVerifying
    private let router = HookObservationAdapterRouter()
    private lazy var observations = HookObservationProductionComposition(router: router)
    private let credentialStore = DerivedClaudeHookCredentialStore()
    private var claudeAdapter: ClaudeCodeAdapter?
    private var codexAdapter: CodexCLIAdapter?
    private let homeDirectory: URL
    private let publish: @MainActor @Sendable (AtlasIntegrationKind, LaunchInstallationReport) -> Void
    private var launchTask: Task<Void, Never>?
    private var stopping = false

    init(
        port: any AdapterIntakePort,
        claudeActionLifecycle: ClaudeActionIntegrationLifecycle,
        detector: any ProductInstallationIdentityVerifying,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        publish: @escaping @MainActor @Sendable (AtlasIntegrationKind, LaunchInstallationReport) -> Void
    ) {
        self.port = port
        self.claudeActionLifecycle = claudeActionLifecycle
        self.detector = detector
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.publish = publish
    }

    func start() {
        guard launchTask == nil, !stopping else { return }
        launchTask = Task { _ = await runOnce() }
    }

    /// Person-initiated re-run of the same bounded, fail-closed install pass.
    /// Identical pipeline to launch — including the code-signature identity
    /// gate — so it never installs into an unverifiable Product; it only runs
    /// on explicit request instead of at launch, and returns the per-product
    /// outcome so a person-facing surface can show it. `applicationSupport`
    /// overrides the durable-state root for isolated verification.
    func installOnRequest(applicationSupport: URL? = nil) async -> [AtlasIntegrationKind: LaunchInstallationReport] {
        await runOnce(applicationSupport: applicationSupport)
    }

    func stop() {
        stopping = true
        launchTask?.cancel()
        launchTask = nil
        observations.stopAll()
    }

    @discardableResult
    private func runOnce(applicationSupport: URL? = nil) async -> [AtlasIntegrationKind: LaunchInstallationReport] {
        var reports: [AtlasIntegrationKind: LaunchInstallationReport] = [:]
        do {
            let store = try DurableInstallationStore(applicationSupportDirectory: applicationSupport)
            // Keep the descriptor alive across every async phase. A second
            // app process cannot interleave recovery, bootstrap, or writes.
            let processLock = try DurableInstallationLock(url: store.directory.appendingPathComponent(".installation.lock"))
            _ = processLock
            let unresolved = try store.journals().filter { $0.phase != .completed && $0.phase != .rolledBack }
            guard unresolved.isEmpty else {
                for kind in AtlasIntegrationKind.allCases {
                    reports[kind] = .refused("An interrupted integration transaction requires review before configuration can change.")
                    await publish(kind, reports[kind]!)
                }
                return reports
            }
            for completed in try store.journals() { try store.removeJournal(transactionID: completed.transactionID) }
            for product in DurableInstallationProduct.allCases {
                guard !Task.isCancelled, !stopping else { return reports }
                let outcome = await install(product, store: store)
                reports[product.atlasKind] = outcome
                await publish(product.atlasKind, outcome)
            }
        } catch {
            for kind in AtlasIntegrationKind.allCases {
                reports[kind] = .failed("Launch integration state is unavailable; no hook configuration was changed.")
                await publish(kind, reports[kind]!)
            }
        }
        return reports
    }

    private func install(_ product: DurableInstallationProduct, store: DurableInstallationStore) async -> LaunchInstallationReport {
        let productCLI = product.productCLI
        guard case .verified(let identity) = await detector.verifyInstallationIdentity(product: productCLI, explicitPath: nil) else {
            return .refused("The installed product could not be trusted for automatic hook setup.")
        }
        guard detector.revalidateInstallationIdentity(identity) == .valid else {
            return .refused("The product executable changed during launch detection.")
        }

        do {
            let target = try UserInstallationConfigurationResolver(homeDirectory: homeDirectory).resolve(for: product)
            let configURL = target.url
            try ensurePrivateParent(of: configURL)
            let installationID = IntegrationInstanceID("agent-island-\(product.rawValue)-user-v1")
            let executable = try resolveBundledHelper(named: product.helperExecutableName)
            let helperPath = try helperLauncherPath(for: product, store: store)
            let helperID = product.helperID(for: helperPath)
            let secret = try credential(for: installationID, helperID: helperID)
            let authenticator = ClaudeIPCAuthenticator(secret: secret)
            guard authenticator.isUsable else { throw LaunchInstallationError.credentialUnavailable }

            let snapshot = try await configureRuntime(
                product: product,
                version: identity.version,
                installationID: installationID,
                helperID: helperID,
                helperPath: helperPath,
                executable: executable,
                authenticator: authenticator
            )
            try probeHelper(product: product, executable: executable, installationID: installationID, helperID: helperID)
            guard detector.revalidateInstallationIdentity(identity) == .valid else {
                throw LaunchInstallationError.productChanged
            }

            if let durable = try store.manifest(installationID: installationID.rawValue),
               let ownership = durable.ownershipManifest {
                guard durable.configurationPath == configURL.path,
                      ownership.installationID == installationID.rawValue,
                      durable.verifiedProductIdentity == identity,
                      launcherIsExact(product: product, installationID: installationID, helperID: helperID, executable: executable, at: helperPath) else {
                    throw LaunchInstallationError.ownedStateDrifted
                }
                let exact = verifyExisting(product: product, manifest: ownership, helperPath: helperPath, snapshot: snapshot)
                guard exact.status == .applied else { throw LaunchInstallationError.ownedStateDrifted }
                if product == .claude {
                    let installation = IntegrationInstallation(id: installationID, product: ownership.product, integrationMode: ownership.integrationMode, scope: ownership.scope, manifestID: ownership.id, lifecycle: .enabled, enabledIntent: true, capabilities: ownership.verification?.capabilityIDs ?? [])
                    guard await claudeActionLifecycle.activate(installation: installation, manifest: ownership, helperID: helperID, snapshot: snapshot, credentialStore: credentialStore) else {
                        throw LaunchInstallationError.contractUnavailable
                    }
                }
                await enable(product: product)
                return .installed(snapshot, alreadyInstalled: true)
            }

            let transactionID = UUID().uuidString
            try store.saveJournal(.init(
                transactionID: transactionID,
                installationID: installationID.rawValue,
                phase: .prepared,
                configurationPath: configURL.path
            ))
            let launcherExisted = FileManager.default.fileExists(atPath: helperPath.path)
            var configurationWritten = false
            do {
                try provisionLauncher(product: product, installationID: installationID, helperID: helperID, executable: executable, at: helperPath)
                guard detector.revalidateInstallationIdentity(identity) == .valid else { throw LaunchInstallationError.productChanged }
                let result = try applyNew(
                    product: product,
                    version: identity.version,
                    installationID: installationID,
                    helperPath: helperPath,
                    configURL: configURL,
                    snapshot: snapshot
                )
                guard result.status == .applied, let ownership = result.manifest else {
                    throw LaunchInstallationError.configurationRefused(result.reason)
                }
                configurationWritten = true
                if product == .claude, let installation = result.installation {
                    guard await claudeActionLifecycle.activate(installation: installation, manifest: ownership, helperID: helperID, snapshot: snapshot, credentialStore: credentialStore) else {
                        throw LaunchInstallationError.contractUnavailable
                    }
                }
                try store.saveJournal(.init(transactionID: transactionID, installationID: installationID.rawValue, phase: .configWritten, configurationPath: configURL.path, configurationDigest: ownership.verification?.sourceFingerprint.content?.rawValue))
                try store.saveManifest(.init(
                    installationID: installationID.rawValue,
                    product: product,
                    configurationPath: configURL.path,
                    managedEntryIdentifiers: ownership.entries.map(\.selector.key),
                    ownershipManifest: ownership,
                    verifiedProductIdentity: identity
                ))
                try store.saveJournal(.init(transactionID: transactionID, installationID: installationID.rawValue, phase: .completed, configurationPath: configURL.path))
                try store.removeJournal(transactionID: transactionID)
                await enable(product: product)
                return .installed(snapshot, alreadyInstalled: false)
            } catch {
                if configurationWritten {
                    // The config has a complete exact-entry receipt in the
                    // in-memory result, but durable commit failed. Preserve
                    // both config and launcher and retain a recovery journal;
                    // deleting either would create an unreceipted broken hook.
                    try? store.saveJournal(.init(transactionID: transactionID, installationID: installationID.rawValue, phase: .configWritten, configurationPath: configURL.path))
                    throw LaunchInstallationError.recoveryRequired
                }
                // Coordinators remove exact entries they inserted when apply
                // fails. Remove only a launcher this transaction created.
                if !launcherExisted { try? removeLauncherIfExact(product: product, installationID: installationID, helperID: helperID, executable: executable, at: helperPath) }
                try? store.saveJournal(.init(transactionID: transactionID, installationID: installationID.rawValue, phase: .rolledBack, configurationPath: configURL.path))
                try? store.removeJournal(transactionID: transactionID)
                throw error
            }
        } catch LaunchInstallationError.configurationRefused(let reason) {
            return .refused("Existing or unsupported hook configuration was left unchanged (\(reason?.rawValue ?? "not safe to mutate")).")
        } catch LaunchInstallationError.ownedStateDrifted {
            return .refused("Agent Island's owned hook entries changed; automatic repair was refused.")
        } catch {
            return .failed("Automatic hook setup could not complete; configuration was left unchanged or rolled back.")
        }
    }

    private func configureRuntime(
        product: DurableInstallationProduct,
        version: String,
        installationID: IntegrationInstanceID,
        helperID: String,
        helperPath: URL,
        executable: URL,
        authenticator: ClaudeIPCAuthenticator
    ) async throws -> NegotiationSnapshot {
        try observations.start(product.observationProduct)
        let outcome: NegotiationOutcome
        switch product {
        case .claude:
            let adapter = ClaudeCodeAdapter(port: port, integrationInstanceID: installationID, helperID: helperID, authenticator: authenticator)
            claudeAdapter = adapter
            router.register(claude: adapter)
            outcome = await adapter.negotiate(version: .init(productVersion: version, executablePath: nil, support: .known))
        case .codex:
            let adapter = CodexCLIAdapter(port: port, integrationInstanceID: installationID, helperID: helperID, authenticator: authenticator)
            codexAdapter = adapter
            router.register(codex: adapter)
            outcome = await adapter.negotiate(version: .init(productVersion: version, documentedHooksAvailable: true))
        case .cursor:
            let evidence = CursorHooksContractEvidence(productVersion: version, observedAt: Date())
            let adapter = CursorHooksAdapter(port: port, integrationInstanceID: installationID, helperID: helperID, authenticator: authenticator, evidence: evidence)
            router.register(cursor: CursorHooksReceiver(adapter: adapter))
            outcome = await adapter.negotiate()
        }
        guard case .compatible(let snapshot) = outcome else { throw LaunchInstallationError.contractUnavailable }
        return snapshot
    }

    private func applyNew(product: DurableInstallationProduct, version: String, installationID: IntegrationInstanceID, helperPath: URL, configURL: URL, snapshot: NegotiationSnapshot) throws -> IntegrationInstallationApplyResult {
        let scope = IntegrationInstallationScope(kind: .user, identifier: "user", path: configURL)
        let planID = "launch-\(product.rawValue)-\(UUID().uuidString)"
        switch product {
        case .claude:
            let coordinator = ClaudeCodeInstallationCoordinator(helperExecutablePath: try resolveBundledHelper(named: product.helperExecutableName).path)
            let discovery = coordinator.discover(installationID: installationID, scope: scope, helperPath: helperPath, snapshot: snapshot)
            guard discovery.state == .notConfigured, discovery.safeToMutate else { throw LaunchInstallationError.configurationRefused(discovery.inspection.reason) }
            let plan = coordinator.makePlan(id: planID, installationID: installationID, scope: scope, helperPath: helperPath, snapshot: snapshot)
            return coordinator.apply(try coordinator.approve(plan, personIdentifier: "automatic-launch-policy:ADR-0009"), currentSnapshot: snapshot, helperPath: helperPath)
        case .codex:
            return try applyCodexJSON(installationID: installationID, helperPath: helperPath, configURL: configURL, snapshot: snapshot)
        case .cursor:
            let evidence = CursorHooksContractEvidence(productVersion: version, observedAt: Date())
            let coordinator = CursorHooksInstallationCoordinator(runtimeContract: CursorProvisionedHookRuntimeContract(credentialStore: credentialStore, endpoint: endpoint(for: product), executablePath: helperPath.path))
            let discovery = coordinator.discover(installationID: installationID, scope: scope, helperPath: helperPath, evidence: evidence)
            guard discovery.state == .notConfigured, discovery.safeToMutate else { throw LaunchInstallationError.configurationRefused(discovery.inspection.reason) }
            let plan = coordinator.makePlan(id: planID, installationID: installationID, scope: scope, helperPath: helperPath, evidence: evidence)
            return coordinator.apply(coordinator.approve(plan, personIdentifier: "automatic-launch-policy:ADR-0009"), helperPath: helperPath, evidence: evidence)
        }
    }

    private func verifyExisting(product: DurableInstallationProduct, manifest: OwnershipManifest, helperPath: URL, snapshot: NegotiationSnapshot) -> IntegrationInstallationApplyResult {
        switch product {
        case .claude:
            return ClaudeCodeInstallationCoordinator().discover(installationID: .init(manifest.installationID), scope: manifest.scope, helperPath: helperPath, manifest: manifest, snapshot: snapshot).state == .ownedIntact ? .init(status: .applied, manifest: manifest) : .init(status: .degraded, reason: .sourceChanged)
        case .codex:
            let entries = codexEntries(helperPath: helperPath)
            let exact = manifest.product == CodexCLIIntegration.productNamespace && manifest.sourcePath == manifest.scope.path && entries.allSatisfy { entry in
                ClaudeJSONHookEditor.inspect(at: manifest.scope.url, entry: entry).exactMatches == 1 && manifest.proving(entry.selector, at: manifest.sourcePath) != nil
            }
            return exact ? .init(status: .applied, manifest: manifest) : .init(status: .degraded, reason: .sourceChanged)
        case .cursor:
            return CursorHooksInstallationCoordinator(runtimeContract: CursorProvisionedHookRuntimeContract(credentialStore: credentialStore, endpoint: endpoint(for: product), executablePath: helperPath.path)).verify(manifest, helperPath: helperPath)
        }
    }

    private func enable(product: DurableInstallationProduct) async {
        // Adapters begin disabled so a socket alone cannot create sessions.
        // The exact durable installation is the enabling boundary.
        switch product {
        case .claude: _ = await claudeAdapter?.setEnabledIntent(true)
        case .codex: await codexAdapter?.setEnabledIntent(true)
        case .cursor: break
        }
    }

    private func codexEntries(helperPath: URL) -> [ClaudeJSONHookEditor.Entry] {
        CodexHookName.allCases.filter { $0 != .activity }.map { event in
            let marker = "agent-island:codex-hooks-observation:v1:\(event.rawValue)"
            let quotedPath = "'" + helperPath.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let command = quotedPath + " # " + marker
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let rendered = "{\"hooks\":[{\"type\":\"command\",\"command\":\"\(escaped)\"}]}"
            let selector = ExactEntrySelector(key: "codex-hooks-\(event.rawValue)", renderedLine: rendered, marker: marker)
            return ClaudeJSONHookEditor.Entry(selector: selector, event: event.rawValue, helperPath: helperPath.path)
        }
    }

    private func applyCodexJSON(installationID: IntegrationInstanceID, helperPath: URL, configURL: URL, snapshot: NegotiationSnapshot, now: Date = Date()) throws -> IntegrationInstallationApplyResult {
        guard configURL.lastPathComponent == "hooks.json", configURL.path.hasSuffix("/.codex/hooks.json"),
              snapshot.productNamespace == CodexCLIIntegration.productNamespace,
              snapshot.grants(WellKnownCapability.configuration, direction: .configure),
              case .success = endpoint(for: .codex).validate(),
              credentialStore.secret(for: installationID, helperID: CodexCLIIntegration.helperID(for: helperPath))?.isEmpty == false
        else { throw LaunchInstallationError.configurationRefused(.unsupported) }
        let entries = codexEntries(helperPath: helperPath)
        let inspections = entries.map { ClaudeJSONHookEditor.inspect(at: configURL, entry: $0) }
        guard inspections.allSatisfy({ $0.supported && $0.markerMatches == 0 && $0.exactMatches == 0 }) else {
            throw LaunchInstallationError.configurationRefused(.ambiguous)
        }
        var receipts: [(ExactEntryReceipt, String)] = []
        var expected = inspections.first?.source.fingerprint ?? ExactEntryEditor.snapshot(at: configURL).fingerprint
        do {
            for entry in entries {
                let receipt = try ClaudeJSONHookEditor.add(entry: entry, at: configURL, expected: expected, now: now)
                receipts.append((receipt, entry.event))
                expected = ExactEntryEditor.snapshot(at: configURL).fingerprint
            }
        } catch {
            var rollbackExpected = ExactEntryEditor.snapshot(at: configURL).fingerprint
            for (receipt, event) in receipts.reversed() {
                if let removed = try? ClaudeJSONHookEditor.remove(receipt: receipt, event: event, at: configURL, expected: rollbackExpected, now: now) {
                    rollbackExpected = removed.sourceFingerprint
                }
            }
            throw error
        }
        let source = ExactEntryEditor.snapshot(at: configURL)
        guard let launcherFingerprint = ExactEntryEditor.snapshot(at: helperPath).fingerprint.content else {
            throw LaunchInstallationError.helperUnavailable
        }
        let scope = IntegrationInstallationScope(kind: .user, identifier: "user", path: configURL)
        let manifest = OwnershipManifest(
            id: "launch-codex-\(UUID().uuidString)-manifest",
            installationID: installationID.rawValue,
            product: CodexCLIIntegration.productNamespace,
            integrationMode: CodexCLIIntegration.integrationMode,
            scope: scope,
            sourcePath: configURL.path,
            entries: receipts.map(\.0),
            artifacts: [.init(path: helperPath.path, kind: .generatedFile, fingerprint: launcherFingerprint, createdAt: now)],
            productVersion: snapshot.productVersion,
            interfaceVersion: snapshot.interfaceVersion,
            verification: .init(verifiedAt: now, reread: true, probeSucceeded: true, sourceFingerprint: source.fingerprint, capabilityIDs: [CodexCLIIntegration.observationCapability]),
            createdAt: now,
            updatedAt: now
        )
        return .init(status: .applied, manifest: manifest, installation: .init(id: installationID, product: manifest.product, integrationMode: manifest.integrationMode, scope: scope, manifestID: manifest.id, lifecycle: .enabled, enabledIntent: true, capabilities: [CodexCLIIntegration.observationCapability]))
    }

    private func credential(for installationID: IntegrationInstanceID, helperID: String) throws -> Data {
        // The secret is derived deterministically from the installation/helper
        // identity, so both the app and the separate helper binary recompute it
        // identically with no Keychain access and no cross-process ACL prompt.
        guard let secret = credentialStore.secret(for: installationID, helperID: helperID), !secret.isEmpty else {
            throw LaunchInstallationError.credentialUnavailable
        }
        return secret
    }

    private func probeHelper(product: DurableInstallationProduct, executable: URL, installationID: IntegrationInstanceID, helperID: String) throws {
        let process = Process()
        process.executableURL = executable
        var environment = [
            "AGENT_ISLAND_INSTALLATION_ID": installationID.rawValue,
            "AGENT_ISLAND_HELPER_ID": helperID,
            "PATH": "/usr/bin:/bin",
            "AGENT_ISLAND_HELPER_PROBE": "1",
        ]
        let payload: Data
        switch product {
        case .claude:
            payload = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"agent-island-probe\",\"event_id\":\"agent-island-probe\",\"sequence\":1}".utf8)
        case .codex:
            environment["AGENT_ISLAND_CODEX_OBSERVATION_ONLY"] = "1"
            payload = Data("{\"hook_event_name\":\"SessionStart\",\"session_id\":\"agent-island-probe\",\"event_id\":\"agent-island-probe\",\"sequence\":1}".utf8)
        case .cursor:
            environment["AGENT_ISLAND_CURSOR_OBSERVATION_ONLY"] = "1"
            // A deliberately unsupported version proves helper -> derived
            // credential -> authenticated socket delivery without a live session.
            payload = Data("{\"hook_event_name\":\"sessionStart\",\"conversation_id\":\"agent-island-probe\",\"generation_id\":\"agent-island-probe\",\"cursor_version\":\"0.0.0\"}".utf8)
        }
        process.environment = environment
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: payload)
        try input.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(10_000) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw LaunchInstallationError.helperUnavailable
        }
    }

    private func endpoint(for product: DurableInstallationProduct) -> ClaudeLocalEndpoint {
        ClaudeLocalEndpoint(path: observations.appOwnedRoot.appendingPathComponent(product.observationProduct.socketFileName), appOwnedRoot: observations.appOwnedRoot)
    }

    private func helperLauncherPath(for product: DurableInstallationProduct, store: DurableInstallationStore) throws -> URL {
        let directory = store.directory.appendingPathComponent("helpers", isDirectory: true)
        // The app-owned helpers directory persists across launches and is
        // shared by every product's install pass, so its creation must be
        // idempotent. Creating it unconditionally throws EEXIST on the second
        // product and on every relaunch, which previously failed the whole
        // install before any adapter could be enabled. Mirror the check-then-
        // create idiom used by `ensurePrivateParent`; re-assert 0o700 either way.
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        }
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: directory.path)
        return directory.appendingPathComponent("\(product.rawValue)-hook")
    }

    private func resolveBundledHelper(named name: String) throws -> URL {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: name), FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        #if DEBUG
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name), FileManager.default.isExecutableFile(atPath: executable.path) { return executable }
        #endif
        throw LaunchInstallationError.helperUnavailable
    }

    private func ensurePrivateParent(of config: URL) throws {
        let parent = config.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: NSNumber(value: 0o700)])
        }
    }

    private func provisionLauncher(product: DurableInstallationProduct, installationID: IntegrationInstanceID, helperID: String, executable: URL, at path: URL) throws {
        let expected = product.bootstrap(installationID: installationID, helperID: helperID, executable: executable)
        if FileManager.default.fileExists(atPath: path.path) {
            guard try Data(contentsOf: path) == expected else { throw LaunchInstallationError.ownedStateDrifted }
            return
        }
        try expected.write(to: path, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: path.path)
    }

    private func removeLauncherIfExact(product: DurableInstallationProduct, installationID: IntegrationInstanceID, helperID: String, executable: URL, at path: URL) throws {
        guard try Data(contentsOf: path) == product.bootstrap(installationID: installationID, helperID: helperID, executable: executable) else { return }
        try FileManager.default.removeItem(at: path)
    }

    private func launcherIsExact(product: DurableInstallationProduct, installationID: IntegrationInstanceID, helperID: String, executable: URL, at path: URL) -> Bool {
        guard let status = try? POSIXFileSafety.lstat(path), POSIXFileSafety.isRegularFile(status),
              !POSIXFileSafety.isSymlink(status), status.st_uid == POSIXFileSafety.currentUserID,
              POSIXFileSafety.mode(status) == 0o700,
              let bytes = try? Data(contentsOf: path) else { return false }
        return bytes == product.bootstrap(installationID: installationID, helperID: helperID, executable: executable)
    }
}

public enum LaunchInstallationReport: Sendable {
    case installed(NegotiationSnapshot, alreadyInstalled: Bool)
    case refused(String)
    case failed(String)
}

private enum LaunchInstallationError: Error {
    case credentialUnavailable
    case helperUnavailable
    case contractUnavailable
    case productChanged
    case ownedStateDrifted
    case recoveryRequired
    case configurationRefused(ExactEntryFailureReason?)
}

private extension InstallationConfigurationTarget {
    var url: URL { switch self { case .existing(let url), .missing(let url): url } }
}

private extension DurableInstallationProduct {
    var atlasKind: AtlasIntegrationKind { switch self { case .claude: .claudeCode; case .codex: .codexCLI; case .cursor: .cursor } }
    var productCLI: ProductCLI { switch self { case .claude: .claudeCode; case .codex: .codexCLI; case .cursor: .cursor } }
    var observationProduct: HookObservationProduct { switch self { case .claude: .claude; case .codex: .codex; case .cursor: .cursor } }
    var helperExecutableName: String { switch self { case .claude: "ClaudeHookHelper"; case .codex: "CodexHookHelper"; case .cursor: "CursorHookHelper" } }
    func helperID(for path: URL) -> String { switch self { case .claude: ClaudeCodeIntegration.helperID(for: path); case .codex: CodexCLIIntegration.helperID(for: path); case .cursor: CursorHooksIntegration.helperID(for: path) } }
    func bootstrap(installationID: IntegrationInstanceID, helperID: String, executable: URL) -> Data {
        switch self {
        case .claude: return ClaudeCodeIntegration.helperBootstrap(installationID: installationID, helperID: helperID, executablePath: executable.path)
        case .codex: return CodexCLIIntegration.helperBootstrap(installationID: installationID, helperID: helperID, executablePath: executable.path)
        case .cursor:
            let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            return Data("#!/bin/sh\nset -eu\nexport AGENT_ISLAND_INSTALLATION_ID=\(quote(installationID.rawValue))\nexport AGENT_ISLAND_HELPER_ID=\(quote(helperID))\nexport AGENT_ISLAND_CURSOR_OBSERVATION_ONLY=1\nexec \(quote(executable.path))\n".utf8)
        }
    }
}
