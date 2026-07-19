#!/bin/bash
# Shared helpers for the disposable native Island Overlay spike evidence tools.
# macOS ships Bash 3.2, so keep this file deliberately POSIX-ish Bash.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_BINARY="$SPIKE_DIR/.build/release/NativeIslandOverlay"

die() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "note: $*" >&2
}

timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

default_results_dir() {
  printf '%s/Evidence/runs/%s' "$SPIKE_DIR" "$(date -u '+%Y%m%dT%H%M%SZ')"
}

require_supported_host() {
  [ "$(uname -s)" = "Darwin" ] || die "this spike is supported only on macOS"

  major="$(sw_vers -productVersion | awk -F. '{ print $1 }')"
  case "$major" in
    ''|*[!0-9]*) die "could not determine the macOS version" ;;
  esac
  [ "$major" -ge 14 ] || die "macOS 14 or newer is required (found $(sw_vers -productVersion))"

  machine="$(uname -m)"
  arm64="$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)"
  [ "$machine" = "arm64" ] || [ "$arm64" = "1" ] || die "Apple Silicon is required (found $machine)"
}

resolve_binary() {
  if [ -n "${OVERLAY_BINARY:-}" ]; then
    BINARY="$OVERLAY_BINARY"
  else
    BINARY="$DEFAULT_BINARY"
  fi
  [ -x "$BINARY" ] || die "overlay binary is not executable: $BINARY (set OVERLAY_BINARY to override)"
}

ensure_results_dir() {
  RESULTS_DIR="${OVERLAY_RESULTS_DIR:-$(default_results_dir)}"
  mkdir -p "$RESULTS_DIR"
}

command_path() {
  command -v "$1" 2>/dev/null || true
}

# Print processes that still appear to be executing this exact binary path.
# This only detects processes; it never terminates a process it did not start.
find_binary_processes() {
  binary="$1"
  ps -axo pid=,ppid=,state=,etime=,command= | awk -v binary="$binary" '
    {
      command = $0
      # Strip the four ps columns, leaving the command as executed. Matching
      # its first token avoids treating the caller, shell history, or this awk
      # process as an Overlay merely because it mentions the binary path.
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", command)
      if (command == binary || index(command, binary " ") == 1) print
    }
  '
}

write_run_metadata() {
  output="$1"
  {
    echo "captured_at_utc=$(timestamp_utc)"
    echo "binary=${BINARY:-${OVERLAY_BINARY:-$DEFAULT_BINARY}}"
    echo "macos=$(sw_vers -productVersion 2>/dev/null || true)"
    echo "architecture=$(uname -m)"
    echo "script=$(basename "$0")"
  } > "$output"
}
