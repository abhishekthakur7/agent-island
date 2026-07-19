# Codex CLI adapter surface

Observed and documented on 2026-07-18 with `codex-cli 0.144.5` on macOS. This
is an integration-surface record, not permission to parse or mutate private
Codex state indiscriminately.

## Conclusion

Codex can support the Parity Baseline through two deliberately different
paths:

1. A version-pinned local `codex app-server` connection is the rich control
   path for Codex Threads that Agent Island starts or explicitly resumes through
   that connection. Its documented JSON-RPC protocol provides native Thread,
   Turn, item, approval, question, plan, token-usage, interruption, and
   streaming semantics.
2. Opt-in Codex lifecycle hooks are the observation path for independently
   launched interactive CLI work. They can identify the parent Codex Session,
   Turn, working directory, permission mode, tool/permission activity, and
   subagent start/stop. They do not grant Agent Island authority to answer an
   approval or take over a running terminal conversation.

The adapter must keep these modes distinct. An observed-only CLI Session can
notify and Jump Back, but an action that needs a response remains native to the
Codex terminal. A directly connected app-server Thread can receive a response
only through the outstanding server request that supplied its native IDs.

## Version and compatibility boundary

`codex app-server` is labelled experimental by the installed CLI, although its
protocol is documented and is used by rich Codex clients. Its generated schema
is version-specific. The adapter therefore pins the discovered CLI version and
generates a fresh schema during setup or after every CLI update:

```sh
codex --version
codex app-server generate-json-schema --out <empty-temporary-directory>
```

The 0.144.5 bundle contains `codex_app_server_protocol.v2.schemas.json`,
`ServerNotification.json`, and `ServerRequest.json`. A connection must first
send `initialize`, then `initialized`; it must retain only methods and fields
offered by that generated schema. It must not opt into
`capabilities.experimentalApi` merely to claim feature parity. Experimental
methods are separately detected, labelled, and disabled by default.

Use a child process over the documented default `stdio://` JSONL transport.
The WebSocket listener is documented as experimental and unsupported, and a
non-loopback listener can be unsafe without explicit WebSocket authentication.
It is not a baseline transport.

## Supported capability record

