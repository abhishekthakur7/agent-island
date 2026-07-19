Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Codex
Blocked by: none
Blocks: 15-define-persistence-history-recovery-and-retention.md, 18-define-integration-setup-reconciliation-and-uninstall.md, 19-prototype-onboarding-settings-and-diagnostics-information-architecture.md, 21-research-native-macos-implementation-stacks.md
Resolution: answered

# Define local-first privacy, security, and future-service boundaries

## Question

What data may Agent Island observe, persist, display, export, or redact; what macOS permissions and trust boundaries apply; and which stable seams must exist for future hosted persistence and telemetry without implementing them now?

## Comments

### Resolution — 2026-07-18

The [local-first privacy, security, and future-service boundary](../assets/local-first-privacy-security-boundary.md) defines classified local data handling, presentation/redaction and export rules, protected local storage, least-privilege macOS permission boundaries, and the baseline's no-egress rule. Interaction Content is sensitive by default; credentials are never intentionally collected or exported; diagnostics are redacted by construction; and a person must explicitly preview and confirm any content-bearing local export.

The architecture must retain a local canonical store, classified projections, per-purpose consent gate, outbound-only service ports, local identity mapping, and auditable outbox as future seams. No service, account, endpoint, or telemetry implementation is authorized by those seams. The durable trade-off is also recorded in [ADR 0001](../../../docs/adr/0001-local-canonical-state-and-consent-gated-egress.md).
