# Agent Island

Agent Island is a local-first native macOS companion that lets one person monitor and interact with concurrent AI coding work without leaving the application they are currently using.

## Language

**Agent Island**:
The personal macOS application being specified in this repository.
_Avoid_: Vibe Island clone, orchestrator, agent

**Agent Product**:
An external AI coding tool that owns conversations, their native identifiers, and coding work, such as Claude Code, Codex CLI, or Cursor.
_Avoid_: Provider, CLI, model, agent

**Agent Adapter**:
The Product-specific integration boundary through which Agent Island observes and controls one Agent Product without taking ownership of its conversations.
_Avoid_: Plugin, hook, connector

**Integration Installation**:
One explicit, reversible configuration of one Agent Adapter integration mode at one selected Product or Host scope. It is neither the Agent Product nor an Agent Session.
_Avoid_: Setup, connection

**Ownership Manifest**:
Agent Island's local evidence record for the exact configuration entry and application-owned artifact created for one Integration Installation. It does not confer ownership of a whole configuration file, directory, or similarly configured external entry.
_Avoid_: Install record, config ownership

**Agent Session**:
One independently addressable conversation or task execution owned by an Agent Product, including its turns and any child work.
_Avoid_: Process, terminal, tab, thread

**Turn**:
One ordered exchange or execution step within an Agent Session, as identified by its owning Agent Product. A rewind changes which turns are current; it does not create a new Agent Session.
_Avoid_: Session, prompt, message

**Subagent Run**:
A child execution created within and owned by an Agent Session.
_Avoid_: Session, background process

**Attention Request**:
A durable request from an Agent Session that requires a person to approve, deny, answer, review, or otherwise respond.
_Avoid_: Alert, popup, permission boolean

**Notification Policy**:
The local, user-configured rules that decide how one validated Agent Session event is presented without changing its Product-owned state.
_Avoid_: Alert settings, notification engine

**Quiet Scene**:
A locally detected privacy or interruption context in which Agent Island suppresses automatic alerts while retaining the underlying local state.
_Avoid_: Do Not Disturb, pause

**Action Attempt**:
One durable local record of a person's explicit intent to send one typed action to an Agent Product. Its outcome records dispatch evidence; it does not itself prove that the Product applied the action.
_Avoid_: Click, response, command

**Action Lease**:
Short-lived, single-use authority from a live Agent Product surface to route one exact typed action to its owning Attention Request or Agent Session/Turn. It is not a permission grant and cannot survive restart, reconnection, expiry, or a source-state change.
_Avoid_: Permission, token, session

**Normalized Event Fact**:
An immutable, validated local record of one source-proven Agent Product, Host, or integration observation with its owner identity, provenance, ordering evidence, and classification. It is evidence from which Agent Island derives state, not a mutable status or raw Product event archive.
_Avoid_: Event, status update, log entry

**Negotiation Snapshot**:
The immutable local record of one Agent Adapter or Host contract/version/capability negotiation and the evidence that supports it. It is provenance for later facts and actions, not a claim that a capability remains live.
_Avoid_: Connection state, feature flag, capability cache

**Session History**:
The protected local record of an Agent Session's retained facts and authorized received content after it no longer occupies the compact working set. It is not Agent Product-owned transcript storage.
_Avoid_: Transcript archive, deleted session

**Archive**:
A compact Session History presentation and storage tier for a safely inactive Agent Session. It is not a Product lifecycle state, deletion, or proof that monitoring stopped.
_Avoid_: Completed state, purge

**Project**:
A logical coding-work grouping, usually a repository lineage, which may contain more than one Worktree. It is descriptive context for an Agent Session, not its owner or primary identity.
_Avoid_: Folder, repository, workspace

**Worktree**:
One exact local checkout or working directory within a Project, with its own filesystem and version-control state.
_Avoid_: Project, branch, folder

**Model**:
The Agent Product-selected AI model or model configuration used for a Turn. It is attributed context, not an Agent Session's identity.
_Avoid_: Agent Product, provider, session type

**Host**:
The local terminal, IDE, or agent workspace that presents an Agent Session, such as iTerm2, Warp, Cursor, or Orca.
_Avoid_: Agent, provider

**Host Context**:
The Host-native visible surface for an Agent Session, identified by documented
Host evidence and a live incarnation rather than by presentation metadata.
_Avoid_: Window title, terminal

**Island Overlay**:
The non-modal, top-edge Agent Island presentation surface that communicates and
accepts local interaction without normally activating the application or a Host.
_Avoid_: Notification toast, main window, notch

**Jump Back**:
Navigation from Agent Island to the most precise valid Host Context for an Agent Session, with an explicit fallback when exact targeting is unavailable.
_Avoid_: Open app, focus terminal

**Capability**:
A behavior that a particular Agent Adapter or Host can demonstrably support, such as questions, plan review, or exact pane navigation.
_Avoid_: Feature flag, assumption

**Interaction Content**:
Sensitive payload originating from an Agent Session or Agent Product, including prompts, responses, approval context, commands, code, diffs, and project or file references.
_Avoid_: Metadata, log data, telemetry

**Operational Metadata**:
Non-content facts required to identify, present, reconcile, or diagnose a local Agent Session, Agent Adapter, or Host.
_Avoid_: Session content, harmless data

**Diagnostic Bundle**:
A person-initiated, redacted local export that explains Agent Island's integration and capability behavior without including Interaction Content or credentials.
_Avoid_: Support upload, crash dump

**Service Egress**:
A future, consent-gated, outbound copy of classified local data for one stated purpose; it is never the canonical source of Agent Island state.
_Avoid_: Sync, cloud backend

**Usage Snapshot**:
Display-only provider limit, usage, and reset information supplied through an available Agent Adapter capability.
_Avoid_: Billing state, quota estimate

**Parity Baseline**:
The in-scope behavior and visual quality evidenced by Vibe Island v1.0.42 and its public materials as observed on July 18, 2026, excluding the boundaries recorded in the Wayfinder map.
_Avoid_: Latest Vibe Island, moving target
