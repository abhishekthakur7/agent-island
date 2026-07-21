# Implementation task: correct hook installation for Claude Code and Codex

## Context
Agent Island installs "documented hooks observation" entries into each agent's
user config. The current Claude installer writes **schema-invalid** entries and
targets **non-existent events**, so every observation hook it installs is
silently ignored by Claude Code and it emits "Unknown hook event" / "Expected
array" warnings. Codex uses a separate path that must be brought to the same bar.

Reference implementation to match (verified correct in the wild): `vibe-island`,
which writes, per event:

    "<Event>": [
      { "hooks": [ { "type": "command",
        "command": "/bin/sh -c '[ -x BRIDGE ] && BRIDGE --source claude; exit 0'" } ] }
    ]

i.e. a correctly-wrapped matcher-group, a guarded command that can never block a
tool call or session, installed on a curated set of **real** events only.

## Decisions already made (do not re-litigate)
1. **Claude event set = vibe-island's exact 12**:
   `PreToolUse, PostToolUse, Notification, PermissionRequest, UserPromptSubmit,
    SessionStart, SessionEnd, Stop, StopFailure, SubagentStart, SubagentStop,
    PreCompact`.
   Explicitly NOT installed: `PermissionDenied`, `ConfigChange`, and the four
   events Claude Code does not recognize — `AskUserQuestion`, `ExitPlanMode`,
   `Wakeup`, `BackgroundTask`.
2. **Entry shape = fixed wrap + guard + keep our marker.** Wrap as
   `{"hooks":[…]}`, wrap the command in `/bin/sh -c '[ -x HELPER ] && HELPER; exit 0'`,
   and KEEP the trailing `# agent-island:claude-code-hooks-observation:<Event>`
   marker so our lossless editor can still find and remove exactly our own entries.
3. **Correctness-first; no dedicated self-heal pass.** The install must write the
   correct set on the FIRST try. We do NOT add a migration/purge pass that scans
   for and deletes foreign or legacy agent-island-marked entries without a
   manifest (self-heal is explicitly out of scope — see revised A3). We DO keep
   two cheap, independently-correct behaviors: (a) `discover` reports drift
   accurately so a person-initiated re-connect can correct it, and (b) the normal
   removal path deletes any event key it empties.
4. Deliverable = these code changes + tests. Both Claude and Codex.
   Codex is retargeted to a `hooks.json` file reusing the Claude JSON editor
   (see revised Part B), NOT the TOML dotted-key line.

## Part A — Claude (`src/Sources/ClaudeCodeAdapter/`)

### A1. Fix the rendered entry — `ClaudeJSONHookEditor.entry(for:helperPath:)`
(`ClaudeJSONHookEditor.swift:47`)
Currently renders a **bare** hook object:

    {"type":"command","command":"'<helper>' # <marker>"}

Change it to render a **wrapped matcher-group** array element:

    {"hooks":[{"type":"command","command":"/bin/sh -c '[ -x \"<helper>\" ] && \"<helper>\"; exit 0' # <marker>"}]}

Requirements:
- The `# <marker>` must remain a literal substring of the JSON `command` value
  (it sits after the closing `'` of `/bin/sh -c '…'`, as a shell comment).
  `remove()`/`inspect()` locate entries by `raw(element).contains(marker)`, so the
  marker must survive verbatim.
- For the four **tool** events (`PreToolUse, PostToolUse, Notification,
  PermissionRequest`) include `"matcher":"*"` on the group, matching vibe-island.
  Lifecycle events get no matcher (match-all).
- `PermissionRequest` group's command hook gets `"timeout":86400` (a permission
  prompt can stay open a long time); every other event omits timeout. Make this a
  named constant so it's tunable.
- Escaping: the helper path can contain spaces (`…/Application Support/Agent
  Island/…`). Double-quote the path *inside* the single-quoted `-c` string, exactly
  as vibe-island does. Add a test with a spaced path.

