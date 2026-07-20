# AB-135 — Claude Code Guided Attention actions

This report distinguishes authored deterministic fixture coverage from a live
Claude Code recording. No manual recording is claimed by this change.

| Requirement / trace | Evidence | Status | Boundary |
| --- | --- | --- | --- |
| Permission allow/deny, exact callback owner and typed capture | `ClaudeActionRoutingTests.testPermissionCallbackIsBoundToOneExactIdentityAndOneDispatch` | authored | One PermissionRequest has session, prompt when supplied, hook, fingerprint, fresh nonce; no tool-use ID or text matching. |
| Exact persistent suggestion + second scope confirmation | `testPersistentSuggestionRequiresExactSecondScopeConfirmationAndEchoesOnlyOffer`, `testPermissionSuggestionModeAllowlistNeverBroadensPolicyAndAskKeepsOneShotDeny` | authored | Only an exact Product offer in documented default/normal mode is returned; deny/ask/managed/policy/bypass/unknown suggestion modes have zero route and zero dispatch. Ask may still deny one source-proven live request. |
| Single/multi structured answers and ExitPlanMode approval | `testQuestionAndPlanRequireCompleteDocumentedInput`, `testStructuredAndPlanActionsWaitForLiveTextCompositionToEnd` | authored | PreToolUse requires tool-use ID and complete choices/updated input; structured and plan mappings reject while caller-provided text composition is active, then may route after it ends. Revisions remain Host-native. |
| Faithful Hook fixtures / mode and unsupported path | `testFactoryUsesToolUseNotTextAndRejectsManagedAndUnsupportedPaths` | authored | Managed/bypass mode and unknown semantics do not route. |
| Double submit, stale and resolved elsewhere | `testPermissionCallbackIsBoundToOneExactIdentityAndOneDispatch`, `testResolvedElsewhereAndAcknowledgementOutcomesNeverClaimLifecycleCompletion` | authored | Callback gate is consumed before dispatch; resolved elsewhere has zero dispatch. |
| Rejected / accepted / applied / superseded / indeterminate acknowledgement model | `ActionAttemptStore`, `ClaudeGuidedActionRouter.recordApplied/recordSuperseded/recordIndeterminate` | authored | A socket reply is indeterminate because the documented Hook protocol exposes no Product acknowledgement. Accepted/applied require later explicit Product evidence; no local lifecycle completion claim. |
| Restart, reconnect, wake, helper loss, deadline/capability retirement | `ActionAttemptStore.invalidate*`, `ClaudeGuidedActionRouter.retireAll` | authored | Live callbacks and leases are volatile; no callback recreation or automatic retry. |
| Live backend installation composition | `ClaudeActionIntegrationLifecycle.activate`, `AppDelegate.activateClaudeActionInstallation` and lifecycle tests | authored backend | The retained composition API starts only after enabled manifest, current action capability, and Keychain credential validation; disable/helper loss/capability change retire it. No setup UI calls it yet. |
| Accessibility and unsupported fallback | Pending dedicated routing UI wiring and tests | pending | The existing Guided workflow is not evidence that callback availability, confirmation, scope consequence, text-composition state, or dispatch outcome is exposed accessibly. |

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
those recordings were performed. The live backend composition API is
implemented, but setup UI wiring and all manual/accessibility recordings
remain pending.
