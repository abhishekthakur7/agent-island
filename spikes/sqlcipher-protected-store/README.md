# SQLCipher protected-store feasibility spike

Disposable macOS 14+ AB-117 evidence harness for the encrypted local canonical
store boundary in ADR 0008. It is deliberately **not production code** and
contains no production Agent Session schema: its 30 generic fixture records
exist only to exercise a representative protected workload.

**Current host validation: INCOMPLETE; OWNER-ACCEPTED RISK.** This workspace has Command Line
Tools only, no detected SQLCipher pkg-config/dylib, no XCTest framework from
full Xcode, and no Developer ID/notary credentials. A plain `swift build`
therefore compiles against Apple SQLite, which the executable deliberately
rejects as `storage.sqlcipher_unavailable`; it is not evidence of encryption.

The executable uses SQLCipher only when `PRAGMA cipher_version` is present,
the written file has no plaintext SQLite signature, and the same file rejects
an unrelated random key. A normal macOS `sqlite3` link is rejected; the app
never silently degrades to plaintext SQLite. One random 32-byte key is created
in the login Keychain at explicit bootstrap and is required thereafter. A
missing key does not get regenerated on open. The default account is a
generated per-installation identity marker; if that marker is missing while
database bytes exist, opening fails closed.

## Storage and recovery contract

The single-writer store uses `BEGIN IMMEDIATE`, `journal_mode=DELETE`, and
`synchronous=FULL`; metadata and generic record payloads commit together.
Each open requires SQLCipher and SQLite integrity checks plus a supported
schema. The derived projection is rebuilt from verified stored records and
uses a stable SHA-256 digest; it is never authoritative state.

Migration reads and validates the source without mutation, writes a separately
encrypted `.staging` database, verifies it, atomically replaces the primary
while retaining `.rollback`, then reopens/verifies. A staging file blocks all
normal opens until an explicit recovery call verifies the primary and discards
the stage. Missing key, corrupt database, interrupted stage, unknown schema,
integrity failure, and migration failure return a small redacted diagnostic
code only—no keys, paths, SQL, or Interaction Content.

## Local build and evidence

```sh
brew install sqlcipher pkg-config
cd spikes/sqlcipher-protected-store
Scripts/build.sh
Scripts/test.sh
```

`Scripts/test.sh` runs pure deterministic contracts and then the real bundled
SQLCipher/Keychain clean-launch path. The second portion requires an unlocked
login Keychain and cannot be replaced by a unit-test pass. It intentionally
uses temporary database roots and unique Keychain accounts, then removes them.

Developer ID and notarization are outside the personal-use local baseline.
These optional commands remain available if distribution scope changes:

```sh
DEVELOPER_ID_APPLICATION='Developer ID Application: …' Scripts/sign.sh
NOTARYTOOL_PROFILE=agent-island-notary Scripts/notarize.sh
```

`build.sh` copies SQLCipher into `Contents/Frameworks`, rewrites the binary to
`@rpath/libsqlcipher.dylib`, recursively bundles its non-system dynamic
dependencies (including OpenSSL when linked), and rejects unresolved local or
relative load commands. `sign.sh` signs every nested dylib before the hardened
app. Shipping a Homebrew path, an unsigned nested library, or an
unstapled build is a NO-GO. See [the evidence template](Evidence/AB-117-REPORT-TEMPLATE.md)
for the 30-record benchmark/budget report and required unreduced proof.
