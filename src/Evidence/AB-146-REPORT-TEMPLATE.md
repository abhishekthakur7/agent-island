# AB-146 — 30-session responsiveness and resource envelope

## Automated evidence

Run from `src`:

```sh
Scripts/verify-ab-146.sh
```

The verifier creates `Evidence/AB-146-run-<timestamp>/` with the versioned
fixture hash, machine environment, headless local timing trace, process sample,
and open-handle capture. A valid headless timing or open-handle miss exits
non-zero. Missing privileged energy/wakeup data is explicitly
`measurement-unavailable`, never a pass.

The headless self-check proves these local invariants:

- 30 distinct Product-native Agent Session owners across four Product/Adapter/
  Host profiles; active, waiting, completed, unresolved gap, child, attention,
  rewind, compaction, duplicate, ordinary-event, selection/scroll fixture
  coverage, and source-proven recap/history inputs;
- a safely inactive 31st Session moves losslessly to Session History with its
  two facts and recap inspectable;
- an all-active/all-attention/child-active set reaches 31 with no archive;
- duplicate suppression and gap ambiguity do not cross owners or manufacture a
  terminal state; restart boundary makes nonterminal work unresolved; and
- local receipt-to-revisioned-presentation and a single controllable local
  Adapter handoff satisfy their 250 ms and 150 ms gates.

It does not claim a pixel render, VoiceOver operation, Product application, or
real energy result. Those are separate native evidence below.

## Measured headless numeric resource budget

Source: [`AB-146-NATIVE-BUDGET.txt`](AB-146-NATIVE-BUDGET.txt), derived from
`AB-146-run-20260720-224609` on Apple Silicon `Mac15,6`. The workload fixture
defines the derivation rule: `ceil(max RSS/handles × 1.5)` and
`max CPU × 1.5 + 0.1`. Later valid samples above these values are
`valid-over-target`, release-blocking; the verifier retains every raw sample.
This is a headless 30-session harness budget, not a claim about the native
Overlay process until the native capture cells below are complete.

| Metric | Budget | Required capture |
| --- | ---: | --- |
| Local event → correct revisioned visual/AX state | <250 ms | timestamp trace |
| Confirmed action → one Adapter handoff | <150 ms | correlation trace |
| Warm usable launch | <1,000 ms | native Overlay/recovery capture |
| Cold usable launch | <2,000 ms | native Overlay/integrity capture |
| Resident memory | ≤19 MB | repeated headless process series |
| Idle CPU | ≤2.8% | repeated headless process series |
| Loaded CPU | ≤152.8% | repeated headless process series |
| Open handles | ≤15 | repeated `lsof` series |
| Disk growth / equivalent run | unverified | protected-store directory series |
| Retained tasks/timers / audio outputs | 0 / 0 | task/sound lifetime capture |
| Wakeups | unverified | Energy Log or authorized powermetrics |

## Native evidence matrix (must be completed on supported hardware)

| Cell | Capture path | Result / correlation | Status |
| --- | --- | --- | --- |
| Built-in display: 30 rows, selection, compact scroll | screenshot + AX tree + keyboard traversal |  | unverified |
| External display: same workload | screenshot + AX tree + VoiceOver |  | unverified |
| Accessibility: enlarged text, contrast/transparency, Reduce Motion | screen recording + VoiceOver traversal |  | unverified |
| History: 31st archive, recap inspection | screenshot + redacted fact count |  | unverified |
| All attention/child-active overflow | screenshot showing 31 current rows |  | unverified |
| Cold/warm launch integrity/recovery | timestamp + stale lease/locator evidence |  | unverified |
| Repeated restart/wake and display change | diagnostic correlation + screenshot |  | unverified |
| Extended idle + sound release | Instruments Energy/Leaks + audio lifetime |  | unverified |

## Failure classification

Use [`Fixtures/AB146Workload/failure-classification.json`](../Fixtures/AB146Workload/failure-classification.json).
Retain every failed trace. Only a demonstrated reproducible measurement fault
may be re-run; it is not silently discarded. `measurement-unavailable` and an
unsupported environment are incomplete evidence, not pass results.
