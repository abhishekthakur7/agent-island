# Domain Docs

## Before exploring

- Read `CONTEXT.md` at the repository root.
- Read relevant ADRs under `docs/adr/`.

If either location is absent, proceed without creating placeholder files.

## Use the glossary's vocabulary

Use canonical terms from `CONTEXT.md` in issue titles, requirements, code, tests, and user-facing copy. Do not substitute terms explicitly marked `_Avoid_`.

If a required concept is absent or ambiguous, resolve the language through domain modeling before adding it.

## Layout

```text
/
├── CONTEXT.md
├── docs/
│   ├── agents/
│   └── adr/
└── src/
```
