# AB-138 Cursor Hooks observation evidence

## Verified public contract

On 2026-07-20, `https://docs.cursor.com/agent/hooks` redirected to the Cursor
documentation landing page / 404 rather than a hook specification. Cursor's
published sitemap contained a `hooks-partners` announcement but no end-user
Hooks configuration, supported Cursor version, event schema, stdin/stdout
protocol, timeout, ownership-marker location, or live Host locator contract.

Accordingly this revision records Cursor Hooks as **Unavailable**. It does not
write a configuration file, create a helper artifact, retain a hook envelope,
or emit a Normalized Event Fact. This is a forward-only observation boundary,
not a claim of a working Cursor integration.

## Guarantees tested

- Discovery is read-only and marks the Integration Installation unsupported;
  enable, disable, repair, remove, and verify return unavailable without a
  manifest or mutation.
- The bounded helper is fail-open: malformed, oversized, timeout, transport,
  version, duplicate/gap/collision, and ambiguous-stop observations only have
  redacted diagnostics and cannot close or merge anything.
- Raw IDs, paths, email, transcript locations, commands, output, and content
  are not parsed or exported. A future supported implementation must use only
  received `conversation_id` for Agent Session identity and received
  `generation_id` for Turn identity, in protected local representation.
- There are no action leases, questions, plans, cancellation, terminal input,
  dispatches, or live Cursor Jump Back locator. Attention says to respond in
  Cursor; Jump Back is app-only.

## Evidence fixture

`Fixtures/CursorHooksAdapter/unsupported-contract.json` is deliberately a
negative fixture; it contains no Cursor payload or native identifier.
