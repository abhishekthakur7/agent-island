# 08 — Manage Integration Installations without owning external configuration

## What to build

Deliver a safe end-to-end configuration lifecycle for one selected Agent Adapter mode: read-only discovery, an explicit Integration Installation, a fresh reviewable plan, person approval, lossless exact-entry application, verification, health update, and manifest-proven repair/removal outcomes. The app changes only configuration and artifacts it can prove it created; it must make drift, ambiguity, policy, and lossy syntax visible instead of “fixing” them.

This is the configuration ownership vertical slice behind Atlas Integrations. It does not adopt external setup, alter Product data or permissions, or make a configuration success claim without verification.

## Context and constraints

- An Integration Installation is one explicit, reversible Adapter mode at one selected scope. It is not an Agent Product or Agent Session.
- The Ownership Manifest proves only exact marked entries and application-owned artifacts. It never owns a whole Product config file/directory/profile/repository or a similar external entry.
- Selected scope defaults to user-level. Project/Worktree/repository/custom-path choices are advanced, clearly scoped, and require explicit person selection; discovery does not recursively scan.
- Every enable/repair/migrate/disable/remove mutation is installation-locked, fresh-plan approved, revalidated immediately before apply, lossless, and post-write verified. A stale plan is discarded/regenerated.
- Preserve comments, order, unknown fields, formatting, symlinks, permissions, external edits, and unrelated configuration. Do not parse-and-reserialize a whole document; unsupported/lossy/ambiguous representations are non-mutating.

## Acceptance criteria

- [ ] A person can inspect a selected documented scope read-only and see Not configured, Owned intact, Owned drifted, External candidate, Shadowed/managed, Unsupported, or Unavailable without Agent Island enabling, adopting, or changing anything.
- [ ] Enabling creates a reviewable plan that names selected scope, exact entries/artifacts, compatibility, permissions, affected capabilities, rollback/manual remedy, and explicit non-effects (including Product permissions, credentials, unrelated hooks/extensions, Product sessions, and unselected repository configuration).
- [ ] Immediately before mutation, the application takes the Installation-scoped lock and revalidates source fingerprint, symlink target, Product/version/policy, and ownership. A changed condition expires the plan without a write.
- [ ] Successful apply writes only a losslessly selected, manifest-marked entry/artifact and verifies by rereading/probing. The resulting Ownership Manifest records exact selectors, scope, protected local location/fingerprint facts, artifact receipts, versions, verification evidence, and lifecycle state without retaining whole config contents, credentials, or arbitrary command lines.
- [ ] External drift, duplicate/ambiguous ownership, unknown/lossy syntax, symlink retargeting, policy precedence, failed probe, or interrupted write produces an inspectable Degraded/Unavailable/partial state with repair or manual remedy; it never silently rewrites, adopts, deletes, or works around policy.
- [ ] Disable stops runtime I/O and enabled intent without removing setup. Remove setup deletes only currently manifest-proven exact entries/artifacts after a fresh plan and verification; it reports removed, partial-with-residual, or not-removed accurately.
- [ ] No lifecycle operation deletes Agent Product data, whole configuration roots, credentials, unowned extensions/hooks, worktrees, or another Integration Installation’s records.

## Required evidence

- Plan/approval/apply/verify recording for one selected integration, including manifest evidence and resulting health/capability update.
- Configuration fixtures covering comments/unknown fields, custom path, symlink, external edit, duplicate/external candidate, malformed/lossy syntax, policy precedence, version change, interrupted write/migration, and exact-entry residual removal.
- Negative audit showing all non-effects in the approved plan remained untouched and no mutation happened for stale/ambiguous/lossy/policy-blocked cases.
- Redacted Diagnostics/Atlas capture for intact, drifted, partial residual, and unavailable states.

## Blocked by

- 07 — Negotiate Adapter capabilities and expose honest integration health
