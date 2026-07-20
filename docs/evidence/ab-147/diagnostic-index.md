# AB-147 diagnostic and capture index

AB-147 links only redacted diagnostic correlation. Do not place Interaction
Content, credentials, raw prompts/responses, commands, paths, opaque locators,
or external configuration bytes in this index. A correlation proves that a
capture can be found; it does not prove Product truth by itself.

## Existing evidence provenance

| Ref | Existing evidence | Permitted AB-147 use | Boundary |
| --- | --- | --- | --- |
| D-01 | `src/Evidence/AB-146-CANONICAL-CAPTURE.md` | 30-session headless deterministic workload/timing/resource provenance | Not native visual, AX, VoiceOver, display, or full-app evidence. |
| D-02 | `src/Fixtures/CodexCLIAdapter/reorder-gap-duplicates.json` | Gap/reorder/duplicate safety | No live Codex CLI claim. |
| D-03 | `src/Fixtures/CursorHooksAdapter/negative-cases.json` | Cursor health/installation negative cases | No current Cursor version/health capture. |
| D-04 | `src/Fixtures/CodexAppServerAdapter/initialize-incompatible.json` | Negotiation mismatch/capability degradation | No current live app-server compatibility proof. |
| D-05 | `src/Evidence/AB-146-REPORT-TEMPLATE.md` | Required native visual/AX/display matrix | All listed native cells are still unverified. |
| D-06 | `src/Evidence/AB-135-REPORT-TEMPLATE.md` | Claude action outcome/lease boundary | Accessible/native action evidence remains pending. |
| D-07 | `docs/evidence/AB-140-iterm2-host-navigation.md` | iTerm2 live-locator rules and manual requirements | No live API/VoiceOver run. |
| D-08 | `src/Fixtures/CursorHostAdapter/duplicate-name-pid.json` | Cursor Host collision refusal | No native cursor activation capture. |
| D-09 | `docs/evidence/AB-142-warp-host-navigation.md` | Warp lower-level outcome/AX election rules | Raw AgentIslandApp targeting returned `permission_denied` twice; do not retry as evidence. |
| D-10 | `docs/evidence/AB-143-orca-host-navigation.md` | Read-only Orca contract/probe and exact-tab ceiling | No live terminal switch/assistive-tech capture. |
| D-11 | `src/Tests/AgentIslandAppTests/NotificationPresentationCoordinatorTests.swift` | Quiet/filter/no-repeat deterministic policy seam | No system notification visual/accessibility capture. |
| D-12 | `src/Tests/ApplicationRuntimeTests/AB145RecoveryTests.swift` | Wake invalidates authority/Host evidence without Product facts | No full-app wake/display run. |
| D-13 | `src/Tests/AB146WorkloadTests/AB146WorkloadTests.swift` | History safe-inactive and overflow safety seam | No rendered History observation. |
| D-14 | `src/Tests/AgentIslandAppTests/UsagePresentationTests.swift` | Sourced-or-unavailable Usage Snapshot seam | No provider data or absence visual capture. |

## Future capture naming and redaction protocol

Use a capture correlation such as
`ab147-YYYYMMDD-<profile>-<cell>-<positive|negative>`. Place the redacted
artifact location and only these metadata fields into the completed human
review form:

- Product, Adapter mode, Host profile, Product/Host version, capability, and
  negotiated-contract or probe timestamp;
- test cell and positive/negative outcome, achieved navigation level or honest
  fallback, and reviewer/date/hardware;
- hashes or relative artifact names when useful, never raw private payload.

Before attachment/export, review the artifact using the Diagnostic Bundle
boundary: retain operational metadata needed to explain integration/capability
behavior, remove Interaction Content and credentials, and do not widen local
data collection. The capture owner should retain raw materials locally only
under the applicable product/repository policy.

## Correlation acceptance

A completed AB-147 cell needs all of: capture link, matching row ID, profile
and version/capability, positive or negative expectation, observed outcome,
fallback where unavailable, and a redaction statement. Missing correlation is
an incomplete capture, not a failure that permits fallback to a fixture pass.
