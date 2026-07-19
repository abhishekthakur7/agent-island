# AB-121 — Horizon session-monitoring evidence

## Implemented surface

- Original Horizon hierarchy: concise aggregate, promoted focus, one
  chronological Agent Session flow, inline selection, and source-proven
  Subagent Runs nested under their owner Turn.
- Textual state and ownership labels accompany every glyph; color and motion
  are decorative only. Reduced Motion substitutes a cross-fade for the
  expanded-flow transition.
- The 30-session fixture uses the same Adapter intake boundary as a Product
  integration. It retains all sessions, the pending Attention Request, the
  completed session, and the child run while progressively dropping Host then
  title metadata from non-focused rows.
- A Product result is not yet admitted by the operational-metadata contract.
  Completed rows therefore state that no source-proven recap was received;
  they never infer one from local state or acknowledgement.

## Repeatable headless evidence

```sh
cd src
Scripts/self-check.sh
```

Expected Horizon-specific output:

```text
[PASS] horizonWorkingSet
[PASS] horizonWorkingSet.projectionInvariant sessions=30 attention=1 completed=1 children=1
```

The XCTest suite additionally verifies that the presentation projection keeps
an absent Product timestamp absent even when a local receipt timestamp exists.
Run `swift test` on a full-Xcode macOS machine.

## Native visual/AX review checklist

Capture, using the `Horizon 30-session working set` fixture button:

1. Empty/clean collapsed aggregate and expanded detailed aggregate.
2. Focused attention and focused completion states; attention ranks first.
3. A selected row with inline details and its nested Subagent Run.
4. A 30-session view showing compact and dense rows without hiding active or
   attention sessions.
5. VoiceOver, larger text, increased contrast/transparency, and Reduce Motion
   paths. Confirm no horizontal overflow and that selection never changes
   focus ranking or row order.
