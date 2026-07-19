# Host Context identity, navigation, and fallback

**Decision date:** 2026-07-18  
**Scope:** the Host Context record and association model, live navigation
validation, and person-visible Jump Back behavior. This specifies neither
Host-control input nor macOS window-management APIs beyond the capability
evidence established in [Host navigation and control capabilities](host-navigation-capabilities.md).

## Decision

A Host Context is a Host-native visible surface, not a session identity and
not a generic window/tab/pane string. Agent Island preserves a historical,
provenance-bearing association between an Agent Session and zero or more Host
Contexts. It activates only a currently revalidated typed locator through a
currently negotiated navigation Capability. If either association or locator
is ambiguous, it does not guess: it tries only a lower, independently proven
fallback for the same Host and related Agent Session, then reports the outcome
actually achieved.

A Host Context has two identity layers:

1. **Context identity** is `Host identity + Host Context kind + documented
   Host-native context key`, but only when that Host contract promises such a
   key. It distinguishes a live iTerm2 session, a Cursor extension endpoint's
   retained terminal, an Orca terminal, and any future supported surface;
   Agent Island local IDs are storage keys, not evidence.
2. **Incarnation** is the bounded live occurrence in which a typed locator is
   resolvable. Its lifetime is scoped to the Host runtime, endpoint, and
   capability negotiation that issued it. A Host restart, endpoint reload, or
   unsupported re-creation starts a new incarnation unless the Host itself
   explicitly proves continuity.

No durable Host-native key means there is no continuity claim across that
boundary. For example, a Cursor `Terminal` object is a live locator within
one connected extension endpoint, not a portable terminal identity. Titles,
tab ordinals, PIDs, CWDs, display frames, Accessibility element paths,
worktree paths, visible text, and screenshots may help a person recognize a
record, but never establish either identity layer.

## Record and association model

The persisted model separates the object seen in a Host from the evidence that
relates it to Product-owned work.

| Record | Required contents | Rules |
| --- | --- | --- |
| **Host identity** | Host kind, bundle/application identity, selected installation scope, and observed version/build where available. | A version/build supplies compatibility evidence; it is not by itself a new Host identity. Do not substitute a similarly named application. |
| **Host Context** | Local record ID; Host identity; Host Context kind; documented native context key when supplied; current or most-recent incarnation ID; capture provenance and times. | The local ID and a missing native key cannot prove that a later context is the same one. |
| **Context incarnation** | Host runtime/endpoint instance, negotiation snapshot, one typed locator, locator issue/last-validation times, invalidation reason, and non-identity diagnostic observations. | A typed locator is opaque outside its matching Host capability. It is never transformed into another Host's locator or reconstructed from diagnostic data. |
| **Agent Session–Host Context association** | Product namespace + native Agent Session ID, Host Context/incarnation reference, source or user-assertion provenance, evidence time, and state. | It is many-to-many over history. A Host Context can visibly host sequential work; an Agent Session can move between Hosts or have more than one observed surface. Neither relation changes Agent Session identity. |
| **Navigation attempt** | Deliberate invocation, candidate association/incarnation, capability snapshot, attempted and achieved level, ordered reasons, and timestamp. | Keep operational metadata only. It is an auditable outcome, not proof that the Agent Product acted or that a context remains live. |

An association state is one of `current`, `historical`, `unresolved`, or
`replaced`. `current` means the association has recent, valid evidence; it
does **not** mean its locator remains valid. A new association changes an old
one to `replaced` only when source evidence establishes replacement; otherwise
it remains `historical` or `unresolved`. A closed pane, missing endpoint, or
failed activation makes the old
incarnation unavailable and leaves the association historical or unresolved
as its prior evidence requires. Agent Island never infers that an Agent
Session ended because its Host Context became unavailable.

## Capture and persistence

Capture a Host Context association only from one of these sources:

- a documented Product/Agent Adapter event that names both the owning Agent
  Session and a Host-supported locator or native context key;
- a documented Host/extension/runtime observation that resolves that locator
  within the already proven Agent Session association; or
- a deliberate person selection from a safe Host chooser. This is recorded as
  a **user assertion**, creates a new bounded association, and is not used to
  merge old/recreated contexts or manufacture Product continuity.

The capture must include the Host/endpoint scope and the capability
negotiation snapshot that made it valid. If an Adapter can observe the Agent
Session but cannot bind it to a Host-supported surface, retain the session
with no current Host Context rather than attaching the nearest terminal,
workspace, or app.

