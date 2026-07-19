# Local-first privacy, security, and future-service boundary

**Decision date:** 2026-07-18  
**Applies to:** the personal, single-user Agent Island baseline on macOS 14+ Apple Silicon.  
**Does not implement:** accounts, remote access, cloud sync, hosted storage, telemetry, analytics, or any other network service.

## Decision

Agent Island is a local-only observer and controller for supported local Agent Products. Interaction Content is sensitive by default. It may be collected, shown, and retained only when a supported Agent Adapter requires it for an in-scope local experience; it never leaves the Mac in this baseline. The local store remains the sole canonical state even if a future hosted service is introduced.

The application asks for the least macOS access needed for a demonstrated Capability, scopes access to the named Agent Product or Host, and fails closed when identity, authority, or data classification is unknown. It does not use privileged helpers, process injection, terminal scraping, simulated input to ambiguous targets, screen capture, clipboard monitoring, keylogging, or a remote listener.

## Data policy

Every field crossing an Agent Adapter boundary is classified at capture. An unknown field is Interaction Content, never safe metadata.

| Class | Examples | Observe and show | Local persistence | Export and redaction |
| --- | --- | --- | --- | --- |
| Operational Metadata | opaque local IDs; Agent Product/Agent Adapter/Host identity; state; timestamps; capability, health, and reconciliation status | Only through a supported Adapter or Host interface; show the minimum useful label and status. | Allowed in the application-private store. | User-data export may include it. Diagnostics remove or pseudonymise identifying paths and IDs not needed to troubleshoot. |
| Interaction Content | prompts, responses, plan text, questions, approval context, commands, tool arguments/results, file names and paths, diffs, code, model labels, project/worktree labels, and Subagent Run descriptions | Only when supplied by the owning Adapter and needed to present or route the owning Agent Session. | Allowed only in protected application-private storage; retention and archive rules remain for the persistence decision. | Excluded from diagnostics, telemetry, and automatic export. A user-data export may include selected content only after an explicit scope preview and confirmation. |
| Credentials and secret material | passwords, API keys, access/refresh tokens, private keys, cookies, authorization headers, environment secrets, and keychain references | Never intentionally observe, display, or log. An Adapter must minimize or redact these before emitting an event. | Never persist in session data, settings, diagnostics, installation manifests, or exports. A credential needed by a future service belongs in the macOS Keychain. | Always exclude. Pattern-based secret scrubbing is defense in depth, not permission to collect secrets. |
| Local configuration and installation state | application-owned hook entries, integration intent, health, owned paths, version/capability facts, and before/after validation facts | Only the exact documented configuration surface needed by a selected integration. Do not treat unrelated contents as input. | Persist an ownership manifest and minimum reconciliation facts; protect selected paths and settings as sensitive metadata. | Diagnostics contain only redacted ownership and failure facts, never whole configuration files or unrelated values. |
| Diagnostics | version/capability results, permission state, classified accept/ignore/deduplicate/downgrade reason, error category, and a locally generated correlation ID | Show locally so a person can explain an integration or action outcome. | Allowed locally with the same application-private protections. | Create only on explicit user action. Exclude Interaction Content, credentials, raw command lines, source text, full paths, titles, prompts, and raw external identifiers. |

A file path or command can be needed to make a local approval decision, but is not safe diagnostic or service data. A summary made from Interaction Content remains Interaction Content; changing its shape does not declassify it.

### Presentation and redaction

- The collapsed island and ordinary macOS notifications expose status and a bounded, user-configurable label only. They must not disclose prompts, commands, diff text, response text, or secret-looking values.
- Expanded Agent Session and Attention Request views may show the minimum Interaction Content needed for the exact item, retaining session/turn/request ownership. One session's content never appears in another's view.
- Focus mode, lock/asleep state, and screen recording/sharing suppress content revelation and sound/auto-reveal under the later notification policy; they do not broaden collection or export.
- Redaction is structural first: exporters and future-service ports receive typed allowlisted fields, not a raw record followed only by regular expressions. Unknown, unclassified, or failed-to-redact fields are omitted. Secret-pattern scanning is an additional safeguard before export.

## Storage and export security

- All baseline state stays in application-private local storage. Sensitive persisted data is encrypted at rest with a per-installation key held in the user's macOS Keychain; filesystem permissions and FileVault are complementary protections, not substitutes for this boundary.
- The baseline creates no account, network identity, cloud replica, remote backup, analytics event, automatic external diagnostic upload, or network listener. Adapter-local IPC, if later required, must be authenticated, least-privilege, and local-only, such as a user-owned Unix-domain socket.
- Export is an explicit foreground action with a preview of destination, data classes, session/date scope, and whether Interaction Content is included. It writes only to a user-selected location and is never auto-opened, uploaded, or retained as a second hidden copy.
- A **user-data export** is separate from a **Diagnostic Bundle**. A Diagnostic Bundle is redacted by construction and cannot gain content via a convenience checkbox. A user-data export including Interaction Content requires separate confirmation.
- If the keychain item, store, or classification metadata is missing or corrupt, omit the affected content and surface a recoverable local error. Never substitute guessed data or an unredacted raw payload.

