# Mail scheduled sending — implementation and local verification

## Scope

This increment extends the existing native Outbox with durable UTC deadlines,
an explicit foreground Send later workflow, and a ten-second pre-submission
undo window. Opening or reconnecting Mail never starts saved schedules. Closing
Outbox, changing accounts or suspending the application pauses foreground work;
the user explicitly resumes it. Attempt identity is still persisted before the
provider call. An uncertain result never becomes an automatic retry.

Implementation and final combined-source qualification are in progress. This
record separates completed local checks from pending acceptance. No GitHub
Actions/check/status queue is queried or awaited.

## Intake

Initial remote main: `4970f71f983535d045ce263e86835b499db4fda9`.
The captured inventory covers 376 references: 40 fork branches, 332 PR heads,
and four upstream branches. Of these, 359 were ancestors of the initial main,
14 were independently verified historical replacements, and three branch heads
contained new work. No fork PR was open at intake.

The first remote checkpoint, `71dc9cc0e3696096248b28b02b276dcc14c97f93`,
preserves the three new heads as parents: Zotero image/roundtrip planning and
the Word format-controls work checkpoint. The Word compiler checkpoint was
explicitly incomplete; its native continuation must be integrated and locally
checked before final main publication. The full inventory and dispositions are
retained in [intake.json](intake.json) and [intake-review.md](intake-review.md).

## Completed foundation checks

Pinned local toolchain: Flutter 3.47.8, Dart 3.13.7. The official Flutter
archive SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The committed dependency lock was resolved with `--enforce-lockfile` and was
not changed.

- Full `quds_mail_core` suite: 482 passing cases.
- Store codec, repository, scheduling, Outbox management and draft-transfer
  cohort: 107 passing cases.
- Analysis of `quds_mail_core` and `quds_mail_store`: no issues.
- Formatting of the seven foundation Dart paths and whitespace checks: pass.

These checks cover UTC deadlines, payload-v3 round trips with v1/v2 backward
reads, exact eligibility boundaries, durable reopen, interrupted attempts,
schedule-revision comparison including ABA races, failed-write rollback and
frozen message/envelope preservation. Studio and final combined-source checks
will be recorded separately after their execution.

## Boundaries

This is local foreground scheduling, not a server-side scheduler or OS
background service. Provider Sent reconciliation, provider-side draft sync,
installed-platform acceptance and real-account delivery remain separate work.
The independent archive and mailbox caches retain their existing behavior.
