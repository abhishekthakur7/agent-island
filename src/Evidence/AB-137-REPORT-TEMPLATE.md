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
| missing executable/schema/live digest | failed | no route or lease |
| malformed/oversized/wrong JSON-RPC | failed | no route or lease |
| EOF/timeout/disconnect | disconnected/failed | leases retired; dispatched work indeterminate |
| source gap/reconnect | ready with unresolved gap | reconciliation required; never synthesized completion |

## Deterministic fixture matrix

| Evidence | Fixture/test | Expected outcome |
| --- | --- | --- |
| valid initialize, duplicate response | `initialize-valid.json`, `testHandshakeIsExactlyOnceAndWrongResponseFails` | one initialize response and one `initialized`; duplicate fails |
| wrong/premature/malformed/oversized | `initialize-incompatible.json`, bounded-frame and malformed-frame tests | typed failure; no route |
| independent epoch | reconnect test | new epoch, new initialize, no route recovery |
| Thread/Turn/item identity | `thread-turn-item.json`, missing-identity test | only exact source identifiers normalize; absent source event id becomes unresolved |
| protected activity | schema method allowlist | diffs, output, agent messages, and progress are not terminal completion |
| reconciliation/usage/subagent | schema manifest inspection | no source-proven exhaustive cursor, usage field, or stable child identity means unresolved/unavailable/no Subagent Run |
| approval and structured question | `approval.json`, unavailable-approval test | command is server-request only; absent documented deadline means no Action Lease, response, or invented method |
| plan display | `turn/plan/updated` schema allowlist | display-only; no approve/reject mapping |
| typed controls | schema allowlist test | only exact listed request methods can ever be considered; current app composition offers none |
| zero-or-one dispatch | ActionAttemptStore integration plus unavailable-approval test | durable attempt primitive is reused; unproven routes perform zero native dispatch; reconnect makes in-flight dispatch indeterminate |
| mode separation | schema/mode test | namespace/mode differ from Codex Hooks; no label/cwd/model/Host merge |

## Manual/live evidence

Captured read-only schema evidence: `/opt/homebrew/bin/codex`, `codex-cli 0.144.6`; `codex app-server generate-json-schema --out <temporary-directory>` (no `--experimental`, `--enable`, WebSocket, or configuration override); v2 monolith SHA-256 `5ff91672223f52bdaa35d882db98e7b6a6fccb6add36c96107e64f5fc03fed97`. The generator command reports experimental maturity, therefore no live support is claimed and app composition remains absent.
