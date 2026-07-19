#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_supported_host
ensure_results_dir

configuration="release"
if [ "${1:-}" = "--debug" ]; then
  configuration="debug"
elif [ -n "${1:-}" ]; then
  die "usage: $(basename "$0") [--debug]"
fi

command -v swift >/dev/null 2>&1 || die "Swift is required; install Xcode or the Command Line Tools"
write_run_metadata "$RESULTS_DIR/build-metadata.txt"

{
  echo "swift_version:"
  swift --version
  echo
  echo "build_configuration=$configuration"
  echo "command=swift build --package-path $SPIKE_DIR -c $configuration"
} >> "$RESULTS_DIR/build-metadata.txt"

swift build --package-path "$SPIKE_DIR" -c "$configuration" 2>&1 | tee "$RESULTS_DIR/build.log"
note "build log: $RESULTS_DIR/build.log"
