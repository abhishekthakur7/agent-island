# AB-147 DR checklist

This checklist turns the five frozen review decisions into auditable release
questions. A checked deterministic seam is not a substitute for a required
human/native capture. Current overall status: **BLOCKED**.

| Decision | Requirement and audit evidence | Current result | Required completion evidence |
| --- | --- | --- | --- |
| DR-01 original identity | Preserve the original Product-native Agent Session/Turn/Attention identity and source ordering. See `S-01`, `S-02`, `I-02`, `src/Fixtures/AB146Workload/workload-v1.json`, and `src/Fixtures/CodexCLIAdapter/reorder-gap-duplicates.json`. No title/model/Host inference may join work. | Deterministic seam evidenced; live multi-Product review absent. | Redacted capture mapping displayed rows to source-proven identities without Interaction Content; include duplicate/gap result. |
| DR-02 no active cleanup | History is only for safely inactive work. Attention, active child work, restart/wake loss, and Host loss stay current/unresolved. See `H-01`, `O-01`, `AB146WorkloadTests`, and `AB145RecoveryTests`. | Deterministic seam evidenced; rendered History/recovery capture absent. | Record 31st inactive archive plus 31 attention/child rows; capture restart/wake and confirm no active work disappears. |
| DR-03 native Host fallback | Unsupported, unavailable, degraded, or unactionable capability names an available Native Host next step. See all `A`, `J`, and `H-02` rows. | Documented fallback strings; accessible/native observation absent. | Keyboard and VoiceOver observation that fallback is visible, spoken, reachable, and does not activate/drive the Host automatically. |
| DR-04 achieved navigation | Jump Back reports only `exactSurface`, `exactTab`, `workspaceOrFile`, `windowBestEffort`, `appOnly`, or `unavailable` after current evidence. See `J-01…J-04` and ADR 0004. | Fixtures/read-only Orca probe; live execution capture absent. | Record exact iTerm2, Cursor, Warp degraded, and Orca tab cases; include stale/restart/duplicate negative and achieved wording. |
| DR-05 sourced-or-unavailable usage | Usage Snapshot is display-only Provider data from an available Adapter capability; it never estimates billing/quota. See `H-02`, `UsagePresentationTests`, and AB-137 schema evidence. | Test seam only; live source/absence capture absent. | Capture one sourced value with redacted provider/provenance and one missing capability rendering “Usage unavailable.” |

## Reviewer disposition

- Structural checks: `PASS` when `Scripts/verify-ab-147.sh --structure-only`
  exits `0`.
- Release disposition: **do not mark AB-147 Done** while any row above lacks
  its required evidence. The normal verifier returns `2` to make that state
  machine-visible.
- Follow-up route: use the recommendations in the [gap log](gap-log.md) with
  the repository’s `ready-for-human` triage vocabulary for human capture work.
