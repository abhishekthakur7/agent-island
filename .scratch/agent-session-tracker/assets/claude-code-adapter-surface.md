# Claude Code Agent Adapter surface

**Research date:** July 18, 2026  
**Observed local build:** Claude Code `2.1.205` (`claude --version`)  
**Scope:** documented local Claude Code CLI/IDE behavior only; Remote Control,
cloud sessions, and unsupported transcript scraping are not integration paths.

## Finding

Claude Code's documented hooks are a sufficient, consented event and action
surface for a capability-aware Claude Code Agent Adapter. The installer can
register an application-owned local command hook that forwards structured JSON
to Agent Island over authenticated local IPC. Hooks supply native session IDs,
working directory, permission mode, lifecycle and subagent signals, tool
context, plan Markdown, and structured question options.

This is not a general remote-control API for an arbitrary interactive Agent
Session. The Adapter must not infer unsupported control from terminal text,
directly watch undocumented `~/.claude/projects` layouts, simulate keystrokes,
or issue a competing `claude --resume` process against a live interactive
session. Where a requested action has no documented hook round trip, the only
honest action is Jump Back to the owning Host Context.

## Compatibility policy

Treat `2.1.205` as the observed compatibility baseline, not as a claim that
later behavior is unchanged. Record the executable version at setup and on
every health check; gate a capability at its documented minimum version and
report unknown/new values as degraded until probed. Relevant documented gates
are `prompt_id` at 2.1.196, background-session notifications at 2.1.198, the
`manual` permission-mode alias at 2.1.200, and subagent status-line model and
context fields at 2.1.205. Do not rely on features documented as 2.1.206+
(for example sibling rosters), 2.1.208+ (some background-task behavior), or
2.1.211+ (forwarded subagent text and revised settings-local location) when
supporting the observed build.

## Safe observable surface

| Surface | Documented data available to the Agent Adapter | Parity Baseline use and constraint |
| --- | --- | --- |
| Session identity and start | `SessionStart` and every hook provide `session_id`, `cwd`, `transcript_path`; `prompt_id` after the first prompt; SessionStart may provide model. | Use the namespaced Claude Code `session_id` as the Agent Session identity. Treat model/name as attributed display context, never identity. `transcript_path` is asynchronous and may lag; do not use it to decide current state. |
| Activity and completion | `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Stop`, `StopFailure`, and `SessionEnd` are available. `Stop` provides final assistant text plus `background_tasks` and scheduled wakeups; `StopFailure` classifies rate limit, overload, authentication, billing, model, server, output-limit, and unknown failures. | Produce active, completed, and error presentation from hook events. A `Stop` with running background work is not terminal completion; user interrupt does not fire `Stop`; `SessionEnd` is cleanup, not proof of successful completion. |
| Attention notifications | `Notification` has `permission_prompt`, `idle_prompt`, authentication and MCP-elicitation types; 2.1.198+ also adds `agent_needs_input` and `agent_completed` while terminal agent view is open. | Notification events are reliable cues to reveal or notify, but only a `PermissionRequest` or `PreToolUse` event supplies action context. Notification hooks cannot block or change a notification. |
| Permission request | `PermissionRequest` has `tool_name`, complete `tool_input`, current `permission_mode`, and the Product-provided `permission_suggestions` (including the allowed persistence destination). It may synchronously return allow/deny, amended input, or only one of the supplied rule/mode/directory updates. | Render approval context and the actual Product-provided always-allow choices. A local helper may wait for a request-scoped Island response, then return exactly one allow/deny decision. It must not manufacture a broader rule/mode or override an existing deny/ask/managed rule. |
| Questions | `PreToolUse` observes `AskUserQuestion`: one to four option questions, optional multi-select, and an `answers` mapping accepted through `updatedInput`. | Support documented multiple-choice and multi-select only. The documentation does not establish a general free-text question-response protocol for an interactive existing session; surface free text only when a future capability probe proves it. |
| Plan review | `PreToolUse` observes `ExitPlanMode` with injected Markdown `plan` and `planFilePath`; its post-tool result carries the approved plan. The Product itself changes mode after its native approval choices. | Render the Markdown plan and offer only the documented approval path that returns a valid updated tool input. Do not promise arbitrary written plan-revision feedback: the documented tool input has no feedback field. For "keep planning" or direct plan editing, Jump Back to the owning Host Context. |
| Tool state | `PreToolUse` precedes every tool, with `tool_use_id`, inputs and a decision of allow/deny/ask/defer; post-use events report success/failure. `PermissionDenied` describes an auto-mode classifier denial but cannot reverse it. | This can make normal activity and permission context timely. It is not a license to silently change Product permissions. The `defer` round trip works only for a `claude -p`/SDK caller, one tool at a time, and is ignored interactively; it is not part of the baseline interactive Adapter. |
| Subagent Runs | `SubagentStart` supplies `agent_id` and `agent_type`. `SubagentStop` adds the child transcript path and final assistant text. `PostToolUse` for `Agent` adds child model, duration, token total and tool count for completed foreground work; background launch returns no final usage. | Show children under the owning Agent Session using `agent_id`; a Start event cannot be blocked. Treat a child as completed only on Stop/stop result, not on launch. Do not read or expose its transcript merely because a path exists. |
| Configuration changes | `ConfigChange` identifies user, project, local, policy, and skills sources and may name the changed file. Claude reloads most settings (including hooks and permissions) during a session. | Reconcile health when the Agent Adapter's owned entry disappears, becomes invalid, or is shadowed. Do not block the person's unrelated configuration change. |
| Session data/usage | A configured `statusLine` command receives current model, session ID, context percentage, cumulative cost/duration, lines changed, and subscriber rate-limit windows after an API response. OpenTelemetry can export token/cost metrics and detailed events when independently configured. | Usage is optional and explicitly opt-in. Do not replace or wrap a person's status line by default, and do not enable OTel because it is an outbound telemetry integration. There is no documented, general, passive local usage API for arbitrary interactive Agent Sessions; show no usage header when it is unavailable. |

