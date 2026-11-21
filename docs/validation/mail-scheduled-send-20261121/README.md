# Mail scheduled sending — implementation and local verification

## Qualified scope

Native Studio Mail's existing Outbox now supports **Send later**, saved UTC
deadlines, a ten-second pre-submission **Undo** window, Pause, explicit Resume
and confirmed Send now. It uses the existing account-owned SQLite store and
SMTP/EWS/Gmail/Microsoft 365 submission adapters. The workflow is described in
[scheduled-send.md](../../roadmaps/mail/scheduled-send.md).

Scheduling grants permission for one attempt while Outbox remains open and the
application is active. Closing Outbox, switching accounts or suspending the app
revokes that permission. Reopening, refreshing and reconnecting do not send;
the user explicitly resumes. Original composer Send remains immediate.

Only never-attempted queued entries without earlier uncertainty can be
scheduled. Payload v3 reads v1/v2 entries as unscheduled. Schedule revisions
fence stale edits, cancellation and attempt decisions, including changes away
from and back to the same deadline. Frozen MIME, attachments and the complete
recipient envelope remain unchanged. An uncertain result never authorizes an
automatic retry, and Undo does not recall an already submitted message.

The qualified publication-source checkpoint is
`6426d8877d5a7a2405bdd9060a1b6c443a731cb0`, which also preserves the concurrent
main renderer optimization and its cache correction. Evidence publication
commits preserve that source. The executions below are bound to
their recorded source hashes and scopes; this is not a claim that the entire
repository or every installed platform was tested. GitHub Actions runs, checks
and status queues were neither queried nor awaited.

## Accepted local results

| Scope | Accepted result | Evidence |
| --- | --- | --- |
| Full `quds_mail_core` VM suite | 482 passed | [Core/store archive](evidence/core-store-evidence.tar.xz) |
| Full `quds_mail_store` VM suite | 934 passed, including migrations, archive consumers and real subprocess crash recovery | [Core/store archive](evidence/core-store-evidence.tar.xz) |
| Combined Studio Mail cohort | 143 passed across 13 suites: 66 existing Outbox, 40 scheduling and 37 compose-tools cases | [Final Studio archive](evidence/main-studio-evidence.tar.xz) |
| Earlier Word shading and shared VBA cohort | 933 passed across 12 suites; two portable workflows compile to JavaScript and produce matching VM/Node JSON | [Word archive](evidence/word-evidence.tar.gz) |
| Publication ODT and affected Word engine cohort | 1,725 passed across 86 suites: 64 ODT/ODF-Zotero and 22 affected Word table/style suites | [Publication archive](evidence/publication-evidence.tar.xz) |
| Publication ODT editor cohort | 19 passed across 3 suites | [Publication archive](evidence/publication-evidence.tar.xz) |
| Final renderer and selection cohort | 76 passed across 10 suites, including existing Linux goldens and retained-canvas pixel regression | [Renderer archive](evidence/main-renderer-evidence.tar.xz) |
| Localized visual qualification | 3 passing rendering cases; 7 reviewed EN/DE/AR images, including narrow Arabic controls | [Visual archive](evidence/visual-evidence.tar.xz) |

All accepted test cohorts have zero failures and zero skips. Earlier focused
runs overlap these totals and are not added again. The two portable Word
workflows and seven rendered images are separate artifacts, not extra unit
test counts.

Fatal-infos analysis passes for both complete Mail packages and the selected
Studio, Word and ODT paths. Scoped formatting and whitespace checks pass. The
archives retain exact commands, working directories, JSON test events,
stdout/stderr, source manifests and result receipts. Core/store selected source
hashes and the dependency lock stayed unchanged across their final executions;
the receipt records the local Git HEAD before and after concurrent checkpoint
creation. The Studio receipts also audit all 13 selected suites and their complete event
stream. The final run preserves identical before/after maps for 6,094 workspace
files, 6,211 dependency inputs and 11 selected paths. The final
renderer checks share 1,251 unchanged source inputs. The earlier ODT/table
publication checks share 1,250 unchanged source inputs.
[Source continuity](source-continuity.json) verifies that both complete Mail
package trees and the selected visual inputs remain identical to their earlier
qualified versions. The earlier 933-case VBA cohort predates the latest ODT/table
merge and retains that scope; the 86-suite publication cohort checks the affected
serializers and styles after integration.

