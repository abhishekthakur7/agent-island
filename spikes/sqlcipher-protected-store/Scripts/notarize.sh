#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
APP="$ROOT/.build/AB117-ProtectedStoreSpike.app"
PROFILE=${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a configured notarytool keychain profile.}
[[ -d "$APP" ]] || { print -u2 "Run build.sh and sign.sh first."; exit 2; }
ARCHIVE="$ROOT/.build/AB117-ProtectedStoreSpike.zip"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
"$ROOT/Scripts/clean-launch.sh"
