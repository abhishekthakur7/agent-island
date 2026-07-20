# AB-118 evidence capture

AB-131 uses [AB-131-REPORT-TEMPLATE.md](AB-131-REPORT-TEMPLATE.md) for the
absent-port, consent, classification, one-way delivery, and architecture
review evidence. The template intentionally leaves live/offline observations
unchecked until they are captured on the target machine.

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

AB-132 uses [AB-132-REPORT-TEMPLATE.md](AB-132-REPORT-TEMPLATE.md) for durable
General/Display round trips, exact Host suppression, safe geometry, atomic
display transitions, preview isolation, and honest Jump Back fallback. Native
captures remain explicitly unverified until observed on the target Mac.
