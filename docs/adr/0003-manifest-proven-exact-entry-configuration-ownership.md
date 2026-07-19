# Manifest-proven exact-entry configuration ownership

Agent Island treats each explicitly enabled Agent Adapter mode at one selected
scope as an Integration Installation with a local Ownership Manifest. The
manifest proves only the exact marked configuration entry and application-owned
artifacts Agent Island created; it never conveys ownership of a Product
configuration file, directory, profile, repository, or a similar external
entry. Enable, repair, migration, disablement, removal, and cleanup are
separate lifecycle actions. Every mutation uses a fresh approved plan, a
lossless exact-entry editor or documented exact receipt operation, and
post-write verification.

## Consequences

- Discovery and reconciliation are read-only by default; external drift,
  unknown/upstream syntax, policy precedence, and ambiguous ownership produce
  a visible repair/manual-remedy state, never silent rewrite or adoption.
- Runtime disablement and safety gates do not remove configuration. Complete
  cleanup removes all currently manifest-proven artifacts only after a
  dedicated review, and reports residual ambiguous external entries rather
  than claiming success.
- Configuration formats must preserve unrelated comments, ordering, unknown
  fields, symlinks, custom paths, permissions, and external edits. Unsupported
  or lossy representations are intentionally non-mutating.
- This adds manifest migration, exact-entry editing, verification, residual
  reporting, and privacy-safe diagnostics to the architecture, but prevents
  Agent Island from deleting Agent Product data or writing around security
  policy.
