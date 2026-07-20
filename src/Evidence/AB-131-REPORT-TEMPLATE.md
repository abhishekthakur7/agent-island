# AB-131 — Future Service Egress boundary evidence

This template records evidence for the absent-by-default, one-way Service
Egress seam. It must not be filled with an inferred network result. Capture
only observations made on the target machine; unrun rows remain unverified.

## Automated contract traces

| Scenario | Test/trace | Result | Evidence or notes |
| --- | --- | --- | --- |
| No port attached | `AB131ServiceEgressTests.testAbsentPortIsAFeatureAndLeavesOnlyRedactedLocalEvidence` | ☐ | |
| Failed port, no retry | `AB131ServiceEgressTests.testFailedPortIsOneAttemptWithNoRetryOrFalseDeliveryClaim` | ☐ | |
| Denied/revoked/purpose-isolated consent | `AB131ServiceEgressTests.testDeniedRevokedAndPurposeIsolationAreCheckedAtDispatch` | ☐ | |
| Purpose-specific disable/delete | `AB131ServiceEgressTests.testPurposeSpecificDisableDeletesOnlyThatOutboxScope` | ☐ | |
| Forbidden classification, raw pseudonym, extension, schema | `AB131ServiceEgressTests.testBoundaryRejectsForbiddenClassificationExtensionsSchemaAndRawPseudonym` | ☐ | |
| Successful one-way delivery and identity projection | `AB131ServiceEgressTests.testSuccessfulDeliveryIsOneWayAndPayloadContainsNoRawLocalIdentity` | ☐ | |
| Explicit support diagnostic confirmation | `AB131ServiceEgressTests.testSupportDiagnosticRequiresSeparateExplicitConfirmation` | ☐ | |

## Local baseline / absent-service trace

Run the existing local self-check with no `ServiceEgressPort` implementation
attached. The local commit, recovery, monitoring, Attention Request/action
attempt, and Jump Back rows must be captured independently of this seam.

| Baseline capability | Port state | Local result | Outbound request observed | Evidence |
| --- | --- | --- | --- | --- |
| Fact commit and projection | absent | ☐ | ☐ none | |
| Protected-store reopen/recovery | absent | ☐ | ☐ none | |
| Monitoring / Attention Request | absent | ☐ | ☐ none | |
| Action Attempt outcome remains local | absent | ☐ | ☐ none | |
| Jump Back fallback | absent | ☐ | ☐ none | |
| Failed/revoked dispatch | failed/revoked | ☐ unchanged | ☐ none | |

## Boundary architecture review

Confirm from `Package.swift` and the target sources; do not infer behavior
from a visual result.

- [ ] `ServiceEgressPort` depends on `SessionDomain` only.
- [ ] The protocol has one operation: `dispatch(ServiceEgressChangeSet)`.
- [ ] No Service Egress target imports `SessionStore`, `ProtectedStore`,
      `AdapterPort`, presentation, AppKit, or a network framework.
- [ ] No endpoint, account, retry worker, listener, cloud replica, analytics
      event, or network identity is configured in the baseline.
- [ ] Dispatch is an explicit operation over a local outbox and is not called
      from `SessionStore.intake` or the fact commit path.
- [ ] A port implementation receives no database/key handle or raw Adapter
      record and has no inward command capability.

## Classification / consent review

| Input | Expected result | Observed |
| --- | --- | --- |
| Redacted session state with service pseudonyms | accepted only for hosted persistence | ☐ |
| Aggregate allowlisted metrics | accepted only for telemetry | ☐ |
| Separately confirmed redacted diagnostic | accepted only for support diagnostic | ☐ |
| Interaction Content, credential, raw ID, full path, command line, callback token | rejected | ☐ |
| Raw diagnostic or unknown extension | rejected | ☐ |
| Consent absent, stale, disabled, or revoked at dispatch | local redacted diagnostic; no delivery claim | ☐ |

## Privacy / traffic observation

| Check | Observation |
| --- | --- |
| Normal baseline has no network traffic or listener | ☐ |
| No endpoint/account/remote identity is exposed | ☐ |
| Failed or denied egress leaves local visible state unchanged | ☐ |
| Support diagnostic is explicit and separately redacted; no automatic upload | ☐ |
