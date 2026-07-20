# AB-134 — Claude Code documented Hooks observation

This is an evidence template. `authored` means a deterministic fixture or
source inspection exists; it is not a claim of a live Claude Code install,
manual UI observation, or XCTest execution. Empty rows remain pending.

| Acceptance area | Deterministic fixture / command | Capture or inspection | Result | Notes |
| --- | --- | --- | --- | --- |
| Read-only discovery, fresh reviewed exact-entry plan/apply/verify/removal | `ClaudeCodeAdapterTests`, `ClaudeCodeInstallationCoordinator` | authored | authored | Existing lossless exact-entry coordinator is reused. Nested `settings.json`/JSONC, symlink, policy, and unsupported formatting fail closed with a manual remedy; no synthetic JSON line is written. |
| Enabled intent separate from observed health | `ClaudeCodeAdapter.setEnabledIntent`, `ClaudeIntegrationHealth` | authored | authored | Runtime disablement never removes external setup. |
| Reviewed version/capability negotiation | `ClaudeHooksVersionEvidence`, adapter negotiation fixture | authored | authored | Unknown/new/unsupported executable or interface evidence narrows observation/configuration; no optimistic compatibility. |
| Authenticated bounded local IPC | HMAC fixture and nonce-window/replay checks | authored | authored | HMAC covers installation/helper/nonce/timestamp/body; constant-time comparison; malformed/oversized/replayed/cross-owner input is rejected without raw diagnostics. |
| Concurrent sessions, activity, Stop/background, StopFailure/PermissionDenied, SessionEnd | `ClaudeHookNormalizer` fixtures | authored | authored | Native Claude session ID is the only identity. Stop with background work stays waiting; SessionEnd is cleanup/boundary and never completion proof. |
| Notification cue without action authority | Notification fixture | authored | authored | Cue is observation-only; no Action Lease, Action Attempt, generic action, or simulated input. |
| AskUserQuestion / ExitPlanMode protected observation | question/plan fixtures | authored | authored | Choices are ordinal semantic IDs; prompt/option/plan bytes remain protected Interaction Content. Unsupported free-text/revision semantics fail to Host fallback. |
| PermissionRequest / PreToolUse protected context | hook fixtures | authored | authored | Context is classified and session/request-owned; transcript paths are not read or displayed. |
| Exact parented SubagentStart/Stop | nested child fixtures | authored | authored | Child start is not blocked; terminal child requires source stop/result evidence. |
| ConfigChange, helper probe/loss, policy/drift/health reconciliation | health and installation fixtures | authored | authored | No auto-repair/adoption; IPC loss emits unresolved observation boundary and Host fallback. |
| Diagnostic redaction | `ClaudeIntegrationHealth.redactedDiagnostic`, redaction tests | authored | authored | Closed diagnostics contain only capability/health reason codes; no prompts, plan text, paths, identifiers, raw payloads, credentials, or command syntax. |
| Manual Claude Code run / parity capture | macOS manual run and C-mode S1–S6/I5/I8 matrix | pending | pending | No manual evidence is claimed in this change; capture on a target machine with the reviewed Claude executable. |

## Verification

- `cd src && swift build` — passed on 2026-07-20 (macOS 27 SDK; existing
  command-line-tool linker warnings remain).
- `cd src && Scripts/self-check.sh` — passed on 2026-07-20 (existing
  headless canonical-store scenarios).
- `cd src && swift test --filter ClaudeCodeAdapterTests` — authored tests are
  present; current command-line-only environment cannot resolve XCTest.
- `git diff --check` — passed on 2026-07-20.

## Parity/degraded matrix

| Cell | Evidence status | Honest fallback |
| --- | --- | --- |
| C-mode S1–S6 | pending manual capture | Native Claude Host |
| I5 / I8 | pending manual capture | Native Claude Host; no action claim |
| Unknown/new version | authored | Inspect/update executable and re-probe |
| Missing/shadowed/drifted/policy hook | authored | Manual exact-entry remedy; preserve bytes |
| Helper/IPC loss or hook miss | authored | Degraded/unresolved local projection; Native Host |
