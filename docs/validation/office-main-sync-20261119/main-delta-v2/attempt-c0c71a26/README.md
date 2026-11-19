# Rejected second main-delta attempt

Source: `c0c71a26e014cadda7a1f42244e710509dea5f6c`.
Original execution: 09:52:36–09:59:19 CET on 19 November 2026.

**FAIL; zero application or Python executions are added to accepted totals.**
The raw reporter recorded 469 successful application case events, three failed
Studio assertions and zero skips. The three failures use old module/language
selectors in Zotero shortcuts and two Arabic comment-layout cases. Strict
no-write formatting also rejected `suite_workspace.dart`,
`pdf_gallery_smoke_test.dart` and `pdf_showcase_test.dart`. The plan correctly
rejected the whole attempt. Node tests and browser compilation did not start.

The 17 named Python controls and four successful native groups are preserved
without promoting this incomplete attempt to a passing qualification. Source,
runtime, Git head and tracked checkout remained unchanged. The independent audit
recounts exact reporter events and checks these source/runtime envelopes.

[Raw evidence](evidence.tar.xz), [member index](evidence.index.json),
[original execution](execution.json) and [independent audit](independent-audit.json)
retain the rejected result. Fixes are saved and qualified under a later source;
no parser, threshold or assertion is removed to make this attempt pass.