The scheduling cases cover exact deadline boundaries, UTC normalization,
restart/rollback, stale revisions, immutable bytes and recipients, cancellation,
failed writes/readback, clock jumps and lifecycle changes during pending
storage. Existing immediate Send and uncertain-retry paths remain covered.

## Runtime

The pinned local runtime is **Flutter 3.47.8 / Dart 3.13.7**. Official Flutter
archive SHA-256:
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
Dependency resolution succeeded with `--enforce-lockfile`; the original
`pubspec.lock` SHA-256 remains
`2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.
The actual SQLite native hook produced the test mapping. Setup attempts,
resolved runtime identities and native-library hashes are retained in the
[runtime archive](evidence/runtime-evidence.tar.xz).

## Findings and corrections retained in the evidence

Earlier unsuccessful attempts are preserved in the
[development archive](evidence/development-evidence.tar.xz), runtime, Word and
ODT archives and are not counted as acceptance. Initial package-metadata resolution timed out; normal online and
offline enforced-lock resolution subsequently succeeded. Formatting before
package resolution produced configuration warnings; the resolved checks pass.

Independent scheduling review found three timing races. The accepted source
revokes foreground permission across awaited writes using a generation guard,
starts the usable Undo interval only after save and readback finish, and checks
the deadline again after attempt persistence immediately before provider use.
Regression cases exercise each race. Visual review also removed the generic
queued status from scheduled queued entries so it does not contradict their
timing state.

The initial Word checkpoint lacked its native operation. Incoming native
continuation `655b2722` replaced the local fallback; fallback failures remain
historical. The final cohort passed after six mandatory flow-control braces
were added. A later formatter-only correction was followed by its affected
125-case suite; those cases overlap the 933. The first plain Node launch
produced no output and was rejected. The corrected repository-standard
`globalThis.self=globalThis` runner checks nonempty JSON and exact VM equality.

The first combined ODT engine run had 1,203 passes and three failures.
Corrections preserve unique emitted picture identities while normalizing them
only for story comparison, retain annotation frame structure, and strengthen
the continuous-section regression. A redundant nullable test access was also
fixed. The complete 1,206-case engine and 19-case editor scopes then passed.
A separate Flutter startup race executed zero tests; it is retained as a
failed environment attempt, followed by a successful serialized startup. The
[earlier ODT archive](evidence/odt-evidence.tar.xz) and
[earlier Studio archive](evidence/studio-initial-evidence.tar.xz) retain those
source scopes. They are superseded, not added to the publication totals.

The last image continuation improves the story comparison to retain original
authored picture names instead of discarding all names, and retains styles on
unlinked annotation pictures. Those incoming changes replace the corresponding
intermediate correction while retaining unique emitted identities and the
regression assertion. Native round-trip continuation adds guarded DOCX table
margins and ODT cached-pagination hints. The combined publication run passes
1,725 engine and 19 editor cases without further source repairs.

The final main refresh brought PR #335 and a documentation continuation. The
new renderer selection cache omitted the selected table from its key. A retained
canvas kept stale text tint after switching to a table band, while a fresh
canvas did not. The pixel regression fails on that incoming source and passes
after replacing the always-true permission key with selected table identity.
The correction retains both new bounded caches. All 76 targeted editor cases,
including existing selection goldens, pass. The
[main follow-up](main-followup.md) records the exact scope and original failure.

The first concurrent Studio attempt after that main update timed out opening
SQLite and was cancelled while the source was changing. It is rejected
evidence, not a passing run; its raw events are retained in the
[rejected-run archive](evidence/main-studio-rejected-evidence.tar.xz). The final Studio check runs after the editor checks finish on the
corrected frozen source and passes all 143 cases with zero failures or skips.

## Intake and incremental remote checkpoints

Initial remote main was `4970f71f983535d045ce263e86835b499db4fda9`.
The initial inventory captured 376 refs and no open fork PRs. It identified
three new branch heads and 14 historical replacements; see
[intake.json](intake.json) and [intake-review.md](intake-review.md).

The subsequent frozen inventory contains **377 refs**: 41 fork branches,
332 PR heads and four upstream branches. Its reconciliation preserves **363
refs as ancestors** and independently verifies **14 historical equivalents**:
13 whole-tree equalities and one replacement covering all 37 original changed
paths. The Word continuation and both ODT continuations were integrated; the
ODT reader constructor retains both image ZIP input and producer-specific
note-offset handling. Details and proofs are in
[final-intake.json](final-intake.json) and
[final-intake-review.md](final-intake-review.md).

| Remote checkpoint | Purpose |
| --- | --- |
| `71dc9cc0e3696096248b28b02b276dcc14c97f93` | Preserve the initial incoming Office branch heads before Mail work |
| `a4ff3da2feeb9b0b8ed53718c3143ab68c1c6c1b` | Durable Outbox deadlines, payload compatibility and revision guards |
| `cb56910da89751bb572d4448dfec5e66b38c0662` | Foreground scheduling, Undo and lifecycle/clock safeguards |
| `74c2550412508b90ba649d68c7c92784395f646d` | Scheduling regressions, workflow documentation and reconciled Office heads |
| `e9a95d7795812a8322c3a0c1d508cf05553bfe82` | Narrow ODT integration corrections after complete local qualification |
| `964783488cfa8079464e7dc80c1df6bb139323f5` | Reconcile refreshed main, completed Word qualification and latest image/table continuations |
| `917f7ea13425b2c078cc8f0e6e73d4e59b7e4608` | Preserve initial complete qualification archives, previews and finite intake |
| `d4aa0709f811846cf04a98a99800975a82a92600` | Preserve concurrent main PR #335 renderer cache optimization |
| `6426d8877d5a7a2405bdd9060a1b6c443a731cb0` | Preserve subsequent main documentation and correct stale table-selection cache with pixel regression |

Remote main and active branches advanced after the frozen inventory. The
separate [publication intake](publication-intake.md) accounts for **380 captured
refs**: 42 fork branches, 334 PR heads and four upstream branches. **366 are
ancestors and 14 historical equivalents remain verified**, with no captured
head unaccounted for. It includes main `5c59a062`, Word `26748a56` (PR #334,
already merged), Zotero images `58fe5b97`, and native round-trip `3eac83d1`
(PR #333, draft/open when captured). Original incoming commits remain ancestors;
no force push or destructive replacement was used. This is a finite capture,
not a claim about branches that continue to advance afterward.

The later main commits `a97295f9` (PR #335) and `3440c90b` were preserved after
the finite 380-ref capture. They are additional ancestors rather than a claim
that the historical inventory was captured again. [PR #338](https://github.com/CrispStrobe/quds_office_suite/pull/338)
records the final merge and remote-main readback. Main is checked again
immediately before merging; the work branch and incremental checkpoints remain.

## Reviewing the retained evidence

[Evidence index](evidence-index.json) records archive sizes, SHA-256 values and
member hashes. From this directory, verify compressed files and previews with:

```sh
sha256sum -c SHA256SUMS
```

Each archive contains the exact commands and raw outputs for its named scope.
The runtime archive also retains setup and the earlier overlapping compose
qualification. No SDK installation or dependency cache is included.

[English Outbox preview](previews/outbox-en.png) and
[Arabic narrow-screen picker](previews/picker-ar.png) show the actual widget
renders. The visual archive contains all seven reviewed images and their input
hashes.

## Remaining boundaries

This is foreground scheduling, not a server scheduler or OS background
service. Provider-specific Sent reconciliation, provider-side draft sync,
installed-platform acceptance and real-account delivery remain separate work.
The fixtures and callbacks do not establish delivery by live mail providers.
The visual cases are actual Flutter widget renders, not installed-application
acceptance. Word/ODT checks use local engines and retained interoperability
fixtures; no installed Office, external LibreOffice conversion or live Zotero
plugin/CSL session was exercised. Full Outlook, Thunderbird or eM Client parity
is not claimed; the next increments remain in the [Mail roadmap](../../roadmaps/mail/README.md).
