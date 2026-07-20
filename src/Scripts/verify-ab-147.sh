#!/bin/zsh
set -euo pipefail

# AB-147 validates the evidence package, not product behavior.  A structurally
# complete package is intentionally distinct from release readiness: normal
# mode exits 2 while unresolved native/human gates remain.  Use
# --structure-only when a CI/doc check needs the structural PASS exit status.
ROOT=${0:A:h:h}
FIXTURE="$ROOT/Fixtures/AB147Parity/parity-v1.json"
GATES="$ROOT/Fixtures/AB147Parity/release-gates-v1.json"
DOCS="$ROOT/../docs/evidence/ab-147"
mode=${1:-readiness}

if [[ "$mode" != "readiness" && "$mode" != "--structure-only" ]]; then
  print -u2 "usage: $0 [--structure-only]"
  exit 64
fi

for artifact in "$FIXTURE" "$GATES" \
  "$DOCS/review-index.md" "$DOCS/parity-matrix.md" "$DOCS/dr-checklist.md" \
  "$DOCS/gap-log.md" "$DOCS/human-review-form.md" "$DOCS/diagnostic-index.md"; do
  [[ -f "$artifact" ]] || { print -u2 "AB-147 structure FAIL: missing $artifact"; exit 1; }
done

JQ=${JQ:-/usr/bin/jq}
[[ -x "$JQ" ]] || { print -u2 "AB-147 structure FAIL: jq is required to validate the machine-readable fixture"; exit 1; }
"$JQ" -e '
  .schema == "agent-island.ab-147.parity" and .version == 1 and
  (.records | length >= 8) and
  ([.records[].area] | unique | sort == ["A", "H", "I", "J", "N", "O", "P", "S"]) and
  (. as $document | [.records[] | select(
    (.id | type == "string") and (.area | type == "string") and
    (.product | type == "string") and (.adapterMode | type == "string") and
    (.hostProfile | type == "string") and (.profileVersion | type == "string") and
    (.capability | type == "string") and (.positiveFixture | type == "string") and
    (.negativeFixture | type == "string") and (.expected | type == "string") and
    (.observed | type == "string") and (.fallback | type == "string") and
    (.capture | type == "string") and (.diagnostic | type == "string") and
    (.status | type == "string")
  )] | length == ($document.records | length))
' "$FIXTURE" >/dev/null || { print -u2 "AB-147 structure FAIL: invalid parity schema or required row fields"; exit 1; }
"$JQ" -e '.schema == "agent-island.ab-147.release-gates" and .version == 1 and .readinessExitCode == 2 and (.releaseBlockers | length > 0)' "$GATES" >/dev/null || { print -u2 "AB-147 structure FAIL: invalid release gates"; exit 1; }

required_areas=(S I P A J N O H)
for area in $required_areas; do
  grep -q "\"area\": \"$area\"" "$FIXTURE" || { print -u2 "AB-147 structure FAIL: missing area $area"; exit 1; }
done

records=$("$JQ" '.records | length' "$FIXTURE")
(( records >= 8 )) || { print -u2 "AB-147 structure FAIL: fewer than eight matrix records"; exit 1; }
for evidence in $("$JQ" -r '.records[] | .positiveFixture, .negativeFixture, .capture, .diagnostic | split("#")[0]' "$FIXTURE"); do
  [[ -f "$ROOT/../$evidence" ]] || { print -u2 "AB-147 structure FAIL: evidence target missing $evidence"; exit 1; }
done

for doc in "$DOCS"/*.md; do
  grep -q 'AB-147' "$doc" || { print -u2 "AB-147 structure FAIL: $doc lacks ticket identity"; exit 1; }
done

print "AB-147 structure PASS: $records records cover S/I/P/A/J/N/O/H with required evidence fields."
if [[ "$mode" == "--structure-only" ]]; then
  exit 0
fi

code=$(sed -n 's/.*"readinessExitCode": \([0-9][0-9]*\).*/\1/p' "$GATES")
[[ "$code" == "2" ]] || { print -u2 "AB-147 structure FAIL: readiness exit code must be documented as 2"; exit 1; }
print -u2 "AB-147 release readiness BLOCKED (exit $code): native, accessibility, human, recovery, energy/disk/audio, and live capability captures remain open."
exit "$code"
