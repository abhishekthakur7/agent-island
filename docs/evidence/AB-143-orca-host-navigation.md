# AB-143 Orca Host Jump Back evidence

Private implementation namespace only; no package or application composition registration has been made.

The adapter consumes Orca's documented JSON CLI boundary: `status`, `terminal show`, `terminal switch`, `worktree show`, `file open`, and `open`. It never invokes terminal send/stop/create/split/close/rename or any Product action.

Fixtures cover a version-matched opaque terminal/tab, optional explicit child-surface proof, runtime restart, connection loss, duplicate metadata, incompatible navigation capability, and independently reproven worktree/file fallback. The self-check is intentionally unregistered pending shared composition ownership.

Private validation completed: Swift 6 type-check of the adapter/tests against the current `SessionDomain` build artifact, plus the unregistered `AB143SelfCheck` linked against a temporary private adapter module. This is not application reachability evidence.

A read-only probe against the installed current Orca CLI successfully decoded `status` plus `terminal show` into the typed runtime/handle/tab evidence. It did not send a terminal switch or any terminal/Product control command.

Registration validation: `orca --help` and subcommand help confirm the production vocabulary is limited to documented `terminal show`, `terminal switch`, `worktree show`, `file open`, and `open` (plus `status`). The installed runtime exposes `runtimeId` but no semantic `runtimeVersion`, so the adapter uses the opaque current runtime ID as the strict live-runtime/version discriminator. Its current `terminal show` response does not explicitly prove a selected child surface; therefore production Jump Back can honestly reach `exactTab` through `terminal switch`, never `exactSurface`, unless a future current documented response adds that proof. Package/app registration, `swift build --product AgentIslandApp`, and `AB143SelfCheck` completed successfully.
