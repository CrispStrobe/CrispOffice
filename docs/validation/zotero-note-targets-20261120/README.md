# Zotero research-note insertion targets — 2026-11-20

## Delivered increment

Add Note and Add Annotation can now insert into an authored footnote/endnote
or replace an explicit text selection within one paragraph of the body or
Notes pane. The completed result remains a single undoable transaction.

Embedded citations retain the owning note and document order. The operation
preserves supported headings, nested lists, pictures, surrounding prose and
the automatic note marker/separator without creating nested notes. DOCX
reopening resolves visible list labels separately for each authored note.

Targets remain protected against ordinary complex Word fields as well as
Zotero fields, bookmark boundaries, empty atomic tokens, protected/commented
ranges, structural selections, Unicode boundaries and stale/composing state.
A text box remains a separate field story.

This is an incremental implementation merge with accepted engine execution and
targeted static analysis. **Flutter/controller execution remains unqualified
because shared filesystem capacity blocked the attempts.** This work does not
establish complete Word, LibreOffice or Apache OpenOffice parity.

## Validation results

| Check | Result | Evidence |
| --- | --- | --- |
| Integrated engine cohort | **294 passed; 0 failures, errors or skips**, including all 33 new research-target cases | [Summary](engine/summary.json), [raw events](engine/events.jsonl), [receipt](engine/receipt.json) |
| Targeted Dart analysis | All **11 commands exited 0**, with no errors or warnings | [Analyzer receipt](analysis.json) |
| Harness lint cleanup | Six informational import-order findings fixed; the harness then reported **No issues found** | [Follow-up](analysis-followup.json) |
| Final Dart formatting | **11 files checked, 0 changed**, exit 0 | [Format receipt](format.json) |
| Flutter/controller cohort | **Blocked; 0 visible tests completed** | [Infrastructure status](editor-status.json) |
| Live Zotero / target-application acceptance | Not performed | Separate release-host qualification remains required |

The eleven engine suites cover research targets, Add Note, native note
insertion, citing, rich edits, note lists/images, bibliography layout,
preferences/style review and the incoming slide radial-gradient correction.
Each original suite retains its own test implementation and hooks. A single
importer bounds repeated compiler-cache creation.

All 359 recorded engine source hashes matched before and after the accepted
run. The tested local commit
`730d2177e9dc2648224fc61dd50b594abe8dc278` and remote checkpoint
`586e53502701d2f568f38bdcfb4aa5fd64a53142` have the identical tree
`242f8c111a21cb5baeeed3d6d73902a3821e739c`.

After that run, only the engine aggregation harness's import directives were
alphabetized. Its imported paths/aliases and main/group registration body are
unchanged. Every product source and original engine test remains byte-identical
to the accepted run. [Source continuity](source-continuity.json) records this
narrow difference; it is not represented as another test run.

### Earlier and rejected attempts

The earlier three-suite engine run had 94 passes and two failures in new rich
note fixtures. Review corrected an invalid assertion about transient
`listRestart` state and found/fixed the real note-list-label deserialization
gap. The accepted integrated cohort above covers those cases. A separate
interrupted engine run that filled the workspace disk is excluded entirely.

Flutter setup first identified a missing official shader compiler; the genuine
tool was restored and the SDK archive hash reverified. The subsequent full
11-suite and core 10-suite attempts were terminated at the disk reserve before
any visible assertions completed. Their hidden loading-success events are
explicitly excluded from test counts.

The source, asset and configuration hashes remained unchanged across these
attempts. Their wrappers cleaned temporary and build outputs. Shared free
space fell from roughly 700 MiB to zero while this workspace stayed near
645 MiB and no compiler remained active. The core attempt's partial kernel
was only 4.36 MiB when stopped; the evidence does not establish that the
Studio import itself caused the capacity problem.

The temporary SDK cache was removed after recording the completed checks to
recover publication headroom. Use a fresh SDK installation for replay; the
historical runtime-ready receipts precede that cleanup.

## Incoming work and remote checkpoints

The starting inventory covered 22 fork branches, the 100 most recently updated
PR records, and all four upstream heads. Initial reconciliation checkpoint
`50e33639c545164af9f693265494c28b4ec8c15e` retains these parents:

| Incoming work | Captured head |
| --- | --- |
| Initial main | `d040c15a07f652d01e75363031d0efdee6357bda` |
| Typing/proofing PR #237 | `afa9272a6e31e2cbd6b9896c450a7bccfd62c579` |
| Mail workspace | `1d26181b0161d88abe5977f9848ffd4cd99e6259` |
| Zotero continuation PR #238 | `40a8f8eb76bd9bf51205fa0cb9f576ba497ad76b` |

The three recent branches merged cleanly. Historical ODS/ODT branches were
checked against exactly incorporated file identities, and the prior union
branch has an identical accepted tree. All four upstream heads were already
ancestors of the observed main. The initial JSON records preserve those checks.

Later reconciliation retained main's Mail PR #241 at `50b029b…`, typing's
documentation/workflow-only follow-up at `712d0ea…`, and main's font-pack/PDF
work at `d95e814…`. The last clean Git merge and the API-published tree were
verified identical. No incoming product change overlapped a Zotero target path.

| Remote checkpoint | Purpose |
| --- | --- |
| `50e33639` | Reconciled starting baseline |
| `cfd4cee5` | Initial authored-note/selected-text implementation |
| `c201f68e` | Corrected fixtures, restored surrounding formatting and guidance |
| `09ea0ced` | Native-field/boundary guards, note numbering and replay entrypoints |
| `e867ffaa` | Latest Mail/typing reconciliation and genuine Dart formatting |
| `586e5350` | Current main's font-pack/PDF work; accepted source tree |
| `0f90dc08` | Accepted engine evidence and independent review |

Independent branches that advanced after the starting snapshot are recorded in
[latest-integration.json](latest-integration.json). At that snapshot, the VBA
continuation and separate Downloads redesign remained outside this increment;
the font-pack branch had entered main and was included. No branch was deleted,
force-pushed or silently treated as qualified by this task.

GitHub Actions runs, jobs, checks and commit statuses were neither queried nor
awaited. Publication uses PR [#240](https://github.com/CrispStrobe/quds_office_suite/pull/240)
and preserves the incremental branch history.

## Evidence and runtime provenance

The local checks used genuine Flutter **3.47.8**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`, and Dart **3.13.7**.
The complete official archive SHA-256 was verified:
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.

The final Flutter configuration described 157 real packages and 20 workspace
roots, with no unresolved dependency names. Selected sparse repository inputs
were materialized from exact Git blobs; native-hook inputs came from the exact
locked archives. Test assets and native hooks remained enabled. No production
source, original test, SDK implementation or package implementation was
substituted for execution.

- [Independent source review](source-review.json)
- [Machine-readable validation status](validation-status.json)
- [Compressed editor/analyzer evidence](editor-analysis-evidence.tar.gz)
- [Archive index and hashes](evidence-index.json)
- [Engine invocation provenance](engine/invocation.json)
- [Post-validation runtime cleanup](runtime-cleanup.json)

The archive preserves the rejected Flutter attempts as rejected evidence, the
analyzer results, source/configuration hashes, setup receipts and exact wrapper
scripts. It is an execution record, not a bundled SDK installation.

## Replaying on a host with enough disk capacity

From a full checkout, use a genuine Flutter 3.47.8 / Dart 3.13.7 SDK and the
committed lockfile:

```bash
flutter pub get --enforce-lockfile
cd packages/quds_office_engine
dart test --concurrency=1 tool/zotero/research_target_acceptance.dart
cd ../quds_office_editor
flutter test --no-pub --concurrency=1 tool/zotero/research_target_acceptance.dart
```

The Flutter entrypoint includes the ten Zotero/proofing suites and the incoming
Studio comment-draft regression. Keep the normal asset and native-hook setup.
Record the source, results and application versions before expanding any
qualification claim.

## Remaining parity work

The immediate validation item is the blocked Flutter/controller replay.
Implementation work continues with imported research-note tables, wider
structural selections, JPEG orientation/grayscale/CMYK fidelity, and active
ODT/word-processor transfer. Real Zotero, Word and LibreOffice round trips need
an identified release host and synthetic library. Qualify Apache OpenOffice
separately with explicit application and plugin versions.

The [roadmap](../../roadmaps/zotero/word-processor-parity.md) and
[usage guide](../../zotero-support.md) define the current supported envelope.
