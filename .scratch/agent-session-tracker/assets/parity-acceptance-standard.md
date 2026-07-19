# Parity acceptance standard

**Applies to:** the frozen [Parity Baseline inventory](parity-baseline-inventory.md), not to later Vibe Island releases.  
**Purpose:** decide whether Agent Island achieves the required user outcomes and quality while retaining an independent product identity.

## 1. What is being accepted

Parity is outcome parity, not implementation, asset, copy, or pixel parity. An implementation meets parity only if every *applicable* inventory item has an observable, traceable, passing acceptance scenario. An item is applicable when it is both in scope and supported by the relevant Agent Product, Agent Adapter, Host, and Host Context capability. The capability contract must make that determination explicit; an unsupported or unsafe capability is never silently treated as passed.

Each inventory item must have a parity record containing:

| Field | Required content |
| --- | --- |
| Inventory reference | One or more inventory IDs, or the explicit cross-cutting lifecycle row. |
| Applicability | The relevant Agent Product × Host capability cells, including every cell that is unsupported or intentionally excluded. |
| User outcome | A concise observable result, written without source-product implementation assumptions. |
| Acceptance scenario | Reproducible setup, action/event, expected visible result, and expected negative result. |
| Evidence | Automated-test output where feasible plus a captured video/screenshot, accessibility inspection, event/diagnostic trace, or a combination appropriate to the behavior. |
| Result | Pass, fail, blocked, or approved deviation; include the tested application and adapter versions and date. |
| Deviation link | A deviation record when the result differs materially from the inventory outcome or evidence. |

The implementation-ready specification owns the complete matrix. A prototype or Adapter test may contribute evidence, but it cannot turn a missing matrix row into an implied pass.

## 2. Acceptance gates

### Functional gate

For each applicable cell, the scenario must demonstrate the inventory outcome with real or faithful controllable Agent Adapter input. Adapter claims must be backed by the Adapter's capability evidence, not inference from a title, process, or UI appearance. The application may omit data an Agent Adapter cannot safely provide, but it must not fabricate it.

The following outcomes are release-blocking failures in every applicable cell:

- an Agent Session, Subagent Run, turn, Attention Request, or Host Context is misattributed, duplicated, lost, or acted on as though it belonged to another owner;
- an action, shortcut, or Jump Back targets an ambiguous or stale context, claims success when it did not occur, or bypasses required consent;
- an enabled integration is presented as healthy when delivery is broken;
- an unresolved Attention Request is hidden, a stale one remains actionable, or a completion/notification is falsely attributed;
- recovery, filtering, dismissal, or cleanup turns active work into a ghost or removes it solely because a presentation timer elapsed; or
- an in-scope interaction expands scope into remote, account, commercial, telemetry, unsupported Agent Product/Host, or non-local behavior.

### Interaction gate

The end-to-end scenarios must show that a person can discover, understand, and complete the same in-scope jobs without a new unsafe or confusing detour: monitor concurrent work, distinguish state and health, inspect a session, respond to Attention Requests where supported, recover via an honest Jump Back, and control reveal/collapse/settings behavior.

State-transition evidence must cover the normal path and the relevant interruption path: competing activity and attention, focused versus full-list presentation, action resolution while the panel is open, unavailable routing, and collapse/reopen/restart where applicable. It must also demonstrate that the overlay does not block ordinary Host input or retain an invisible hit region. Exact dwell durations, curves, and dimensions are set by the later interaction and overlay decisions; they are accepted for stable, comprehensible behavior rather than as copied constants.

### Visual-quality gate

Visual parity is evaluated by human review of representative, instrumented states—not an image-diff score against the source. The reviewed set includes, where applicable: resting and active collapsed island; expanded multi-session list; focused completion; Attention Request; setup/health state; Settings; and the built-in-notch and external-display variants. The same review checks reduced-motion, keyboard, VoiceOver text equivalents, and high-contrast treatment as those requirements become specified.

Every reviewed state must pass all of these observations:

