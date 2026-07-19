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

command -v swift >/dev/null 2>&1 || die "Swift is required; install Xcode or the Command Line Tools"
write_run_metadata "$RESULTS_DIR/test-metadata.txt"
echo "command=swift test --package-path $SPIKE_DIR" >> "$RESULTS_DIR/test-metadata.txt"
swift test --package-path "$SPIKE_DIR" 2>&1 | tee "$RESULTS_DIR/test.log"
note "test log: $RESULTS_DIR/test.log"