### A2. Split "installable events" from "ingestable events"
`ClaudeHookName` (`ClaudeCodeAdapter.swift:124`) is used both to PARSE incoming
envelopes (line 552) and to DECIDE what to install (lines 695, 700). These are
different concerns — separate them:
- Add `PostToolUse` and `PreCompact` cases to `ClaudeHookName` (needed so the
  adapter can *ingest* them, since they're now installed).
- Add `public static let installableEvents: [ClaudeHookName]` = the 12 above.
- Change `selector(s)`, `discover`, and `makePlan` (lines 690–712) to iterate
  `installableEvents` instead of `.allCases`.
- Keep `AskUserQuestion/ExitPlanMode/Wakeup/BackgroundTask` out of
  `installableEvents` permanently. Whether they remain in the enum for ingest
  tolerance is your call, but they must never be installed.

### A3. Accurate drift reporting + clean removal (self-heal purge DROPPED)
Decision: the legacy-purge/migration pass is **out of scope** — get the first
install right rather than heal machines the buggy installer already touched.
Replace the old A3 requirement with three smaller, independently-correct changes:
- **Drift detection in `discover`.** `inspect()` already returns `exactMatches`
  separately from `markerMatches`; `discover` currently keys `.ownedIntact` off
  `markerMatches == 1` only (`ClaudeCodeAdapter.swift:711`), so a marked-but-
  wrong-shape entry is mis-reported as healthy. Require `exactMatches == 1` for
  `.ownedIntact` and report `.ownedDrifted` when the marker is present but the
  shape isn't byte-exact. Stays read-only — it only reports; a person-initiated
  reconnect (remove + add) is what actually rewrites a drifted entry.
- **Delete any emptied event key on removal.** In `removeJSON` (the normal
  uninstall/disconnect path), after removing our marked element, if the event
  array is now empty, delete the whole event key — for every event, not just the
  four unrecognized ones. The editor must delete the property, not just the
  element (generalize the existing private `removingMember` used by the Status
  Line editor into a hooks-key removal).
- **Idempotent install.** In `applyJSON`, if a byte-exact correct entry already
  exists for an event (`exactMatches == 1`), skip it rather than failing on the
  existing marker.

### A4. RISK to verify — marker double-counting in `inspect()`
**VERIFIED already mitigated:** `hookEntries(for:)` (`ClaudeJSONHookEditor.swift:292`)
is non-recursive — it returns only top-level event-array elements, not the nested
command objects — so `markerMatches` is already 1 for the new nested shape. No
structural change needed; still add the regression test below.

(`ClaudeJSONHookEditor.swift:84`) `markerMatches` counts objects whose raw
contains the marker. The new shape nests the marker inside `hooks[0].command`, so
if the object enumeration is recursive it will count BOTH the wrapper element and
the inner command object → `markerMatches == 2` → the code at
`ClaudeCodeAdapter.swift:709` flags `.shadowedManaged`/`.ambiguous` and refuses to
manage. Ensure exactly **one** match is counted per installed entry (count only
top-level event-array elements, or dedupe by enclosing array element). Add a
regression test asserting `markerMatches == 1` for a freshly-installed wrapped
entry.

## Part B — Codex (`src/Sources/CodexCLIAdapter/CodexCLIAdapter.swift`)

VERIFIED against the official Codex hooks schema
(developers.openai.com/codex/hooks → learn.chatgpt.com/docs/hooks):
- Codex reads hooks from a **`hooks.json`** file (or inline `[hooks]` /
  `[[hooks.Event]]` array-of-tables in `config.toml`). The `hooks.json` schema is
  **nearly identical to Claude's nested `hooks` object**:

      { "hooks": { "PreToolUse": [ { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "…", "timeout": 30 } ] } ] } }

- The current `hooks.<Event> = ["<helper>"]` dotted-key TOML line is a shape
  Codex does **not** read — same class of bug as the Claude side. It is removed.
- Real Codex event set is **10**: `SessionStart, UserPromptSubmit, PreToolUse,
  PostToolUse, PermissionRequest, PreCompact, PostCompact, SubagentStart,
  SubagentStop, Stop`. Drop the invented `Activity` case from `CodexHookName`
  (and its arm in `CodexHookNormalizer`, `CodexCLIAdapter.swift:240`).

Decision (chosen): **install a Codex `hooks.json` and reuse the Claude JSON editor.**
- Point the Codex installer at a `hooks.json` scope and render the SAME wrapped
  matcher-group element the Claude side now renders, via `ClaudeJSONHookEditor`,
  with a Codex-specific marker prefix (e.g.
  `agent-island:codex-cli-hooks-observation`) kept as the trailing shell comment
  in the `command` value.
- Guarded command: `/bin/sh -c '[ -x "<helper>" ] && "<helper>"; exit 0'`,
  identical to Claude, so a missing/failed helper can never break Codex.
