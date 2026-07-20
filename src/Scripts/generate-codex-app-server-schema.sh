#!/bin/sh
set -eu

# Reproducible AB-137 artifact check.  The reviewed schema is intentionally a
# checked-in, stable JSON fixture; this script rejects drift rather than
# downloading, probing private files, or enabling an unverified live Product.
ab137_out=$(mktemp -d /tmp/ab137-schema-check.XXXXXX)
trap 'rm -rf "$ab137_out"' EXIT
codex app-server generate-json-schema --out "$ab137_out"
test "$(shasum -a 256 "$ab137_out/codex_app_server_protocol.v2.schemas.json" | awk '{print $1}')" = "5ff91672223f52bdaa35d882db98e7b6a6fccb6add36c96107e64f5fc03fed97"
