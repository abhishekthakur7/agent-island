# 11 — Implement coordinated Notification Policy

## What to build

Make one validated, current Agent Session change produce one coordinated local presentation decision. The person can configure and understand whether an eligible attention request, error, completion, session start, reminder, acknowledgement, spam burst, or sourced Subagent Run completion receives a focused Island reveal, collapsed glow, sound, macOS notification, inline-only update, or suppression. The resulting behavior is local presentation only: it never changes Agent Product lifecycle, responds to an Attention Request, or grants action authority.

## Context and constraints

An Alert Candidate is owned by its Product namespace, native Agent Session and Turn/request identity where present, semantic class, and source event/revision identity. It is created only after the canonical reducer accepts and deduplicates source evidence. Candidate identity must never use titles, prompts, paths, models, Host labels, receipt time, or text similarity.

Priority is attention, then error/context limit, completion, session start, idle reminder, acknowledgement/spam. A higher-priority candidate retargets one existing presentation rather than stacking panels, timers, sounds, or banners. Quiet Scenes are Focus mode, locked/asleep display, and active screen recording/sharing. Quiet hours mute sound only. Exact foreground relevance requires a currently revalidated owning Host Context or inspection of that exact Agent Session; same-looking windows and app-only navigation do not qualify.

Collapsed and macOS-notification payloads contain only state and a bounded configured label. Prompts, commands, paths, diffs, response text, and secret-looking values stay out. Imported sound stays local. Usage Snapshot behavior is not in this ticket; missing or unavailable usage must not interfere with this policy, monitoring, queues, or Jump Back.

## Acceptance criteria

- [ ] An accepted source fact creates at most one durable Alert Candidate with the required owner/provenance identity; duplicate, replayed, weak-key-ambiguous, stale, unknown-owner, unsupported, or continuity-gapped evidence creates no user-facing alert and retains only a redacted reason.
- [ ] Candidate evaluation is deterministic and ordered: deduplication/currentness, hard filter, Quiet Scene, quiet-hours sound policy, exact foreground relevance, event preference, then notification permission.
- [ ] One eligible candidate coordinates one primary presentation and optional one sound and one macOS notification; all facets expose the same candidate identity and later source revisions update/coalesce rather than multiply delivery.
- [ ] Attention remains the highest-priority focused item and has no automatic expiry; a completion, error, or new activity cannot displace a guarded response, draft, selection, or keyboard engagement.
- [ ] Source-proven completion appears only when the current lineage is terminal with no pending attention and no known active/waiting child; it uses configured 3–4 second focused recap behavior and becomes persistent on interaction.
- [ ] A current parent session start may use configured 2–3 second focused reveal; a sourced child completion remains nested, never completes its parent, and never posts a separate top-level notification.
- [ ] Focus mode, locked/asleep display, and screen sharing suppress automatic reveal, sound, and banners for every class without clearing the card, queue, or canonical event; leaving the scene does not replay a backlog.
- [ ] Quiet hours and the immediate mute control affect sound only; filtering, quieting, muting, foreground suppression, and permission denial never alter Product state, delete an Attention Request, or hide an eligible exact Host fallback.
- [ ] Foreground exactness is session-scoped: an exact foreground owner or direct inspection updates inline only, while a same title, nearby tab, historical locator, or app-only Host result cannot suppress another eligible candidate.
- [ ] Launcher/probe, built-in internal-work, directory, first-prompt, and source-proven Subagent visibility filters have clear scope, local read-only previews, and redacted diagnostic reasons; a dropped/probe session creates no card, count, glow, sound, banner, or usage target.
- [ ] Sound controls provide master state, volume, class-specific Off-or-local-sound choice, explicit preview, quiet hours, and locally imported audio. Preview creates no Alert Candidate, banner, or Product action, and audio resources are released after use.
- [ ] macOS notification permission and per-class settings apply only to eligible background attention, error, context-limit, completion, and reminder candidates. Restart never reissues a banner from restored durable state.
- [ ] Missing, stale, disabled, or unavailable usage observation cannot produce an estimate, Alert Candidate, or suppression side effect and leaves monitoring, queues, and Jump Back usable.

## Required evidence

- A replay/duplicate trace proving one recap, sound, and banner at most, including a higher-priority retarget and interaction-guarded dwell.
- Captures of Quiet Scene, quiet-hours, foreground-relevance, same-title negative, filter/probe, denied-permission, and unavailable-usage outcomes with redacted diagnostic correlation.
- Sound-import/preview/release evidence showing no extra Product action, event, or sensitive payload.
- Parity-matrix records for applicable N1–N4 and P1–P3 cells, including missing-usage independence.

## Blocked by

- 04 — Deliver the Horizon session-monitoring experience
- 06 — Deliver resumable onboarding and the Atlas Settings shell
- 09 — Handle Attention Requests through the Guided workflow
