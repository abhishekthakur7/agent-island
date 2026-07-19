# Stable identity at the Product boundary

Agent Island identifies an Agent Session, Turn, Subagent Run, and Attention Request by the stable native identifier supplied by its owning Agent Product, scoped by the Agent Adapter's Product namespace. Local records, labels, models, paths, and Host Contexts are supporting evidence only and must not merge distinct Product-owned work. This makes restart and reconnection safe, keeps rewinds within one Agent Session, and favors an explicit unresolved or replacement state over a plausible but unsafe match.

## Consequences

An Agent Adapter must preserve source identity and report uncertainty rather than synthesize continuity from mutable presentation data. A recreated Host Context or Worktree can be rebound only with strong source evidence; otherwise it remains a new context associated with the same Agent Session or an unresolved association.
