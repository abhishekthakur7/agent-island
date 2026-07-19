# AB-118 evidence report

Copy this file per capture session. Fill in the machine/date fields and every
row below. Automated evidence is captured; the human-observed rows are not.

## Environment

- macOS version:
- Hardware:
- Xcode version (full Xcode required for the interactive/XCTest rows):
- Date/time:
- Operator:

## Automated evidence (captured, reproducible)

Real run captured in this repository at
[`runs/self-check-20260720.log`](runs/self-check-20260720.log) via
`swift run AgentIslandApp --self-check` on Command Line Tools only (no full
Xcode, no XCTest — see `../README.md`):

```text
[PASS] positiveObservation
    - negotiate: compatible(snapshot: <uuid>)
    - sessionDeclared: committed(ledgerRevision: 1)
    - activity.started: committed(ledgerRevision: 2)
    - activity.waiting: committed(ledgerRevision: 3)
[PASS] duplicateStableDelivery
    - firstDelivery: committed(ledgerRevision: 1)
    - duplicateDelivery: duplicateIgnored(ledgerRevision: 1)
[PASS] invalidOwnership
    - deliverMissingOwnerIdentity: rejected(missingOrAmbiguousOwnerIdentity)
[PASS] incompatibleContract
    - negotiate.incompatibleMajor: incompatibleContractMajor
    - deliverAfterIncompatibleNegotiation: rejected(unknownNegotiationSnapshot)
[PASS] malformedShape
    - deliverMalformedActivity: rejected(malformedShape)
[PASS] oversizedPayload
    - deliverOversizedPayload: rejected(payloadTooLarge)
[PASS] transportLoss
    - activity.started: committed(ledgerRevision: 1)
    - observationBoundary.transportLost: committed(ledgerRevision: 2)
[PASS] transportLoss.projectionInvariant execution=unresolved observation=unavailable
[PASS] duplicateStableDelivery.singleCardInvariant sessions=1
SELF-CHECK PASSED
```

This satisfies the ticket's positive trace and every named negative capture
(duplicate stable delivery, invalid/ambiguous ownership, incompatible
contract, transport loss) at the `ApplicationRuntime`/`AdapterIntakePort`
boundary, plus the two invariants a scenario-level PASS alone can't prove:
transport loss never reaches a terminal execution state, and duplicate
delivery never produces a second card.

Re-run and attach a fresh log per capture session:

```sh
cd src
swift run AgentIslandApp --self-check | tee "Evidence/runs/self-check-$(date +%Y%m%d-%H%M%S).log"
```

## Required human-observed evidence (not yet captured)

| Row | Expected | Observed | Pass/Fail |
| --- | --- | --- | --- |
| `swift run AgentIslandApp` opens an `NSWindow` (not a SwiftUI `Scene`) hosting SwiftUI content via `NSHostingView` | AppKit-first shell confirmed by reading `AppDelegate.swift` and watching the window appear | | |
| Positive-observation button renders one Agent Session card with title, product namespace, host label, execution/observation badges | Card appears after "Positive observation" is clicked; identity (`productNamespace`/`nativeSessionID`) always visible, `displayTitle`/`hostLabel` shown only when sourced | | |
| Duplicate-delivery button does not add a second card | Card count stays at 1 after "Duplicate stable delivery" | | |
| Transport-loss button never flips a card to a terminal (`terminalCompleted`/`terminalFailed`/`terminalStopped`) badge | Card's execution badge shows `unresolved`, observation shows `unavailable` | | |
| Architecture-boundary review: `Package.swift` dependency edges match the table in `../README.md` | `AdapterFixtureKit` has no `SessionStore` dependency; `PresentationRuntime` has no `SessionStore`/`AdapterPort` dependency | | |
| Local privacy check: no network egress during any scenario, no Interaction Content in diagnostics | Capture via Little Snitch/`nettop`/Activity Monitor during a full scenario pass; inspect `SessionStore.diagnostics` contents | | |

## Disposition

- [ ] All automated scenarios PASS (see log above).
- [ ] All human-observed rows PASS.
- [ ] No Interaction Content, credentials, raw identifiers, or payloads observed in diagnostics or presentation.
- [ ] No network egress observed.

Sign-off:
