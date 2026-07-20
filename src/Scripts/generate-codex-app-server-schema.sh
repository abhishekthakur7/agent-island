#!/bin/sh
set -eu

# Reproducible AB-137 semantic artifact check. The generator's raw key order
# is nondeterministic, so compare canonical parsed JSON, never raw bytes.
ab137_out=$(mktemp -d /tmp/ab137-schema-check.XXXXXX)
trap 'rm -rf "$ab137_out"' EXIT
ab137_again="$ab137_out/again"
mkdir "$ab137_again"
codex app-server generate-json-schema --out "$ab137_out"
codex app-server generate-json-schema --out "$ab137_again"
ab137_digest=$(cd "$ab137_out" && find . -type f -name '*.json' -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s\n' "$f"; jq -S -c . "$f"; done | shasum -a 256 | awk '{print $1}')
ab137_again_digest=$(cd "$ab137_again" && find . -type f -name '*.json' -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s\n' "$f"; jq -S -c . "$f"; done | shasum -a 256 | awk '{print $1}')
test "$ab137_digest" = "$ab137_again_digest"
test "$ab137_digest" = "dac1766a4569654dbda02f879f5e977085863f9714273eae1295095a055ca50f"
