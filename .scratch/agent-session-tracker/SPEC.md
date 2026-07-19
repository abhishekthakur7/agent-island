---
title: Agent Island implementation-ready product and architecture specification
status: ready-for-agent
Triage: ready-for-agent
baseline: Vibe Island v1.0.42, observed 2026-07-18
platform: macOS 14+ on Apple Silicon
---

# Agent Island specification

## Overview

Agent Island is a personal, local-first native macOS companion for one person
to monitor and safely interact with concurrent AI coding work without leaving
the Host they are using. It is not an Agent Product and does not own Product
conversations. It aggregates evidenced work from Claude Code, Codex CLI, and
Cursor, and supports Host Context and Jump Back behavior for iTerm2, Cursor's
IDE and integrated terminal, Warp, and Orca.

This specification is the implementation baseline for the frozen Parity
Baseline. It defines required outcomes and architecture boundaries, not a
production implementation plan. A capability that cannot be proven for the
selected Agent Product, integration mode, and live Host Context must be shown
as unavailable or degraded with its honest fallback; it must never be
approximated by inference, terminal scraping, or simulated input.

## Problem Statement

A person running several Agent Sessions cannot reliably keep track of which
coding work is active, finished, blocked, or needs their decision while staying
in their preferred editor or terminal. Switching among similarly named panes,
tabs, worktrees, and Agent Product conversations is slow and risks responding
to the wrong work. Existing Product interfaces also differ substantially in
what they can observe, control, and navigate.

The person needs a compact macOS companion that makes concurrent work legible,
brings genuine Attention Requests forward without becoming disruptive, enables
only proven in-island actions, and always offers a truthful way back to the
owning Host Context. It must remain reliable after restarts, sleep/wake,
disconnects, Product upgrades, configuration drift, and a full 30-session
working set, while keeping sensitive coding context local.

## Solution

Deliver Agent Island as a local-only, AppKit-first Swift application for
personal use, with a non-activating top-edge Island Overlay and an independently
activating Settings window. A deterministic local core stores immutable,
source-proven Normalized Event Facts in protected local storage and derives
conservative Agent Session state. Product-specific Agent Adapters and Host
ports are versioned, capability-scoped outer boundaries; they may enrich or
act only when their evidence is current and sufficient.

The Island Overlay uses the approved original Horizon visual system: a compact
resting or detailed state, focused reveals, and an expandable chronological
list where selection opens detail inline and TODO/task and Subagent Run detail
remains nested under its owning Agent Session. Attention uses one Guided sheet
with Arrived, Review, Respond, and Acknowledged stages. Every unavailable
action and every failed routing attempt leads to an explicit, capability-honest
Jump Back result rather than a claim that the Product applied something.

## User Stories