## macOS permission and trust boundary

| Boundary | Baseline rule |
| --- | --- |
| Agent Adapter input | Trust only documented, version-checked local interfaces or application-owned integration entries. Validate source identity, schema, size, session ownership, and Capability before accepting an event or action. Do not use arbitrary process output, terminal scrollback, process memory, clipboard, or files as data sources. |
| Files and folders | Read only application-private storage plus paths expressly selected by the person or required by the supported Adapter's documented integration. Use scoped user grants/bookmarks where applicable. Do not request Full Disk Access or scan home directories to discover content. Writes are atomic, preserve unrelated material, and touch only an application-owned entry in the installation manifest. |
| Automation and Apple Events | Request Automation permission only when the chosen Host needs it for a demonstrated Jump Back or supported Host action. Address only the intended Host and stable Host Context; deny ambiguous targets and report the lower available Capability. |
| Accessibility | Request Accessibility only for specific Host discovery/activation behavior lacking a narrower supported API. It is authority to inspect or activate accessibility elements, not to read arbitrary application content or synthesize broad input. Revocation immediately removes dependent Capabilities. |
| Notifications | Request notification permission only for enabled local notification behavior. Payloads follow the presentation/redaction rules. |
| Screen Recording, Input Monitoring, camera, microphone, contacts, calendar, location | Not baseline requirements and must not be requested. The screen-sharing/recording quiet scene is a suppression signal, not permission to capture a screen. |
| Privilege and network | No administrator authorization, root helper, code injection, or remote command channel. No external network access. A local integration must not widen this to a LAN or Internet listener. |

Permission education names the exact Capability, affected Agent Product or Host, data category, and fallback before the system prompt. Declining or revoking a permission never triggers a weaker undisclosed collection method.

## Stable future-service seams

These are contracts to preserve later; no endpoint, account, key, queue, or background retry loop belongs in the baseline.

1. **Local canonical store.** The session engine reads and writes a local canonical model through a storage port. It works when all service ports are absent. Future sync is a versioned replica/export consumer, never authority for live Agent Session state or local action routing.
2. **Classified projection.** Agent Adapters emit typed, schema-versioned records with classification and ownership. Projection policy creates separate local-display, user-data-export, diagnostic, hosted-persistence, and telemetry views. No consumer receives an unfiltered Adapter record by default.
3. **Consent and purpose gate.** Every future outbound operation carries a user-visible destination, purpose (`hosted-persistence`, `telemetry`, or `support-diagnostic`), selected classes/scope, consent version, and time. Consent is opt-in, purpose-granular, revocable, and checked at dispatch. A future service must define deletion and retention explicitly.
4. **Outbound-only service ports.** A hosted-persistence port accepts only a classified, versioned, authorized snapshot/change set. A telemetry port accepts only an allowlisted aggregate/redacted measurement with no Interaction Content, credentials, full local identifiers, paths, command lines, or raw diagnostics. Neither port can initiate Agent Product commands, change permission modes, or alter presentation.
5. **Portable local identity.** The core uses opaque local identifiers and maps Agent Product/Host identifiers inside the local boundary. Future services receive service-specific pseudonyms only when enabled, never reusable raw local IDs.
6. **Auditable local outbox.** A future outbound copy is inspectable before dispatch, records purpose/result without its sensitive payload, and supports per-purpose disable/delete. Its failure cannot block local monitoring, persistence, Attention Request handling, or Jump Back.

## Acceptance scenarios for downstream work

- A permission request containing a command and private file path can be shown in its owning Attention Request and retained only under the later local policy; it cannot appear in a Diagnostic Bundle or telemetry.
- An Adapter emits an unknown field after an upstream update. Treat it as Interaction Content and exclude it from diagnostics/export/service projections until classified.
- Accessibility is denied. Exact Jump Back is unavailable or downgraded; Agent Island does not read terminal text or send keystrokes as a workaround.
- A data-export preview makes clear that it is a local file, whether content is selected, and where it will be written. A Diagnostic Bundle generated afterward contains neither the content nor the export path.
- When future telemetry is disabled or consent is revoked, the app makes no network request and local Agent Session behavior continues unchanged.

## Deferred decisions

This boundary does not choose a database, encrypted-file format, key rotation/recovery scheme, retention periods, archive UI, concrete Adapter schemas, or service protocol. The persistence, integration, architecture, data-contract, and quality decisions must preserve this policy.
