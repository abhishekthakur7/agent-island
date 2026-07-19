# Settings information architecture — throwaway prototype

> PROTOTYPE ONLY — this is a dependency-free review artifact, not production
> UI and it has no connection to Agent Island data, permissions, files, or
> integration mutations.

Question answered: Atlas is the approved way to organize onboarding, Settings,
integration health, diagnostics, and maintenance for Agent Island.

The repository has no application scaffold, so this new-page prototype uses a
single static file and Python's built-in server. Its state is illustrative and
in-memory only.

## Run

From the repository root:

```sh
python3 -m http.server 4184 --directory .scratch/agent-session-tracker/assets/settings-information-architecture-prototype
```

Open <http://localhost:4184/>.

## Approved direction

**Atlas (Option A)** is the human-approved direction: a conventional Settings
window with a persistent sidebar and contextual, resumable onboarding. Flight
and Workbench are rejected as final structures and are no longer exposed by the
runnable reference.

## Apple Design review pass

Atlas uses a macOS-native visual and interaction foundation:

- restrained system typography with optical sizing and size-specific tracking;
- a heavier translucent sidebar/titlebar material and lighter grouped content;
- familiar macOS traffic-light chrome, inset preference groups, and system-blue
  primary actions;
- immediate pointer-down feedback and interruptible, critically damped-feeling
  materialization without decorative bounce;
- explicit focus rings and independent reduced-motion, reduced-transparency,
  and increased-contrast adaptations;
- semantic health colors, visible-only controls, and responsive compact layout.

The active variant switcher has been removed. This remains a non-production,
in-memory reference and no control connects to real mutations.

The durable answer is recorded in
[Settings, onboarding, and diagnostics information architecture](../settings-onboarding-diagnostics-information-architecture.md).