1. As a person using Agent Island, I want to see concurrent Agent Sessions from supported Agent Products in one compact Island Overlay, so that I can monitor work without repeatedly switching Hosts.
2. As a person, I want Claude Code, Codex CLI, and Cursor to be first-class Agent Products, so that their supported local work is covered deliberately rather than through generic guessing.
3. As a person, I want iTerm2, Cursor's IDE and integrated terminal, Warp, and Orca to be first-class Hosts, so that the right navigation capability is available for the tools I use.
4. As a person, I want every Agent Session to retain its Agent Product-native identity across restarts and reconnections, so that distinct work is never merged because labels or paths look alike.
5. As a person, I want Agent Sessions to display sourced project, worktree, Agent Product, Host, Model, elapsed/relative time, title or prompt summary, and activity when available, so that I can recognize work without treating presentation data as identity.
6. As a person, I want working, waiting, completed, stopped, failed, unresolved, and needs-attention states to be visibly distinct, so that I can prioritize safely.
7. As a person, I want absent or contradictory Product evidence to remain unresolved, so that a lost connection, quiet period, or closed Host is not falsely presented as completion.
8. As a person, I want rewinds, retries, forks, and compaction to preserve historical Turns within the correct Agent Session, so that history remains useful without duplicate session cards.
9. As a person, I want sourced Subagent Runs to appear as children of their owning Agent Session, so that background work neither pollutes the top-level list nor disappears.
10. As a person, I want a parent Agent Session to remain active while proven child work is active or waiting, so that parent completion is never inferred prematurely.
11. As a person, I want only adapter-supplied task, TODO, role, timing, and activity detail to appear, so that Agent Island never invents progress information.
12. As a person, I want to inspect a completion recap and received result content in a bounded inline view, so that I can understand what finished without losing my place.
13. As a person, I want up to 30 active and inactive Agent Sessions in the compact working set, so that ordinary parallel work remains fast and legible.
14. As a person, I want safely inactive sessions to move to Session History when needed, so that the compact list stays useful without deleting evidence.
15. As a person, I want the working set to exceed 30 when every retained session is active, unresolved, child-active, or attention-requiring, so that the limit cannot hide active work.
16. As a person, I want historical sessions, rewound Turns, and completion recaps to remain locally inspectable until I explicitly delete them, so that a timer never erases my context.
17. As a person, I want a clean resting Island state and a detailed active Island state, so that the surface stays quiet when work is ordinary yet informative when I need status.
18. As a person, I want the collapsed Island to show a compact, accessible status plus separate total-session and attention counts, so that urgency is not confused with volume.
19. As a person on a notched MacBook, I want the protected physical-notch region to remain free of content and hit targets, so that the overlay looks and behaves correctly.
20. As a person on an external display, I want the Island to use an equivalent floating top-edge form, so that the experience remains coherent without pretending the display has a notch.
21. As a person, I want Horizon's chronological list, inline selection, nested child hierarchy, and progressive compact-row density, so that I can scan a small or large working set without losing ownership context.
22. As a person, I want state communicated by meaningful text and glyphs as well as color and motion, so that status is understandable in every accessibility mode.
23. As a person, I want original Agent Island branding, marks, illustrations, sounds, copy, and visual composition, so that parity does not copy Vibe Island identity or assets.
24. As a person, I want focused automatic reveals for meaningful new-session and completion events, so that I notice useful changes without an always-expanded panel.
25. As a person, I want Attention Requests to outrank ordinary activity and completion in reveal and ordering policy, so that consequential work is not buried.
26. As a person, I want automatic reveal to honor notification policy, quiet scenes, foreground suppression, and interaction guards, so that Agent Island does not interrupt me unnecessarily.
27. As a person, I want any pointer, keyboard, VoiceOver, scrolling, selection, or response interaction to prevent timer-based dismissal, so that an active task or draft is never taken away.
28. As a person, I want hover expand and pointer-exit collapse to be optional, debounced, and limited to visible Island bounds, so that the top edge does not become an invisible trigger or flicker loop.
29. As a person, I want visible geometry, hit testing, and the accessibility tree to contract together on collapse, so that no hidden panel can block Host input or trap focus.
30. As a person, I want click behavior to explicitly describe whether it inspects/expands or performs Jump Back, so that I do not trigger navigation by an ambiguous gesture.
31. As a person with a supported Attention Request, I want one Guided sheet that takes me from Arrived to Review, Respond, and Acknowledged, so that approvals, questions, plans, warnings, and results are handled consistently.
32. As a person, I want multiple concurrent Attention Requests kept in a compact, stable priority queue, so that parallel requests remain separate and none is lost.
33. As a person, I want permission review to display the minimum sourced context required to make a decision, so that I can approve or deny knowingly without leaking content elsewhere.
34. As a person, I want only the Product's proven allow, deny, persistent-permission, and mode choices, so that an in-island control does not change a Product permission mode unexpectedly.
35. As a person, I want capability-supported single-choice, multi-select, free-text, and multi-question responses to show each visible choice's keyboard mapping outside text entry, begin with no implicit or recommended default, allow single and multi-selection to be reversed before submission, and keep Next disabled until the current answer is valid, so that the response shape matches its owner without an accidental or incomplete response.
36. As a person, I want incomplete multi-question drafts retained while I navigate the queue or change presentation state, so that I do not lose local work.
37. As a person, I want plan review to render sourced plan content and offer only supported approval, rejection, and revision-feedback paths, so that plan feedback never masquerades as a different permission action.
38. As a person, I want completed, failed, context-warning, expired, and resolved-elsewhere requests acknowledged truthfully, so that local presentation and Product state are never conflated.
39. As a person, I want dismissing an Attention Request to change only Agent Island presentation, so that a dismissal never silently approves, denies, cancels, or resolves Product work.
40. As a person, I want each submitted action to be a single typed Action Attempt backed by a live, one-use Action Lease, so that a response cannot cross sessions, survive restart, or be sent twice.
41. As a person, I want an action result to distinguish rejected, accepted by Product, applied, superseded, and indeterminate, so that I can tell what is actually known.
42. As a person, I want stale, mismatched, expired, duplicated, killed, disconnected, and indeterminate actions to stop safely and point me to Jump Back, so that Agent Island never retries an unsafe command.
43. As a person, I want a consequential shortcut to require the same confirmation and live action checks as a visible control, so that keyboard speed cannot bypass safety.
44. As a person, I want Jump Back to revalidate the live Host Context before navigation, so that I am never directed to a similar-looking but wrong pane or window.
45. As a person, I want Jump Back to report whether it reached exactSurface, exactTab, workspaceOrFile, windowBestEffort, appOnly, or unavailable, so that the result matches what actually happened.
46. As a person, I want iTerm2 exact navigation when a live supported session locator validates, so that terminal work can be reopened precisely where the Host supports it.
47. As a person using Cursor, I want exact integrated-terminal navigation only while a connected extension retains the live terminal reference, so that reloads, duplicate names, and other windows do not create false precision.
48. As a person using Cursor's IDE Agent threads, I want an honest app/workspace/file fallback when exact native thread selection is unsupported, so that Agent Island does not emulate clicks into a guessed thread.
49. As a person using Warp, I want app-level navigation and an opt-in Accessibility best-effort window fallback only when valid, so that unsupported tabs or panes are never claimed exact.
50. As a person using Orca, I want runtime-validated terminal/tab or workspace/file navigation at the Host's actually supported level, so that Host evolution does not turn a tab result into a pane claim.
51. As a person, I want Spaces, fullscreen placement, window titles, paths, geometry, PIDs, and accessibility labels treated as presentation or diagnostic evidence rather than durable exact targets, so that navigation remains safe.
52. As a person, I want each Integration Installation discovered read-only and enabled explicitly, so that detected software is not silently configured.
53. As a person, I want setup, repair, migration, disablement, setup removal, local-data deletion, and complete cleanup to be distinct actions, so that consequential changes have clear scope.
54. As a person, I want each configuration change to start with a reviewable plan and end with verification, so that Agent Island changes only what I approved.
55. As a person, I want an Ownership Manifest to prove only the exact Agent Island-owned entry or artifact, so that custom configuration, comments, symlinks, ordering, and unrelated settings remain untouched.
56. As a person, I want drift, unknown syntax, policy precedence, ambiguous ownership, and lossy formats to produce a repair/manual-remedy or residual state, so that Agent Island never silently rewrites, adopts, or deletes external material.
57. As a person, I want integration intent distinct from observed health, so that an enabled toggle is never mistaken for verified event delivery or action readiness.
58. As a person, I want Disabled, Setup required, Healthy, Degraded, Unavailable, and Incompatible summaries backed by inspectable dimensions, so that I can understand the exact affected capability and safe next step.
59. As a person, I want Claude Code hook behavior limited to its documented observed events and live synchronous decisions, so that unsupported arbitrary input, cancellation, and plan-revision text use the native Host instead.
60. As a person, I want Codex CLI hooks to observe independently launched terminal work without taking over a terminal-owned prompt, so that no terminal input is simulated.
61. As a person, I want direct Codex app-server sessions to support only their version-pinned typed native stream and live request responses, so that disconnects retire routing rather than being repaired from private state.
62. As a person, I want Cursor Hooks to observe compatible local IDE Agent Sessions but send no external approval, question, or plan response, so that I am directed to Cursor when it owns the interaction.
63. As a person, I want Cursor ACP actions only for Agent Island-started ACP sessions, so that controlled and independently launched Cursor work are never conflated.
64. As a person, I want one coordinated Notification Policy that derives a deduplicated signal bundle from validated event evidence, so that Island reveal, glow, sound, and macOS notifications do not multiply.
65. As a person, I want event priority, custom filters, directory/prompt/launcher/subagent rules, foreground suppression, quiet scenes, quiet hours, mute, and probes to alter presentation only, so that they cannot alter Product state or delete a request.
66. As a person, I want collapsed notification payloads to expose only bounded safe status/labels, so that prompts, commands, diffs, response text, paths, and secrets are not disclosed outside the protected view.
67. As a person, I want event-specific sounds, imported local sounds, mute, quiet-hours behavior, and released audio resources, so that sound is helpful but never repetitive or disruptive.
68. As a person, I want to configure a trustworthy, display-only provider Usage Snapshot header—its visibility, used-versus-remaining value, preferred provider or following the currently selected active Agent Session's provider, and sourced provider, observation-time, reset, stale, or unavailable state—so that missing usage is not estimated or treated as billing state.
69. As a person, I want contextual, resumable onboarding that introduces the product promise, detection, capabilities, permissions, and display choices, so that I can complete setup without a separate permanent wizard.
70. As a person, I want a conventional Atlas Settings sidebar with General, Integrations, Notifications, Display, Sound, Usage, Shortcuts, Labs, Diagnostics, and Maintenance destinations, including General controls for launch at login, hover expansion and pointer-exit collapse, exact-Host foreground suppression, fullscreen and no-active-session hiding, completion/attention reveal, and labelled click behavior, so that everyday settings and consequential maintenance are easy to find and clearly separated.
71. As a person, I want local read-only previews beside display and filter settings, and Display controls for selected display, clean/detailed collapsed layout, content size, maximum panel width/height, completion-card height, optional project/worktree/model/Subagent Run/activity metadata, and notch/pill geometry, so that I can understand a preference without triggering an alert, moving the overlay, or mutating an integration.
72. As a person, I want configurable global and focused shortcuts with collision detection, physical-key binding, input-source awareness, and a master disable switch, so that shortcuts work safely with non-QWERTY and CJK input methods.
73. As a person, I want one selected display and only one live Island Overlay, so that the overlay never silently migrates after a display disconnect.
74. As a person, I want the selected display to withdraw its Overlay and visible input/accessibility regions if unavailable, so that a deliberate reselection is required rather than an off-screen or relocated surface.
75. As a person, I want fullscreen, no-active-session, and screen-recording/sharing conditions to follow the configured General, Display, and Quiet Scene rules without activating a Host or collecting screen data, so that privacy and focus are respected.
76. As a person, I want Settings to be a normal independently activating macOS window, so that I can configure Agent Island even when the Overlay is unavailable and without making the Overlay a conventional main window.
77. As a person, I want complete keyboard and VoiceOver operation of the visible Island and Settings content, so that monitoring, inspection, setup, and safe fallbacks do not require pointer hover.
78. As a person, I want Reduce Motion, Reduce Transparency, Increase Contrast, and increased text to preserve ownership, controls, hierarchy, and status semantics, so that accessibility is not a lesser product mode.
79. As a person, I want a new high-priority Attention Request announced once with its owner context while preserving my current focus and draft when safe, so that dynamic updates remain usable.
80. As a person, I want Agent Island to preserve protected local history across crash, restart, and sleep/wake but invalidate Action Leases and live Host locators, so that recovery restores evidence without reviving unsafe authority.
81. As a person, I want recovery to rebuild derived cards and queues from verified immutable facts, so that a bad snapshot, cache, or partially written update cannot create a ghost session.
82. As a person, I want Product reconciliation to use only documented read, list, replay, status, or probe surfaces, so that private transcripts, terminal scrollback, and local Product state are never used to manufacture truth.
83. As a person, I want encrypted local data, a Keychain-held per-installation key, authenticated integrity checks, and fail-closed migration/corruption handling, so that sensitive state is protected and never silently reset.
84. As a person, I want a selected user-data export to preview destination, scope, classes, and Interaction Content inclusion, so that local export is deliberate and no hidden second copy or upload occurs.
85. As a person, I want a Diagnostic Bundle to contain only redacted operational evidence in human-readable and machine-readable forms, so that support information never includes Interaction Content, credentials, raw IDs, titles, paths, commands, or locators.
86. As a person, I want no accounts, cloud copy, telemetry, analytics, remote listener, remote control, or network egress in this baseline, so that local operation remains private and independent.
87. As a future product owner, I want classified, consent-gated, outbound-only Service Egress seams retained, so that a future service can be designed without becoming canonical state or controlling Agent Products.
88. As a person, I want explicit Quit to cancel presentation activity, remove monitors and hit regions, invalidate volatile authority, persist durable records, and stop only application-owned helpers, so that shutdown sends no pending Product action and leaves no ghost UI.

