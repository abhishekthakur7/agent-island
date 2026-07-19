# Agent Island approved Horizon reference

> APPROVED VISUAL REFERENCE — rewrite for production; do not ship this
> dependency-free review implementation.

Horizon (prototype Variant A) is the approved top-edge Agent Island visual
system. The reference covers clean, detailed, focused auto-reveal,
expanded-list, selected-detail, TODO task/Subagent Run, and large-session
states. The rejected Current and Ledger directions have been removed.

## Run

From the repository root:

```sh
python3 -m http.server 4183 --directory .scratch/agent-session-tracker/assets/island-visual-system-prototype
```

Open <http://localhost:4183/?state=clean>.

## Controls

- Use the top review rail (or keys `1`–`7`) to change presentation state.
- Toggle built-in versus external display and standard versus increased text.
- The URL stores the current review configuration and is reload/share stable.

## Review question

The direction is final: Horizon. `REVIEW.md` records the decision and
`../island-interaction-visual-system.md` is the durable specification.
