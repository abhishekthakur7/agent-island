# 10 — Navigate through the capability-honest Jump Back ladder

## What to build

Deliver explicit Jump Back from an Agent Session to the most precise currently valid Host Context, with independently negotiated Host navigation capability, live locator revalidation, a strict lower-fallback ladder, and clear visual/spoken/diagnostic reporting of what actually happened. It must never guess a same-looking terminal/window/thread, simulate input, claim a Space/fullscreen result, or turn navigation into Product action authority.

The slice covers first-class iTerm2, Cursor, Warp, and Orca Host behavior behind a typed Host port. It makes the fallback required by unavailable Attention actions and labelled Overlay/Settings actions real.

## Context and constraints

- An Agent Session and Host Context are different identities. Associations are many-to-many historical evidence with host kind/version/endpoint/incarnation/typed locator/provenance/invalidation state; title, CWD/path, PID, geometry, Space, and AX label never create exactness.
- Revalidate immediately before every Jump Back. Persisted locators are historical/unvalidated after restart or wake; Host closure/reload/permission loss changes navigation capability, not Product lifecycle.
- Report only the achieved ladder level: `exactSurface`, `exactTab`, `workspaceOrFile`, `windowBestEffort`, `appOnly`, or `unavailable`. A failure may only descend to a separately proven lower capability.
- iTerm2 exactness is live-session scoped; Cursor terminal exactness needs a connected extension-held live terminal object and native Cursor threads have no exact selector; Warp is app-only except opt-in single-window AX best effort; Orca reports exact tab unless current runtime proves child-surface focus.
- `windowBestEffort` needs intentional Accessibility opt-in and exactly one current AX candidate. It is not durable identity and must not use UI automation, clicks, keystrokes, or terminal input.

## Acceptance criteria

- [ ] An explicit person action from visible Agent Session detail initiates Jump Back through a typed Host navigation port. Card selection, notification display, automatic reveal, reconciliation, and ordinary Overlay activation never navigate a Host.
- [ ] Before attempt, the app validates association ownership for the selected Agent Session, revalidates current Host/mode/capability/permission/locator state, and records the candidate/attempt without permitting another session’s similar context to be used.
- [ ] A live iTerm2 session locator reaches `exactSurface`; live tab-only capability reaches `exactTab`; a proven related workspace/file reaches `workspaceOrFile`; the UI/result says the actual level and limitation rather than generic success.
- [ ] Cursor extension reload/window closure invalidates terminal exactness; duplicate names/PIDs never rebind it. Native Cursor Agent threads never claim exact selection and may only use independently proven workspace/file or app fallback.
- [ ] Warp offers only `appOnly` unless the person enabled Accessibility and one current window is found, in which case it reports `windowBestEffort` explicitly. A URL scheme alone never becomes navigation evidence.
- [ ] Orca revalidates a version-matched runtime handle and reports `exactTab` unless its current documented runtime proves a more precise result; invalid handle may use a separately proven workspace/file or app fallback only.
- [ ] Missing/revoked permissions, unavailable/changed integration, closed/recreated locator, multiple same-level candidates, full-screen/Space/display changes, or unavailable Host result in the named lower level or `unavailable`, with actionable reason and no fuzzy matching/synthetic input/false exactness.
- [ ] Visual, VoiceOver, and redacted diagnostic outcomes all include Host, achieved qualifier, time, and limitation/reason. `appOnly` and `windowBestEffort` cannot be presented as exact success.
- [ ] A successful navigation attempt never sends Product input, approves/denies/cancels work, changes lifecycle, or restores an Action Lease; those retain their own capability and routing gates.

## Required evidence

- Host-matrix captures for exact iTerm2, Cursor extension exact/lost locator, Cursor native-thread fallback, Warp app-only/opt-in AX best effort, and Orca tab/runtime validation, with achieved-level UI, VoiceOver, and diagnostic records.
- Negative fixtures for identical titles/CWDs/windows, duplicate Cursor terminals, Host restart, extension reload, missing/revoked Accessibility/Automation, full-screen/Spaces, changed display, and absent Host; each proves no fuzzy target, simulated input, or false exact result.
- Restart/wake trace showing persisted locators treated as unvalidated until documented read-only Host reprobe and proving lifecycle/action authority are unaffected.
- Capability/health capture showing navigation readiness independently from Adapter observation/action state.

## Blocked by

- 04 — Deliver the Horizon session-monitoring experience
- 07 — Negotiate Adapter capabilities and expose honest integration health