## Implementation Decisions

1. Scope and identity. Support only macOS 14+ Apple Silicon, one local person,
   the first-class Agent Products and Hosts named above, and the frozen Parity
   Baseline. Use the glossary terms exactly. Product namespace plus stable
   Product-native IDs identify Agent Sessions, Turns, Subagent Runs, and
   Attention Requests. A Host Context, title, prompt, model, path, worktree,
   process, timestamp, or local record ID cannot create or merge identity.

2. Application architecture. Use an AppKit-first Swift application shell with
   SwiftUI-hosted Island and Settings views, Swift concurrency, and a pure,
   deterministic, replay-safe SessionDomain reducer. AppKit owns the Island
   Overlay, display, window-level, lifecycle, global-input, and activation
   mechanics. The main actor receives revisioned projections only; it does not
   determine Product truth.

3. Dependency direction. The core owns typed inward-facing ports and the sole
   SessionStore. UI, Agent Adapters, Hosts, helpers/extensions, configuration,
   diagnostics, export, and future services are isolated outer implementations.
   No outer component receives a store handle or Keychain key, writes canonical
   state directly, or bypasses ownership, classification, capability,
   configuration, navigation, or Action-Lease gates.

4. Canonical ledger. Commit accepted Normalized Event Facts atomically before
   publishing their projection. Facts are immutable logical history with native
   owner tuples, source ordering evidence, classification, negotiation
   provenance, receipt order, deduplication evidence, corrections, gaps, and
   reconciliation evidence. Lifecycle, queue, working-set, archive, search,
   and presentation records are replaceable deterministic projections.

