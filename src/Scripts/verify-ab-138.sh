#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture="$root/Fixtures/CursorHooksAdapter/documented-v1-lifecycle.json"
negative="$root/Fixtures/CursorHooksAdapter/negative-cases.json"
test -f "$fixture"
test -f "$negative"
cd "$root"
swift run AB138SelfCheck "$fixture" "$negative"
