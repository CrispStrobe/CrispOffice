# Mail repository sessions — local work record

This continuation advances the accepted desktop-mail roadmap with bounded
repository observers, guarded folder sessions and connected/cached Studio
integration. See the [behavior and next steps](../../roadmaps/mail/repository-sessions.md).
It does not claim complete Outlook, Thunderbird or eM Client parity.

## Reconciled starting point and remote checkpoints

Initial fork `main` was `84046975f286407e3c62e5e5352bc16bc89c0d26` (PR #283).
The initial intake found no open PRs and one incoming branch: the three-commit
Word performance continuation through `2cd11ced136a30354169fd0043e002079bcabfa3`.
The working branch starts from that head, retaining its ancestry.

The initial [intake](intake.json) covers 335 refs: 311 ancestors and 24 independently
verified historical equivalents, with zero uncovered refs at that cutoff. The
[review](intake-review.md) records exact replay and incoming-source details.
Later branch snapshots are reviewed separately before final publication.

Work is retained on `work/mail-repository-sessions-20261121` in incremental
remote commits:

| Commit | Retained work |
| --- | --- |
| `c375becb51939dcca5c145bf1bcdb14a4febe041` | Initial intake, mailbox view/catalog streams, incoming Word failure-recovery fix and local receipts |
| `6ec90c8a3acdc8fb5878f1decef0131e478e6b1d` | Guarded selected-folder sessions, original-provider identity projection and focused regressions |
| `4d435f81493c88e8fd4fb90a62558a1cc8a7ec22` | Connected and cached Studio workflows, localized counts, error recovery, pagination/identity regressions and roadmap |
| `9276a267e83ab903d18b5af38975e15d183b7e7b` | Combined source with the four additional pinned branch heads retained as merge parents |

The [late intake review](late-intake-review.md) and [exact snapshot](late-intake-review.json)
record the additional performance, Word sections, Zotero transfer and proofing
scheduling branches. Incoming qualification and an integrated-source Mail check
precede main publication. GitHub Actions are neither awaited nor used
as a substitute for local results; checkpoint messages use `[skip ci]`.

## Local qualification retained so far

The toolchain is the repository-pinned Flutter 3.47.8 with Dart 3.13.7. The
official SDK archive and 202 locked hosted dependency archives were verified;
offline lock-enforced resolution left `pubspec.lock` unchanged. No replacement
database, source stub, fake SDK library or modified access rule was used.

| Scope | Result | Evidence |
| --- | --- | --- |
| Mail store streams, existing saved views, flag journal and reconciliation | 117 passed, no failures/skips | [Store receipt](store-validation.json) |
| Ten-suite Studio Mail cohort: connected providers, cached reader, sessions, journal/reconciliation and workspace | 285 passed, no failures/skips; 16-file fatal-info analysis clean; 1,029 source inputs unchanged | [Studio receipt](studio-validation.json) and [full evidence](studio-validation.tar.xz) |
| Selected-folder session, stale delivery, listener-driven switching/close and error recovery (included in the Studio total) | 14 passed, no failures/skips; fatal-info analysis clean | [Session receipt](session-validation.json) |
| Incoming Word layout equivalence and failed-layout retry | 70 passed, 8 existing image-only fixtures explicitly skipped, no failures; six-file analysis clean | [Word receipt](incoming-word-validation.json) and [logs](incoming-word-logs.tar.xz) |

The eight Word fixtures contain no editable paragraphs; the receipt names them.
They are not reported as passing coverage. The new failure-injection regressions
exercise both lazy and explicit layout retries and pass.

The ordinary `dart test` launcher stalled after the real SQLite build hook.
Store tests used the locked `test` 1.31.1 entry point directly with its kernel/VM
runner and actual SQLite native asset. The receipt records the exact command
and hashes. Flutter host tests use the genuine Flutter test runner.

The Studio evidence preserves an initial 284-pass/one-fixture-failure attempt.
The native SQLite fixture had exhausted a fixed number of zero-delay widget
pump turns while real isolate work was still pending. Its setup now runs in
`tester.runAsync`, retaining every quota/cleanup assertion. The focused case and
the complete 285-case rerun passed. Stream-cancellation fixture checks likewise
drain both real and widget event queues; they retain all ownership assertions.

## Remaining acceptance boundaries

Native deterministic tests establish this source increment, not live-provider,
browser-storage or installed Windows/macOS/Linux/mobile release acceptance.
Saved windows remain partial caches; provider cursors, authentication and
foreground fetch authority remain session-owned. Durable synchronization,
complete shared workspace integration, unified/account-wide search,
conversations and broader durable commands remain ordered next steps.
