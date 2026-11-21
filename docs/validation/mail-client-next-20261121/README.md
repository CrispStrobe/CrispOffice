# Mail saved searches and conversation triage — 21 November 2026

## Delivered increment

Native Studio now saves, reopens, renames, updates and deletes named searches
over current retained headers. Each definition keeps an exact account scope;
later accounts never silently join it. Reopening resolves the current verified
directory and begins a fresh bounded local search. Missing accounts, stale
edits, name conflicts and uncertain writes have explicit user paths. Deleting
a definition preserves messages, drafts, retained bodies and queued Outbox
bytes. Schema 9 adds transactional, revision-guarded persistence.

Shared loaded conversations now expand and collapse, show observed unread and
flag counts with unknown-state detail, and support accessible disclosure and
direction-aware keyboard controls. Hidden members are immediately removed
from checked selection; bulk actions retain explicit visible message IDs.
Both workflows have English, German and Arabic host controls.

See the [saved-search contract](../../roadmaps/mail/saved-searches.md) and
[conversation contract](../../roadmaps/mail/conversations.md) for user paths,
public APIs and limits. Continuous refresh, whole-server/body search,
persistent cross-folder conversation indexing and full desktop-client parity
remain open.

## Source preservation and incoming work

The work started from main 01517de8886ef7bd24947894be5dc823d0328869.
The initial [intake record](intake.md) and [machine-readable audit](intake-audit.json)
established that all 27 current fork branches, the 100 newest PR heads and four
upstream branches were already ancestors; no open PR remained.

During implementation, branches and main advanced. The final captured snapshot
covers all **31 fork heads**, **four upstream heads**, and the **100 latest
updated PRs**: 91 PR heads are ancestors and nine historical heads are covered
through their recorded merge commits. Captured open PR #311 is also covered.
The [evidence index](evidence/evidence-index.json) locates the captured and
reconciled finite-snapshot records.

These incoming tips were preserved through real merge ancestry:

| Captured source | Included work |
| --- | --- |
| 0fe00b18fef6b79a435817c99714f987329d5f3c | Word AllCaps compiler/native/model/layout/editor and Zotero preservation |
| 2aa7833239ec4507a4a9db1c7f23c84bd01b4028 | Initial LibreOffice/Zotero intake |
| 3f6b9a2b9209693aa32bbad402bb7d093cf8b4db | Captured main, including About privacy-link and App Store documentation PRs #312/#313 |
| d86d0d1325cb3c663970f5d52e7386b0b0c775b8 | German proofing/editor localization and German mail-composer strings |
| 2e3280a175814dab7fccf14363f8dd1785acc78e | LibreOffice ODT typography/script-style import and fixtures |

The combined qualified application source is
**3a8d466fac738973dcffdae58c3d7ac0fd594e86**. Subsequent work-record, evidence,
changelog and README edits do not alter production or test inputs.
The [checkpoint map](checkpoints.json) records eleven incremental remote commits
on work/mail-client-next-20261121, exact tree checks and preserved merge
parents. It maps local execution commit IDs to byte-identical remote trees.
No branch was force-pushed, and existing branch tips were retained.

During final publication, main advanced to
49adcd6b693712b9e82f9fdefd2fdf09d0db4ee2 through the completed Word PR #311.
That main tip was integrated with both parents preserved. Its net addition to
this branch was ten Word validation documentation/evidence paths; production
and test inputs remained unchanged. The [publication reconciliation](publication-reconciliation.json)
records those paths and the already-published Mail evidence checkpoint. This
documentation-only integration reuses the source qualification below.

## Local verification

Every listed completed test process exited **0**, with **zero failures and
zero skips**. Counts use non-hidden test events and exclude suite-load events.
Do not add them into a grand total: several cohorts overlap.