5. Lifecycle reduction. Derive independent execution, attention, observation,
   and lineage dimensions. A validated Product fact, not local receipt order,
   action outcome, Host lifetime, timer, helper exit, or transport loss, may
   change Product lifecycle. Gaps, restart, reconnect without authoritative
   continuity, conflict, and unproven continuity result in unresolved state.
   Rewind and compaction preserve historical Turns inside the same Agent
   Session; a proven new Product session remains distinct.

6. Event acceptance. Validate contract version, authentication where required,
   size, source identity, owner chain, negotiated capability, schema, and
   classification before accepting an event. Stable source IDs are idempotent.
   An Adapter weak deduplication key can suppress only its documented replay;
   a collision remains ambiguity/gap evidence. Text, titles, paths, timestamps,
   and payload similarity are never deduplication evidence.

7. Adapter contract. Each Agent Adapter independently implements discovery,
   event ingestion, capability negotiation, typed action routing, owned
   configuration lifecycle, health/degradation, and observation/action/
   configuration kill switches. A Negotiation Snapshot records contract,
   Adapter/Product/interface versions, mode, probes, capabilities, health, and
   extension namespaces. Unknown major versions are incompatible; unknown or
   changed interfaces require read-only reprobe and capability-local narrowing.

8. Capability model. A Capability is a versioned evidence-bearing record with
   direction, scope, availability, maturity, constraints, provenance,
   freshness, and safe fallback. Observation does not grant action authority.
   Keep permissions, questions, free-text, plan review/feedback, interruption,
   usage, configuration, and exact navigation as materially distinct claims.
   Preserve Product-specific semantic variants rather than flattening them.

