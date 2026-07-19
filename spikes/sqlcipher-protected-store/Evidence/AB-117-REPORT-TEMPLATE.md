# AB-117 — SQLCipher protected-store feasibility evidence

**Status:** `OWNER ACCEPTED WITH WAIVERS`  
**Decision:** `GO FOR IMPLEMENTATION`  
**Spike revision / captured date:** `[value]`

This template is evidence, not a claimed result. The SwiftPM pure-core tests
do not prove encryption, Keychain behavior, atomicity, app signing, or
notarization. Do not mark this gate `GO` until every applicable row has raw
artifacts from a clean supported Mac.

## Owner decision — 2026-07-19

The owner approved this disposable spike and authorized production
implementation to proceed. Developer ID signing, notarization, and
full-Xcode-only test execution are outside the personal-use local baseline.
SQLCipher/Keychain and other `NOT RUN` rows remain unverified implementation
risks; this approval does not represent them as passing evidence.

## Pre-approval local validation outcome (2026-07-19)

**Incomplete on this host; subsequently accepted as implementation risk.** The available Command Line Tools Swift build
can compile the spike but links `/usr/lib/libsqlite3.dylib`; the runner rejects
it with `storage.sqlcipher_unavailable`. `swift test --filter StorageCoreTests`
is also blocked because this host lacks the XCTest framework supplied by full
Xcode. `pkg-config sqlcipher`, a SQLCipher dylib, a Developer ID Application
identity, and notarization credentials are unavailable. Consequently the
clean-launch, signing, notarization, performance, and all integration rows
below remain `NOT RUN`; no unit/build result is a feasibility pass. The owner
decision above waives these as prerequisites without changing their evidence
status.

| Proof | Command / evidence | Result |
| --- | --- | --- |
| SQLCipher, not Apple SQLite | `pkg-config --modversion sqlcipher`; app runtime codec check; `otool -L` shows bundled `@rpath/libsqlcipher.dylib` | `NOT RUN` |
| Per-install Keychain key | clean launch creation/reopen; missing-key output `storage.keychain_key_missing` and unchanged DB SHA-256 | `NOT RUN` |
| Ciphertext at rest | raw first 16 bytes are not `SQLite format 3`; retain hash only, never a DB copy | `NOT RUN` |
| Durable atomic write/restart | two fresh executable processes, JSON projection digest equality | `NOT RUN` |
| Staged migration | v1 source validate → v2 stage validate → atomic promote → reopened integrity check; capture logs | `NOT RUN` |
| Fail-closed recovery | corrupt bytes, interrupted `.staging`, unknown schema, integrity and migration failures preserve source bytes and report redacted code | `NOT RUN` |
| Deterministic rebuild | 30-record fixture digest `7d4db561e017f26875e7893cf64fa3ec459c376aac7b3d9deae7a0fd25942530` | `NOT RUN` |
| Diagnostics redaction | output contains operation/code/schema only—no path, key, SQL, or record payload | `NOT RUN` |
| Developer ID hardened signing | `codesign --verify --deep --strict`; nested bundled dylib signature | `NOT RUN` |
| Notarization / stapling | `notarytool` accepted, `stapler validate`, online/offline clean launch | `NOT RUN` |

## 30-record benchmark and budget report

Run `Scripts/build.sh`, then invoke the bundled executable with `--benchmark`
against a new storage root at least 20 times, recording raw JSON and the
machine/power state. This fixture is generic spike evidence only and is not a
production Agent Session schema.

| Metric | Feasibility guardrail, not a release budget | Result |
| --- | --- | --- |
| 30-record bootstrap + verified encrypted write | p95 `< 250 ms` on stated supported hardware | `NOT RUN` |
| 30-record cold verified open + deterministic rebuild | p95 `< 150 ms` | `NOT RUN` |
| Migration v1 → v2 and verified reopen | p95 `< 500 ms` | `NOT RUN` |
| DB size / RSS / CPU | report min/median/p95/max and tool; no unbounded growth across 20 runs | `NOT RUN` |

State the count, min/median/p95/max, exclusions, device, OS, Swift/Xcode,
SQLCipher version, power state, and raw artifact locations. Missing optional
distribution tooling is recorded as `NOT RUN`, not pass.
