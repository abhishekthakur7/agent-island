#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

require_supported_host
if [ "$#" -gt 1 ] || [ "${1:-}" = "--help" ]; then
  echo "usage: $(basename "$0") [absolute-overlay-binary]" >&2
  exit 64
fi

if [ -n "${1:-}" ]; then
  BINARY="$1"
else
  resolve_binary
fi

matches="$(find_binary_processes "$BINARY" || true)"
if [ -n "$matches" ]; then
  echo "$matches"
  exit 2
fi

echo "No processes matched: $BINARY"
