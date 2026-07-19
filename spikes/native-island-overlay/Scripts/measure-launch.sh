#!/bin/bash
# Capture reproducible launch samples. A process runtime is not a usable-launch
# latency: that verdict requires the app's launch_usable instrumentation record.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

usage() {
  echo "usage: $(basename "$0") [--runs count] [--timeout seconds] [--] [overlay arguments...]" >&2
  echo "Pass an app-supported argument such as --evidence-quit-after-ready after --." >&2
}

runs=5
timeout_seconds=20
while [ "$#" -gt 0 ]; do
  case "$1" in
    --runs)
      [ "$#" -ge 2 ] || die "--runs needs a positive whole number"
      runs="$2"
      shift 2
      ;;
    --timeout)
      [ "$#" -ge 2 ] || die "--timeout needs a positive whole number"
      timeout_seconds="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

case "$runs:$timeout_seconds" in
  *[!0-9:]*|0:*|*:0) die "--runs and --timeout must be positive whole numbers" ;;
esac

require_supported_host
resolve_binary
ensure_results_dir
write_run_metadata "$RESULTS_DIR/launch-metadata.txt"

if [ -n "$(find_binary_processes "$BINARY")" ]; then
  find_binary_processes "$BINARY" > "$RESULTS_DIR/residual-before-launch.txt"
  die "an overlay process already matches this binary; see $RESULTS_DIR/residual-before-launch.txt"
fi

samples="$RESULTS_DIR/launch-samples.tsv"
printf 'run\tstarted_epoch_ms\texited_epoch_ms\tprocess_runtime_ms\tapp_usable_latency_ms\texit_status\ttimed_out\tinstrumentation_log\n' > "$samples"

epoch_ms() {
  # Perl is bundled with supported macOS releases and supplies sub-second time
  # without depending on GNU date.
  /usr/bin/perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000'
}

app_launch_latency_ms() {
  log="$1"
  [ -f "$log" ] || { printf 'UNAVAILABLE'; return; }
  /usr/bin/perl -ne '
    my ($event) = /"event"\s*:\s*"([^"]+)"/;
    my ($timestamp) = /"timestampNs"\s*:\s*"?(\d+)"?/;
    next unless defined $event && defined $timestamp;
    $start = $timestamp if $event eq "launch_process_started" && !defined $start;
    if ($event eq "launch_usable" && defined $start) {
      printf "%.3f", ($timestamp - $start) / 1_000_000;
      exit;
    }
  ' "$log"
}

run=1
while [ "$run" -le "$runs" ]; do
  log="$RESULTS_DIR/launch-$run.instrumentation.jsonl"
  stdout="$RESULTS_DIR/launch-$run.stdout.log"
  stderr="$RESULTS_DIR/launch-$run.stderr.log"
  started="$(epoch_ms)"
  AI_OVERLAY_EVIDENCE_LOG="$log" "$BINARY" "$@" >"$stdout" 2>"$stderr" &
  pid=$!
  elapsed_ticks=0
  max_ticks=$((timeout_seconds * 10))
  timed_out=0
  while kill -0 "$pid" 2>/dev/null && [ "$elapsed_ticks" -lt "$max_ticks" ]; do
    sleep 0.1
    elapsed_ticks=$((elapsed_ticks + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    timed_out=1
    kill -TERM "$pid" 2>/dev/null || true
  fi
  set +e
  wait "$pid"
  status=$?
  set -e
  ended="$(epoch_ms)"
  runtime=$((ended - started))
  usable_latency="$(app_launch_latency_ms "$log")"
  [ -n "$usable_latency" ] || usable_latency="UNAVAILABLE"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$run" "$started" "$ended" "$runtime" "$usable_latency" "$status" "$timed_out" "$log" >> "$samples"
  run=$((run + 1))
done

find_binary_processes "$BINARY" > "$RESULTS_DIR/residual-after-launch.txt" || true
if [ -s "$RESULTS_DIR/residual-after-launch.txt" ]; then
  note "residual process(es) detected: $RESULTS_DIR/residual-after-launch.txt"
  exit 2
fi

cat <<EOF
Launch samples: $samples

Interpretation: process_runtime_ms is only spawn-to-exit duration. The
app_usable_latency_ms field is calculated solely from same-process monotonic
launch_process_started and launch_usable JSONL markers; UNAVAILABLE means the
markers were absent or incomplete.
EOF