9. Product modes. Claude Code uses documented, consented hooks and an
   application-owned local helper only for version-gated observed events and
   live documented decisions. Codex CLI uses separate hook observation for
   independently launched terminal sessions and a version-pinned app-server
   for directly controlled work. Cursor uses observation-only Hooks for new
   IDE Agent Sessions and ACP control only for sessions Agent Island starts.
   Unsupported interaction always remains native-Host work.

10. Attention routing. Create an Attention Request only from validated native
    request evidence. Retain its immutable owner tuple, constraints, source
    provenance, safe content, draft, local presentation state, and action
    history. A live Action Lease is volatile, one-use, request/action-scoped,
    bound to Product-native state and deadline, and revoked on use, expiry,
    source change, capability change, gate closure, reconnect, restart, and
    wake. Persist one Action Attempt before at most one dispatch.

    For a negotiated structured-choice schema, render visible option-to-keyboard
    mappings only while focus is outside text entry. Start with no default
    selection, including a recommended option; replace the selected option for
    single-choice, toggle a source-permitted multi-select, preserve and allow
    reversal of each draft until submission, and enable Next only after the
    source-required answer is valid. Keyboard engagement does not bypass the
    same draft, capability, validation, confirmation, Action Lease, or typed
    Action Attempt gates.

11. Action semantics. Use typed Product actions only: allow/deny once,
    offered persistent permission, structured answer, plan accept/reject with
    reason, documented Turn input, named Turn interruption, and negotiated
    Product extension actions. Do not provide generic execution, raw command,
    terminal-key injection, or reply-by-text fallback. An action result is an
    operational outcome, not a lifecycle fact; indeterminate dispatch never
    retries automatically.

12. Host Context and Jump Back. Retain historical many-to-many Agent
    Session–Host Context associations with provenance, incarnation, locator
    state, invalidation, and navigation attempts. A locator is opaque,
    Host-specific, version/mode-scoped, and must be revalidated live. Return
    the achieved ladder level only: exactSurface, exactTab, workspaceOrFile,
    windowBestEffort, appOnly, or unavailable. Accessibility best effort is
    opt-in and cannot become a durable locator or automated-input channel.

13. Island system. Implement the approved Horizon hierarchy and bounded
    content rules with original diamond/shoreline marks and semantic visual
    states. Use critically damped, interruptible, top-anchored transitions;
    Reduce Motion uses an understandable short cross-fade. Global controls sit
    outside scrollable session content. Long content truncates, compacts, or
    scrolls before it collides with ownership or action labels.

14. Overlay mechanics. The Island Overlay is non-modal and normally
    non-activating. Only its currently visible silhouette is interactive or
    accessible. Built-in-notch safe geometry and external-display form are
    recomputed from the selected display's current safe bounds. It never spans
    the protected notch reserve, stores a Space identity, crosses Spaces, or
    silently migrates display. Display loss withdraws it; Settings remains
    independently available.

15. Focus, keyboard, and accessibility. Automatic reveal/collapse, hover,
    redraw, screen/display changes, and ordinary expand/inspect clicks retain
    the current Host key state. Explicit keyboard engagement creates a visible
    focus target; escape and Settings follow the defined safe focus behavior.
    Persist physical-key shortcuts, reject collisions, honor IME marked text,
    and apply Action-Lease and confirmation checks to consequential shortcuts.
    Use semantic macOS accessibility roles, labelled disabled reasons,
    structured child rows, one-time attention announcements, and visible-only
    accessibility focus.

16. Notification Policy. Derive one Alert Candidate from validated source
    evidence, then select a coordinated bundle of Island reveal/glow, sound,
    and macOS notification. Deduplicate across replay and parallel sources;
    suppress according to filters, quiet scenes/hours, foreground context,
    mute, probe classification, and interaction guard without altering the
    underlying facts. Attention never auto-expires. Usage Snapshots are
    display-only, capability-gated, and separate from context health. When an
    available `usageObservation` Capability supplies them, the Usage Settings
    and expanded-panel header provide reversible visibility, used-versus-
    remaining presentation, preferred-provider selection or following the
    currently selected active Agent Session's provider, and sourced provider,
    observation time, reset information, and stale/absent indication. A missing field remains
    absent rather than estimated. A Claude Status Line bridge is optional and
    reversible, preserves the person's existing visible output and exact-entry
    ownership, and cleanly disconnects; no bridge is required or implied for
    an unsupported Agent Adapter or Host.

