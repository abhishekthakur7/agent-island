#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_supported_host
ensure_results_dir

if [ -n "${1:-}" ]; then
  die "usage: $(basename "$0")"
fi

environment="$RESULTS_DIR/environment.txt"
hardware="$RESULTS_DIR/hardware.txt"

{
  echo "captured_at_utc=$(timestamp_utc)"
  echo
  echo "## Operating system"
  sw_vers
  uname -a
  echo
  echo "## Developer tools"
  xcodebuild -version 2>&1 || true
  swift --version 2>&1 || true
  xcrun --find xctrace 2>&1 || true
  echo
  echo "## Power and display state"
  pmset -g batt 2>&1 || true
  pmset -g custom 2>&1 || true
  system_profiler SPDisplaysDataType 2>&1 || true
} > "$environment"

# Do not collect hardware UUIDs or serial numbers. These fields are sufficient
# to compare runs while keeping the evidence bundle locally shareable.
{
  echo "captured_at_utc=$(timestamp_utc)"
  echo
  echo "## CPU and memory"
  sysctl -n machdep.cpu.brand_string 2>&1 || true
  sysctl -n hw.model 2>&1 || true
  sysctl -n hw.memsize 2>&1 || true
  sysctl -n hw.ncpu 2>&1 || true
  sysctl -n hw.physicalcpu 2>&1 || true
  sysctl -n hw.logicalcpu 2>&1 || true
  sysctl -n hw.optional.arm64 2>&1 || true
  echo
  echo "## Storage capacity (no volume UUIDs)"
  df -h / 2>&1 || true
} > "$hardware"

note "environment: $environment"
note "hardware: $hardware"
