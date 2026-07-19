# AB-118 evidence capture

`Scripts/self-check.sh` produces the automated portion of the required
evidence: a positive fixture trace and every negative capture named in the
ticket, run against the real `ApplicationRuntime`/`SessionStore` pair.

```sh
cd src
Scripts/self-check.sh > Evidence/runs/self-check-$(date +%Y%m%d-%H%M%S).log
```

That automated trace does not replace the human-observed rows in
[AB-118-REPORT-TEMPLATE.md](AB-118-REPORT-TEMPLATE.md): visible native
rendering of the card, the AppKit shell/SwiftUI hosted-content boundary read
directly from `Package.swift`, and a local privacy check (no network egress,
no Interaction Content in diagnostics) observed on real hardware. Until
those rows are captured, they remain unverified — the same standard already
applied to the AB-116/AB-117 spikes.
