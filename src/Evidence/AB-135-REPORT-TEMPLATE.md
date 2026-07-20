# AB-135 — Claude Code Guided Attention actions

This report distinguishes authored deterministic fixture coverage from a live
Claude Code recording. No manual recording is claimed by this change.

| Requirement / trace | Evidence | Status | Boundary |
| --- | --- | --- | --- |
| Permission allow/deny, exact callback owner and typed capture | `ClaudeActionRoutingTests.testPermissionCallbackIsBoundToOneExactIdentityAndOneDispatch` | authored | One PermissionRequest has session, prompt when supplied, hook, fingerprint, fresh nonce; no tool-use ID or text matching. |
| Exact persistent suggestion + second scope confirmation | `testPersistentSuggestionRequiresExactSecondScopeConfirmationAndEchoesOnlyOffer` | authored | Only the Product-offered JSON is returned; missing/mismatched scope has zero dispatch. |
| Single/multi structured answers and ExitPlanMode approval | `testQuestionAndPlanRequireCompleteDocumentedInput` | authored | PreToolUse requires tool-use ID and complete choices/updated input; revisions remain Host-native. |
| Faithful Hook fixtures / mode and unsupported path | `testFactoryUsesToolUseNotTextAndRejectsManagedAndUnsupportedPaths` | authored | Managed/bypass mode and unknown semantics do not route. |
| Double submit, stale and resolved elsewhere | `testPermissionCallbackIsBoundToOneExactIdentityAndOneDispatch`, `testResolvedElsewhereAndAcknowledgementOutcomesNeverClaimLifecycleCompletion` | authored | Callback gate is consumed before dispatch; resolved elsewhere has zero dispatch. |
| Rejected / accepted / applied / superseded / indeterminate acknowledgement model | `ActionAttemptStore`, `ClaudeGuidedActionRouter.recordApplied/recordSuperseded/recordIndeterminate` | authored | Accepted means helper handoff only; no local lifecycle completion claim. |
| Restart, reconnect, wake, helper loss, deadline/capability retirement | `ActionAttemptStore.invalidate*`, `ClaudeGuidedActionRouter.retireAll` | authored | Live callbacks and leases are volatile; no callback recreation or automatic retry. |
| Accessibility and unsupported fallback | `GuidedSheetView`, existing GuidedSheet tests | authored review | Owner, consequence, disabled/fallback state and local-only acknowledgement remain exposed; no unsupported action control is added. |

## C-mode parity matrix

| C-mode | Capability-scoped result |
| --- | --- |
| A1 Allow / A2 Deny | Routed only during one exact live `PermissionRequest`. |
| A3 Structured answers | Routed only through `PreToolUse` `AskUserQuestion` with complete documented selections. |
| A4 Plan approve | Routed only through `PreToolUse` `ExitPlanMode` with valid native input. |
| A5 Persistent suggestion | Exact Product offer plus explicit repeated persistence scope. |
| A6 Revision/cancel/mode cycling | Native Claude Host / Jump Back. |
| A7 Arbitrary prompt/subagent steering | Native Claude Host / Jump Back. |
| P3 Consequential confirmation | Deliberate confirmation; persistent change requires a separate scope confirmation. |

## Manual evidence

Pending: run the reviewed Claude Code build with a real synchronous Hook
callback endpoint, capture VoiceOver/keyboard/reduced-motion/high-contrast
flows, and attach typed native response captures. This change does not claim
those recordings were performed.
