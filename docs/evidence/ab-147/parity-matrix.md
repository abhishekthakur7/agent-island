# AB-147 S/I/P/A/J/N/O/H parity matrix

AB-147 maps the frozen baseline to existing local evidence without asserting
unrecorded Product or native UI behavior. “Blocked” means the listed fallback
must be used until a human records the specified capture. Each row has both a
positive and a negative fixture in `src/Fixtures/AB147Parity/parity-v1.json`.

| ID / scope | Product · Adapter mode · Host profile/version/capability | Positive / negative evidence | Expected → observed → fallback | Capture / diagnostic / status |
| --- | --- | --- | --- | --- |
| S-01 concurrent monitoring | Claude Code · Hooks · iTerm2; fixture contract, live versions absent; observation | AB-146 workload / Claude negative | Separate owners and state → headless deterministic only → native Claude/iTerm2 | AB-146 canonical / D-01 / blocked native+human |
| S-02 ordering safety | Codex CLI · Hooks · Warp; hooks fixture, live versions absent; observation-only | independent lifecycle / reorder-gap-duplicates | Gap stays unresolved → authored only → native Codex/Warp | AB-136 / D-02 / blocked human |
| I-01 health/install | Cursor · Hooks · Cursor Host; Hooks v1 fixture; observation | Cursor Hooks lifecycle / negative cases | Intent ≠ Active → authored only → native Cursor/manual remedy | AB-138 / D-03 / blocked human |
| I-02 capability negotiation | Codex · App Server · Orca; reviewed 0.144.6 schema, live current version absent; negotiated typed capability | initialize-valid / initialize-incompatible | Drift retires affected route → fixture/schema only → native Host | AB-137 / D-04 / blocked human |
| P-01 attention presentation | Cursor · ACP · Cursor Host; ACP fixture; local presentation | ACP positive / ACP negative | Nonactivating, no duplicate/stale card → model seam only → keep Host focus/no overlay | AB-146 native matrix / D-05 / blocked native+human |
| A-01 typed actions | Claude Code · Hooks · iTerm2; Hook contract; live version absent; owner-bound action | approval / Claude negative | One live lease, no implied applied outcome → deterministic only → native Claude | AB-135 / D-06 / blocked native+human |
| J-01 exact iTerm2 | Claude Code · Hooks · iTerm2; API fixture; live module/version absent; exact context | exact surface / revalidation negative | Revalidate then report exact level → seam only → native iTerm2 | AB-140 / D-07 / blocked native+human |
| J-02 Cursor Host | Cursor · Cursor Host Adapter · Cursor Host; fixture contract; exact terminal if proven | live reveal / duplicate PID/name | Reject lookalike → fixture only → native Cursor/unavailable | Host fixtures / D-08 / blocked native+human |
| J-03 Warp fallback | Codex CLI · Hooks · Warp; AX boundary; live Warp version absent; app/elected window | jump boundary / permission or stale case | Never guess pane/tab → boundary only → app-only/unavailable | AB-142 / D-09 / blocked native+human |
| J-04 Orca context | Codex · App Server · Orca; runtime ID observed, semantic version absent; exact tab at most | exact child surface / restart-loss-duplicate | No unproven exact surface → read-only+fixture only → native Orca | AB-143 / D-10 / blocked native+human |
| N-01 quiet policy | Claude Code · Hooks · iTerm2; local policy; OS settings absent | notification coordinator tests / quiet+duplicate cases | Suppress disruption, retain state → automated only → deliberate/native inspection | AB-146 matrix / D-11 / blocked human |
| O-01 recovery | Codex CLI · Hooks · Warp; recovery contract; wake/display sequence absent | AB145 recovery tests / restart-loss-duplicate | Invalidate only authority/locator → test only → native Host and reprobe | AB-146 matrix / D-12 / blocked native+human |
| H-01 History | Claude Code · Hooks · iTerm2; workload contract; local History | 31st archive test / active-child overflow test | Archive only safely inactive, sourced recap → headless store only → working set/native Host | AB-146 matrix / D-13 / blocked native+human |
| H-02 Usage Snapshot | Codex · App Server · Orca; schema allowlist; live usage absent | usage presentation tests / unavailable cases | Sourced value or unavailable → test seam only → native Product account | AB-137 / D-14 / blocked native+human |

## Coverage audit

The 14 records cover every canonical area: `S` (2), `I` (2), `P` (1), `A`
(1), `J` (4), `N` (1), `O` (1), and `H` (2). Profiles span Claude Code,
Codex CLI, Cursor, iTerm2, Cursor Host, Warp, and Orca. A record’s
`profileVersion` is deliberately “not captured” where the repository has no
current Product/Host capture. That is an observation, not an omission to be
filled by inference.

## Required review invariants

| Invariant | Evidence rule |
| --- | --- |
| No invented Product truth or owner crossing | Native IDs/cursors and source provenance only; duplicate/gap yields ambiguity or unresolved. |
| No stale/duplicate control | Action Lease is live, single-use, owner-bound; notification policy retargets rather than repeats. |
| No unsafe navigation | Revalidate a current Host locator; report achieved level, never guess title/path/window. |
| No active-work loss | History/cleanup cannot treat Host loss, restart, wake, or attention as Product completion. |
| No disruptive/duplicate presentation | Nonactivating selected-display Overlay and Quiet Scene/filter policy govern automatic presentation. |
| No privacy/config overreach | Exact manifest-owned entries only; diagnostics remain redacted and no Interaction Content is required. |
| No dishonest health or inaccessible fallback | Intent/capability/outcome are separate; unavailable has a readable native-Host next step. |

The frozen baseline also requires visual comparison of collapsed Clean/Detailed
island, expanded session list/detail/footer, setup banner, Settings, History,
and Usage Snapshot on both display forms. That comparison is intentionally
left to the [AB-147 human review form](human-review-form.md).
