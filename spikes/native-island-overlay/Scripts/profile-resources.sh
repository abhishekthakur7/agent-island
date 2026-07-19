#!/bin/bash
# Observe a running overlay with macOS-native tools. It does not require root;
# optional powermetrics requires an explicitly root-launched invocation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

usage() {
  echo "usage: $(basename "$0") (--pid pid | --binary path) [--samples count] [--interval seconds] [--xctrace-energy] [--powermetrics]" >&2
}

pid=""
binary=""
samples=12
interval=5
capture_xctrace=0
capture_powermetrics=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pid) [ "$#" -ge 2 ] || die "--pid needs a PID"; pid="$2"; shift 2 ;;
    --binary) [ "$#" -ge 2 ] || die "--binary needs a path"; binary="$2"; shift 2 ;;
    --samples) [ "$#" -ge 2 ] || die "--samples needs a count"; samples="$2"; shift 2 ;;
    --interval) [ "$#" -ge 2 ] || die "--interval needs whole seconds"; interval="$2"; shift 2 ;;
    --xctrace-energy) capture_xctrace=1; shift ;;
    --powermetrics) capture_powermetrics=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

case "$samples:$interval" in
  *[!0-9:]*|0:*|*:0) die "--samples and --interval must be positive whole numbers" ;;
esac

require_supported_host
ensure_results_dir

if [ -n "$pid" ] && [ -n "$binary" ]; then
  die "use either --pid or --binary, not both"
fi
if [ -z "$pid" ] && [ -z "$binary" ]; then
  resolve_binary
  binary="$BINARY"
fi
if [ -n "$binary" ]; then
  matches="$(find_binary_processes "$binary" || true)"
  count="$(printf '%s\n' "$matches" | awk 'NF { n++ } END { print n + 0 }')"
  [ "$count" -eq 1 ] || die "expected exactly one matching process for $binary; found $count"
  pid="$(printf '%s\n' "$matches" | awk 'NF { print $1; exit }')"
fi
case "$pid" in ''|*[!0-9]*) die "PID must be numeric" ;; esac
kill -0 "$pid" 2>/dev/null || die "PID $pid is not running"

write_run_metadata "$RESULTS_DIR/resource-metadata.txt"
{
  echo "pid=$pid"
  echo "samples=$samples"
  echo "interval_seconds=$interval"
  echo "xctrace_energy_requested=$capture_xctrace"
  echo "powermetrics_requested=$capture_powermetrics"
} >> "$RESULTS_DIR/resource-metadata.txt"

series="$RESULTS_DIR/resource-series.tsv"
printf 'captured_at_utc\tpid\tppid\tpercent_cpu\trss_kib\tetime\tcommand\n' > "$series"
sample=1
while [ "$sample" -le "$samples" ]; do
  if ! kill -0 "$pid" 2>/dev/null; then
    note "process exited before sample $sample"
    break
  fi
  row="$(ps -p "$pid" -o pid=,ppid=,%cpu=,rss=,etime=,command= 2>/dev/null | sed -e 's/^[[:space:]]*//')"
  if [ -n "$row" ]; then
    printf '%s\t%s\n' "$(timestamp_utc)" "$row" >> "$series"
  fi
  top -l 1 -pid "$pid" -stats pid,command,cpu,mem,threads,ports 2>&1 >> "$RESULTS_DIR/top-samples.txt" || true
  sample=$((sample + 1))
  [ "$sample" -le "$samples" ] && sleep "$interval"
done

vmmap -summary "$pid" > "$RESULTS_DIR/vmmap-summary.txt" 2>&1 || true
lsof -n -P -p "$pid" > "$RESULTS_DIR/open-files.txt" 2>&1 || true

if [ "$capture_xctrace" -eq 1 ]; then
  if xcrun --find xctrace >/dev/null 2>&1; then
    # The trace stays unprocessed: Xcode's Instruments is the authority for
    # Energy Impact and wakeups, and versions expose different export schemas.
    xcrun xctrace record --template 'Energy Log' --output "$RESULTS_DIR/energy.trace" --attach "$pid" --time-limit "$((samples * interval))s" > "$RESULTS_DIR/xctrace-energy.log" 2>&1 || true
  else
    echo "xctrace_energy_status=unavailable" >> "$RESULTS_DIR/resource-metadata.txt"
    note "xctrace unavailable; Energy Log was not captured"
  fi
fi

if [ "$capture_powermetrics" -eq 1 ]; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "powermetrics_status=requires_root" >> "$RESULTS_DIR/resource-metadata.txt"
    note "powermetrics skipped: rerun this entire command as root to opt in"
  elif command -v powermetrics >/dev/null 2>&1; then
    powermetrics --samplers tasks -i 1000 -n "$((samples * interval))" > "$RESULTS_DIR/powermetrics-tasks.txt" 2>&1 || true
  fi
fi

cat <<EOF
Resource series: $series
Native snapshots: $RESULTS_DIR/top-samples.txt, $RESULTS_DIR/vmmap-summary.txt, $RESULTS_DIR/open-files.txt
Energy/wakeups require manual review in the optional Energy Log trace or the
root-only powermetrics capture. No derived CPU, energy, or wakeup pass/fail is
claimed by this script.
EOF
