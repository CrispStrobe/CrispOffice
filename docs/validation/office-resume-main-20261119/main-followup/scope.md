# Reconciliation with main's subsequent Mail integration

Before PR #192 was merged, remote main advanced from
`b070e228a749e22cc8ce2098029a76ab5fb8eccb` to
`666e9a2ea46f7aeaaa1d01b60aabea0c2fe6f0fd`. This follow-up integrates that exact
additional main head with publication checkpoint
`656ff82366c6d835acee29affb9f77371e4cd383` through a normal merge.

The graph has three best common ancestors: `d00bd397`, `2abf5d26` and `e80beb2e`.
Main contributes 13 commits beyond the publication checkpoint. The separate
fixed capture of 465 references retains its original scope and exact identities;
this additional main head does not silently replace or expand that capture.

## Source changes requiring fresh qualification

- Preserve main's modular native/browser Mail implementation, Word composer,
  bounded UID/raw-octet message loader, shared saved reader, localized actions,
  and reply, forward and mark-read commands.
- Restore independent transport abort, pending-client identity, nonselectable
  INBOX filtering, stale-completion guards and confirmed-submission warnings in
  the modular client. Preserve main's `appendToSent: false` policy.
- Quote the loaded reader body for reply/forward and hold the mailbox operation
  guard during mark-read, including a session identity check on completion.
- Preserve the SMTP pending-command abort repair and its transaction regression.
- Combine main's proofing-range and script-routing safeguards with the existing
  two-slot Word command default and explicit `activeLanguageOnly` option.
- Retain About and ordinary morphology setup coverage. The separate real
  morphology backend test requires its own native library and dictionary bundle
  and is outside this local zero-skip gate.

The only manifest delta supplied by main is the example's path dependency on
the already-present `quds_mail_transport` workspace package. Offline
`dart pub get --enforce-lockfile` succeeds with the retained pinned runtime.
The package configuration stays byte-identical; the workspace dependency graph
records the additional edge. Before/after files and the command log are retained.

## Development records

The [initial Mail reconciliation review](mail-reconciliation.md) maps the prior
71 executions to the modular APIs. Its 114 passing development cases preceded
independent review of quote contents. That review found that the reader's full
presentation includes headers and attachment metadata, so quoting it could copy
Bcc into a forwarded body. The final implementation uses only the existing
bounded, sanitized body projection. Body-specific controls accompany the fresh
gate; the earlier development result does not establish that correction.

The [additive quote review](body-quote-followup.md) records 44 passing current
Studio Mail cases and 16 passing presentation cases. Its
[archive](body-quote-development.tar.xz) retains the initial HTML expectation
failure as well as the corrected result; the correction preserves the existing
blocked-image marker. These remain development controls, separate from the
committed-source qualification.

The [development archive](development.tar.xz) preserves the initial Mail and
non-Mail raw records under their original filenames, as listed in its
[index](development.index.json). The Mail review's adjacent-file references
refer to those original archive members. The separate preparation archive
retains the offline dependency-resolution receipt and before/after files.

## Evidence identities

The exact report published at `656ff823` is preserved as
[`../qualified-22ffa8bd.md`](../qualified-22ffa8bd.md). Its qualification is for
source `22ffa8bdcc11e5e10eb37f2326f832066f609a08`, not this new merge.
Its 1,564 successful Dart/Flutter executions and 21 Python controls contribute
zero cases to the follow-up totals. The original plans, final archive, audits,
rejected attempt and superseded run remain unchanged.

The incoming `../final/plan.json` and `../final/node-plan.json` are historical
planning files carried by main. They are not the plans that produced the
source-22 archive. This directory's committed native/Node plans select the new
combined-source gate. Raw accepted results will be stored under `final/` here.

The earlier publication-continuity checker remains unchanged and only proves
the source-22 documentation publication. A separately bound follow-up checker
applies the same restrictive rules to the newly qualified source: all accepted
inputs must remain exact, all tracked tree differences are inspected, and only
direct inert evidence additions and the parent validation README may change.

No Actions queue, run, job or status is queried, dispatched or awaited. Actual
browser persistence, installed Studio/IME behavior, external Mail accounts,
Zotero/Word/LibreOffice interoperability and independent linguistic review retain
their separate acceptance requirements.
