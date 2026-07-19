#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
APP="$ROOT/.build/AB117-ProtectedStoreSpike.app"
BIN="$APP/Contents/MacOS/SQLCipherProtectedStoreSpike"
[[ -x "$BIN" ]] || { print -u2 "Run Scripts/build.sh first."; exit 2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ab117-clean.XXXXXX")
ACCOUNT="ab117-clean-$(uuidgen | tr '[:upper:]' '[:lower:]')"
ACCOUNTS=($ACCOUNT)
trap 'for candidate in $ACCOUNTS; do security delete-generic-password -s com.agentisland.sqlcipher-protected-store-spike -a "$candidate" >/dev/null 2>&1 || true; done; rm -rf "$TMP"' EXIT

# First process exercises source validation, a staged v1→v2 target, atomic
# promotion/reopen verification, ciphertext check, and explicit interrupted
# staging recovery. A second fresh process proves durable reopen.
"$BIN" --smoke --storage-root "$TMP" --keychain-account "$ACCOUNT"
"$BIN" --storage-root "$TMP" --keychain-account "$ACCOUNT"

extract_digest() { sed -nE 's/.*"projectionDigest":"([^"]+)".*/\1/p' "$1"; }
"$BIN" --storage-root "$TMP" --keychain-account "$ACCOUNT" > "$TMP/before-kill.json"
if "$BIN" --crash-before-commit --storage-root "$TMP" --keychain-account "$ACCOUNT" >/dev/null 2>&1; then
  print -u2 "Injected pre-commit kill unexpectedly returned"; exit 1
fi
"$BIN" --storage-root "$TMP" --keychain-account "$ACCOUNT" > "$TMP/after-kill.json"
[[ "$(extract_digest "$TMP/before-kill.json")" == "$(extract_digest "$TMP/after-kill.json")" ]] || { print -u2 "Killed transaction changed the durable projection"; exit 1; }

DB="$TMP/protected-store.db"
[[ "$(head -c 16 "$DB")" != "SQLite format 3"* ]] || { print -u2 "plaintext SQLite signature found"; exit 1; }
shasum -a 256 "$DB" > "$TMP/before-missing-key.sha256"
security delete-generic-password -s com.agentisland.sqlcipher-protected-store-spike -a "$ACCOUNT" >/dev/null
if "$BIN" --storage-root "$TMP" --keychain-account "$ACCOUNT" 2>"$TMP/missing-key.stderr" | tee "$TMP/missing-key.json"; then
  print -u2 "Missing Keychain key unexpectedly opened protected storage"; exit 1
fi
rg -q 'storage.keychain_key_missing' "$TMP/missing-key.json"
shasum -a 256 "$DB" > "$TMP/after-missing-key.sha256"
diff -u "$TMP/before-missing-key.sha256" "$TMP/after-missing-key.sha256"

# Preserve original bytes in the temp evidence directory, then verify corrupt
# ciphertext cannot be opened. No automatic key recreation is permitted.
# Use a new app-created key/database to exercise corruption; never recreate
# the removed original key with shell data.
CORRUPT_ACCOUNT="${ACCOUNT}-corrupt"
ACCOUNTS+=($CORRUPT_ACCOUNT)
"$BIN" --smoke --storage-root "$TMP/corrupt" --keychain-account "$CORRUPT_ACCOUNT" >/dev/null
shasum -a 256 "$TMP/corrupt/protected-store.db" > "$TMP/corrupt-before-open.sha256"
dd if=/dev/zero of="$TMP/corrupt/protected-store.db" bs=1 seek=0 count=16 conv=notrunc status=none
shasum -a 256 "$TMP/corrupt/protected-store.db" > "$TMP/corrupt-before-failed-open.sha256"
if "$BIN" --storage-root "$TMP/corrupt" --keychain-account "$CORRUPT_ACCOUNT" 2>"$TMP/corrupt.stderr" | tee "$TMP/corrupt.json"; then
  print -u2 "Corrupt ciphertext unexpectedly opened"; exit 1
fi
rg -q 'storage.database_corrupt|storage.integrity_failed' "$TMP/corrupt.json"
shasum -a 256 "$TMP/corrupt/protected-store.db" > "$TMP/corrupt-after-failed-open.sha256"
diff -u "$TMP/corrupt-before-failed-open.sha256" "$TMP/corrupt-after-failed-open.sha256"

for failure in stage promote kill; do
  ROOT_FOR_FAILURE="$TMP/migration-$failure"
  ACCOUNT_FOR_FAILURE="${ACCOUNT}-migration-$failure"
  ACCOUNTS+=($ACCOUNT_FOR_FAILURE)
  "$BIN" --bootstrap-legacy --storage-root "$ROOT_FOR_FAILURE" --keychain-account "$ACCOUNT_FOR_FAILURE" >/dev/null
  shasum -a 256 "$ROOT_FOR_FAILURE/protected-store.db" > "$TMP/$failure-before.sha256"
  case "$failure" in
    stage) "$BIN" --fail-migration-stage --storage-root "$ROOT_FOR_FAILURE" --keychain-account "$ACCOUNT_FOR_FAILURE" >/dev/null 2>&1 && exit 1 ;;
    promote) "$BIN" --fail-migration-promotion --storage-root "$ROOT_FOR_FAILURE" --keychain-account "$ACCOUNT_FOR_FAILURE" >/dev/null 2>&1 && exit 1 ;;
    kill) "$BIN" --crash-after-stage-verify --storage-root "$ROOT_FOR_FAILURE" --keychain-account "$ACCOUNT_FOR_FAILURE" >/dev/null 2>&1 && exit 1 ;;
  esac
  shasum -a 256 "$ROOT_FOR_FAILURE/protected-store.db" > "$TMP/$failure-after.sha256"
  diff -u "$TMP/$failure-before.sha256" "$TMP/$failure-after.sha256"
  if [[ "$failure" == stage || "$failure" == kill ]]; then
    "$BIN" --storage-root "$ROOT_FOR_FAILURE" --keychain-account "$ACCOUNT_FOR_FAILURE" > "$TMP/$failure-interrupted.json" 2>/dev/null && { print -u2 "Interrupted migration opened normally"; exit 1; }
    rg -q 'storage.interrupted_write' "$TMP/$failure-interrupted.json"
    "$BIN" --discard-interrupted-stage --storage-root "$ROOT_FOR_FAILURE" --keychain-account "$ACCOUNT_FOR_FAILURE" >/dev/null
  fi
  "$BIN" --migrate --storage-root "$ROOT_FOR_FAILURE" --keychain-account "$ACCOUNT_FOR_FAILURE" >/dev/null
done
print "AB-117 clean-launch integration evidence passed (temporary artifacts removed on exit)."