17. Settings and onboarding. Implement the approved Atlas sidebar and
    contextual/resumable onboarding. Integration intent and health are always
    distinct. Previews are read-only local representations. General provides
    launch-at-login; independently persisted hover expansion and pointer-exit
    collapse; exact-Host foreground suppression; fullscreen and no-active-
    session hiding; completion/attention reveal controls subject to the
    Notification Policy; and a labelled, configured click action that either
    inspects/expands or performs separately revalidated Jump Back. It must
    never make click-to-Jump-Back ambiguous or turn a same-title/unvalidated
    Host into foreground suppression. Source idle cleanup is an approved
    material-improvement deviation: no automatic time or idle policy removes
    or conceals an Agent Session; evidence-based history transition and
    explicit person-selected deletion remain separate. Display provides the
    selected display, clean/detailed collapsed layout, content size, maximum
    panel width/height, completion-card height, optional sourced
    project/worktree/Model/Subagent Run/activity visibility, a live read-only
    preview, and safe notch/pill geometry clamped to the current display.
    Integrations owns installation plans and health. Custom Jump Back rules
    are inapplicable to the first-class Hosts: no in-scope Host has a supported
    user-defined destination grammar, and a URL-scheme registration alone is
    not a navigation contract. A future Host may expose such configuration
    only as a negotiated capability and a reversible, manifest-proven
    Integration Installation plan. Notifications, Sound, Usage, Shortcuts,
    Labs, Diagnostics, and the isolated Maintenance destination own their
    listed policy areas.

18. Configuration ownership. Model each enabled mode at a selected scope as
    an Integration Installation with a local Ownership Manifest. Discovery and
    reconciliation are read-only by default. Mutation is an installation-locked
    fresh plan, explicit approval, lossless exact-entry apply, and verification
    operation. Preserve unrelated content, comments, formatting, ordering,
    symlinks, paths, permissions, and external edits. Runtime disablement does
    not remove configuration; residual and ambiguous material is reported, not
    claimed removed.

19. Persistence and recovery. Use a single-writer encrypted SQLCipher SQLite
    canonical store with a Keychain-held per-installation key. Protect records
    with authenticated encryption and versioned schemas. At launch/wake,
    integrity-check then load or rebuild a projection from verified facts;
    retain durable records and drafts, mark formerly live work unresolved,
    expire leases, invalidate locators, append a recovery boundary, and use
    only documented reconciliation. Migrate by preflight, staged encrypted
    replacement, deterministic verification, and atomic promotion. Corruption
    or missing keys fail closed and preserve protected bytes for a person-led
    recovery/purge choice.

20. Retention and deletion. Session History is an Archive tier, not Product
    completion or deletion. Do not use time, idle cleanup, or resource
    pressure to remove active work. Separate moving to history, deleting
    selected inactive history, stopping local observation and deleting active
    local history, deleting diagnostics/preferences/cache/manifests, removing
    setup, and complete cleanup. Each requires scope preview and consequential
    confirmation; no action deletes Product data, unproven configuration, or
    another Installation's state.

21. Privacy and diagnostics. Classify every Adapter field at capture; unknown
    is Interaction Content. Keep baseline data local and protected. Never
    intentionally collect credentials, screen/clipboard/input-monitor data,
    arbitrary Product files, terminal scrollback, process memory, or raw
    secrets. Diagnostic events are allowlisted and redacted structurally;
    Diagnostic Bundles are person-initiated local Markdown plus JSON. User-data
    export is separate, selected, local, integrity-manifested, and requires an
    extra content confirmation.

22. Future extension boundary. Keep versioned internal extension namespaces,
    classified projections, consent/purpose gate, portable local identity, and
    a local auditable outbox seam. Service Egress is absent in v1 and, if later
    implemented, outbound-only and unable to read raw store data, merge remote
    state, block local commits, or initiate Product, Host, or configuration
    actions. Public third-party adapter loading is not a baseline feature.

23. Packaging and process posture. Run and distribute locally for the owner's
    personal use; Developer ID signing, notarization, licensing, pricing, and
    multi-user distribution are outside the baseline. Constrained
    application-owned helpers, extensions, and background/login items are
    permitted only where a capability requires them; they use authenticated
    least-privilege local IPC and have no direct UI/store/configuration/action
    authority. Do not use a privileged helper, code injection, a network
    listener, Catalyst, Electron, Tauri, or a web-wrapper architecture.

24. Mandatory feasibility gates. Before production implementation proceeds,
    complete and record two bounded spikes: (a) a native AppKit Overlay spike
    proving non-activating visible-only input, selected-display/notch geometry,
    accessibility, Spaces/fullscreen, sleep/wake, Settings independence, and
    termination behavior; and (b) an encrypted-store spike
    proving SQLCipher/Keychain creation, durable atomic write, restart,
    migration staging, key loss, integrity failure, and fail-closed recovery.
    The owner accepted both spike architectures on 2026-07-19 with explicit
    waivers for Developer ID signing, notarization, and full-Xcode-only test
    execution. Unrun checks remain implementation risks rather than claimed
    passes. Measured native-stack resource budgets remain release work.

## Testing Decisions

Test externally observable outcomes and contract boundaries, not private
implementation structure. The primary seam is a traceable parity matrix: each
applicable Parity Baseline item is exercised through a controllable Adapter or
faithful real integration input and observed at the visible Island, Settings,
Host-navigation, diagnostic, and persistent-outcome boundaries. One matrix
record identifies Agent Product, Agent Adapter mode, Host, version/capability
cell, fixture, evidence, expected outcome, deviation (if any), capture, and
human visual-review status. Mocks supplement but do not replace real or
faithful controllable Adapter evidence.

