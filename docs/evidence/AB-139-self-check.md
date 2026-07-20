# AB-139 self-check

Run from `src/`:

```sh
swift run AB139SelfCheck
```

The deterministic ACP fixture proves a version/authenticated handshake, a
source-created native session ID, protected-store registration before load,
one persisted Guided permission Action Attempt, and a protected reopen where
the exact ID remains loadable while an unrecorded Cursor IDE-like ID remains
refused. The local JSON-RPC handoff is retained as `indeterminate`, not
accepted/applied, so it cannot replay on reopen. `Fixtures/CursorACPAdapter`
retains the broader source/negative scenarios for XCTest on a full Xcode
installation. This is not live Cursor verification.