Persist the association and opaque locator evidence locally as Operational
Metadata. Non-content display/frame/Accessibility structure may be retained
as diagnostic evidence, never as a locator; a Diagnostic Bundle exports only
redacted structural facts. Window names, terminal labels, project/worktree
paths, files, commands, and visible text are Interaction Content under the
local-first policy and must not enter a Diagnostic Bundle.
Persisting a locator lets Agent Island explain prior evidence after restart;
it does not make the locator live after restart.

The supported typed locator families are intentionally Host-specific:

| Host surface | Valid live locator | Continuity and capture constraint |
| --- | --- | --- |
| iTerm2 pane/tab/window | iTerm2 API session ID, optionally tab/window IDs, scoped to its live API connection. | Re-resolve before every Jump Back. The session ID is exact only while the Host supports its resolution; no iTerm2 relaunch continuity is assumed. |
| Cursor integrated terminal | Extension-endpoint instance plus the retained live `Terminal` capability/reference in that Cursor window. | Never persist `name` or `processId` as an identity substitute. Extension reload, endpoint loss, or window closure invalidates exact navigation. |
| Cursor IDE Agent/Composer thread | None in the researched public surface. | Preserve Product thread evidence but associate no exact native thread surface. Only workspace/file/app fallbacks may be offered when independently proved. |
| Orca terminal | Version-matched runtime endpoint and revalidated terminal handle; a runtime-confirmed tab/pane capability determines exactness. | A private stable-pane observation is not a cross-version public locator. A returned handle must be live when invoked. |
| Warp | None in the researched public surface. | A URL scheme, block text, title, or Accessibility label does not create an exact locator. |

## Invalidation, reconciliation, and recreation

Every locator has an explicit validity boundary. Invalidate it immediately on
its Host-reported pane/tab/window closure, Host termination, endpoint/API
disconnection or reload, capability expiry, incompatible version, permission
revocation, validation failure, or contradictory same-scope Host evidence.
Persist the reason and time; do not erase the historical association.

On Agent Island launch/wake or Agent Adapter reconnect, all formerly live
locators begin `unvalidated`. A read-only Host probe may revalidate one only
when the current negotiated Host contract resolves its exact native key in the
required endpoint/runtime scope. Otherwise mark that incarnation unavailable.
Agent Island must not launch, resume, focus, or scan a Host merely to repair
an association. A Host may be launched only by an explicit Jump Back that
uses the app-level fallback.

Reconciliation has three separate outcomes:

| Evidence result | Required result |
| --- | --- |
| The same supported Host key resolves in the required live scope. | Retain the Context identity and add a new validated incarnation/locator if the Host documents that continuity. |
| A Product event or a deliberate user assertion names a different live supported surface. | Create a distinct association. Mark the old association `replaced` only if the source explicitly says it moved/replaced it; otherwise preserve it as historical/unresolved. |
| The source cannot prove continuity, or several plausible windows/tabs/panes exist. | Preserve the old record as unavailable/historical, create no automatic binding, and offer a safe chooser or a lower fallback if one exists. |

This covers similar terminals, duplicate titles, multiple worktrees, pane
splits, reopened windows, and recreated contexts: similarity is never a
reconciliation key. Worktree continuity is independently governed by its
version-control evidence and may make `workspaceOrFile` available; it cannot
revive an exact Host Context.

Spaces and full-screen placement have no public stable activation identity.
Store neither as a navigable key. A Host API may make its own exact surface
frontmost and macOS may choose a Space; report only the Host-confirmed
navigation level. With no exact Host API, an app activation is the highest
honest result across hidden, minimized, moved-display, full-screen, and
other-Space conditions.

## Jump Back algorithm and capability ladder

Jump Back is an explicit person action. Card selection, notification display,
reconciliation, and automatic focus never activate a Host or cross Spaces.
For the selected Agent Session, Agent Island evaluates candidates in recency
order only after proving that each association belongs to that session. It
does not try a different Agent Session's similar Host Context.

For each candidate, it revalidates the exact capability and uses the first
available level in this strict ladder. A failure at one level can continue
only to a lower independently negotiated capability; it cannot broaden a
locator, simulate input, or guess a sibling surface.

| Achieved level | Invocation rule | Required feedback |
| --- | --- | --- |
| `exactSurface` | A supported Host API revalidated and selected the recorded exact pane, terminal, or equivalent visible surface. | “Opened the exact <Host surface>.” |
| `exactTab` | The supported API selected the recorded tab but cannot select its child pane. | “Opened the exact tab. Select the pane.” |
| `workspaceOrFile` | A supported API opened a workspace/file explicitly associated with the Agent Session or its proven Worktree. | “Opened the related workspace/file; the original context is unavailable.” |
| `windowBestEffort` | The person has opted in to Accessibility and a current AX query identifies exactly one candidate window. | “Brought a matching Host window forward (best effort); the original context was not verified.” |
| `appOnly` | macOS launched or activated the recorded Host application. | “Opened <Host>; the original context could not be located.” |
| `unavailable` | No supported, permissioned route can be attempted. | “Can’t jump back: <specific, actionable reason>.” |