1. Maintain deterministic SessionDomain contract fixtures for stable and weak
   duplicate delivery, reorder, equal timestamps, gaps, resets, corrections,
   conflicts, rewind, compaction, ambiguous child completion, parent/child
   activity, Host closure, reconnect, reconciliation scope, restart, and wake.
   Assert facts are retained, projection is conservative, and no transport or
   local action event manufactures Product truth.

2. Test adapter contracts per Product mode: negotiation/version changes,
   unknown minor fields, incompatible majors, intake validation, malformed or
   oversized input, classification, capability scope, kill switches, health
   dimensions, documented degradation, and configuration ownership. Prove
   Claude hooks, Codex hooks/app-server, Cursor Hooks, and Cursor ACP retain
   their different observation and action boundaries.

3. Test Attention Request and Action Attempt behavior at the typed port seam:
   parallel requests; owner/Turn/request mismatches; stale/expired/reused
   lease; double activation; shortcut repeat; changed source state; gate
   closure; disconnect; Product-native resolution; indeterminate dispatch;
   plan/permission semantic differences; and restart/wake. Prove zero or one
   dispatch as appropriate and never treat acceptedByProduct as applied. For
   each supported structured-choice schema, prove visible option mappings
   select only outside text entry, no option is implicitly selected, single and
   multi-selection are reversible, drafts survive page/presentation changes,
   and Next remains disabled for an invalid or required-empty answer.

4. Test HostNavigationPort with identical titles, paths, panes, and windows;
   invalidated iTerm2/Orca locators; Cursor extension reload and multiple
   windows; native Cursor threads; Warp's app-only posture; Accessibility
   denial/revocation; fullscreen/Spaces; and each achieved navigation level.
   Assert every visual, spoken, and Diagnostic outcome names the achieved
   level, and no test uses synthetic input as fallback.

5. Test configuration plan/apply/verify/reconcile and cleanup using custom
   locations, symlinks, comments, ordering, unknown fields, external edits,
   policy precedence, ambiguous ownership, lossy syntax, interrupted writes,
   repair, uninstall residuals, and separate local-data categories. Assert
   no unproved entry or unrelated data is changed.

6. Test storage at the persistence boundary: atomic fact-plus-projection
   commits, crash between intake and presentation, deterministic snapshot
   rebuild, ciphertext/key/schema failure, interrupted and failed migration,
   deletion boundary, selected History deletion, active local-history deletion,
   export selection, diagnostic redaction, and absence/failure of Service
   Egress. Seed Interaction Content, credentials, paths, commands, IDs, and
   locators to prove prohibited outputs never contain them.

7. Test Island behavior using native UI and accessibility automation where it
   observes the public experience: resting/detailed states, focused reveals,
   Horizon selection, compact rows, scroll boundaries, completion recap,
   setup notice, attention sheet/queue, motion interruption, manual collapse,
   and all interaction guards. Verify no focus theft, panel flicker, duplicate
   reveal/sound/notification, or hidden hit/accessibility region.

8. Execute the overlay acceptance matrix across built-in notch and selected
   external displays: safe geometry, disconnect/reconnect/reselection,
   Spaces/fullscreen policies, screen-recording quiet-scene behavior, visible
   bounds, hover races, click configurations, Settings independence, quit,
   repeated sleep/wake, keyboard engagement, and exact/best-effort/app-only/
   unavailable Jump Back outcomes.

9. Perform keyboard, VoiceOver, Reduce Motion, Reduce Transparency, Increase
   Contrast, increased-text, non-QWERTY, and CJK/IME acceptance passes on
   Island and Settings. Verify complete operation, stable focus, semantic
   labels, disabled reasons, one-time attention announcements, no color-only
   state, no clipped owner/action labels, and no horizontal overflow.

10. Test Notification Policy with duplicate/replayed events, competing
    attention/activity/completion, foreground work, quiet scenes/hours, mute,
    filters, probe traffic, custom rules, sound import/playback/release, and
    missing usage. Assert one eligible coordinated signal bundle, protected
    payloads, correct dwell/persistence behavior, and no Product-state change.
    With a live usage capability, verify visibility, used/remaining, preferred
    provider and selected-session following, provider/observation/reset state,
    and a reversible Status Line bridge that retains existing visible output.
    With missing, stale, disabled, or reverted capability/bridge evidence,
    verify an honest stale/unavailable state, no estimated usage, and unchanged
    monitoring, queue, and Jump Back behavior.

11. Measure local event-to-first correct visual/accessibility presentation
    under 250 ms, local confirmed-action-to-one Adapter handoff under 150 ms,
    warm usable launch under one second, and cold usable launch under two
    seconds on supported Apple Silicon. Record environment, versions, traces,
    timestamps, and diagnostic correlation. An over-target valid sample fails.

