# AB-132 — General and Display settings evidence

This template records deterministic local contract evidence. Native AppKit
rendering, display disconnect/reconnect, accessibility, and launch-at-login
observations remain unchecked until captured on the target machine.

## Automated contract traces

| Scenario | Test/trace | Result | Evidence or notes |
| --- | --- | --- | --- |
| General defaults and restart round-trip | `AtlasSettingsRepositoryTests` | ☐ | |
| Display controls and restart round-trip | `AB132GeneralDisplaySettingsTests.testDisplayDefaultsRoundTripAndRestart` | ☐ | |
| Selected stable ID through Atlas model/repository | `AB132GeneralDisplaySettingsTests.testSelectedDisplayPersistsThroughAtlasModelAndRepository` | ☐ | |
| Exact owning Host foreground only | `SessionDomainTests/PresentationSettingsTests.testExactForegroundRequiresCurrentOwningLiveContext` | ☐ | |
| Disabled/enabled Jump Back outcome | `SessionDomainTests/PresentationSettingsTests.testClickPolicyDisabledNeverNavigatesAndEnabledReportsAchievedLevel` | ☐ | |
| Display switch/disconnect/reconnect | `AB132GeneralDisplaySettingsTests.testSelectionSwitchEndsEngagementAndReconnectsCollapsedAfterRevalidation` | ☐ | |
| Nil/unavailable explicit selection | `AB132GeneralDisplaySettingsTests.testNilOrUnavailableExplicitSelectionNeverMigratesToAnotherDisplay` | ☐ | |
| Pointer-exit policy and guards | `AB132GeneralDisplaySettingsTests.testPointerExitPolicyPreservesInteractionAndKeyboardGuards` | ☐ | |
| Built-in notch and external pill geometry | `AB132GeneralDisplaySettingsTests.testDisplayValidationAndGeometryClampForBuiltInAndExternalForms` | ☐ | |
| Preview side-effect isolation/unavailable display | `AB132GeneralDisplaySettingsTests.testPreviewDisplayAndGeneralChangesOnlyClosedLocalTrace` | ☐ | |
| Live preview availability bridge | `AB132GeneralDisplaySettingsTests.testLiveAvailabilityBridgeUpdatesPreviewWithoutPersistingDisplaySettings` | ☐ | |
| Preview starts unavailable without selection | `AB132GeneralDisplaySettingsTests.testPreviewStartsUnavailableUntilAnExplicitDisplayIsSelected` | ☐ | |
| Completion height/content scale and metadata | `AB132GeneralDisplaySettingsTests.testCompletionHeightAndContentScaleAffectOverlayGeometryAndPreviewMetrics`; `testOptionalMetadataRemainsAbsentInCurrentProjection` | ☐ | |
| No custom rule without documented grammar | `SessionDomainTests/PresentationSettingsTests.testCustomRuleRequiresDocumentedGrammarAndNeverAcceptsBareURL` | ☐ | |

## Architecture and safety review

- [ ] General and Display values persist only through the namespaced Atlas
  settings repository; no canonical Session/Product state is changed.
- [ ] The Overlay remains one AppKit-owned panel on one selected display.
- [ ] A selection-unavailable transition removes visible, hit-testing, and
  accessibility regions before a replacement can be rendered.
- [ ] Preview trace contains only `previewStateChanged`; no Alert Candidate,
  sound, notification, Product action, Installation mutation, or live Overlay
  movement is observable.
- [ ] Exact foreground suppression is sourced from a current owning Host
  Context; title/path/nearby-tab/app-only/historical evidence is rejected.
- [ ] Fullscreen/no-active-session suppression leaves Settings and menu access
  available and does not cross Spaces or activate a Host.

## Native capture rows

| Capture | Observation |
| --- | --- |
| Built-in display with notch | ☐ content and hit/AX regions remain outside protected gap |
| External display | ☐ single honest floating pill; no hardware-notch claim |
| Disconnect/reconnect | ☐ withdrawn/unavailable, then collapsed only after revalidation |
| Fullscreen/no active Session | ☐ local presentation withdrawn; Settings/menu remain reachable |
| Accessibility adaptations | ☐ readable with contrast, text, transparency, and motion adaptations |
| Launch-at-login capability | ☐ OS registration result is reported honestly; unavailable is not claimed enabled |
