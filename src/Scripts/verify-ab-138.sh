#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
adapter="$root/Sources/CursorHooksAdapter/CursorHooksAdapter.swift"
helper="$root/Sources/CursorHookHelper/main.swift"
evidence="$root/Evidence/AB-138-REPORT-TEMPLATE.md"
fixtures="$root/Fixtures/CursorHooksAdapter"

test -f "$adapter"; test -f "$helper"; test -f "$evidence"
test -f "$fixtures/documented-v1-lifecycle.json"
test -f "$fixtures/negative-cases.json"
test -f "$fixtures/installation-jsonc.jsonc"
rg -q 'https://cursor.com/docs/hooks.md' "$adapter"
rg -q 'case sessionStart, sessionEnd' "$adapter"
rg -q 'subagentStop' "$adapter"
rg -q 'failClosed' "$adapter"
rg -q 'weak-owner-key' "$adapter"
rg -q 'AGENT_ISLAND_CURSOR_OBSERVATION_ONLY' "$helper"
rg -q 'dispatchCount = 0' "$adapter"
! rg -q 'unsupported-contract.json|no-public-cursor-hooks-contract' "$adapter" "$evidence"
echo 'AB-138 verifier: PASS (documented Cursor Hooks v1 observation implementation and evidence present)'