## Action-routing rules

1. The hook helper creates an Attention Request only while its synchronous
   Claude Code hook invocation remains live. Its internal request key includes
   the Agent Session identity, prompt ID when present, hook event, tool-use ID
   when supplied, and a helper-generated nonce. `PermissionRequest` lacks a
   `tool_use_id`, so it must never be matched by command text or by a later
   request alone.
2. The helper validates the response against the pending hook's exact native
   input, permission mode, and Product-provided suggestions before it emits
   JSON. Expired, duplicate, disconnected, or mismatched responses do
   nothing; the terminal retains its native prompt and Agent Island presents
   the routing failure.
3. `PermissionRequest` may return `allow` or `deny`; permission updates are
   allowed only by echoing an offered `permission_suggestions` entry. Existing
   deny and ask rules, MCP interaction requirements, and managed policy still
   win. Bypass mode is never enabled by Agent Island.
4. `AskUserQuestion` and `ExitPlanMode` require `PreToolUse` to return
   `allow` plus a complete `updatedInput`; an allow alone does not satisfy
   their user-interaction requirement. The helper may wait only within its
   configured hook deadline and must fail closed to the native terminal prompt
   when it cannot validate or reach Agent Island.
5. Cancellation, arbitrary turn prompting, text-only plan revision, mode
   cycling, and interactive-subagent steering have no documented general
   Adapter action. They are Host Context actions, not Island controls.

## Installation and configuration boundary

Claude Code's supported settings scopes are `~/.claude/settings.json`,
`.claude/settings.json`, and `.claude/settings.local.json`; command-line and
managed settings take precedence, and permission arrays merge. The local file
also stores a person's permanent approvals. User settings are therefore the
only appropriate default location for an opt-in, machine-wide personal Agent
Adapter hook. A project entry requires a separate explicit decision because it
changes shared repository configuration.

