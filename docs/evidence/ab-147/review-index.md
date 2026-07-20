# AB-147 frozen parity review index

This is the review package for the frozen **Vibe Island v1.0.42** Parity
Baseline observed 2026-07-18, scoped to macOS 14+ on Apple Silicon. It is an
evidence and release-readiness review; it makes no Product or feature change.

The package is structurally complete, but release readiness is **BLOCKED**.
The AB-146 deterministic/headless evidence is useful only for the cells it
actually captures. Its missing native rendered, AX, VoiceOver, keyboard,
scroll, full-app launch, restart/wake/display, energy, disk, and audio cells
remain blockers. The two current `permission_denied` attempts to target raw
`AgentIslandApp` are a diagnostic fact, not a substitute for any capture.

| Review artifact | Purpose |
| --- | --- |
| [Parity matrix](parity-matrix.md) | Canonical S/I/P/A/J/N/O/H coverage and evidence links. |
| [DR checklist](dr-checklist.md) | Auditable DR-01…DR-05 decisions. |
| [Gap log](gap-log.md) | Blocking gaps, honest interim behavior, and follow-up recommendation. |
| [Human review form](human-review-form.md) | Required visual/accessibility observations; automation cannot sign it. |
| [Diagnostic index](diagnostic-index.md) | Redacted capture correlation, provenance, and diagnostic references. |
| `src/Fixtures/AB147Parity/parity-v1.json` | Machine-readable matrix source. |
| `src/Fixtures/AB147Parity/release-gates-v1.json` | Explicit readiness gates and exit-code contract. |

## How to verify

Run from `src/`:

```sh
Scripts/verify-ab-147.sh --structure-only
Scripts/verify-ab-147.sh; echo $?
```

The first command is the package-structure check and must exit `0`. The second
prints structural `PASS`, then exits `2` with `release readiness BLOCKED` while
the documented release gates are open. Exit `2` is intentional and is not a
test/product failure or a readiness pass.

## Review rules

- The Parity Baseline is a visual/behavioral reference, never Product truth.
  Only current Agent Product and Host evidence can establish identity,
  lifecycle, action outcome, capability, or navigation target.
- A capability missing from a reviewed profile is displayed as unavailable or
  its documented lower result; it is never represented as `N/A` or silently
  emulated.
- Native Host is the fallback for an unavailable Adapter action or uncertain
  navigation. Local state may be unresolved/degraded but must not imply that
  active Product work ended.
- Automated fixture coverage is structural/contract evidence. Visual fidelity,
  macOS interaction, assistive technology, and subjective human review require
  the form in this package, signed by a person with redacted capture links.

The detailed authoritative row data is the versioned JSON fixture; this index
and its Markdown matrix intentionally repeat it in a reviewable format.
