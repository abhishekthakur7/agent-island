# 0001: Transcript reading as a second, explicitly separate evidence path

**Status: Proposed**

> **Note on this ADR's own location and numbering.** `docs/adr/` did not exist
> before this ticket (AB-156), although `CLAUDE.md` already referenced it. This
> file both creates the directory and is `0001`. The convention itself —
> `docs/adr/NNNN-slug.md`, sequential numbering, one file per decision — is
> therefore also part of what's being proposed here, not an established
> precedent this ADR merely follows. A human should confirm the directory
> location and numbering scheme (this ADR follows `.agents/skills/domain-modeling/ADR-FORMAT.md`,
> which already documented this exact convention pre-emptively) before a
> second ADR is added.

## Context

Agent Island's only prior evidence path for Agent Session state is the
`NormalizedEventFact` (`SessionDomain/Envelope.swift`): a record admitted only
after `SessionDomainValidator` checks contract-version compatibility, a
granted Adapter capability, and Product/owner identity (ADR-numbered decision
referenced throughout the codebase as "ADR 0001" in code comments, predating
this directory's existence). `CONTEXT.md` defines a Normalized Event Fact as
"an immutable, validated local record of one source-proven ... observation
... evidence from which Agent Island derives state." Every session field the
UI has ever shown — `execution`, `observation`, `displayTitle`, `hostLabel`,
Turn/Subagent Run lifecycle — flows through that single, negotiated,
capability-gated pipeline.

The in-flight overlay redesign (`docs/agents/tasks/overlay-visual-redesign.md`,
§1.6 session rows and §1.10 focused card) needs data that pipeline has never
carried: per-message token usage, the agent's current message body, the
person's last prompt, and a scrollable recent-turns excerpt. None of this is
available from a documented Claude/Codex hook payload today. It *is*,
however, sitting in plain sight in the Product's own on-disk transcript files
(`~/.claude/projects/**/*.jsonl`, `~/.codex/sessions/**/*.jsonl`) — each
`.jsonl` line carries the full message text and a `usage` block. Reading
these files was explicitly approved for this ticket (they are local,
already-written-by-the-Product files, not a new external dependency), with
two decisions deliberately left open rather than guessed at:

1. How is transcript-derived evidence distinguished from hook-proven,
   `NormalizedEventFact`-backed evidence in the model, so a caller can never
   mistake one for the other?
2. Does introducing this second evidence path deserve a recorded decision?

## Decision

**(1) Transcript reading is a genuinely second evidence path, and it is kept
type-level separate — never folded into `NormalizedEventFact` or an existing
`SessionProjection` field.**

A transcript read has none of the properties that make a
`NormalizedEventFact` trustworthy: no negotiation, no capability grant, no
delivery guarantee, no schema contract with Agent Island. The file is simply
whatever the Agent Product happens to have written for its own purposes; it
may be rotated, truncated mid-write, briefly absent, or shaped differently
across Product versions. Treating it as equivalent evidence would let a
best-effort filesystem read silently masquerade as a source-proven
observation — the exact failure mode the whole `NormalizedEventFact`/
`SessionDomainValidator` design exists to prevent.

The chosen mechanism is a single new optional sub-struct on
`SessionProjection`:

```swift
public let transcriptEvidence: TranscriptEvidenceProjection?
```

`TranscriptEvidenceProjection` (`SessionDomain/TranscriptEvidence.swift`) is a
pure `Sendable`/`Equatable`/`Codable` struct holding *all and only* the
transcript-derived fields: `modelFromTranscript`, `latestUsage`
(`TranscriptUsageProjection`), `latestAgentMessageText`,
`latestUserPromptText`, `recentTurns` (`[TranscriptTurnProjection]`), a
`truncated` flag, and `readAt`. Because it is a separate, nullable,
explicitly-named bag:

- `nil` cleanly and only means "no transcript was read for this session" —
  never a fabricated empty-but-present value.
- No reader can accidentally attribute transcript data to `execution`,
  `observation`, `displayTitle`, or any other hook-sourced field.
- A consumer that wants to distinguish provenance in the UI (e.g. "this
  model name came from the transcript, not a hook") can do so by construction
  — it's a different field, in a different, clearly-named, clearly-documented
  type.

**Alternative considered and rejected: a per-field `Provenance` enum.** Wrapping
every field individually (e.g. `Sourced<T> { value: T; provenance: .hook |
.transcript }`) was considered. Rejected because almost none of
`SessionProjection`'s *existing* fields would need it (they are unconditionally
hook-sourced today), so it would mean invasively wrapping fields that don't
need wrapping just to accommodate the few new ones that do. A single
nullable, wholly-transcript-sourced bag says the same thing more simply: *the
whole bag has one provenance*, so the type itself is the provenance tag.

**`model` is carried through only from `transcriptEvidence`, not from the
hook-parsed value.** `ClaudeAttributedContext.model`
(`ClaudeCodeAdapter.swift:589`) is parsed from the hook payload today but
never reaches `NormalizedEventFact`/`SessionProjection` — it is dropped after
`ClaudeHookNormalizer.normalize` returns. Threading it through would need a
new field on `RawEventEnvelope`/`NormalizedEventFact` and one line in
`SessionReducer.reduce` (precedented exactly by how `displayTitle`/
`hostLabel` already flow through that same pipeline, and low-risk since both
types are persisted as JSON blobs — an added `Optional` field decodes as `nil`
for every existing persisted row). That is a small, mechanical change, but it
touches shared fact/validation/reducer files used by every Adapter, which
AB-156 was not scoped to modify. It is flagged for whichever ticket does the
row-metadata plumbing (§1.6) rather than done speculatively here.

**(2) Yes, this is worth an ADR**, and this file is it. The rationale: the
decision is architectural (a second evidence path alongside the codebase's
one well-established observation model), hard to reverse cheaply once UI code
starts depending on the type-level split, and genuinely surprising without
context — a future reader who finds `SessionProjection.transcriptEvidence`
sitting next to `execution`/`observation` should not have to reverse-engineer
why it doesn't go through `SessionDomainValidator` like everything else.

## Consequences

- The reader (`TranscriptEvidenceReader` target) lives entirely outside
  `SessionDomain` and outside `ClaudeCodeAdapter`/`CodexCLIAdapter` — both of
  which are documented as boundaries that deliberately never receive "a
  transcript reader." It depends only on `SessionDomain`, for the pure
  projection types it produces.
- `TranscriptEvidenceProjection` carries Interaction Content-shaped data
  (prompts, agent message text — `CONTEXT.md`'s definition, not
  `PayloadClassification.operationalMetadata`). It is persisted as part of
  `SessionProjection` in the encrypted `ProtectedStore`, which is the
  appropriate place for it, but it must never be included in a
  `DiagnosticBundle` or cross `ServiceEgressPort` without the same explicit
  review any other Interaction Content would require — this ADR does not
  grant it a lighter classification just because it arrived through a
  different door.
- Because there is no negotiation or delivery guarantee, every field in
  `TranscriptEvidenceProjection` is independently optional, and the reader
  never throws: an unreadable file, a truncated multi-byte UTF-8 sequence at
  the read boundary, or a malformed JSON line all degrade to a missing field
  or a `nil` bag, never a crash.
- Live periodic-refresh wiring of `transcriptEvidence` into the running,
  published `SessionProjection` is explicitly deferred to the consuming
  tickets (§1.6, §1.10) — AB-156 delivers the reader and the model
  extension, not the population/refresh loop.
