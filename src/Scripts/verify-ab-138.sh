#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture="$root/Fixtures/CursorHooksAdapter/documented-v1-lifecycle.json"
test -f "$fixture"
cd "$root"
swift run AB138SelfCheck "$fixture"
