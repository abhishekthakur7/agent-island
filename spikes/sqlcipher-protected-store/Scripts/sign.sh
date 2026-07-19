#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
APP="$ROOT/.build/AB117-ProtectedStoreSpike.app"
IDENTITY=${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to a Developer ID Application identity.}
[[ -d "$APP" ]] || { print -u2 "Run Scripts/build.sh first."; exit 2; }

# Sign the bundled SQLCipher payload first, then the outer hardened app. This
# rejects a Homebrew dylib dependency at shipment time.
for library in "$APP/Contents/Frameworks"/*.dylib; do
  codesign --force --sign "$IDENTITY" --timestamp --options runtime "$library"
done
codesign --force --sign "$IDENTITY" --timestamp --options runtime "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP" || true # pre-notarization assessment may fail
