# AB-146 canonical automated capture

The canonical supported-hardware headless capture is
`AB-146-run-20260720-224609` (Apple Silicon `Mac15,6`, macOS `27.0`).

- Local event to revisioned presentation: `<250 ms` (raw result retained).
- Confirmed local action to one Adapter handoff: `<150 ms` (raw result retained).
- Headless warm/cold starts: `565.48 ms` / `143.03 ms`.
- Five workload samples: maximum RSS `12,864 KB`, CPU `101.8%`, handles `10`.
- Five idle samples: maximum CPU `1.8%`; no retained task/timer or audio output.
- Established headless limits, calculated by the fixture’s documented 1.5×
  rule: RSS `19 MB`, workload CPU `152.8%`, idle CPU `2.8%`, handles `15`.

`AB-146-NATIVE-BUDGET.txt` is the verifier baseline. The earlier timestamped
run directories are retained diagnostic iterations, not release evidence.
Disk growth, wakeups/energy, and every native/manual matrix cell remain
unverified as documented in `AB-146-REPORT-TEMPLATE.md`.
