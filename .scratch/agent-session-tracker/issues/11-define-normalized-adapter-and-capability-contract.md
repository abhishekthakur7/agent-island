Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Codex
Blocked by: 03-define-domain-language-and-identity-boundaries.md, 05-research-claude-code-adapter-surface.md, 06-research-codex-cli-adapter-surface.md, 07-research-cursor-adapter-surface.md
Blocks: 12-define-canonical-event-and-session-lifecycle.md, 13-define-attention-request-and-action-routing-semantics.md, 14-define-host-context-identity-navigation-and-fallback.md, 18-define-integration-setup-reconciliation-and-uninstall.md, 19-prototype-onboarding-settings-and-diagnostics-information-architecture.md, 22-select-application-architecture-and-component-boundaries.md
Resolution: answered

# Define the normalized adapter and capability contract

## Question

What versioned contract must every Agent Adapter implement for discovery, ingestion, capability negotiation, actions, configuration ownership, health, degradation, and kill switches while preserving Agent Product-specific semantics?

## Comments

### Resolution — 2026-07-18

Every Agent Adapter implements the [Normalized Agent Adapter and Capability
Contract](../assets/normalized-adapter-capability-contract.md): a negotiated,
versioned, fail-closed boundary with independent discovery, event ingestion,
capability, typed-action, configuration-ownership, health/degradation, and
kill-switch surfaces. Capabilities are evidence-backed records scoped to the
configured integration mode and, where necessary, the Agent Session or live
native request; observation never implies action authority, enabled intent
never implies health, and Product-specific semantics are preserved as explicit
variants rather than flattened into generic controls.

The durable architectural rationale is recorded in [ADR
0002](../../../docs/adr/0002-versioned-capability-scoped-adapter-boundary.md).
Exact serialized schemas and canonical lifecycle/action state machines remain
for their downstream tickets.
