# AB-120 Lifecycle Projection Evidence

Capture this report from a real `ApplicationRuntime` / `SessionStore` run.
Do not include Interaction Content, credentials, raw commands, or private
Product state.

## Trace matrix

| Trace | Fact / authority evidence | Expected derived tuple | Result |
| --- | --- | --- | --- |
| Stable duplicate | Same stable source-event ID twice | original projection; one committed revision | |
| Weak key collision | Same declared weak key, different claim | `execution=unresolved`, `observation=fresh` | |
| Reorder / equal time | Source cursor sequence decreases or conflicts | `execution=unresolved`, `observation=gap` | |
| Cursor gap / reset | Cursor skips or resets in one scope | `execution=unresolved`, `observation=gap` | |
| Rewind / compaction | Historical Turn plus current replacement Turn | historical fact retained; current Turn unchanged by late history | |
| Parent / child | Parent terminal evidence while child is working/waiting | `execution=unresolved` | |
| Attention | Pending Attention Request | visible label `needsAttention` | |
| Restart / wake | Reopen a ledger with non-terminal work | `execution=unresolved`, observation degraded/unavailable | |
| Reconciliation | Non-exhaustive or unavailable read | no inferred terminal; unresolved/gap | |

## Replay versus rebuild

Record the same committed ledger revision from initial intake and reopen:

```text
ledgerRevision: <n>
initialProjection: <redacted tuple>
rebuiltProjection: <redacted tuple>
equal: true
```

## Negative proof

Record separate traces showing `transportLost`, Host loss, helper exit, and a
local Action Attempt result do not produce `completed`, `stopped`, or `failed`
without a validated Product fact.