1. Status, urgency, session count, selection, completion, setup, and error are immediately distinguishable through more than color alone.
2. The island remains a compact, non-modal top-edge companion with clear hierarchy and bounded density; details, controls, and long text neither collide nor obscure the current task.
3. Expanded content, recaps, and session lists preserve readable hierarchy and independent scrolling without losing context or action ownership.
4. Motion clarifies state changes without layout jitter, flicker, trapped input, or a dependence on motion to convey meaning.
5. Settings and maintenance information are scannable, native-macOS-appropriate, and visually distinguish ordinary, warning, and destructive actions.
6. The result is recognizably Agent Island, not a look-alike source surface.

Prototype tickets require live human review under the Wayfinder map. Their review artifacts and findings feed this gate; final acceptance is subject to the human-owner approval ticket and cannot be self-certified by a passing automated suite.

## 3. Identity boundary

The source is evidence of hierarchy, density, state differentiation, and interaction quality. It is not a design kit. Agent Island must use its own name, wordmark, icons, illustrations, glyph shapes and animation frames, onboarding imagery, sounds, screenshots, copy, and layout details. It must not ship source artwork, logos, screenshots, strings, or a substantially similar arrangement of distinctive branded elements.

Generic macOS conventions and functional necessities may overlap: top-edge placement, a dark companion surface, native controls, semantic state colors, rounded geometry, compact metadata, and accessible status redundancy are acceptable when they solve the documented user problem. The visual-quality gate asks whether Agent Island independently composes those necessities into its own system; it does not prohibit ordinary platform conventions.

## 4. Permitted deviations

An omission or difference is acceptable only under one of these categories:

| Category | When it is permitted | Required compensating evidence |
| --- | --- | --- |
| Scope exclusion | The behavior is explicitly excluded by the Wayfinder map. | Link to the map exclusion; do not represent it as a parity shortfall. |
| Capability limitation | The relevant Agent Adapter or Host cannot safely observe or route the behavior. | Capability proof, accurate unavailable state, and the safest useful fallback—usually Jump Back to the owning Host Context. |
| Evidence gap | The source outcome or visual detail was not observed. | An original decision, usability/prototype evidence, and a test for the chosen behavior; never present a guess as source parity. |
| Material improvement | The difference preserves the baseline job and is demonstrably safer, more accessible, more private/local, more reliable, or clearer. | Side-by-side outcome rationale and passing scenario proving no lost ownership, action, or discoverability. |
| Platform or security constraint | macOS or a required trust boundary makes the source behavior unsafe or unavailable. | Constraint evidence, honest UI, and a non-deceptive fallback. |

No deviation is permitted merely because it is difficult, visually different, unimplemented, or unsupported by an unverified assumption. Replacing a supported in-island action with a generic Host instruction is not an improvement. A capability limitation is also not permission to show invented details, target an ambiguous Host Context, or claim that a request was applied.

## 5. Deviation record and decision rule

Each material deviation receives a stable record with the inventory IDs, category, affected capability cells, source evidence, proposed Agent Island behavior, user impact, fallback, test evidence, owner, and disposition. A record is **proposed**, **approved**, **rejected**, or **superseded**. Proposed records remain visible gaps and cannot be counted as parity passes.

Agent Island qualifies as meeting the Parity Baseline when:

1. every applicable inventory item has a passing parity record;
2. every inapplicable item is backed by a scope or capability determination;
3. there are no release-blocking failures;
4. every material deviation is approved by the human owner in the final approval workflow; and
5. visual review passes while the identity boundary is intact.

It may be described as **exceeding** the Parity Baseline only when the same five conditions hold and the improvement evidence shows that the baseline job is preserved or made safer, clearer, more accessible, more reliable, or more private without expanding scope. New capability claims require their own evidence and do not offset an unmet baseline item.

## 6. Downstream use

- The island and attention-workflow prototypes use the visual-quality and interaction gates as their review script.
- Adapter, Host, lifecycle, overlay, and settings tickets add their scenarios to the parity matrix rather than creating isolated pass criteria.
- The final specification assembles the matrix and deviation register.
- The final audit verifies completeness; the final human-approval ticket is the authority for accepting or rejecting deviations.
