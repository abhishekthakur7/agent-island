# Cursor adapter surface

**Research date:** 2026-07-18  
**Scope:** documented Cursor IDE, Cursor CLI, ACP, Hooks, and SDK behavior.
This evidence does not authorize inspection of undocumented Cursor storage,
process memory, terminal scrollback, clipboard data, or Accessibility surfaces.

## Decision

Cursor has separate Agent Product and Host roles. A Cursor IDE conversation,
Cursor CLI conversation, or ACP-created session owns its Agent Session identity;
the Cursor app, IDE, integrated terminal, and Agents Window are Host surfaces.
This research makes no Host navigation claim.

The Cursor Agent Adapter must expose two explicitly labelled, non-equivalent
tiers:

| Tier | Eligible Agent Sessions | Source of truth | Result |
| --- | --- | --- | --- |
| **IDE Hook observation** | Local Cursor IDE Cmd+K/Agent Chat conversations created after a documented Agent Island Hook is installed | Cursor Hooks input | Rich live observation and source-native policy blocking; no documented companion response route. |
| **ACP control** | Cursor CLI sessions Agent Island starts as an ACP client | ACP JSON-RPC stream/methods | Monitor-and-interact support for documented permissions, questions, plans, todos, subagent completion, cancellation, and terminal status. |

ACP cannot attach to arbitrary existing IDE or interactive CLI conversations.
The Cursor SDK creates separate application-owned agents, so it may be an
adapter fixture, never discovery of an existing person-owned conversation.

## IDE Hook observation

