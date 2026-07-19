# Normative parity acceptance matrix and deviation register

**Version:** 1.0.0  
**Record date:** 2026-07-18  
**Owner:** [Agent Island specification](../SPEC.md) (normative appendix)  
**Source baseline:** Vibe Island v1.0.42, observed 2026-07-18  
**Record scope:** specification completeness, not a production-test report.

This is the complete acceptance record required by the [Parity Baseline
inventory](parity-baseline-inventory.md), [parity acceptance
standard](parity-acceptance-standard.md), and `SPEC.md`. It preserves the
first-class scope: Claude Code, Codex CLI, and Cursor; iTerm2, Cursor Host,
Warp, and Orca; macOS 14+ on Apple Silicon. The original evidence is the
frozen [local research record](../../../VIBE_ISLAND_FUNCTIONALITY.md), E1–E4
in the inventory. It does not report an implementation or owner-review pass.

## Normative interpretation and result legend

- **Applicable** means the cell must be tested when its negotiated Capability
  and evidence are available; it does not pre-claim that a future build has
  that Capability.
- **N/A** is an explicit out-of-combination cell, not an omitted cell. An
  unavailable negotiated capability is applicable and must take the stated
  fallback instead.
- **Result** has two parts: `pass` means this version contains the required
  normative specification trace; `blocked` means production/visual evidence
  has not been collected. No `pass` in this document is a production or
  owner-approval result.
- A row with an approved deviation says `approved deviation / blocked`; the
  deviation preserves the baseline job but still needs its stated production
  evidence. A proposed deviation is a release/specification gap and keeps
  this ticket open.

## Product × Adapter-mode × Host cell profiles

The following compact profile is the complete cross-product cell register.
It is referenced by every matrix row; a row's `Modes` value states the
feature-level capability within each applicable cell. Host navigation is an
independent Host capability and is resolved by `H` below, never inferred from
the Agent Adapter mode.