- `"matcher":"*"` on the tool-matched events (`PreToolUse, PostToolUse,
  PermissionRequest`); long `timeout` constant on `PermissionRequest`; lifecycle
  events get no matcher/timeout — mirror the Claude rules.
- Route Codex discover/makePlan/apply/remove through the JSON editor path (as the
  Claude `isClaudeJSON` branch does), replacing the TOML `ExactEntry` line path
  and the TOML-scanning `CodexHooksConfigurationContract.hasExistingEventDefinition`.
- Removal deletes any emptied event key, same as Claude. No self-heal purge.

## Acceptance criteria
- Fresh install on an empty `~/.claude/settings.json` produces exactly 12
  wrapped, schema-valid entries; `claude` (or the settings validator) emits **zero**
  hook warnings.
- Running install twice is idempotent (no duplicates, no drift flagged).
- `discover` reports a marked-but-wrong-shape entry as `.ownedDrifted`
  (repairable), NOT `.ownedIntact`.
- Uninstall/disconnect removes each owned entry and deletes any event key it
  empties, leaving no empty `"<Event>": []` behind.
- Unrelated hooks in the same file (statusbar, AgentPeek, orca, rtk) are byte-for-byte
  untouched — assert via full-file comparison outside the marked ranges.
- `inspect()` reports `markerMatches == 1` per installed entry.
- Codex: install writes a `hooks.json` with exactly the 10 real Codex events in
  the valid nested schema, guarded, idempotent, with the same drift/removal
  behavior. `Activity` is gone from the catalog.
- All commands remain `exit 0`-guarded: a deleted/non-exec helper never blocks a
  tool call, prompt, or session on either agent.
- Out of scope now: self-heal / migration of legacy malformed marked entries.

## Tests to add/update
- `Tests/ClaudeCodeAdapterTests/ClaudeCodeAdapterTests.swift`: rendered-shape
  snapshot (wrapped + matcher + guard + marker + timeout); spaced-helper-path
  escaping; 12-event install set; idempotency; markerMatches==1; drift reported
  as `.ownedDrifted`; removal deletes an emptied event key; unrelated-hooks-
  preserved full-file assertion.
- `Tests/CodexCLIAdapterTests/CodexCLIAdapterTests.swift`: 10-event install set
  (no `Activity`); wrapped hooks.json render + guard + marker; idempotency;
  removal deletes an emptied event key.
- Keep `swift build` green from `src/`. (`swift test` isn't runnable in this
  environment — CI must run the suite.)

## Out of scope
Runtime IPC/helper protocol, capability negotiation, and the helper binaries
themselves. This task only changes what gets written into the config files and
the repair pass.

## Implementation status (done)
- One shared renderer: `ClaudeJSONHookEditor.wrappedEntry(event:keyPrefix:
  markerPrefix:helperPath:matcher:timeoutSeconds:)`. Claude uses it via
  `entry(for:)`; Codex via `CodexCLIInstallationCoordinator.hookEntry(...)`.
- **Critical finding:** there are TWO install paths. The real ship path is
  `AgentIslandApp/.../LaunchIntegrationAutoInstaller` (person-initiated, ADR-0009).
  Claude flows through its coordinator (Part A applies), but Codex previously
  BYPASSED the coordinator with its own inline `codexEntries()` rendering a bare,
  UNGUARDED command. Fixed to call the shared `hookEntry`, so the ship path now
  writes the guarded/wrapped/matcher/timeout shape into `~/.codex/hooks.json`.
- Claude: `installableEvents` (12), wrapped+guarded render, drift detection in
  `discover` (exactMatches), emptied-key deletion in `removeJSON`,
  `ClaudeHookName` gains PostToolUse/PreCompact (+ normalizer arms).
- Codex: coordinator retargeted to `hooks.json` via the JSON editor, `Activity`
  dropped (10 events), guard/matcher/timeout/drift/emptied-key parity with Claude.
- `swift build` from `src/` is green. Render validated out-of-band: every entry is
  valid JSON, parses as a `/bin/sh -c` command, and the guard exits 0 for missing/
  failing/non-exec/spaced-path helpers. Tests written but `swift test` is not
  runnable here (no XCTest) — CI must run the suite.
- Consequence of "no self-heal": machines with the OLD malformed entries are
  refused on reinstall (not repaired); only FRESH installs get the correct set.