The setup flow may add a uniquely recognizable, absolute-path command-hook
entry for the Agent Island helper in the selected scope. It must preserve every
unrelated hook, rule, MCP setting, formatting, symlink, and external edit; it
must not rewrite a configuration file whose syntax or formatting it cannot
round-trip losslessly, and may remove only the exact entry it previously
installed. It must not modify permission mode, allow/deny rules,
`statusLine`, `subagentStatusLine`, OTel environment variables, or managed
settings. `ConfigChange`, a fresh `claude --version`, and a no-action helper
probe form the health signal; they are not permission to repair automatically.

The helper is security-sensitive: documented command hooks run with the local
user's full permissions. It must use an absolute executable path, validate all
JSON as untrusted input, redact sensitive paths/content before diagnostics,
authenticate its local IPC peer, enforce a small timeout, and never execute
data from a tool input as shell syntax. Setup must explain that safe mode,
bare mode, disabled hooks, excluded setting sources, untrusted workspaces,
invalid JSON, managed policy, or a removed hook can make monitoring/actions
unavailable without ending the native Agent Session.

## Failure and degradation matrix

| Condition | Required Adapter behavior |
| --- | --- |
| Helper unavailable, IPC rejects a request, timeout, malformed hook JSON, or duplicate event | Do not approve, deny, or persist anything. Preserve the native Claude Code flow where possible; mark the Agent Adapter degraded with a reason. |
| Session interrupted, hook missed, transcript lagged, compaction/restart, or hook ordering differs | Reconcile only from a new documented event. Never synthesize completion, replay a stale Attention Request, or derive current truth from an on-disk transcript layout. |
| `Stop` while `background_tasks`/wakeups remain | Keep the Agent Session active/idle rather than completed; child events determine child state. |
| `StopFailure`, auto-mode `PermissionDenied`, or unavailable auto mode | Present a Product-originated error/denial state and Jump Back. Do not retry, relax a permission mode, or reclassify as ordinary completion. |
| Settings source disappears, invalid settings, workspace trust/safe/bare mode disables hooks, or managed policy wins | Report capability unavailable and give a non-destructive repair explanation. Do not write around policy or enable itself elsewhere. |
| Unsupported version/capability | Disable only the affected capability, retain passive Host navigation where available, and require explicit setup/revalidation after upgrade. |
| Claude Code has already resolved an attention prompt in its terminal | Atomically retire the Island Attention Request; a later Island action must be rejected as stale. |

## Downstream contract inputs

- The normalized Adapter contract needs independently negotiated capabilities
  for structured questions, plan approval, permission approval/denial,
  permission-suggestion persistence, subagent visibility, completion,
  failure, and optional usage. Do not collapse them into an `isClaudeCode`
  boolean.
- Attention routing needs a live synchronous-action lease and a native-input
  fingerprint. It must distinguish Product-owned permission updates from a
  session-only allow/deny decision.
- The attention-flow prototype should include multiple choice, multi-select,
  plan approval with Markdown, native-terminal fallback, and unsupported
  free-text/revision cases.
- Integration setup needs exact-entry ownership, version/capability health,
  external-edit reconciliation, and a no-automatic-repair rule.

## Sources

All sources were consulted on July 18, 2026.

- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks): lifecycle, hook locations, JSON schemas, decision controls, async limits, security, questions, plan tool input, subagents, and failures.
- [Claude Code settings](https://code.claude.com/docs/en/settings): scopes, paths, precedence, reload behavior, and status verification.
- [Configure permissions](https://code.claude.com/docs/en/permissions) and [choose a permission mode](https://code.claude.com/docs/en/permission-modes): mode semantics, rule precedence, protected paths, and plan approval behavior.
- [Run Claude Code programmatically](https://code.claude.com/docs/en/headless): JSON/stream output and its non-interactive defer/resume boundary.
- [Customize your status line](https://code.claude.com/docs/en/statusline): optional context, cost, model, rate-limit, and subagent fields.
- [Create custom subagents](https://code.claude.com/docs/en/sub-agents): background lifecycle, failures, stable child IDs, and transcript retention.
- [Monitoring](https://code.claude.com/docs/en/monitoring-usage): opt-in OpenTelemetry metrics/events and their privacy boundary.