| Mode code | Product × Adapter mode | iTerm2 | Cursor Host | Warp | Orca | Evidence / boundary |
| --- | --- | --- | --- | --- | --- | --- |
| `C` | Claude Code documented Hooks | C-I applicable | C-C applicable | C-W applicable | C-O applicable | [Claude surface](claude-code-adapter-surface.md): version-gated hook observation and only live documented callback actions. Host association must be separately evidenced. |
| `D` | Codex CLI direct app-server | D-I applicable | D-C applicable | D-W applicable | D-O applicable | [Codex surface](codex-cli-adapter-surface.md): version-pinned direct stream/request surface; its Product capability is Host-independent and a Host Context is optional/separately evidenced. |
| `K` | Codex CLI observed Hooks | K-I applicable | K-C applicable | K-W applicable | K-O applicable | [Codex surface](codex-cli-adapter-surface.md#hooks-for-independently-launched-cli-sessions): independent terminal observation; no terminal prompt takeover. |
| `R` | Cursor IDE Hooks | N/A | R-C applicable | N/A | N/A | [Cursor surface](cursor-adapter-surface.md#ide-hook-observation): local Cursor IDE Agent Sessions only; forward-only observation, no external response. |
| `A` | Cursor ACP controlled session | N/A | A-C applicable | N/A | N/A | [Cursor surface](cursor-adapter-surface.md#cursor-cli-acp-control): Agent Island-started ACP sessions only; typed request responses while the callback is live. |
| `H` | Host navigation, for any above cell with an evidenced Host Context | `exactSurface` live iTerm2 session ID; then `exactTab`, window, app | live extension-held integrated terminal `exactSurface`; IDE Agent threads only workspace/file or app | app-only; opt-in Accessibility `windowBestEffort` only | runtime handle `exactTab`; then workspace/file or app | [Host matrix](host-navigation-capabilities.md#host-matrix); [Host Context decision](host-context-identity-navigation-fallback.md). No title/path/Space/AX label creates exactness. |

`C`, `D`, and `K` apply only to sessions launched/presented at the named Host
or separately associated by strong evidence. `R-C` and `A-C` are the only
Cursor Product cells; no Cursor Hook or ACP capability is silently extended
to a terminal in another Host. In every applicable cell, unknown/incompatible
versions, missing proof, disabled Installation, or lost liveness narrows the
Capability and yields its row fallback—not an inferred replacement.

## Reproducible scenario catalogue

Each matrix row names one positive (`+`) and negative (`−`) scenario below.
Fixtures use recorded capability/version/Host evidence, a controllable Adapter
or faithful protocol fixture, visible Island/Settings/Host outcome capture,
and redacted Diagnostic Bundle correlation. The matrix records future evidence
requirements; it records no invented test execution.

| Scenario | Reproducible positive and negative observation |
| --- | --- |
| `S` | **+** Negotiate each listed mode, deliver native start/activity/child/complete facts for concurrent sources, then inspect sourced aggregate, health, recap, and child hierarchy. **−** Replay/reorder/omit a fact, lose the integration, or present ambiguous child completion; retain one unresolved/evidence-limited record, never a guessed completion or false health. |
| `I` | **+** Render resting/detailed, expanded, focused recap, rich sourced task/child, built-in-notch and external forms. **−** Long/unsourced content, reduced accessibility settings, or protected notch pressure must truncate/compact/scroll and preserve text, ownership, bounds, and original identity. |
| `P` | **+** Deliver start, completion, and attention events under eligible policy and observe focused reveal, priority, independent list state, and configured hover/click. **−** Compete events, rapid pointer exit, interaction, quiet scene, or collapse; no flicker, timer loss, invisible hit region, focus theft, or universal click meaning. |
| `A` | **+** With live request-scoped typed capability, queue parallel permission/question/plan requests, validate draft, confirm, dispatch once, and acknowledge the source outcome. **−** Use observation-only, stale, mismatched, expired, disconnected, unsupported semantic, or resolved-elsewhere input; dispatch zero actions and show exact Host fallback. |
| `J` | **+** Revalidate a live host locator and report its achieved level. **−** Close/reload/recreate it, deny Accessibility, duplicate title/window, or change Space; invalidate and report only the supported lower level. |
| `N` | **+** Feed one eligible event through configured policy/sound/filter/Usage Snapshot and observe one bounded signal bundle and correct Settings values. **−** Replay, filter, quiet, mute, probe, missing/stale usage, or revert bridge; no duplicate/secret payload/estimate/Product-state mutation. |
| `O` | **+** Discover read-only, explicitly enable, plan/apply/verify exact owned entry, configure Settings/onboarding/preview, then inspect health/diagnostics. **−** Introduce drift, unknown syntax, policy, symlink, lossy format, unavailable display, or destructive cleanup request; make no unproved mutation and expose repair/residual/withdrawal. |
| `H` | **+** Exercise duplicate/reorder/restart/wake, 30-session overflow, Overlay display/accessibility, and recovery fixture. **−** Seed identity/action/configuration/privacy/accessibility failure; preserve evidence and fail closed without active-work loss, false truth, or unsafe navigation. |

## Complete inventory matrix

`Req` refers to User Stories (`US`), Implementation Decisions (`ID`), and
Testing Decisions (`TD`) in [SPEC.md](../SPEC.md). `Decision/evidence` names
the controlling closed decision plus the frozen inventory/original evidence.
All rows are source-evidence dated 2026-07-18 and require a future capture of
application, macOS, Product, Adapter, Host, contract, and capability versions.

| ID | Req | Decision/evidence | Cells and capability | + / − | Fallback / deviation | Result |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | US 1–3, 52, 57–63; ID 7–9; TD 2 | Inventory S1 E1/E2; adapter contract | C,D,K,R,A observation; H where present | S+/S− | Degraded health, native work continues | pass / blocked |
| S2 | US 4–8, 13–16; ID 1,4–6; TD 1,7,12 | Inventory S2 E1/E2; lifecycle | C,D,K,R,A sourced fields only; H | S+/S− | Missing fields absent, never identity | pass / blocked |
| S3 | US 5–7,11; ID 4–9; TD 1,2,7 | Inventory S3 E1/E2; adapter surfaces | C,D,K,R,A negotiated activity | S+/S− | Unavailable activity is omitted | pass / blocked |
| S4 | US 9–11; ID 4–9; TD 1,2,12 | Inventory S4 E1/E2; lifecycle | C,D,K,R,A source-proven children only | S+/S− | Ambiguous completion stays unresolved | pass / blocked |
| S5 | US 12,14–16,80–81; ID 4–6,19–20; TD 1,6,12 | Inventory S5 E1/E2; persistence | C,D,K,R,A; H optional | S+/S− | Session History, not timer deletion | pass / blocked |
| S6 | US 52,57–58; ID 7,18; TD 2,5,7 | Inventory S6 E1 | C,D,K,R,A Installation health | S+/S− | Setup/Degraded/Unavailable explanation | pass / blocked |
| I1 | US 17–18,71; ID 13–14; TD 7–9,13 | Inventory I1 E1; Horizon | All C,D,K,R,A; H not required | I+/I− | DR-01 | approved deviation / blocked |
| I2 | US 18–20,71,73–74; ID 13–15; TD 7–9 | Inventory I2 E1/E2; overlay | All C,D,K,R,A; H not required | I+/I− | External equivalent, DR-01 | approved deviation / blocked |
| I3 | US 6,18,22,77–79; ID 13,15; TD 7,9,13 | Inventory I3 E1 | All C,D,K,R,A | I+/I− | Text/glyph/motion redundancy, DR-01 | approved deviation / blocked |
| I4 | US 17,21,71,76; ID 13–14,17; TD 7–9,13 | Inventory I4 E1 | All C,D,K,R,A | I+/I− | Original hierarchy, DR-01 | approved deviation / blocked |
| I5 | US 5,11,21–22; ID 13; TD 7,9 | Inventory I5 E1 | C,D,K,R,A sourced metadata | I+/I− | Bound absent/long metadata, DR-01 | approved deviation / blocked |
| I6 | US 21,24,30; ID 13–15; TD 7–8 | Inventory I6 E1 | All C,D,K,R,A | I+/I− | Separate selection/reveal/list state, DR-01 | approved deviation / blocked |
| I7 | US 12,16,71; ID 13,19–20; TD 7,9,12 | Inventory I7 E1/E2 | C,D,K,R,A received recap only | I+/I− | Bounded recap, DR-01 | approved deviation / blocked |
| I8 | US 9–11,21,71; ID 4,13; TD 1,7,12 | Inventory I8 E1/E2 | C,D,K,R,A source-proven detail | I+/I− | Omit/summary when unsupplied, DR-01 | approved deviation / blocked |
| P1 | US 24,26–29; ID 13–16; TD 7–10 | Inventory P1 E1 | C,D,K,R,A event evidence | P+/P− | Notification Policy suppression | pass / blocked |
| P2 | US 12,24,26–27; ID 13–16; TD 7–10 | Inventory P2 E1 | C,D,K,R,A completion evidence | P+/P− | Interaction guard preserves recap | pass / blocked |
| P3 | US 18,25–27,32; ID 10,13,16; TD 3,7,10 | Inventory P3 E1 | C,D,K,R,A valid Attention Request | P+/P− | Unsupported attention: DR-03 | approved deviation / blocked |
| P4 | US 28–30,70,77; ID 14–15,17; TD 7–9,15 | Inventory P4 E1/E2 | All C,D,K,R,A | P+/P− | Labelled inspect/Jump Back | pass / blocked |
| P5 | US 27–29,75,77; ID 14–15; TD 7–9 | Inventory P5 E1/E3; overlay OW-1–OW-4 | All C,D,K,R,A | P+/P− | Visible-only hit/AX region | pass / blocked |
| A1 | US 31–32,38–43; ID 8–11; TD 2–3,7,9 | Inventory A1 E1–E3; routing | C,D,A action; K,R observe only | A+/A− | DR-03 | approved deviation / blocked |
| A2 | US 33–34,40–43; ID 8–11; TD 2–3 | Inventory A2 E1/E2; routing | C,D,A applicable semantic capability; K,R observe only | A+/A− | Source-minimum context; DR-03 | approved deviation / blocked |
| A3 | US 35–36,40,43,77; ID 10; TD 3,9,15 | Inventory A3 E1/E2; remediation | C,D,A structured schema; K,R observe only | A+/A− | No schema/action => DR-03 | approved deviation / blocked |
| A4 | US 31–32,36,39; ID 10; TD 3,7 | Inventory A4 E1; workflow | C,D,A draft capability; K,R presentation only | A+/A− | Retain local draft/no dispatch | pass / blocked |
| A5 | US 31,37,40–42; ID 8–11; TD 3,7 | Inventory A5 E1–E3; workflow | C plan approval; D scoped Turn input; A accept/reject; K,R observe only | A+/A− | Semantic-specific Host fallback, DR-03 | approved deviation / blocked |
| A6 | US 42,45,59–63; ID 9–12; TD 2–4 | Inventory A6 E1 | K,R and any unavailable C/D/A action | A+/A− | Exact H ladder, DR-03/DR-04 | approved deviation / blocked |
| A7 | US 32,38–43; ID 4–6,10–11; TD 1,3 | Inventory A7 E3; lifecycle/routing | C,D,A action; K,R observe only | A+/A− | Retire stale; no retry; DR-03 | approved deviation / blocked |
| J1 | US 44–50; ID 12; TD 4,8 | Inventory J1 E1/E2; Host matrix | H for C,D,K,R,A with Host Context | J+/J− | DR-04 | approved deviation / blocked |
| J2 | US 44–51; ID 12; TD 4,8 | Inventory J2 E2/E3; Host matrix | H exact/lower level per host | J+/J− | Achieved level only, DR-04 | approved deviation / blocked |
| J3 | US 4,44,47,50–51,80; ID 4–6,12,19; TD 1,4,8 | Inventory J3 E3; Host Context | H runtime locator/association | J+/J− | Invalidate, never fuzzy-rebind, DR-04 | approved deviation / blocked |
| J4 | US 42,44–51; ID 11–12; TD 3–4,8 | Inventory J4 E3; Host matrix | H all valid cells | J+/J− | Lower ladder/no simulated input, DR-04 | approved deviation / blocked |
| N1 | US 24–27,64–67; ID 16; TD 7,10 | Inventory N1 E1/E2; notifications | C,D,K,R,A source event classes | N+/N− | Unknown class is bounded/quiet | pass / blocked |
| N2 | US 64–67,70; ID 16–17; TD 10 | Inventory N2 E1; notifications | All C,D,K,R,A | N+/N− | Local mute/quiet hours/release | pass / blocked |
| N3 | US 26,64–66,75; ID 14,16; TD 7–10 | Inventory N3 E1/E2; notifications | All C,D,K,R,A | N+/N− | Presentation-only suppression | pass / blocked |
| N4 | US 57–58,64–66,71; ID 7,16–18; TD 2,7,10 | Inventory N4 E1/E3; integration | C,D,K,R,A | N+/N− | Diagnose/filter; no phantom session | pass / blocked |
| N5 | US 68,70; ID 8,16–17; TD 10 | Inventory N5 E1; remediation | C/D only if `usageObservation`; K/R/A unavailable unless newly proven | N+/N− | DR-05; no estimate | approved deviation / blocked |
| O1 | US 52,57–58,69; ID 7,17–18; TD 2,5,7 | Inventory O1 E1/E2; Atlas | C,D,K,R,A Installation | O+/O− | Read-only detect then explicit enable | pass / blocked |
| O2 | US 52–58,69–79; ID 14–18; TD 5,7–9 | Inventory O2 E1/E5; Atlas | All C,D,K,R,A | O+/O− | Excluded remote/commercial/telemetry stays absent | pass / blocked |
| O3 | US 16,24–30,65,70,75; ID 14–17,20; TD 7–10,15 | Inventory O3 E1; remediation | All C,D,K,R,A | O+/O− | DR-02 | approved deviation / blocked |
| O4 | US 52–58,70; ID 7–9,12,17–18; TD 2,5,15 | Inventory O4 E1/E2; Host matrix | C,D,K,R,A + H | O+/O− | O4 custom rules N/A: no host grammar | pass / blocked |
| O5 | US 17–23,71,73–75; ID 13–15,17; TD 7–9,15 | Inventory O5 E1; remediation | All C,D,K,R,A | O+/O− | Read-only preview; display withdrawal | pass / blocked |
| O6 | US 30,43,70,72,77; ID 15,17; TD 3,8–9 | Inventory O6 E1/E3; overlay | All C,D,K,R,A | O+/O− | Collision/IME/lease rejection | pass / blocked |
| O7 | US 52–58,69–70,84–85; ID 7–8,18,21; TD 2,5–6 | Inventory O7 E1/E3; integration | C,D,K,R,A | O+/O− | Inspectable degraded/repair/residual | pass / blocked |
| O8 | US 52–56,84–88; ID 18–21; TD 2,5–6 | Inventory O8 E2/E3; ownership | C,D,K,R,A Installation | O+/O− | Exact manifest only; no adoption/deletion | pass / blocked |
| H | US 4,6–16,27–30,40–51,73–85,88; ID 1–24; TD 1–14 | Inventory H E3; quality/overlay/lifecycle | C,D,K,R,A and H as applicable | H+/H− | DR-02/DR-03/DR-04/DR-05 | approved deviation / blocked |

**Completeness check:** 44/44 IDs recorded: S 6, I 8, P 5, A 7, J 4,
N 5, O 8, and H 1. Every row has a normative requirement, decision/evidence,
cell profile, positive and negative fixture, fallback/deviation pointer, and
the two-part current result.

## Stable deviation register

The register uses stable IDs. `Approved deviation` is used only where a prior
human-owner-approved decision or confirmed product direction explicitly
supports it. `Proposed` records are material gaps, not passes; the register
does not relabel them as N/A or as implementation failures.

| ID | Inventory / cells | Category and source evidence | Agent Island behavior and user impact | Fallback / required production evidence | Owner / disposition |
| --- | --- | --- | --- | --- | --- |
| DR-01 | I1–I8, P1–P5; all presentation cells | Material improvement/identity boundary. [Acceptance standard §3](parity-acceptance-standard.md#3-identity-boundary); human owner finalized Horizon with original diamond/shoreline marks in [visual-direction resolution](../issues/09-prototype-island-interaction-and-visual-system.md). | Do not copy Vibe Island pixel art, logo, copy, screenshots, sounds, or distinctive arrangement; use approved original Horizon hierarchy and marks. The monitored/interaction jobs remain. | Human visual review must confirm hierarchy, state distinction, density, accessibility, and independent identity; no source asset in bundle. | Human owner, 2026-07-18 Horizon decision / **approved deviation**. |
| DR-02 | O3, S5, H cleanup; all cells | Material improvement. [Remediation](attention-usage-settings-parity-remediation.md#approved-deviation-and-fallbacks), [persistence decision](persistence-history-recovery-and-retention.md#history-archive-and-cleanup), and confirmed [product defaults](product-direction-defaults.md#agent-session-working-set-and-lifecycle). | Replace the source idle-cleanup preference with no automatic time/idle cleanup that removes or conceals an Agent Session. Evidence-based History transition and explicit scoped local deletion remain distinct. | Time/idle fixture must leave active/unresolved/attention/child-active work visible; test explicit History/deletion scope separately. | Confirmed product direction; recorded as approved by the remediation / **approved deviation**. |
| DR-03 | A1–A7, P3, H action; K-I/K-C/K-W/K-O, R-C and any unavailable C/D/A action capability | Capability limitation. [Product-mode routing matrix](attention-request-action-routing-semantics.md#product-mode-routing-matrix); Claude, Codex, Cursor research. | Codex Hooks and Cursor Hooks observe/queue but cannot externally answer. Claude, direct Codex, and ACP expose only their live typed semantics; unsupported free text, cancellation, plan feedback, or schema remain native. | Show an explicit unavailable reason and `H` Jump Back; zero-dispatch stale/unsupported fixture and real/faithful per-mode action fixture. | Human owner, 2026-07-18 / **approved deviation**. |
| DR-04 | J1–J4, A6, H navigation; all `H` cells | Capability/platform limitation. [Host matrix](host-navigation-capabilities.md#host-matrix); [ADR 0004](../../../docs/adr/0004-live-host-context-locators-and-honest-navigation.md). | Exact iTerm2 is live-session scoped; Cursor exactness is extension-object scoped and never native thread; Warp is app-only except opt-in AX window best effort; Orca is `exactTab` unless current runtime proves more. | Revalidation/loss/duplicate/AX-denial fixture records exactSurface/exactTab/workspaceOrFile/windowBestEffort/appOnly/unavailable precisely; no simulated input. | Human owner, 2026-07-18 / **approved deviation**. |
| DR-05 | N5; C/D only when live `usageObservation`, K/R/A unavailable unless proven | Capability limitation/privacy boundary. [Usage decision](notifications-sounds-filters-and-usage-behavior.md#optional-provider-usage); remediation N5. | Display a Usage Snapshot only from a live sourced capability. No usage estimate or Cursor ACP usage display is fabricated; optional Claude bridge preserves existing visible output. | Fresh/stale/missing/reverted bridge fixture shows provider/time/reset or unavailable and does not alter monitoring, queue, or Jump Back. | Human owner, 2026-07-18 / **approved deviation**. |

## Owner approval recorded

On 2026-07-18 the human owner explicitly approved DR-03 (capability-scoped
native-Host fallback for unsupported Agent Product actions), DR-04 (the
documented lower Host navigation ladder), and DR-05 (usage unavailable rather
than estimated) for their stated cells. No proposed material deviation remains
in this version of the register.

The approval resolves specification completeness only. Production evidence and
human visual review remain `blocked`; no row may yet be described as a
released parity pass.