Cursor Hooks use configuration schema `version: 1` in
`~/.cursor/hooks.json` (user) or `<project>/.cursor/hooks.json` (project).
They are command or prompt processes using JSON over stdio. Project hooks are
trusted-workspace only; Cursor watches configuration and reloads it.
[Cursor Hooks](https://cursor.com/docs/hooks.md)

All agent hooks carry these base fields:

| Field | Treatment |
| --- | --- |
| `conversation_id` | Stable Cursor Agent Session ID across turns; use as namespaced source identity. |
| `generation_id` | Cursor Turn ID; changes with each person message. |
| `cursor_version` | Compatibility gate and diagnostic metadata. |
| `model`, `model_id`, `model_params` | Attributed Model context only, never identity. |
| `workspace_roots` | Worktree evidence only; may be multi-root and is Interaction Content. |
| `transcript_path` | Interaction Content locator, not permission to ingest content. There is no documented transcript schema, replay contract, or reply API; do not use it for discovery or recovery. |
| `user_email` | Sensitive identifying data; do not retain/export it in this baseline. |

The local IDE events are `sessionStart`, `sessionEnd`, `preToolUse`,
`postToolUse`, `postToolUseFailure`, `subagentStart`, `subagentStop`,
`beforeShellExecution`, `afterShellExecution`, `beforeMCPExecution`,
`afterMCPExecution`, `beforeReadFile`, `afterFileEdit`, `beforeSubmitPrompt`,
`preCompact`, `stop`, `afterAgentResponse`, and `afterAgentThought`. Tab and
`workspaceOpen` are separate, non-Session surfaces.

| Capability | Evidence | Adapter rule |
| --- | --- | --- |
| Identity and lifecycle | Stable conversation and per-message generation IDs | Create/update only from received source events; never infer identity from title, path, window, or transcript name. |
| Activity/tool state | Generic and tool-specific before/after events, assistant/thought completion | Tool input/output, commands, paths, thoughts, and responses are Interaction Content; project only minimum live state/tool label. |
| Completion/error/abort | `stop` has `completed`, `aborted`, or `error`; `sessionEnd` adds duration and end reason | Agent-loop completion and IDE-lifetime end are distinct; neither substitutes for the other. |
| Context health | `preCompact` has trigger, token counts/window, percentage, and message counts | Show sourced current compaction state only; it is not provider-usage data. |
| Subagent Run start | `subagentStart` has unique `subagent_id`, parent conversation, task, type, model, parallel flag, and optional branch | Represent it as a child of its named parent. |
| Subagent Run completion | `subagentStop` has outcome, summary, duration, counts, changed files, and transcript path | The documented stop payload lacks `subagent_id` and parent ID. It cannot safely close one of several indistinguishable concurrent children; preserve an unresolved completion summary instead of guessing. |

`sessionStart` and `sessionEnd` are fire-and-forget. Hooks have no documented
sequence cursor, acknowledgement, replay, active-session listing, or
backfill guarantee. This tier is forward-only observation, not lossless cold
discovery or recovery.

### Hooks are not external action routing

`preToolUse`, `subagentStart`, `beforeShellExecution`, `beforeMCPExecution`,
and `beforeReadFile` can return policy. The documented Hook contract lacks a
request identifier plus later response API that would let an Agent Island
Attention Request answer a native Cursor approval, question, or plan.
`preToolUse` specifically says `ask` is accepted by schema but not enforced.

Consequently, Hook-tier attention must direct the person to continue in Cursor.
Do not claim that returning `ask`, adding an undocumented local socket, or
editing undocumented Cursor files permits external approval, free-text answers,
or plan review. Observation Hooks must be non-blocking and fail open. Cursor
defaults command-hook crash, timeout, and invalid-JSON handling to fail open;
`failClosed` is for separately person-owned security policy, not Agent Island
availability.

Store `cursor_version` with every Hook event and select an explicit capability
profile. Cursor 3.5 deprecated “Ask Every Time” (May 22, 2026), and Cursor 3.6
introduced Auto-review (May 29, 2026). Unknown versions receive observation
only: never inferred approval semantics.
[Run Modes](https://cursor.com/docs/agent/security/run-modes.md)

## Cursor CLI ACP control

`agent acp` is a documented custom-client transport: newline-delimited JSON-RPC
2.0 over stdio. The client initializes/authenticates, creates or loads a
session, prompts it, consumes `session/update`, handles
`session/request_permission`, and may cancel. The documented example uses
`protocolVersion: 1`. [Cursor CLI ACP](https://cursor.com/docs/cli/acp.md)

| Capability | Documented behavior | Adapter contract |
| --- | --- | --- |
| Identity/lifecycle | `session/new` returns `sessionId`; `session/load` resumes a known session | Persist only returned source IDs. Load only IDs this adapter recorded. |
| Activity/completion | `session/update` streams output; prompt has stop reason; `session/cancel` exists | Map events to the owned Agent Session/Turn; EOF, JSON-RPC error, or child-process exit is transport degradation, not completion. |
| Permission | Blocking `session/request_permission` needs `allow-once`, `allow-always`, or `reject-once` | Source-owned, request-scoped Attention Request. Never broaden/reuse a response. |
| Questions | Blocking `cursor/ask_question` has a tool-call ID, question IDs, choices, and multi-select flag | Support this multiple-choice shape only; do not manufacture free-text questions. |
| Plan review | Blocking `cursor/create_plan` has Markdown, todos/phases, tool-call ID; accepted/rejected-with-reason/cancelled outcomes | Render, accept, or reject with feedback without changing Cursor permission mode. |
| Todo state | `cursor/update_todos` notification has merge semantics | Source activity only, not an independently actionable task list. |
| Subagent completion | `cursor/task` provides task/type and optional model, source ID, duration | Completion notification only; nest only when the source envelope proves parent association. |
| Usage | No ACP token/remaining/reset contract is documented | Do not display Cursor usage for this tier. |

## Other Cursor surfaces and exclusions

| Surface | Safe support | Boundary |
| --- | --- | --- |
| Interactive Cursor CLI | Person-facing agent/plan/ask modes; `agent ls` and `resume` | No documented passive monitor, event stream, or external response API. Do not parse a terminal or impersonate input. [CLI overview](https://cursor.com/docs/cli/overview.md) |
| Headless CLI | An Agent Island-launched `--output-format stream-json` process has progress output | Its process is separate controlled work, not observation/control of an interactive session. `--force` is never an approval bridge. [Headless CLI](https://cursor.com/docs/cli/headless.md) |
| Cursor SDK | Application-created agent/run IDs, streaming, status/cancel, and SDK-run token usage | Requires API credentials and creates separate Cursor work; no baseline credential collection. [SDK](https://cursor.com/docs/sdk/typescript.md) |
| Deep links | Prefill a new prompt for a person to review/confirm | Not Jump Back or an existing-session action. [Deep links](https://cursor.com/docs/reference/deeplinks.md) |
| Agents Window | Cursor 3 UI for parallel work | Cursor Host surface; no documented external query, stable Host Context ID, or exact navigation API. [Agents Window](https://cursor.com/docs/agent/agents-window.md) |

## Failure and reconciliation requirements

1. Installation is explicit/reversible. Manifest only Agent Island-owned Hook
   entries/scripts; preserve person-owned Cursor configuration. Enabled intent,
   loaded configuration, and live event path are separate health states.
2. Hook timeout/crash/invalid JSON, malformed records, ACP stdio exit,
   authentication failure, missing callback response, unknown method, or Cursor
   upgrade stop action routing and mark the tier degraded. None completes,
   dismisses, or merges an Agent Session or Attention Request.
3. Prompts, responses, thoughts, tool data, paths, plans, questions, summaries,
   and error text are Interaction Content. Unknown fields default to Interaction
   Content; credentials are never intentionally collected.
4. Cursor window/process identity, workspace roots, titles, and Agents Window
   rows cannot identify or reopen Agent Sessions. Host navigation needs its own
   evidence and contract.

## Sources

- [Cursor Hooks](https://cursor.com/docs/hooks.md)
- [Cursor CLI ACP](https://cursor.com/docs/cli/acp.md)
- [Cursor Run Modes](https://cursor.com/docs/agent/security/run-modes.md)
- [Cursor CLI overview](https://cursor.com/docs/cli/overview.md) and
  [Headless CLI](https://cursor.com/docs/cli/headless.md)
- [Cursor SDK](https://cursor.com/docs/sdk/typescript.md),
  [Deep links](https://cursor.com/docs/reference/deeplinks.md), and
  [Agents Window](https://cursor.com/docs/agent/agents-window.md)