`workspaceOrFile` requires an independently proven Product/Worktree relation,
not a path or title resemblance. `windowBestEffort` is optional, must be
explicitly enabled after contextual Accessibility education/consent, and
cannot use clicks, keystrokes, terminal text, or arbitrary UI automation. If
an AX query finds zero or multiple candidates, skip it. `appOnly` is not a
claim that the correct Space, window, tab, pane, or thread is visible.

The preferred candidate is the most recent association with a fresh exact
locator. If it fails, Agent Island may try another association of the **same
Agent Session** only when it has its own valid capability and the attempt log
can name which association was tried. When more than one candidate provides
the same highest level, present a safe chooser with non-identity recognition
metadata; never select one by score. If no chooser can represent them safely,
downgrade to an applicable lower level.

Navigation remains separate from control. A successful Jump Back never
authorizes terminal input, approval, question response, cancellation, or
other Agent Product action. Those require their own live, scoped Capability
and action-routing checks.

## Feedback, permissions, and accessibility

Before the attempt, the control describes the best currently known route—for
example, **Jump Back to exact iTerm2 pane** or **Open related workspace**—but
the post-attempt result always states the achieved level. The session detail
keeps a compact, accessible navigation status containing the achieved level,
Host, time, and redacted reason; a disclosure exposes capability/permission
recovery steps without Interaction Content.

Do not use a success checkmark for `windowBestEffort` or `appOnly` without
the accompanying limitation. For `unavailable`, distinguish at least:

- Host not installed/not running or launch failed;
- the required Host integration, endpoint, or API is disconnected;
- exact locator expired because the original surface closed or was recreated;
- required Automation or Accessibility permission is denied/revoked;
- an unsupported Host surface (including a Cursor native thread or Warp pane);
- several similar candidate surfaces require user choice; and
- no related workspace/file or Host application is available.

Ask for Automation or Accessibility only when a person invokes the relevant
route, naming the Host, capability, and fallback first. Declining, revoking,
or timing out a permission removes only the affected level, updates health,
and continues to the next safe level when available. Accessibility is never
requested to make an exact claim that the Host cannot make itself.

VoiceOver and keyboard paths announce the exactness qualifier and reason,
not just “Jump Back complete.” Reduced-motion, quiet scenes, panel collapse,
and notification suppression may change presentation but never suppress the
persisted navigation outcome or alter its target.

## Required conformance scenarios

The later persistence, overlay, quality, and data-contract work must prove:

1. Two iTerm2 panes and two Cursor terminals with identical titles/CWDs never
   merge or receive each other's Jump Back.
2. A live iTerm2 pane resolves to `exactSurface`; after its closure or Host
   restart, its old session ID is invalidated and is never recreated by title,
   CWD, PID, ordinal, or screen location.
3. Cursor extension reload/window closure invalidates the retained terminal
   reference; an independently proved workspace may open, but no new terminal
   association is guessed. Native Cursor threads never claim exact selection.
4. An Orca runtime handle is revalidated through the version-matched runtime;
   tab-only support reports `exactTab`, not pane success.
5. Warp offers only app activation unless the person enabled Accessibility and
   exactly one window is currently found; that result remains best effort.
6. A Host Context moved, minimized, hidden, put full-screen, or left on a
   different Space never causes a Space/full-screen success claim. Only a
   Host-confirmed exact result may exceed `appOnly`.
7. After Agent Island restart/wake, persisted locators are historical until a
   read-only documented probe revalidates them; Agent Session lifecycle and
   action authority remain unaffected by failure.
8. Missing/revoked Automation or Accessibility access yields the named lower
   level or `unavailable`, never UI automation, simulated input, or a false
   success indication.
9. A recreated or user-selected Host Context produces a distinct,
   provenance-marked association. It does not replace old history or merge
   Agent Sessions without explicit source continuity.
10. Exact navigation, a workspace/file fallback, a best-effort window, app
    activation, and no route produce distinct visual, spoken, and diagnostic
    outcomes.

## Consequences

The persistence decision must retain Host Context history and invalidation
reasons separately from Product lifecycle history. The overlay decision must
render Jump Back as an explicit action and show the achieved ladder level.
Integration health must report Host navigation independently from observation
and Agent Product action capabilities. The data/event/action contract must
serialize typed Host locators, association provenance, and navigation outcomes
without exposing Interaction Content or treating a locator as cross-Host data.
