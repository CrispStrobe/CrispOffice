# Executor interruption and remote preservation

This checkpoint preserves the reviewed IME guards, reconnect behavior, note-order correction and their regression fixtures on the remote branch while the local executor is unavailable.

The shared filesystem ran out of capacity during focused verification. Eventually even a read-only process failed before execution with the sandbox helper's `No space left on device` diagnostic. The desktop runtime was also unavailable. Workspace policy rejected the requested outside-sandbox cleanup of a verified generated test cache. No source, runtime, dependency cache or Git data was deleted in these recovery attempts.

Before the interruption, the exact local staged tree was `eff63c16b872b0bf0c45394c543e4666375ec4ad`, based on `243f0175a0d2d3d724677aba15b57927ef43d3a9`. The checkpoint's controller and engine product edits were recovered exactly from the executed replacement operations and published first as `14835c7639314ce734db8518e356fe344221e5b8`. The other guards and regression fixtures were restored through the authenticated GitHub connector using saved source and edit records. Test wrapping and wording have not yet been reconciled against that inaccessible local staged tree.

This is an incremental preservation checkpoint, not a completed final qualification. In particular:

- The note-order regressions failed before the comparator fix; the focused engine run subsequently passed 87 tests.
- The first four controller IME cases passed in a 27-case controller run.
- The Studio composition shortcut/ribbon case passed.
- The UI return-path regression exposed automatic focus restoration clearing composition. The subsequent narrow `attachInput` fix passed strict analysis, but that regression and five additional reconnect cases still require execution.
- The final planned 77-file local gate has not run. Do not attach earlier counts to this checkpoint as an exact-source total.
- Newly captured incoming Mail/review/thesaurus heads must be integrated and their changed locked dependencies resolved before the final run.

The planned final runner and file selection remain in `run_local.py` and `plan.json`. No GitHub Actions, check, workflow-run or status endpoint was queried or awaited.
