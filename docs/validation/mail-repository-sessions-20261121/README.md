# Mail repository sessions — local work record

This continuation advances the desktop-mail roadmap with bounded repository
observers, guarded folder sessions and connected/cached Studio integration.
See the [behavior and next steps](../../roadmaps/mail/repository-sessions.md).
It does not claim complete Outlook, Thunderbird or eM Client parity.

Publication is tracked in [PR #284](https://github.com/CrispStrobe/quds_office_suite/pull/284).
GitHub Actions were neither queried nor awaited.

## Reconciled starting point and remote checkpoints

Initial fork main was `84046975f286407e3c62e5e5352bc16bc89c0d26` (PR #283).
The initial intake found no open PRs and one incoming branch: the three-commit
Word performance continuation through `2cd11ced136a30354169fd0043e002079bcabfa3`.
The working branch starts from that head, retaining its ancestry.

The initial [intake](intake.json) covers 335 refs: 311 ancestors and 24 independently
verified historical equivalents, with zero uncovered refs at that cutoff.
The [initial review](intake-review.md) and [late intake](late-intake-review.md)
record the intermediate reconciliation.

The [final incoming review](final-intake-review.md) fixes the observed branch
snapshot at **21 November 2026, 07:15:44 Europe/Berlin / 06:15:44 UTC**.
Its [exact audit](final-intake-review.json) covers **339 refs: 315 ancestors,
24 reverified historical equivalents and zero uncovered refs**. Original incoming
commit ancestry is retained. Historical divergent branches are covered by exact
full-tree or changed-path equivalence to incorporated replacements.

Work is retained on `work/mail-repository-sessions-20261121` in incremental
remote commits:

| Commit | Retained work |
| --- | --- |
| `c375becb51939dcca5c145bf1bcdb14a4febe041` | Initial intake, mailbox streams, incoming Word failure recovery and local receipts |
| `6ec90c8a3acdc8fb5878f1decef0131e478e6b1d` | Guarded selected-folder sessions, original-provider identity projection and regressions |
| `4d435f81493c88e8fd4fb90a62558a1cc8a7ec22` | Connected/cached Studio workflows, localized counts, recovery, pagination and roadmap |
| `9276a267e83ab903d18b5af38975e15d183b7e7b` | First four-branch union, with all incoming heads retained as merge parents |
| `c0d390653b6a081a3d6df27316cd39b763266e0d` | Accepted 285-case Mail slice, native fixture correction and full local evidence |
| `e162101d6852c6522850b848bb6473676d7fe02a` | Proofing API contract, changelogs and mechanical Zotero strict-lint correction |
| `99e46629eb9743ffb190183ab1b65c4ad259137b` | Accepted 309-case integrated Mail gate, incoming Word/Zotero/proofing evidence and changelogs |
| `721ad2c74a5d81d54c2eaa2af084e82ba5077991` | Final fixed incoming snapshot, resolved documentation overlap and typed benchmark forwarding |
| `f63ba0dc85f5ed419fb184fd166971e981d997f6` | Concurrent main publication reconciled without changing qualified source |

The final evidence commit and merge are retained in the PR history.

## Local qualification

The runtime is the repository-pinned **Flutter 3.47.8 / Dart 3.13.7**. The
official SDK archive and 202 locked hosted dependency archives were verified;
offline lock-enforced resolution left `pubspec.lock` unchanged. Tests use the
actual native SQLite binary and controlled provider fixtures. No source stub,
replacement database or fake SDK library was introduced.

The rows below are source-bound qualification runs and **may overlap**. They
must not be summed as a count of unique tests.

| Scope | Accepted result | Evidence |
| --- | --- | --- |
| Mail store streams, saved views, flag journal and reconciliation | 117 passed; no failures/skips | [Receipt](store-validation.json) |
| Eleven-suite integrated Studio Mail cohort, including Word-based composer | 309 passed; no failures/skips; 17-file fatal-info analysis clean; 1,032 measured inputs unchanged | [Receipt](union-studio-validation.json), [full evidence](union-studio-validation.tar.xz) |
| First pinned Zotero/proofing union | 649 passed; no failures/skips; five analyzer groups clean | [Receipt](incoming-zotero-proofing.json), [full evidence](incoming-zotero-proofing.tar.xz) |
| Word sections, geometry and fidelity | 294 passed; no failures/skips | [Word receipt](incoming-word.json), [full evidence](incoming-word.tar.xz) |
| Word incremental layout and replacement failure/retry | 70 passed; eight existing skips; no failures | [Word receipt](incoming-word.json), [full evidence](incoming-word.tar.xz) |
| Final incoming transfer/ODT/proofing changes | 562 passed; no failures/skips; three analyzer groups clean | [Receipt](final-intake-zotero-proofing.json), [full evidence](final-intake-zotero-proofing.tar.xz) |
| Composer after the final shared-editor changes | 24 repeated cases passed; no failures/skips; two-file analysis clean; 428 measured Mail/Studio inputs identical to the 309-case gate | [Receipt](final-intake-composer.json), [full evidence](final-intake-composer.tar.xz) |
| Portable macro execution and trace parser | Both actual BAS examples produced byte-identical VM/compiled-JavaScript output; five synthetic trace fixtures passed | [Word receipt](incoming-word.json), [full evidence](incoming-word.tar.xz) |

The eight Word skips are image-only DOCX fixtures with no editable paragraphs;
the receipt names them. They are not reported as passing coverage. Both new
explicit and lazy replacement-layout failure/retry regressions pass. Trace
fixtures establish parser behavior, not a measured performance improvement.

Earlier focused results remain available: the [285-case Mail slice](studio-validation.json)
with [full evidence](studio-validation.tar.xz), the [14-case session gate](session-validation.json),
and [initial Word qualification](incoming-word-validation.json). These are
retained development checkpoints, not additional unique-test totals.

The ordinary `dart test` launcher stalled after the real SQLite build hook.
Pure Dart groups use the locked `test` 1.31.1 entry point directly with its
kernel/VM runner and actual SQLite native asset. Flutter groups use the genuine
Flutter test runner. Receipts record exact commands and runtime identities.

## Retained diagnostics and source applicability

The evidence preserves unsuccessful attempts as well as accepted reruns.
Two native SQLite fixtures exhausted a fixed number of zero-delay widget-pump
turns while real isolate work was pending. Only those native setup/save calls
were moved into `tester.runAsync`; all cleanup, ownership, deletion and row
membership assertions remain intact. The focused proofs and complete Mail
cohorts then passed.

The first final composer attempt lost its compiler process before any case
started. No root cause is asserted. Its diagnostic is retained, source and
runtime hashes were unchanged, and the isolated 24-case rerun passed with no
code or test edits.

The [final assembly](final-intake-assembly.json) binds the four changed shared
production files and the exact custom merge blobs. The final focused gates
ran at tree `c6e320878ceffb5ba640e62e4f0046988c86dfbe`, which is identical to
remote checkpoint `721ad2c74a5d81d54c2eaa2af084e82ba5077991`.

While those checks ran, main advanced through PR #286 to
`e1ebcb0cd65716a2a78d2ea1114d9ee37a3017ec`. The
[publication reconciliation](publication-main-merge.json) incorporates it at
`f63ba0dc85f5ed419fb184fd166971e981d997f6`. Its 12 changed paths are all under
`docs/validation/`; production, package tests, tools, manifests and locks
remain unchanged. Both validation owners independently checked applicability.
Final receipt/index changes are likewise documentation only.

## Remaining acceptance boundaries

These deterministic local tests establish the selected source increment.
Live-provider behavior, browser storage, installed desktop/mobile releases,
installed Word/LibreOffice/Zotero plugin interoperability, native dictionary
quality and comparative device performance remain separate acceptance work.

Saved windows remain partial caches; provider cursors, authentication and
foreground fetch authority remain session-owned. Durable synchronization,
complete shared workspace integration, unified/account-wide search,
conversations and broader durable commands remain ordered next steps in the
[Mail implementation plan](../../roadmaps/mail/implementation-plan.md).
