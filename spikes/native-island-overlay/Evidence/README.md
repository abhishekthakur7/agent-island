# Native Island Overlay evidence harness

This directory holds **evidence templates and capture tooling**, not claimed
test results. Run it on a real Apple-Silicon Mac running macOS 14 or newer.
Simulator, screenshots without the corresponding trace, and automated checks
do not replace the human accessibility and focus evidence required by AB-116.

## Reproducible capture

Set one results directory before a capture sequence so the commands contribute
to the same evidence bundle. The default creates a timestamped directory per
command beneath `Evidence/runs/`.

```sh
cd spikes/native-island-overlay
export OVERLAY_RESULTS_DIR="$PWD/Evidence/runs/$(date -u +%Y%m%dT%H%M%SZ)-ow1"

Scripts/capture-environment.sh
Scripts/build.sh
Scripts/test.sh
Scripts/run-overlay.sh --duration 30 -- --evidence-scenario OW-1
Scripts/residual-processes.sh
```

When `--duration` sends the child its expected `SIGTERM`, `run-overlay.sh`
returns success after verifying that no matching process remains. A crash or
any other nonzero child result still fails the capture.

`run-overlay.sh` gives the application an opt-in `AI_OVERLAY_EVIDENCE_LOG`
path. When supported by the executable it should append redaction-safe JSONL;
the tool always retains stdout, stderr, run metadata, and the raw JSONL file.
An absent or malformed log is **unavailable evidence**, not a passing result.

For OW-1, run the automatic-reveal mode from an already-focused terminal or
editor and keep that Host focused while the panel appears:

```sh
Scripts/run-overlay.sh -- --evidence-scenario OW-1 --evidence-automatic-reveal-after-ready
```

The JSONL records `applicationIsActive` at the request and synchronous AppKit
presentation boundaries. It is diagnostic Operational Metadata, not proof of
the current Host or VoiceOver operation; retain the required pre/post Host
capture and human observation in the report.

For launch samples, pass an application argument that makes the test process
exit after it has reached its usable collapsed state:

```sh
export OVERLAY_RESULTS_DIR="$PWD/Evidence/runs/$(date -u +%Y%m%dT%H%M%SZ)-launch"
Scripts/measure-launch.sh --runs 10 -- --evidence-quit-after-ready
```

The `process_runtime_ms` column is deliberately not reported as usable-launch
latency. `app_usable_latency_ms` is emitted only when matching
`launch_process_started` and `launch_usable` markers share the app's monotonic
clock; otherwise it says `UNAVAILABLE`. To inspect a trace directly:

```sh
Scripts/summarize-instrumentation.sh Evidence/runs/[run]/launch-1.instrumentation.jsonl
```

To profile a deliberately running instance, identify its PID and capture it
without killing it:

```sh
Scripts/profile-resources.sh --pid 12345 --samples 60 --interval 5
Scripts/profile-resources.sh --pid 12345 --samples 12 --interval 5 --xctrace-energy
```

The second command writes an Xcode Instruments Energy Log trace if `xctrace`
is installed. Review energy impact and wakeups in Instruments; Xcode versions
have incompatible exports, so the script does not invent derived values. A
root-only `powermetrics` capture is opt-in:

```sh
sudo Scripts/profile-resources.sh --pid 12345 --samples 12 --interval 5 --powermetrics
```

Do not run the `sudo` command unless the person conducting the capture has
chosen to grant that local privilege. The ordinary profile records CPU, RSS,
thread/port snapshots, virtual-memory summary, and open files using native
macOS tools. `residual-processes.sh` only detects matching processes; it never
terminates a process it did not start.

## Instrumentation contract

Instrumentation is opt-in and must contain Operational Metadata only: no
Interaction Content, credentials, titles, paths, or prompts. Recommended
newline-delimited JSON records are:

```json
{"event":"launch_process_started","timestampNs":"123","schemaVersion":1,"scenario":"OW-1"}
{"event":"launch_usable","timestampNs":"456","schemaVersion":1,"scenario":"OW-1"}
{"event":"interaction_requested","timestampNs":"789","schemaVersion":1,"metadata":{"kind":"automaticReveal","applicationIsActive":false}}
{"event":"interaction_rendered","timestampNs":"910","schemaVersion":1,"metadata":{"kind":"automaticReveal","presentation":"focused","keyboardEngaged":false,"applicationIsActive":false}}
```

Use one monotonic clock per process. `elapsedMs` must start at the documented
boundary: `launch_process_started` (emitted from `main` before
`NSApplication` is created) to the responsive collapsed Overlay (or explicit
selected-display-unavailable state), and an interaction request to the first
synchronous AppKit presentation result. VoiceOver accessibility operation
remains a human-observed boundary. Preserve the raw JSONL alongside the report
and state the exact event names/version used.

The implementation should also log state transitions useful for diagnosis
(`overlay_collapsed`, `overlay_expanded`, `keyboard_engaged`,
`keyboard_released`, and `panel_withdrawn`). Their presence assists review but
does not prove focus, visible hit regions, VoiceOver, or display/Space behavior
without the human checks in the report template.

Current fixture schema: `schemaVersion: 1`. Interaction records carry only a
kind, presentation/keyboard flags, and Agent Island's active-state snapshot;
they deliberately omit Agent Session titles, paths, prompts, Host identity,
and Interaction Content.
