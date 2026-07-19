# Local canonical state and consent-gated egress

Agent Island keeps its canonical state and all baseline data on the local Mac, with Interaction Content classified as sensitive by default. This is a hard boundary: a future hosted-persistence or telemetry service can receive only a classified, purpose-limited, explicitly consented copy through an outbound port; it can neither become the live source of truth nor initiate Agent Product actions. The alternative—a cloud-shaped core or generic event export—would couple local reliability and privacy to services deliberately out of scope and would make later data minimisation difficult to recover.

## Consequences

- The local storage model must work while every service port is absent or failing.
- Agent Adapters and exporters must classify and project data before it reaches diagnostics or any future service boundary.
- Future service work must define its own consent, retention, deletion, and authentication behavior without weakening this local policy.
