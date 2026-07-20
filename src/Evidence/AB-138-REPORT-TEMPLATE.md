# AB-138 Cursor Hooks observation evidence

## Contract provenance

Verified 2026-07-20 from `https://cursor.com/docs/hooks.md` (the canonical
HTML route is `https://cursor.com/docs/agent/hooks`). Cursor documents user
configuration at `~/.cursor/hooks.json`, project configuration at
`<project>/.cursor/hooks.json`, configuration `version: 1`, JSON stdin/stdout
command hooks, and `failClosed` defaulting to `false`.

This adapter installs only marked v1 command entries for documented Agent
hooks: `sessionStart`, `sessionEnd`, tool/activity hooks, `subagentStart`,
`subagentStop`, shell/MCP/read/edit/prompt hooks, `preCompact`, `stop`,
`afterAgentResponse`, and `afterAgentThought`. It omits `failClosed`, so
Cursor's documented fail-open default applies. `beforeSubmitPrompt` is a
command hook; no prompt-type hook and no hook response is installed.

## Boundaries and known limitations

- A received `conversation_id` is the only Agent Session identity and a
  received `generation_id` is the only Turn identity. Similar presentation
  metadata never identifies either. Identity remains protected locally.
- Cursor documents no stable event ID or source sequence. Duplicate handling
  is therefore owner-scoped weak fact evidence; collisions are retained by
  the canonical reducer and transport loss invalidates continuity. Receipt
  order is not Product order.
- `subagentStart` becomes nested only with its documented `subagent_id` and
  matching `parent_conversation_id`. Documented `subagentStop` lacks those
  identifiers, so it is unresolved and closes nothing.
- Only lifecycle/activity/compaction/terminal/session-end facts project.
  Email, transcript paths, subagent transcript paths, workspaces/paths,
  models, files, commands/output, prompts/responses/thoughts and unknown
  fields are discarded.
- The helper accepts one bounded authenticated local IPC envelope with a
  two-second deadline and no stdout/stderr, spool, or replay. Malformed,
  oversized, timeout, unavailable, and transport failures return silently to
  Cursor (fail-open).
- There are no approvals, questions, plans, free-text, cancellation, terminal
  input, action lease, route, or dispatch. Attention says to respond in
  Cursor. Jump Back is honestly app-only because no live Cursor Host locator
  is documented.

## Installation evidence

Installation is explicit and selected-scope only. Read-only discovery and a
fresh plan precede apply; apply rechecks fingerprint/version/policy/symlink
state, records an Ownership Manifest of exact entries, and rereads on verify.
The lossless JSON editor preserves unrelated ordering, whitespace/newlines,
bytes, and permissions. (Cursor's documented path is `hooks.json`, not an
arbitrary `hooks.jsonc` path.) Marker collisions, malformed or
unsupported inputs, policy blocks, symlinks, external entries, and drift do
not mutate. Disable/remove touch only manifest-proven entries; repair makes a
new plan.

Fixtures cover two same-looking conversations, multiple generations,
lifecycle/activity/compaction/session end, source-proven child start, plus
failure/timeout/version/malformed/oversize/duplicate-gap/orphan/ambiguous-stop
and installation preservation negatives. The deterministic AB-138 verifier
executes a faithful lifecycle replay through `ApplicationRuntime` and
`SessionStore`, checks canonical child ownership and redaction sentinels, and
also exercises the authenticated receiver's unresolved child-stop behavior.
