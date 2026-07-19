Status: closed
Type: prototype
Label: wayfinder:prototype
Parent: ../MAP.md
Assignee: Codex
Blocked by: 01-establish-authoritative-parity-inventory.md, 02-define-parity-acceptance-standard.md, 05-research-claude-code-adapter-surface.md, 06-research-codex-cli-adapter-surface.md, 07-research-cursor-adapter-surface.md
Blocks: 13-define-attention-request-and-action-routing-semantics.md, 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Prototype attention, completion, plan, and question workflows

## Question

How should approvals, denials, free-text and multiple-choice questions, multi-question wizards, plan review and revision, completion recaps, errors, context warnings, and dismissal behave and look from arrival through acknowledged resolution?

## Comments

### Prototype ready for live review — 2026-07-18

The reviewed throwaway attention-workflow prototype compared three structurally
different models on one URL: **A — Focused card**,
**B — Triage workspace**, and **C — Guided sheet**. Each model exercises
approval and denial, stale resolution, structured and free-text multi-question
input, plan approval/revision boundaries, completion recap, failure, context
warning, acknowledgement, queue navigation, and explicit Jump Back fallback.

The capability picker demonstrates the material Claude Code, Codex direct and
observed CLI, Cursor ACP, and Cursor Hook differences from the adapter research.
Unsupported actions never imply that a response was applied. A live state
inspector exposes request ownership, routing, drafts, resolution, and the last
presentation action after each interaction.

Automated browser review covered all three variants at 1440×1000 and the guided
sheet at 900×780, with no console errors or horizontal overflow. It verified
Host fallback, stale-request retirement, multi-question submission, URL-stable
variant switching, plan revision, non-archival completion acknowledgement, and
truthful failure acknowledgement. The ticket remains open and unresolved until
the required live human review selects or combines a direction.

### Resolution — 2026-07-18

Live human review selected **C — Guided sheet**. The durable
[attention, completion, plan, and question workflow design](../assets/attention-completion-workflow-design.md)
uses one compact top-edge sheet with an explicit Arrived → Review → Respond →
Acknowledged progression, a preserved compact queue, and capability-gated
actions or honest Jump Back fallback. It specifies approval/denial, structured
and free-text multi-question input, plan review/revision boundaries, completion
recap, failure, context warning, stale resolution, acknowledgement, collapse,
accessibility, and motion behavior. The reviewed throwaway prototype was
deleted after its answer was absorbed.
