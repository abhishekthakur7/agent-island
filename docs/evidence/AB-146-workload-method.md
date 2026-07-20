# AB-146 workload method

The AB-146 fixture is versioned at `src/Fixtures/AB146Workload/workload-v1.json`.
It supplies 30 independently owned Agent Sessions distributed across Claude
Code Hooks/iTerm2, Codex Hooks/Warp, Cursor ACP/Cursor, and Codex App
Server/Orca profiles. The deterministic headless harness uses the same typed
Adapter intake and PresentationPort path as the product; it never obtains a
SessionStore handle from an Adapter.

`src/Scripts/verify-ab-146.sh` records fixture hash, environment, cold/warm
headless process samples, local timing output, and open handles. It repeats a
CPU-active workload phase and quiescent idle phase five times each, retaining
the raw CSV and deriving/rechecking its numeric RSS/CPU/handle limits from
`src/Evidence/AB-146-NATIVE-BUDGET.txt`. It fails on a valid local timing,
launch, or established resource-budget miss. The resource budget and
non-headless capture matrix are in `src/Evidence/AB-146-REPORT-TEMPLATE.md`.

Native visual, VoiceOver, display, sleep/wake, and energy observations require
the recorded supported Apple Silicon environment and stay unverified until
captured. This distinction prevents a fixture from overstating native UI or
Product-application evidence.