12. Execute the 30-session workload with concurrent sessions, parent/child
    work, attention, selection, scroll, recap, history, duplicate/reordered
    input, reconnect, and recovery. Verify a safely inactive thirty-first
    session archives losslessly and an all-active/all-attention set overflows
    safely. Record idle and loaded CPU, memory, wakeups/energy, disk, open
    handles, tasks/timers, and audio-resource lifetime against resource budgets
    established by the native feasibility work.

13. Require human visual parity review of resting and active collapsed Island,
    expanded multi-session list, focused completion, Attention Request,
    integration health/setup, Settings, built-in-notch and external-display
    forms, and accessibility adaptations. Review functional hierarchy,
    density, readability, original identity, non-disruptiveness, and motion;
    image diff against the source is not an acceptance method.

14. Treat as release-blocking: invented Product truth; ownership crossing;
    stale/duplicate control; unsafe navigation claims; active-work loss;
    duplicate/disruptive presentation; privacy/configuration overreach;
    dishonest health/degradation; and inaccessible fallback. A capability
    downgrade may reduce scope but cannot waive any of these invariants.

15. Execute the explicit A3, O3, O4, and O5 Settings acceptance scenarios.
    In a live or faithful capability fixture, verify that General persists and
    applies launch-at-login, hover/reveal/collapse, exact-Host foreground
    suppression, fullscreen/no-active-session hiding, completion/attention
    reveal, and the labelled inspect/expand versus explicit Jump Back click
    behavior; a same-titled or unrevalidated Host must not suppress, a disabled
    click-to-Jump-Back configuration must not navigate, and no time/idle policy
    may remove or conceal an Agent Session. Verify that Display changes selected
    display, clean/detailed layout, content size, maximum panel bounds,
    completion-card height, optional sourced metadata, and notch/pill geometry
    only in its read-only local preview until saved; the preview must not emit
    an alert, move the live Overlay, mutate an Integration Installation, cross
    the protected notch, or silently migrate an unavailable display. Verify
    that no custom Jump Back rule is offered for an in-scope Host without a
    documented user-defined destination contract, including a bare URL-scheme
    registration; its available lower fallback remains labelled.

## Out of Scope

- Pricing, purchases, licensing, passes, device seats, or commercial
  entitlement flows.
- SSH Remote, tunnels, bastions, remote Host setup/monitoring, or multi-Mac
  fan-out.
- Accounts, teams, collaboration, multi-user administration, cloud sync, and
  hosted-service implementation.
- Telemetry and analytics implementation; only constrained future seams exist.
- Agent Products beyond Claude Code, Codex CLI, and Cursor, and Hosts beyond
  iTerm2, Cursor, Warp, and Orca, except contract-extension test cases.
- Codex Desktop, Intel Macs, macOS before 14, Windows, Linux, iOS, Android,
  and web clients.
- Copying Vibe Island branding, proprietary assets, screenshots, source code,
  or distinctive identity.
- Generic public plug-in loading or arbitrary third-party executable code.
- Privileged helpers, code injection, terminal scraping, simulated terminal
  input, screen capture, clipboard monitoring, keylogging, or a network
  listener.
- Production implementation, release execution, and final owner approval.

## Further Notes

### Traceability and acceptance

The normative [parity acceptance matrix and deviation register](assets/parity-acceptance-matrix-and-deviation-register.md)
is the canonical acceptance seam (version 1.0.0, 2026-07-18). It owns the
complete S1–S6, I1–I8, P1–P5, A1–A7, J1–J4, N1–N5, O1–O8, and cross-cutting H
records, including the complete Product × Adapter-mode × Host profile, source
evidence, positive/negative fixtures, current specification-versus-production
result, and stable deviation/fallback record. Each in-scope inventory item
must have a passing evidence record, a capability-backed inapplicability
record, or an approved permitted deviation. Deviations are limited to explicit
scope exclusions, proven capability limitations with safe fallback, documented
evidence gaps with an original tested decision, material improvements, or
platform/security constraints. A proposed deviation is an open gap, not a
pass. Final visual/deviation approval remains with the human owner.

Supporting traceability sources:

- [Parity Baseline inventory](assets/parity-baseline-inventory.md) and
  [parity acceptance standard](assets/parity-acceptance-standard.md)
- [Approved product defaults](assets/product-direction-defaults.md) and
  [quality attributes and failure invariants](assets/quality-attributes-and-failure-invariants.md)
- [Application architecture](assets/application-architecture-and-component-boundaries.md)
  and [data, event, action, and extension contracts](assets/data-event-action-and-extension-contracts.md)
- [Horizon visual system](assets/island-interaction-visual-system.md),
  [attention workflow](assets/attention-completion-workflow-design.md), and
  [Atlas Settings architecture](assets/settings-onboarding-diagnostics-information-architecture.md)

The architecture must preserve the stable identity, local canonical state,
versioned capability, immutable lifecycle, exact configuration ownership,
live Action Lease, live Host locator, non-activating Overlay, and AppKit-first
boundaries already accepted in the repository ADRs. The two feasibility spikes
and the measured resource budget are pre-production gates, not optional polish.
