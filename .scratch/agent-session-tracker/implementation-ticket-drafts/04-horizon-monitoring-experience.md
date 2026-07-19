# 04 — Deliver the Horizon session-monitoring experience

## What to build

Build the approved original Horizon monitoring experience over derived Agent Session projections: calm compact status, focused reveal, chronological expanded list, inline selection/recap, nested source-proven Subagent Runs, and progressive row compaction for a working set that can reach 30 sessions. The experience must make state, ownership, attention count, and total count legible without copying source identity or inventing work detail.

This ticket owns SwiftUI presentation content and interaction semantics, not the native panel/window mechanics, notification eligibility, action dispatch, or Host navigation implementation.

## Context and constraints

- Horizon Variant A is final: one chronological flow, focused content promoted in that flow, inline selected detail, and children under their parent. Do not substitute a table, a detached inspector, or source-product visual identity.
- Render only Adapter-supplied project/worktree/title/prompt summary/activity/result/Model/Host fields. Missing or long detail is absent, truncated, compacted, or independently scrolled—not inferred.
- Preserve ownership before descriptive metadata under constrained width or increased text. Keep attention count separate from total session count.
- States require redundant text/glyph/semantic cues; color and motion alone are insufficient. Reduced Motion uses an understandable cross-fade and decorative marks are not accessibility content.
- Selection is independent from focused reveal and list ordering. A completion recap is bounded and scrolls inside its owner row without reordering neighbors.

## Acceptance criteria

- [ ] The collapsed clean/detailed Horizon states show a concise accessible aggregate with separate total Agent Session and Attention Request counts, stable leading/protected/trailing zones, and no claim that decorative animation conveys required meaning.
- [ ] A focused session/attention/completion view promotes the relevant session while retaining compact concurrent context; attention ranks above completion and ordinary activity, and focus/reveal does not mutate list selection.
- [ ] The expanded view presents a chronological Agent Session flow with inline selected detail. Each row preserves sourced state, ownership, relative time, and available metadata; optional detail compactly degrades before owner or action labels are lost.
- [ ] Completion recap/result content is shown only when received from the Agent Product, within a bounded independently scrolling region. Opening it preserves scroll/list context and does not turn local acknowledgement into Product completion.
- [ ] Source-proven Subagent Runs and task detail remain visually and semantically nested under the owning Agent Session. Unsupplied task/progress structure is omitted rather than manufactured.
- [ ] At 30 sessions, large-session density progressively compacts the same Horizon hierarchy while preserving scroll anchor, selected detail, ownership, and non-color status cues; all-active/all-attention overflow is not hidden merely to enforce a count cap.
- [ ] Keyboard, VoiceOver, increased-text, increased-contrast, reduced-transparency, and reduced-motion paths preserve readable ownership, hierarchy, labels, and operation without horizontal overflow.

## Required evidence

- Native UI/AX captures of clean, detailed, focused attention, focused completion recap, expanded multi-session, selected inline detail, nested child work, and large-session density states.
- Fixture-driven positive/negative evidence for long/absent metadata, unsourced child/task detail, 30-session compaction, and all-active overflow.
- Human visual-review packet confirming original Horizon hierarchy/marks, state distinction, accessibility, density, and no source assets or distinctive source arrangement.

## Blocked by

- 03 — Derive conservative Agent Session lifecycle from immutable facts
