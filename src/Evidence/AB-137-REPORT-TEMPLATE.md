# AB-137 evidence report

This template records deterministic evidence only. A fixture or generated schema artifact does not claim a locally installed Codex app-server is supported.

| Area | Evidence required | Fail-closed behavior |
| --- | --- | --- |
| D-mode S1-S6 | exact executable path/version, child ownership, stdio, schema digest, initialization result, epoch | unavailable/pending; native Host or Hooks observation remains separate |
| A1-A7 | capability-specific request/response fixture and live negotiated support | action disabled; no generic control fallback |
| N5 | exact Thread/Turn/item identifiers and source cursors | unresolved/gap, never title/cwd/model/Host matching |

## Degradation matrix

| Condition | State | Action result |
| --- | --- | --- |
| missing executable/schema/live digest, or generated digest drift | failed | no route or lease |
| malformed/oversized/wrong JSON-RPC | failed | no route or lease |
| EOF/timeout/disconnect | disconnected/failed | leases retired; dispatched work indeterminate |
| source gap/reconnect | ready with unresolved gap | reconciliation required; never synthesized completion |

## Deterministic fixture matrix

| Evidence | Fixture/test | Expected outcome |
| --- | --- | --- |
| valid initialize, duplicate response | `initialize-valid.json`, `testHandshakeIsExactlyOnceAndWrongResponseFails` | one initialize response and one `initialized`; duplicate fails |
| wrong/premature/malformed/oversized | `initialize-incompatible.json`, bounded-frame and malformed-frame tests | typed failure; no route |
| independent epoch | reconnect test | new epoch, new initialize, no route recovery |
| Thread/Turn/item identity | `thread-turn-item.json`, actual-shape normalizer tests | native `thread.id`, `turn.id`, `item.id`, status and documented timestamps form canonical immutable identities; no synthetic event ID/sequence |
| protected activity | schema method allowlist | diffs, output, agent messages, and progress are not terminal completion |
| reconciliation/usage/subagent | schema manifest inspection | no source-proven exhaustive cursor, usage field, or stable child identity means unresolved/unavailable/no Subagent Run |
| approval | generated `ServerRequest.json` plus approval params/response schemas | command/file/permission approval uses same JSON-RPC ID, one-use local lease and conservative connection-scoped deadline; no invented method |
| structured question | `ToolRequestUserInput*.json` | experimental schema is unavailable because this connection never opts into experimental API |
| plan display | `turn/plan/updated` schema allowlist | display-only; no approve/reject mapping |
| typed controls | schema allowlist test | only exact listed request methods can ever be considered; current app composition offers none |
| zero-or-one dispatch | ActionAttemptStore integration plus unavailable-approval test | durable attempt primitive is reused; unproven routes perform zero native dispatch; reconnect makes in-flight dispatch indeterminate |
| mode separation | schema/mode test | namespace/mode differ from Codex Hooks; no label/cwd/model/Host merge |

## Manual/live evidence

Captured read-only schema evidence: `/opt/homebrew/bin/codex`, `codex-cli 0.144.6`; `codex app-server generate-json-schema --out <temporary-directory>` (no `--experimental`, `--enable`, WebSocket, or configuration override); SHA-256 `dac1766a4569654dbda02f879f5e977085863f9714273eae1295095a055ca50f` over every generated JSON schema file, sorted by relative path and canonicalized with `jq -S -c`. Raw byte digests vary because generator key ordering is nondeterministic and are not compatibility evidence. The production coordinator regenerates, canonicalizes, and hashes the full semantic bundle before launch, binding executable path/version/digest to its epoch; canonical drift fails closed. The generator command reports experimental maturity, so this remains an explicit opt-in child-process mode.
