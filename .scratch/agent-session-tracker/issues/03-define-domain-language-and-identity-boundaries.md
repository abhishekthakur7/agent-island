Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Codex
Blocked by: none
Blocks: 11-define-normalized-adapter-and-capability-contract.md, 12-define-canonical-event-and-session-lifecycle.md, 14-define-host-context-identity-navigation-and-fallback.md
Resolution: answered

# Define domain language and identity boundaries

## Question

What canonical concepts and ownership boundaries distinguish Agent Products, Agent Adapters, Agent Sessions, turns, Subagent Runs, Attention Requests, Hosts, Host Contexts, projects, worktrees, and models, including identity across restart, rewind, and reconnection?

## Comments

### Resolution — 2026-07-18

The canonical language is recorded in [the repository glossary](../../../CONTEXT.md)
and the durable identity decision in [ADR 0001](../../../docs/adr/0001-stable-identity-at-product-boundary.md).

**Ownership and identity.** An Agent Product owns its conversations and their
native identifiers. Its Agent Adapter is a Product-specific translation and
control boundary; it never becomes the owner of a conversation. Agent Island's
canonical identity for every Product-owned record is the tuple of the Adapter's
Product namespace and the stable native identifier supplied by that Product.
The local database may assign record IDs, but they are not evidence that two
source records are the same.

| Concept | Owner | Identity boundary |
| --- | --- | --- |
| Agent Product | External coding tool | Its configured Product namespace; a Product is distinct from the Host that happens to present it. |
| Agent Adapter | Agent Island integration | Its adapter kind plus configured Product namespace; it translates source identity without replacing it. |
| Agent Session | Agent Product | Stable native session/conversation/task identifier within that Product namespace. A process, terminal, title, initial prompt, model, path, or Host Context is never session identity. |
| Turn | Agent Session / Agent Product | Stable Product turn identifier within its Agent Session. Its position, text, and status are mutable attributes. |
| Subagent Run | Parent Agent Session / Agent Product | Stable child-run identifier within the parent Agent Session. It remains a child even when the Product exposes a separate execution surface. |
| Attention Request | Agent Session and, where applicable, Turn / Agent Product | Stable source request identifier scoped to its owning session and turn. It must never be matched to a later prompt by text or position. |
| Host | Local application | Installed local application identity; Cursor may be both an Agent Product and a Host, but those are separate roles and identities. |
| Host Context | Host | Host-native durable context identity plus its current incarnation. A visible title, pane ordinal, or screen location is only corroborating data. |
| Project | Source/workspace context | Product- or VCS-evidenced repository lineage when available. It groups work but does not own or identify an Agent Session. |
| Worktree | Project / local filesystem | Exact checkout identity: strong VCS worktree evidence and canonical local root when available. Branch name, repository basename, and path text alone cannot merge worktrees. |
| Model | Agent Product | Product-provided model/configuration identifier attached to a Turn. The displayed session model is a derived current or most-recent attribution. |

**Continuity rules.** Restarting Agent Island, reconnecting an Agent Adapter, or
reopening a Host must recover the same record only when the source's stable
identifier and Product namespace agree. A new connection, process, window,
pane, project path, worktree path, title, model, or timestamp does not replace
that test. Recreated Host Contexts and relocated or recreated Worktrees may be
rebound only when the Host, Product, or version-control evidence explicitly
proves continuity; otherwise retain the old association as historical and show
the new one as distinct or unresolved.

**Rewind rule.** A rewind, compact, retry, or branch selection is a change to
the current Turn lineage inside the same Agent Session. Previously observed
turns and their child records remain historical; a newly emitted turn or child
run must receive a distinct native identity. The adapter must report ambiguous
or missing source identity rather than infer it from copied text, sequence
numbers, or an apparent continuation.

**Safety invariant.** Presentation metadata may enrich, rank, or help a person
recognize work; it must not create identity. When evidence is insufficient,
Agent Island preserves separate records and routes actions only to a proven
owner. This deliberately permits a visible unresolved/replacement state rather
than a false merge or cross-session action.
