# Studio mail reply threading — 2026-11-19

**Status: source-reviewed implementation; runtime qualification pending.**

The requested continuation extends Studio mail with reply-thread metadata and
preserves the prior branch reconciliation. This session has GitHub connector
access but no executor, terminal, Dart SDK or Flutter runtime. No Dart/Flutter
tests, analyzer or formatter have run. GitHub Actions are neither awaited nor
used as an acceptance gate. Publication and runtime qualification are reported
separately; this report does not claim a locally tested release.

## Implemented behavior

- Replies carry the validated parent `Message-ID` as `In-Reply-To`, and retain a
  bounded `References` chain. Outgoing messages keep a newly generated identity.
- Immutable metadata survives composer recipient/subject/body edits and explicit
  retries of an uncertain foreground draft. Native SMTP and shared EWS/cloud
  hosts already retain the complete draft and use the common MIME builder.
- New compositions and forwards start without threading metadata.
- Only complete ASCII angle-bracketed dot-atom IDs of at most 254 characters are
  accepted. Unsupported/missing parents leave the reply usable but unthreaded.
- Any unsupported token rejects the entire inherited References chain. This
  avoids treating a valid-looking ID inside a whitespace-split comment as an
  ancestor; the immediate valid parent is retained, without fallback mining.
- Chains deduplicate exact IDs, preserve case, keep the root and newest fitting
  contiguous tail, and place the parent last once. Values are at most 900 ASCII
  bytes. More than 1,024 source entries produces parent-only metadata.

[The behavior guide](../../roadmaps/mail/reply-threading.md) documents fallback
semantics, absent-versus-empty model limitations, unsupported grammar and the
remaining foreground/session-only scope.

## Incoming work and preservation

Starting main: `5715d56053e93dc11e8b5165bd13f8db2a1f3917`.
Starting task branch: `2638a2c96ea5e66ace5884896fe09de92a7ce380` (draft #216).
All fourteen external branch heads match the handoff. The only open PRs at the
initial audit were #210, #211 and #216. The latest 100 updated PR records were
also inspected before publication, with no new external update after the handoff.
The refreshed [remote inventory](remote-inventory.json) records exact refs.

The baseline already preserves the complete #210/#211 heads as merge parents,
two additional dark-theme regressions, and 221 previously absent evidence files.
Their earlier qualification remains historical author evidence. Nine unchanged
historical divergent branches retain their documented equivalence dispositions;
those proofs were not rerun here. This increment does not rewrite any of those
reconciliation files or advance archive/provider roadmap acceptance gates.

## Review and verification performed

The source/test candidate is bound to commit
`64613125ab139fcb5fe42cba9a5d7a896e646c0b`, tree
`2cd5c395fde3c82eab21ad5dc72ba8af23967bf8`. Later publication documents do not
change its product/test blobs. [review-receipt.json](review-receipt.json) records
the exact blobs, inspected dependency contracts and verification limits.

Independent reviews inspected the helper, reply builder, composer, MIME builder,
codec projections, enough_mail header serialization and native/EWS/cloud retry
paths. They found and corrected the comment-ancestry issue before publication.
The final reviewed code had no remaining identified source defect. This is
source review, not proof of runtime correctness.

GitHub readback of ten implementation/test/behavior-document files matched the
reviewed source strings exactly. The complete delta from the reconciled baseline
contained only the expected four product files, three mail test files, package
changelog and new/updated continuation documentation. Dependency manifests,
lockfiles, vendored dependencies, archive schema and unrelated product files
are unchanged. Simple fixture-length arithmetic independently confirmed the
254/255-character ID boundaries and the exact 900-byte chain; this is not a
Dart execution or a MIME round-trip result.

## Prepared regressions and open qualification

There are **28 added test declarations** across three files: 24 threading cases,
three reply cases and one composer widget case. Two existing composer cases were
strengthened. Coverage includes trailing controls/header injection, comments,
case-sensitive duplicates, malformed/adjacent IDs, missing parents, source-list
bounds, exact chain limits, maximum-ID MIME round trips, source decoding,
forward/new-compose isolation, edited snapshots and uncertain retry retention.

**Fresh Dart/Flutter executions: 0. Analyzer: not run. Formatter: not run.**
The two widget suites introduced by the preceding reconciliation also remain
unexecuted in this continuation. Historical 2,243-execution and 50-case reports
are not reused as acceptance for this combined tree. No live-provider
interoperability or actual mail submission was performed.

When an executor is available, run the focused suites from
`packages/quds_office_editor/example` with the pinned Flutter environment:

```sh
flutter test test/studio_mail_threading_test.dart test/studio_mail_reply_test.dart test/studio_mail_compose_test.dart test/studio_layout_theme_test.dart test/studio_downloads_manager_test.dart
```

Analyze and format the four changed production Dart files and three mail test
files as part of that runtime qualification. The source/API review and exact
Git publication checks in this record do not close those gates.

## Remote checkpoints and publication

All continuation commits are fast-forward additions to
`work/mail-next-20261119` using an expected prior head, with no forced updates.

- `c4b41f75ef06c0021ec31ff9c188c4982dd6dff2` — scope and inventory.
- `1e09b082fbeaa5e472957be1fca771aad3f92526` — reply threading implementation.
- `20f2ae344ae0dccb8b86fb52c85d601c3ef75865` — reject ambiguous ancestry and document behavior.
- `64613125ab139fcb5fe42cba9a5d7a896e646c0b` — focused regression tests.

This report and receipt are preserved in a further documentation checkpoint.
PR #216 carries the final publication candidate and, after merge, the exact
main commit, parent identities and same-tree readback receipt. The final merge
uses the expected PR head. Runtime qualification remains pending after merge.
