#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

usage() {
  echo "usage: $(basename "$0") [--duration seconds] [--] [overlay arguments...]" >&2
}

duration=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --duration)
      [ "$#" -ge 2 ] || die "--duration needs a positive number of seconds"
      duration="$2"
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
    *)
      die "unknown option: $1"
      ;;
  esac
done

require_supported_host
resolve_binary
ensure_results_dir
write_run_metadata "$RESULTS_DIR/run-metadata.txt"

evidence_log="$RESULTS_DIR/instrumentation.jsonl"
stdout_log="$RESULTS_DIR/overlay.stdout.log"
stderr_log="$RESULTS_DIR/overlay.stderr.log"

if [ -n "$(find_binary_processes "$BINARY")" ]; then
  find_binary_processes "$BINARY" > "$RESULTS_DIR/residual-before.txt"
  die "an overlay process already matches this binary; see $RESULTS_DIR/residual-before.txt"
fi

echo "instrumentation_log=$evidence_log" >> "$RESULTS_DIR/run-metadata.txt"
echo "started_at_utc=$(timestamp_utc)" >> "$RESULTS_DIR/run-metadata.txt"

# The application may opt in to this append-only, redaction-safe JSONL sink.
# Its absence is recorded as unavailable by the reporting template.
AI_OVERLAY_EVIDENCE_LOG="$evidence_log" "$BINARY" "$@" >"$stdout_log" 2>"$stderr_log" &
pid=$!
echo "pid=$pid" >> "$RESULTS_DIR/run-metadata.txt"

if [ -z "$duration" ]; then
  note "running pid $pid; press Ctrl-C to stop. Logs are in $RESULTS_DIR"
  trap 'kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' INT TERM
  set +e
  wait "$pid"
  status=$?
  set -e
else
  case "$duration" in
    ''|*[!0-9]*) die "--duration must be a whole positive number" ;;
  esac
  [ "$duration" -gt 0 ] || die "--duration must be greater than zero"
  note "running pid $pid for $duration seconds"
  sleep "$duration"
  stopped_by_harness=0
  if kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null; then
    stopped_by_harness=1
  fi
  set +e
  wait "$pid"
  status=$?
  set -e
fi

echo "ended_at_utc=$(timestamp_utc)" >> "$RESULTS_DIR/run-metadata.txt"
echo "exit_status=$status" >> "$RESULTS_DIR/run-metadata.txt"

find_binary_processes "$BINARY" > "$RESULTS_DIR/residual-after.txt" || true
if [ -s "$RESULTS_DIR/residual-after.txt" ]; then
  note "residual process(es) detected: $RESULTS_DIR/residual-after.txt"
  exit 2
fi

if [ "${stopped_by_harness:-0}" -eq 1 ] && { [ "$status" -eq 0 ] || [ "$status" -eq 143 ]; }; then
  note "overlay stopped by the requested duration; treating its normal SIGTERM exit as capture completion"
  exit 0
fi

exit "$status"
