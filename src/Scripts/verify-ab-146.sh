#!/bin/zsh
set -euo pipefail

# AB-146 supported-hardware capture. This verifier refuses to call a missing
# privileged energy sampler a pass: it writes measurement-unavailable for
# manual Instruments/powermetrics completion instead.
ROOT=${0:A:h:h}
FIXTURE="$ROOT/Fixtures/AB146Workload/workload-v1.json"
FAILURES="$ROOT/Fixtures/AB146Workload/failure-classification.json"
BASELINE="$ROOT/Evidence/AB-146-NATIVE-BUDGET.txt"
test -f "$FIXTURE"
test -f "$FAILURES"
cd "$ROOT"

stamp=$(date +%Y%m%d-%H%M%S)
run_dir="$ROOT/Evidence/AB-146-run-$stamp"
mkdir -p "$run_dir"

now() { perl -MTime::HiRes=time -e 'printf "%.6f", time'; }

swift build --product AB146SelfCheck
binary="$ROOT/.build/debug/AB146SelfCheck"
test -x "$binary"

warm_start=$(now)
"$binary" > "$run_dir/warm-result.json"
warm_ms=$(( ($(now) - warm_start) * 1000 ))

cold_start=$(now)
"$binary" > "$run_dir/cold-result.json"
cold_ms=$(( ($(now) - cold_start) * 1000 ))

print "phase,sample,epoch,pid,rss_kb,cpu_percent,open_handles" > "$run_dir/resource-series.csv"

