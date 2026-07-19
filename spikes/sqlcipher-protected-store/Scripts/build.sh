#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"
command -v pkg-config >/dev/null || { print -u2 "pkg-config is required; install SQLCipher with: brew install sqlcipher pkg-config"; exit 2; }
pkg-config --exists sqlcipher || { print -u2 "SQLCipher pkg-config metadata is required; refusing Apple's unencrypted SQLite."; exit 2; }

SQLCIPHER_DYLIB=${SQLCIPHER_DYLIB:-"$(pkg-config --variable=libdir sqlcipher)/libsqlcipher.dylib"}
[[ -f "$SQLCIPHER_DYLIB" ]] || { print -u2 "Set SQLCIPHER_DYLIB to the SQLCipher dynamic library to bundle."; exit 2; }

swift build -c release
RAW="$ROOT/.build/release/SQLCipherProtectedStoreSpike"
SQLCIPHER_LOAD_COMMAND=$(otool -L "$RAW" | awk '/libsqlcipher/ { print $1; exit }')
[[ -n "$SQLCIPHER_LOAD_COMMAND" ]] || { print -u2 "Swift build did not link SQLCipher; refusing an Apple SQLite fallback."; exit 1; }
APP="$ROOT/.build/AB117-ProtectedStoreSpike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp "$ROOT/.build/release/SQLCipherProtectedStoreSpike" "$APP/Contents/MacOS/"
typeset -A COPIED
bundle_dependency() {
  local source="$1" base="${1:t}" destination="$APP/Contents/Frameworks/${1:t}"
  [[ -n "${COPIED[$source]:-}" ]] && return
  COPIED[$source]=1
  cp "$source" "$destination"
  install_name_tool -id "@rpath/$base" "$destination"
  local dependency resolved
  for dependency in ${(f)$(otool -L "$source" | tail -n +2 | awk '{print $1}')}; do
    resolved="$dependency"
    if [[ "$dependency" == @rpath/* || "$dependency" == @loader_path/* ]]; then
      resolved=""
      for candidate in "${source:h}/${dependency:t}" "${SQLCIPHER_DYLIB:h}/${dependency:t}"; do
        [[ -f "$candidate" ]] && { resolved="$candidate"; break; }
      done
      [[ -n "$resolved" ]] || resolved=$(find /opt/homebrew /usr/local -type f -name "${dependency:t}" -print -quit 2>/dev/null || true)
    fi
    if [[ "$resolved" == /opt/homebrew/* || "$resolved" == /usr/local/* ]]; then
      [[ -f "$resolved" ]] || { print -u2 "Unresolved non-system SQLCipher dependency: $dependency"; exit 2; }
      bundle_dependency "$resolved"
      install_name_tool -change "$dependency" "@loader_path/${resolved:t}" "$destination"
    elif [[ "$dependency" == @rpath/* || "$dependency" == @loader_path/* ]]; then
      print -u2 "Unresolved relative SQLCipher dependency: $dependency"
      exit 2
    fi
  done
}
bundle_dependency "$SQLCIPHER_DYLIB"
install_name_tool -change "$SQLCIPHER_LOAD_COMMAND" @rpath/libsqlcipher.dylib "$APP/Contents/MacOS/SQLCipherProtectedStoreSpike"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/SQLCipherProtectedStoreSpike" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SQLCipherProtectedStoreSpike</string>
<key>CFBundleIdentifier</key><string>com.agentisland.ab117-protected-store-spike</string>
<key>CFBundleName</key><string>AB117 Protected Store Spike</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
print "Built $APP"
otool -L "$APP/Contents/MacOS/SQLCipherProtectedStoreSpike"
! otool -L "$APP/Contents/MacOS/SQLCipherProtectedStoreSpike" | rg -q '/(opt/homebrew|usr/local)/' || { print -u2 "Unbundled local dylib load command remains"; exit 1; }
otool -L "$APP/Contents/MacOS/SQLCipherProtectedStoreSpike" | rg -q '@rpath/libsqlcipher\.dylib' || { print -u2 "Executable does not load bundled SQLCipher"; exit 1; }
for library in "$APP/Contents/Frameworks"/*.dylib; do
  otool -D "$library" | rg -q "@rpath/${library:t}" || { print -u2 "Unexpected bundled dylib ID: $library"; exit 1; }
  ! otool -L "$library" | rg -q '/(opt/homebrew|usr/local)/' || { print -u2 "Unbundled dependency remains in $library"; exit 1; }
done
