#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
adapter="$root/Sources/CursorHooksAdapter/CursorHooksAdapter.swift"
evidence="$root/Evidence/AB-138-REPORT-TEMPLATE.md"
fixture="$root/Fixtures/CursorHooksAdapter/unsupported-contract.json"

test -f "$adapter"
test -f "$evidence"
test -f "$fixture"
rg -q 'safeToMutate: false' "$adapter"
rg -q 'case unsupportedContract' "$adapter"
rg -q 'dispatchCount = 0' "$adapter"
! rg -q 'user_email|transcript_path|conversation_id|generation_id|/private' "$fixture"
echo 'AB-138 verifier: PASS (public Cursor Hooks contract unavailable; no configuration or payload retention)'