| Cohort | Passed | Scope / overlap |
| --- | ---: | --- |
| Complete Mail core, Dart VM | **449** | 19 suites, including final validation and conversations |
| Saved model and conversations, Node/dart2js | **42** | Portable replay of core cases |
| Complete Mail store, native SQLite | **884** | All store suites, migrations and process-crash transactions |
| Focused model/store/migration gate | **87** | Included in core/store coverage |
| Shared message-list widgets | **108** | Includes 18 conversation cases plus navigation/bulk regressions |
| Studio conversation and Boolean localization | **6** | Three EN/DE/AR conversation cases and three existing locale cases |
| Studio cached-search/mailbox regression | **298** | Ten suites; includes 13 new dialog cases |
| Final integrated saved-search host replay | **32** | 13 dialog + 19 native-store cases; repeats the dialog subset |
| Incoming Word engine/editor | **179 + 12** | AllCaps/typography/Zotero and editor compatibility |
| Incoming German engine/editor/Studio | **64 + 75 + 58** | Proofing, editor localization, compose/attachments/cache recovery + About |
| Incoming Zotero/ODT/AllCaps merge gate | **210** | 160 ODT cases + 50 repeated AllCaps cases |

A separate real-ODT probe passed four DOCX round trips with simultaneous
AllCaps and complex-script font/size/weight/italic edits. It verified native
formatting, language, text and unchanged fixture bytes across AllCaps
true-to-false transitions. The incoming Zotero README's provisional
hyperlink/citation failure note is superseded for this integrated source:
that exact test passes in the 210-case merge gate.

Strict analysis is clean for complete core/store libraries and all changed
Mail UI/Studio library and test paths. Affected files use the pinned formatter.
Final whitespace checks are part of publication.

### Runtime and source binding

The genuine **Flutter 3.47.8 stable / Dart 3.13.7** runtime used locked
dependencies and real native SQLite hooks. The official SDK archive SHA-256 is
baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2.
Setup verified **202 hosted dependency archives** and enforced the lock offline.
The tracked lock stayed
0d64a732cd7f6c7cc4e1e01255276f081b59e6f43039636c3d36f6785a958ce2.

The final core gate bound **44** unchanged inputs; store **129**; Node **25**;
final integrated host replay **1,052**. Incoming Word bound **1,252**;
localization engine/editor/host **395 / 505 / 886**; ODT **948**.
Exact commands, runtime identities, timestamps and source hashes are retained.

The conversation manifest was captured during its final run, rather than
before it, and remained unchanged thereafter; its receipt preserves that
qualification. The broad 298-case host run did not capture a complete pre/post
manifest; the final 32-case integrated replay did.

The [evidence index](evidence/evidence-index.json) maps logs, receipts, manifests
and runtime records to original/stored SHA-256 values. Deterministic gzip
retains exact original bytes; gzip -dc restores each compressed log.

Example commands for an equipped checkout with the pinned SDK and lock:

~~~bash
cd packages/quds_mail_core
dart test
dart test --platform node test/saved_header_search_test.dart test/conversations_test.dart
cd ../quds_mail_store
dart test --concurrency=2
cd ../quds_mail_ui
flutter test --no-pub test/message_list_conversations_test.dart test/message_list_test.dart test/message_list_bulk_test.dart test/bulk_message_list_test.dart
cd ../quds_office_editor/example
flutter test --no-pub test/studio_mail_saved_search_dialog_test.dart test/studio_mail_saved_search_store_test.dart
~~~

Receipts additionally record the direct compiled package:test runner used here
to avoid dependency resolution. The archived standalone ODT probe contains its
original workspace fixture path; adjust it for another checkout before replay.

## Development findings and practical boundaries

The first full-store run exposed two older tests that reconstructed schema 7
by dropping only schema 8's table, leaving schema 9 objects behind. Those
fixtures now represent actual schema 7; the whole suite was rerun.

A separate probe demonstrated that lone UTF-16 surrogates could silently become
U+FFFD in SQLite. The model now rejects malformed values in every persisted
field while valid emoji and Arabic survive exact restart round trips. Final
VM, Node and complete-store results above include that fix. Early widget
harness issues and a native fixture's missing required recipient field were
corrected before their successful final runs.

No pass is inferred from inspection, a prior session or queued remote jobs.
GitHub Actions runs, jobs, checks and statuses were neither queried nor awaited.
Live-provider acceptance, installed-platform checks and full desktop-client
parity are not claimed by these local fixture tests.
