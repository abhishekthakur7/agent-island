# AB-136 — Codex CLI reviewed Hooks-contract observation

This evidence is intentionally limited to independently launched Codex CLI
terminal sessions. It is observation-only: there is no app-server control,
Action Lease, callback response, terminal injection, or text reply path. The
event-qualified TOML in the fixture is a reviewed `hooks-v1` adapter contract,
not evidence that a live arbitrary Codex installation accepts that grammar;
any version/interface mismatch is non-mutating and requires manual setup.

| Acceptance area | Deterministic evidence | Result | Notes |
| --- | --- | --- | --- |
| Independent lifecycle, tool/compact, permission, child fixtures | `Fixtures/CodexCLIAdapter/independent-lifecycle.json`, `testIndependentLifecycleFixtureNormalizesEveryDocumentedHook` | authored | Exact native session IDs and source cursors are retained; permission is a Host/Jump Back cue only. |
| Reordered, concurrent, gap, duplicate reduction | `reorder-gap-duplicates.json`, `testAdapterRequiresSourceStartBaselineAndExactTerminalRedelivery`, `testSourceOrderGapAndReorderingRemainUnresolved` | authored | A source `SessionStart` at sequence 1 is the only local baseline. Stop-first, a gap, and reordering deliver non-exhaustive reconciliation only; a withheld terminal requires exact redelivery after continuity. |
| Bounded authenticated intake and quarantine | `testQuarantineRejectsUntrustedInputWithoutDeliveryOrReplayState`, `testReplayDuplicateMalformedOversizedAndDisabledAreQuarantined` | authored | Malformed, unknown, oversized, cross-owner, duplicate, replay, disabled, and unauthenticated input produce a redacted quarantine outcome and no delivery. |
| Protected content and redaction | `testClassifiedContentNeverLeaksIntoFactsOrUnconsentedOutput` | authored | Only explicit prompt/command scalar content crosses the protected boundary after local opt-in; raw envelopes, IDs, facts, health diagnostics, notifications, and exports receive none. |
| Health/degradation | `testHealthNeverClaimsTerminalAndCoversDegradation` | authored | Disabled, helper loss/timeout, duplicate definition, drift, unsupported version/interface narrow health only and retain native Host fallback. |
| Exact reversible selected-scope installation | `configuration-contract.json`, `testFreshPlanApprovalApplyVerifyAndExactRemovalPreserveTOML`, `testHelperContractPathSafetyAndApplyRollbackFailClosed`, `testUnprovenRuntimeContractNeverPlansOrApplies`, `testDiscoveryExaminesEveryOwnedHookSelector` | authored | A private 0700 bootstrap exports exact owner identity and immutable observation-only mode before executing `CodexHookHelper`. The manifest proves it; changed/symlinked helpers and unproven helper credential/receiver contracts fail closed; rollback removes a newly created launcher when config apply fails. Discovery scans every owned hook selector; TOML comments/profile fields remain preserved. Generic `notify` is never used as a lifecycle hook. |
| Manual K-mode S1–S6/A6 capture | reviewed Codex terminal | pending | Native Host / Jump Back fallback until a reviewed live capture exists. |

## Verification

- `cd src && swift test --filter CodexCLIAdapterTests` — attempted; the
  command-line-tools XCTest resolution result is recorded with the commit.
- `cd src && swift build` — recorded with the commit.
- `cd src && Scripts/self-check.sh` — recorded with the commit.
- `git diff --check c14388b5236d323ccdd5cbfc94906ef547d620c7..HEAD` — recorded with the repair commit.

## K-mode / degraded parity matrix

| Cell | Evidence | Honest fallback |
| --- | --- | --- |
| K-mode S1 independent start | authored fixture | Native Host / Jump Back |
| K-mode S2 prompt/activity | authored fixture | Native Host / Jump Back |
| K-mode S3 tool + compaction | authored fixture | Native Host / Jump Back |
| K-mode S4 permission cue | authored fixture | Native Host / Jump Back; no response control |
| K-mode S5 child hierarchy | authored fixture | Native Host / Jump Back |
| K-mode S6 source stop | authored fixture | unresolved on missing ordering/evidence |
| A6 action parity | intentionally unavailable | Native Host only |
| reordering/gap/duplicate/helper loss/drift | authored fixture/tests | unresolved/degraded local projection; manual exact-entry remedy |