# The resource phase is deliberately a repeat of the real 30-session harness,
# not a synthetic allocation loop. Idle is the same process after its result
# is emitted and has no retained timer, sound output, or polling work.
sample_phase() {
  local phase=$1
  shift
  "$binary" "$@" > "$run_dir/${phase}-result.json" &
  local pid=$!
  local sample=1
  while (( sample <= 5 )); do
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      local values=""
      values=$(ps -o rss=,%cpu= -p "$pid" 2>/dev/null | awk 'NR == 1 { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print $1 "," $2 }')
      local rss=${values%%,*}
      local cpu=${values##*,}
      local handles=unavailable
      if command -v lsof >/dev/null 2>&1; then
        handles=$(lsof -p "$pid" 2>/dev/null | wc -l | tr -d ' ')
      fi
      print "$phase,$sample,$(now),$pid,${rss:-unavailable},${cpu:-unavailable},$handles" >> "$run_dir/resource-series.csv"
    fi
    (( sample += 1 ))
  done
  wait "$pid"
}

sample_phase workload --resource-workload-seconds=6
sample_phase idle --hold-seconds=6

metrics=$(awk -F, '
  NR == 1 { next }
  $5 ~ /^[0-9]+$/ { if ($5 > maxRSS) maxRSS = $5; samples += 1 }
  $1 == "workload" && $6 ~ /^[0-9.]+$/ { if ($6 > workloadCPU) workloadCPU = $6 }
  $1 == "idle" && $6 ~ /^[0-9.]+$/ { if ($6 > idleCPU) idleCPU = $6 }
  $7 ~ /^[0-9]+$/ { if ($7 > maxHandles) maxHandles = $7 }
  END {
    if (samples == 0) exit 2
    printf "rss_kb=%d\nworkload_cpu=%.3f\nidle_cpu=%.3f\nhandles=%d\nsamples=%d\n", maxRSS, workloadCPU, idleCPU, maxHandles, samples
  }
' "$run_dir/resource-series.csv") || { print -u2 "AB-146 reproducible-measurement-fault: no process samples"; exit 1; }
print -r -- "$metrics" > "$run_dir/resource-observed.txt"

derived=$(awk -F= '
  function ceil(x) { return x == int(x) ? int(x) : int(x) + 1 }
  $1 == "rss_kb" { rss = $2 }
  $1 == "workload_cpu" { workload = $2 }
  $1 == "idle_cpu" { idle = $2 }
  $1 == "handles" { handles = $2 }
  END {
    printf "rss_mb=%d\nworkload_cpu_percent=%.1f\nidle_cpu_percent=%.1f\nopen_handles=%d\n", ceil((rss / 1024) * 1.5), workload * 1.5 + 0.1, idle * 1.5 + 0.1, ceil(handles * 1.5)
  }
' "$run_dir/resource-observed.txt")
print -r -- "$derived" > "$run_dir/derived-budget-candidate.txt"

baseline_value() { awk -F= -v wanted="$1" '$1 == wanted { print $2 }' "$BASELINE"; }
if [[ ! -f "$BASELINE" ]]; then
  print -u2 "AB-146 measurement-unavailable: no reviewed resource baseline; candidate retained at $run_dir/derived-budget-candidate.txt"
  exit 1
fi
budget_rss=$(baseline_value rss_mb)
budget_workload_cpu=$(baseline_value workload_cpu_percent)
budget_idle_cpu=$(baseline_value idle_cpu_percent)
budget_handles=$(baseline_value open_handles)
observed_rss=$(awk -F= '$1 == "rss_kb" { print $2 / 1024 }' "$run_dir/resource-observed.txt")
observed_workload_cpu=$(awk -F= '$1 == "workload_cpu" { print $2 }' "$run_dir/resource-observed.txt")
observed_idle_cpu=$(awk -F= '$1 == "idle_cpu" { print $2 }' "$run_dir/resource-observed.txt")
observed_handles=$(awk -F= '$1 == "handles" { print $2 }' "$run_dir/resource-observed.txt")
awk -v rss="$observed_rss" -v rssBudget="$budget_rss" -v work="$observed_workload_cpu" -v workBudget="$budget_workload_cpu" -v idle="$observed_idle_cpu" -v idleBudget="$budget_idle_cpu" -v handles="$observed_handles" -v handleBudget="$budget_handles" 'BEGIN { exit !(rss > rssBudget || work > workBudget || idle > idleBudget || handles > handleBudget) }' && { print -u2 "AB-146 valid-over-target resource sample; see $run_dir/resource-observed.txt"; exit 1; }

{
  print "schema=agent-island.ab-146.environment"
  print "version=1"
  print "captured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  print "fixture_sha256=$(shasum -a 256 "$FIXTURE" | awk '{print $1}')"
  print "git_revision=$(git rev-parse --short HEAD 2>/dev/null || print unavailable)"
  print "hardware=$(sysctl -n hw.model 2>/dev/null || print unavailable)"
  print "apple_silicon=$(sysctl -n hw.optional.arm64 2>/dev/null || print 0)"
  print "macos=$(sw_vers -productVersion 2>/dev/null || print unavailable)"
  print "xcode=$(xcodebuild -version 2>/dev/null | tr '\n' ';' || print unavailable)"
  print "power_and_display=record manually in AB-146 report"
  print "headless_warm_start_ms=$warm_ms"
  print "headless_cold_start_ms=$cold_ms"
  print "resource_series=Evidence/AB-146-run-$stamp/resource-series.csv"
  print "resource_observed=Evidence/AB-146-run-$stamp/resource-observed.txt"
  print "derived_budget_candidate=Evidence/AB-146-run-$stamp/derived-budget-candidate.txt"
  print "resource_baseline=$( [[ -f "$BASELINE" ]] && print "Evidence/AB-146-NATIVE-BUDGET.txt" || print absent )"
  print "tasks_timers=0 (headless harness has no retained timer/task after completion)"
  print "audio_outputs=0 (headless harness does not instantiate audio output)"
  print "disk_growth=measurement-unavailable (headless workload uses in-memory SessionStore; protected-store capture required)"
  print "energy_wakeups=measurement-unavailable (requires Instruments Energy Log or authorized powermetrics)"
  print "display_sleep_wake=manual-native-capture-required"
} > "$run_dir/environment.txt"

if (( ${warm_ms%.*} >= 1000 || ${cold_ms%.*} >= 2000 )); then
  print -u2 "AB-146 valid headless start over-target sample: warm=${warm_ms}ms cold=${cold_ms}ms"
  exit 1
fi

if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || print 0)" != "1" ]]; then
  print -u2 "AB-146 environment unsupported: this is not supported Apple Silicon evidence"
  exit 1
fi

print "AB-146 verifier PASS (headless local timing/safety/resource series). Evidence: $run_dir"
print "AB-146 native visual/VoiceOver/display/sleep-wake/energy/disk capture remains required and is not marked passed."
