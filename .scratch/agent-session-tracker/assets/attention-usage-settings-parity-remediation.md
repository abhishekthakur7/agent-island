# Attention, usage, and Settings parity remediation

**Resolution date:** 2026-07-18  
**Owner ticket:** [Close explicit attention, usage, and Settings parity requirement gaps](../issues/27-close-explicit-attention-usage-and-settings-parity-gaps.md)  
**Scope:** explicit requirement and acceptance closure for A3, N5, O3, O4,
and O5. This is not the complete parity matrix or deviation register; those
records remain the work of [Complete parity acceptance matrix and deviation register](../issues/28-complete-parity-acceptance-matrix-and-deviation-register.md).

## Resolution

`SPEC.md` now owns normative, testable requirements for the audit findings
without changing user-story numbering (it remains 1–88), Product scope, or a
capability boundary. The additions preserve the selected Guided sheet, Atlas
Settings, non-activating Island Overlay, typed Action Lease, Host locator, and
local-first decisions.

| Inventory ID | Exact baseline now made explicit in `SPEC.md` | Evidence and decision basis |
| --- | --- | --- |
| A3 | Visible choice-to-keyboard mappings outside text entry; no implicit or recommended default; reversible single/multi-select drafts; valid-answer-only Next; and the same capability, validation, Action Lease, and typed Action Attempt gates for keyboard use. | [Parity inventory A3](parity-baseline-inventory.md#d-attention-requests-and-action-workflows); [original wizard evidence](../../../VIBE_ISLAND_FUNCTIONALITY.md) lines 414–438; [attention workflow](attention-completion-workflow-design.md#single-and-multiple-choice-questions); [action routing](attention-request-action-routing-semantics.md#validation-authorization-and-dispatch). |
| N5 | Capability-gated header visibility; used versus remaining; preferred provider versus following the currently selected active Agent Session; provider, observation time, reset, stale, and unavailable display; and an optional reversible Claude Status Line bridge that preserves existing visible output. | [Parity inventory N5](parity-baseline-inventory.md#f-notifications-sound-filtering-and-usage); [original usage evidence](../../../VIBE_ISLAND_FUNCTIONALITY.md) lines 153–155 and 259–263; [usage decision](notifications-sounds-filters-and-usage-behavior.md#optional-provider-usage). |
| O3 | General controls for launch at login; independently persisted hover expansion and pointer-exit collapse; exact-Host foreground suppression; fullscreen and no-active-session hiding; completion/attention reveal; and unambiguous configured inspect/expand versus explicit Jump Back click behavior. | [Parity inventory O3](parity-baseline-inventory.md#g-onboarding-settings-integrations-and-maintenance); [original General controls](../../../VIBE_ISLAND_FUNCTIONALITY.md) lines 83–90; [Overlay decision](overlay-window-display-input-accessibility.md#hover-pointer-and-hit-testing); [Atlas decision](settings-onboarding-diagnostics-information-architecture.md#sidebar-structure). |
| O4 | Custom Jump Back rules are explicitly **inapplicable** to all first-class Hosts: none supplies a documented user-defined destination grammar. A URL-scheme registration alone cannot create a rule or a Jump Back capability. A future Host can add it only through a negotiated capability and reversible, manifest-proven Integration Installation plan. | [Parity inventory O4](parity-baseline-inventory.md#g-onboarding-settings-integrations-and-maintenance); [Host capability evidence](host-navigation-capabilities.md#host-matrix) and [URL-scheme rule](host-navigation-capabilities.md#failure-and-reconciliation-rules); [original third-party-only setting](../../../VIBE_ISLAND_FUNCTIONALITY.md) line 88. |
| O5 | Display controls for selected display; clean/detailed layout; content size; maximum panel width/height; completion-card height; optional sourced project/worktree/Model/Subagent Run/activity visibility; live read-only preview; and safe selected-display notch/pill geometry. | [Parity inventory O5](parity-baseline-inventory.md#g-onboarding-settings-integrations-and-maintenance); [original Display controls](../../../VIBE_ISLAND_FUNCTIONALITY.md) lines 83–91; [Overlay geometry](overlay-window-display-input-accessibility.md#displays-notch-geometry-spaces-and-full-screen); [Atlas preview rule](settings-onboarding-diagnostics-information-architecture.md#presentation-rules). |

## Exact specification additions

- **User stories:** strengthened 35 (A3), 68 (N5), 70 (O3), 71 (O5), and 75
  (O3 fullscreen/no-active-session) without adding or renumbering a story.
- **Implementation decisions:** decision 10 owns structured-choice keyboard and
  validity rules; 16 owns Usage Snapshot controls and bridge fallback; 17 owns
  the complete General/Display control set, the O4 applicability declaration,
  and the cleanup deviation.
- **Testing decisions:** 3 adds A3 positive and negative external behavior;
  10 adds N5 capability/bridge success and unavailable/stale failure behavior;
  15 defines the O3/O4/O5 Settings positive and negative scenarios.

## Approved deviation and fallbacks

| Item | Disposition | Prior approval / evidence | Required user-visible result and test |
| --- | --- | --- | --- |
| O3 source idle-cleanup setting | **Approved material improvement:** Agent Island has no automatic time or idle cleanup that removes or conceals an Agent Session. Evidence-based Session History transition and explicit person-selected deletion remain separate. | [Persistence, history, recovery, and retention decision](persistence-history-recovery-and-retention.md#retention-archive-and-deletion) explicitly prohibits automatic retention, idle cleanup, quota eviction, and timer deletion/concealment of active work, and applies the approved product defaults; [quality invariant Q4](quality-attributes-and-failure-invariants.md#required-quality-outcomes) forbids idle cleanup/resource mitigation from deleting, concealing, or reclassifying Agent Session evidence. This is the audit-identified safer replacement, not an omission. | A time/idle-policy fixture cannot remove or conceal an Agent Session; only source evidence, safe history transition, or explicit scoped local deletion may change local presentation/retention. |
| N5 unsupported or stale usage / bridge | **Capability limitation:** no header data or bridge is fabricated. | [Usage decision](notifications-sounds-filters-and-usage-behavior.md#optional-provider-usage) limits usage to a live `usageObservation` Capability and makes non-Claude bridges non-mandatory. | Show stale or unavailable state with no estimate; monitoring, queue, and Jump Back continue. A reverted bridge preserves the person's visible status-line output and disconnects cleanly. |
| O4 custom Jump Back rules | **Inapplicable capability cell:** no first-class Host offers a supported configurable destination grammar. | [Host navigation capabilities](host-navigation-capabilities.md#host-matrix) documents the first-class Host contracts; its [URL-scheme rule](host-navigation-capabilities.md#failure-and-reconciliation-rules) rejects a bare scheme, including Warp. | Do not offer a custom rule. Show only the current proven exact/lower/unavailable Jump Back result; never invoke or infer a URL destination. |

## Acceptance scenarios recorded for the later parity matrix

1. **A3 positive:** with a live structured-choice Capability and focus outside
   text entry, the visible mapping selects its corresponding option; a
   single-choice replacement and multi-select toggle remain reversible, drafts
   persist across question/page and focused/full-list changes, and Next enables
   only after the source-required answer is valid.
2. **A3 negative:** a recommended option begins unselected; an empty required
   response keeps Next disabled; typing/IME composition in a text entry does
   not invoke an option mapping; and no keyboard path dispatches without the
   normal validation, confirmation, live Action Lease, and typed Action Attempt.
3. **N5 positive:** a live Usage Snapshot can be shown/hidden, switched between
   used and remaining, switched between a preferred provider and the currently
   selected active Agent Session's provider, and displays its provider, observation
   time, reset information, and fresh state. An enabled Claude bridge retains
   existing visible status-line output.
4. **N5 negative:** missing, stale, disabled, or reverted capability/bridge
   shows absent/stale/unavailable rather than an estimate; it leaves monitoring,
   Attention Requests, queue, and Jump Back available.
5. **O3 positive:** persisted General controls apply launch-at-login,
   hover/reveal/collapse, exact-Host foreground suppression, fullscreen/no-
   active-session hiding, completion/attention reveal, and the labelled click
   action. A configured Jump Back click revalidates its Host Context and reports
   the achieved level.
6. **O3 negative:** a same-titled or unrevalidated Host cannot suppress an
   event; disabled click-to-Jump-Back does not navigate; and time/idle cleanup
   cannot remove or conceal an Agent Session.
7. **O4 positive/negative:** each first-class Host exposes only its documented
   Jump Back capability and lower fallback. No custom rule appears for a bare
   URL scheme or unsupported destination grammar.
8. **O5 positive:** a saved Display preference applies selected display,
   clean/detailed layout, content size, maximum panel bounds, completion-card
   height, optional metadata, and clamped notch/pill geometry; its live preview
   is local and read-only.
9. **O5 negative:** the preview emits no alert, moves no live Overlay, and
   mutates no Integration Installation; a disconnected selected display
   withdraws the Overlay rather than silently migrating it, and no configured
   geometry can cross the protected notch or visible safe bounds.

These scenarios are specification-level acceptance inputs, not completed
production evidence or a parity pass. The next ticket must add each applicable
capability cell, evidence capture, result, and deviation reference to the
complete matrix/register.
