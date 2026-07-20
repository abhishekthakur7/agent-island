# Bounded launch-time Integration Installation

Agent Island automatically discovers installed Agent Products when the
application launches and may create a pristine user-scope Integration
Installation without a separate confirmation. This replaces the prior
approval requirement only for an initial installation whose Product identity,
documented hook contract, configuration source, runtime helper, credential,
and exact-entry mutation are all freshly verified.

The automatic path is deliberately narrower than repair. It may write only:

- Claude Code user hooks in `~/.claude/settings.json` or one existing supported
  `settings.jsonc`;
- Codex CLI's documented user hook registry in `~/.codex/hooks.json` (the
  unrelated `config.toml` and its `notify` setting are never rewritten);
- Cursor user hooks in `~/.cursor/hooks.json`;
- Agent Island-owned Application Support artifacts and product-scoped Keychain
  credentials.

Discovery alone never authorizes a write. A Product must have one unambiguous,
canonical, approved installation identity and a checked-in reviewed contract
covering its current version. Before a Product configuration refers to a
helper, Agent Island must provision its product-scoped credential, bind the
authenticated local listener, verify the bundled helper, and complete a
nonce-bearing probe. Missing or unreviewed evidence produces a visible
unsupported state and zero configuration writes.

Every mutation uses a crash-consistent local journal, a just-before-write
source fingerprint and filesystem-identity check, a lossless exact-entry
editor, an atomic same-directory replacement, reread verification, and an
Ownership Manifest. Concurrent application processes serialize mutations.
Credentials never appear in configuration, arguments, environment variables,
logs, diagnostics, manifests, journals, or receipts.

Automatic installation refuses symlinked mutation targets, malformed or lossy
sources, conflicting or unreceipted matching entries, policy ambiguity,
multiple Product candidates, concurrent source changes, and unavailable
credentials or helpers. It never adopts an external candidate and never
repairs, recreates, upgrades, removes, or rewrites an owned entry after drift.
Those actions retain the fresh person-reviewed plan required by ADR 0003.

## Consequences

- Opening Settings is not required to begin discovery or installation.
- A second launch is an exact manifest-backed verification and performs no
  Product configuration write.
- Installed but unsupported Agent Products remain detected with an actionable
  incompatibility reason rather than receiving speculative hooks.
- Existing configuration and hooks outside Agent Island's exact receipts remain
  untouched.
