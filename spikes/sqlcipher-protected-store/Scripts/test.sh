#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
cd "$ROOT"

# These protect deterministic fixture/projection contracts only. They do not
# count as SQLCipher/Keychain evidence.
swift test --filter StorageCoreTests

# This is intentionally gated: it requires a bundled SQLCipher dylib and a
# login Keychain on a real macOS user session.
"$ROOT/Scripts/clean-launch.sh"