| Parity concern | Documented/observed Codex surface | Adapter rule |
| --- | --- | --- |
| Native identity and recovery | App-server `thread/list`, `thread/read`, `thread/start`, `thread/resume`, and `thread/fork`; Thread/Turn notifications carry `threadId` and `turnId`. | Namespace the native thread ID as Codex-owned. Recover only through the same native ID; never match a title, cwd, model, or terminal pane. |
| Live state and completion | `thread/started`, `thread/status/changed`, `turn/started`, `item/started`, item deltas/completion, `turn/completed`, and `thread/archived`/`unarchived`. | Subscribe while directly connected. On reconnect, read/list native Threads and reconcile by ID; mark a gap rather than inventing missing events. |
| Work control | `turn/start`, `turn/steer`, `turn/interrupt`, plus thread archive, unarchive, fork, and resume. | Send only to an explicitly selected, directly connected Thread. Treat an interrupt response as a request accepted by Codex, not proof that work has stopped; wait for `turn/completed`. |
| Command, file-change, and permission attention | Server requests `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, and `item/permissions/requestApproval`, with native thread, turn, item, timestamp, and where applicable opaque `approvalId`. Their response schemas require a decision or granted permission profile. | Create one durable Attention Request per outstanding server request. Route the response only through that request's JSON-RPC ID and supplied native IDs. A stale, disconnected, or already-resolved request is not retryable by guessing. |
| Questions | `item/tool/requestUserInput` supplies `threadId`, `turnId`, `itemId`, questions, and an optional auto-resolution timeout; the response maps question IDs to answers. It is explicitly **EXPERIMENTAL**. `mcpServer/elicitation/request` can provide an MCP form response, but only when the client opted into that capability. | Expose structured/multi-question UI only when the generated schema and negotiated capability contain it. Otherwise treat Codex's prose question as message content and answer via the next native Turn/steer action; do not manufacture choice IDs. |
| Plan flow | Interactive Codex has `/plan`; app-server emits `turn/plan/updated` with step/status pairs. `item/plan/delta` is explicitly experimental and its concatenation is not guaranteed to equal the completed plan. | Present the completed `turn/plan/updated` state as the plan. There is no documented special plan accept/reject RPC in this surface; review comments are a scoped Turn input/steer, not a fictional approval. |
| Diff and detailed activity | `turn/diff/updated`, command/file-change item output and patch deltas, agent-message deltas, and tool progress. | Display only data received on the active connection and classify it as sensitive Interaction Content. Tool output is progress, not proof of a completed action. |
| Subagent activity | Codex documents subagent workflows. Hooks expose `SubagentStart` and `SubagentStop`; in this build, the persisted event stream also observed `sub_agent_activity` start/interacted records. The generated app-server notification surface has no separately documented, stable Subagent Run lifecycle or child identity. | Show hook-detected subagent activity as capability-limited child activity. Do not assign a stable Subagent Run identity, offer individual controls, or infer parent/child continuity from the observed local JSONL format. |
| Context and usage | `thread/tokenUsage/updated` includes last and total token breakdowns and context-window capacity. The schema also offers account rate-limit and usage reads/updates. | Thread token/context display is available in direct mode. Account usage/rate-limit display is optional, least-privilege, and unavailable rather than estimated when the account API or fields are absent. It is not billing truth. |
| Diagnostics | `codex doctor --json` is a redacted machine-readable health report; `codex features list` reports maturity/effective feature state. | Use only as consented setup/repair diagnostics. Store a redacted capability result, never credentials, full configuration, or raw transcript content. |

## Hooks for independently launched CLI Sessions

Codex loads lifecycle hooks from `hooks.json` or inline `[hooks]` beside active
configuration layers. The useful locations are user-level
`~/.codex/hooks.json` / `~/.codex/config.toml` and trusted project-level
`.codex/hooks.json` / `.codex/config.toml`. Profiles are
`$CODEX_HOME/<profile>.config.toml`.

The documented hook events are `SessionStart`, `UserPromptSubmit`,
`PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`,
`SubagentStart`, `SubagentStop`, and `Stop`. Common hook input contains the
native `session_id`, `cwd`, event name, model, and transcript path; turn-scoped
events include `turn_id`. Codex explicitly says the transcript format is not a
stable hook interface.

The adapter's hook process should emit a minimal, authenticated local event to
Agent Island. It should send identifiers and classified state by default, and
send command or prompt content only when the person has opted into that local
display. Hook behavior has important limits:

- Matching hooks run concurrently; their arrival order is not causal order.
- Unmanaged hooks are skipped until their exact definition is trusted. A
  changed definition needs review again, and hooks can be disabled.
- Only command hooks run today; parsed `prompt`, `agent`, and asynchronous
  handlers are skipped. The default hook timeout is 600 seconds.
- `PermissionRequest` observes a permission request but is not an Agent Island
  approval callback. For an independently launched terminal Session, approval,
  denial, and free-text response stay in the Codex UI.
- Tool hooks are a guardrail, not a complete security or telemetry boundary;
  hosted-tool paths and specialised paths may not use them.

Setup must add only an explicitly owned hook entry after review and preserve
every unrelated config field and comment. Disable/uninstall removes only that
verified entry and local receiver state; it never deletes `CODEX_HOME`, session
files, credentials, or another hook.

## Additional observable surfaces and non-contracts

`codex exec --json` and `codex exec resume --json` provide machine-readable
JSONL for non-interactive work launched by the adapter. They are useful for a
separate non-interactive capability, but they do not turn a terminal session
into an interactively controllable one. If a fresh approval cannot be surfaced
in a non-interactive flow, Codex reports a failure back to the run.

`CODEX_HOME` (normally `~/.codex`) is a documented root for configuration,
auth, logs, sessions, skills, and standalone package metadata. The installed
0.144.5 state happened to contain JSONL session rollouts and SQLite state.
Their observed envelope included `session_meta`, `event_msg`, `response_item`,
`turn_context`, and `sub_agent_activity` payloads, but neither the local file
layout nor transcript/rollout JSONL shape is documented as a public adapter
contract. Agent Island may inspect it only as a user-consented,
version-gated, read-only diagnostic/reconciliation hint. It must never tail it
as the authoritative live feed, mutate it, or derive action routing from it.

## Failure and degradation rules

- If the executable, schema generation, initialize handshake, or a required
  stable method is unavailable, disable direct mode and explain the failed
  capability. Do not fall back to private state-file writes or terminal key
  injection.
- Before an app-server connection is initialized, requests fail; duplicate
  initialization also fails. A disconnect invalidates every outstanding
  Attention Request until Codex proves its state through the reconnected
  protocol.
- The documented WebSocket listener can return `-32001` (server overloaded).
  If a user explicitly enables it for local use, retry new requests with capped
  exponential backoff and jitter; never replay a completed response.
- An experimental method/field without `experimentalApi` is rejected. An
  experimental schema field, auto-approval review payload, or plan delta is
  not a durable storage contract.
- A hook can be missing, untrusted, disabled, timed out, duplicated across
  config layers, or unable to deliver to Agent Island. Mark the observed CLI
  Session stale/unknown and offer Jump Back; do not mark it complete or imply
  that the attention was resolved.
- Codex may persist no reusable local session for an `--ephemeral` execution.
  Archival/deletion and compaction are Product actions and must be represented
  as source state, not silently replaced by local retention behavior.

## Sources and reproduction

- Codex Manual, refreshed 2026-07-18: [App Server](https://learn.chatgpt.com/docs/app-server.md), [Hooks](https://learn.chatgpt.com/docs/hooks.md), [Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security.md), [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), and [non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).
- Local, read-only verification: `codex --version` (`0.144.5`), `codex --help`, `codex exec --help`, `codex app-server --help`, `codex doctor --summary`, `codex features list`, and the version-specific JSON schemas generated by the command above.

The exact installed protocol is evidence for 0.144.5 only. The setup health
check, regenerated schema, and explicit degradation states are the durable
contract for later Codex releases.
