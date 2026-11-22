# Native Zotero field recovery — 22 November 2026

## Delivered behavior

This continuation makes damaged Zotero metadata recoverable when the native
Word field still has complete, unambiguous structural ownership. Previously,
invalid metadata prevented the native transaction from starting, so Zotero
could not present its own repair workflow.

- Recognized citation fields with invalid JSON or citation schema, and owned
  bibliography fields with invalid JSON, can enter the native transaction.
  Quds sends their original payload to Zotero and never infers bibliographic
  data from the cached display text.
- **Repair in Zotero…** opens the native workflow. Explicit `Field.select`
  retains the original-source highlight, excerpt and body/note location, with
  a damaged-metadata explanation.
- Zotero's exact temporary empty citation reset is permitted only for an
  originally damaged citation inside the detached operation. Every remaining
  active field must have valid metadata before publication.
- Confirmed individual **Convert to text…** preserves cached text and supported
  rich formatting. Native `Field.removeCode` preserves the result, while
  `Field.delete` actually removes it. A preceding `setText` is retained when
  the processor unlinks a field whose intermediate metadata is still invalid.
- Successful repair or conversion is one undoable change and persists through
  DOCX save/reopen. Cancellation, unfinished repair, changed source or stale
  host state leaves the original document untouched.

The structural envelope includes supported body paragraphs, table cells and
authored footnotes/endnotes, plus complete contiguous multipart bibliography
owners. Actual section/table/cell/note ownership is captured and revalidated.
Shared paragraph or result objects, incomplete boundaries, unsupported stories,
nested/opaque packets, cross-owner ranges and selected protected content remain
guarded. An unrelated content control outside the exact packet does not block
an otherwise supported citation.

`WmlZoteroField.canEdit` retains its metadata-valid contract for existing callers;
`canEditNativeResult` expresses the separate structural capability. The editor
validates complete packets and exclusive owners before direct conversion.
Document-wide unlinking retains its malformed-field refusal. This milestone
does not reconstruct missing field boundaries or claim arbitrary structural
corruption recovery.

The [usage guide](../../zotero-support.md),
[detailed contract](../../zotero-support-details.md), and
[parity roadmap](../../roadmaps/zotero/word-processor-parity.md) describe the
controls and remaining limits.

## Incoming work and incremental remote saves

The initial baseline was main
`a5b4eb7d329b0700768b1fc72bb63cf58a9f5cd6` (PR #361). All 24 captured fork
branch tips and all four upstream tips were ancestors of it. Neither repository
had an open PR. The [initial intake](intake.json) records the exact refs and
recent PR inventory.

Two new branches appeared during this continuation. Their original histories
were incorporated and qualified locally:

- Mail durable move/delete: first captured at
  `cd6aa8044a7c6fb0738758a4038cdbd626b5721d`, then updated through
  `918e7dd12e66b79e75082a41c250887a92db0d4e`. The latter incorporates the
  foreground-host fixes and membership UI/journal tests in `f14974a4`, as well
  as the captured Word and Zotero histories.
- Word VBA cell-paragraph formatting: first captured at
  `708bf4a6cf2651a2f08f900631119f357aef4611`, then updated through
  `45a1c0846f3fb78a203f2967e5b80a79fdca2ca9` (PR #362). Its late delta is
  documentation, evidence and a workflow comparison correction; production
  and test source are identical.

The [bounded refresh](final/intake-refresh.json) records 27 fork tips and four
upstream tips, all contained by `918e7dd1`. At that snapshot main remained
`a5b4eb7`; the only open fork PR was #362, whose head was already included.
Publication preserves the incoming histories with ordinary fast-forwards and
merge parents. No force push or incoming-commit rewrite is used.

| Remote checkpoint | Purpose |
| --- | --- |
| `3786a8a86786fc0d76fbf648e1debe3af4f309f3` | Reconciled baseline and recovery contract |
| `d226355c729b31f09923f93b5cd538f2259e2a76` | Native engine recovery and ownership guards |
| `465ba7e241e17f290a7861ceaa3c8ec09cc1ce67` | Editor controls and 28 new editor tests |
| `0138eb8e1684e4adbb677a078a97ec09c6f5c37a` | Final engine guards and 38 new recovery tests |
| `35ef8f30d1de145bdf92d280e4aa54982d662f79` | User guide, detailed contract and roadmap |
| `2ea6ceaa5cb4c1409c73ce81c6743cd387bf51e6` | Malformed-note regression for detached recovery |
| `c9874d1f19ec4f867c4a2fb8db86872994d649a9` | Captured Mail branch ancestry |
| `6ba219a03a9933eded77980f9d7cdbd118183ee1` | Captured Word ancestry and combined source gate |
| `918e7dd12e66b79e75082a41c250887a92db0d4e` | Latest captured Mail/Word integration |

The checkpoint branch is `codex/zotero-field-recovery-20261122`. GitHub Actions
were neither awaited nor used as evidence; qualification ran locally.

## Accepted local qualification

These [nine gates](final/all-gates-summary.json) contain **3,384 passing cases**, with zero failures, errors or
skipped test events. Loading events, hidden events, repeated development runs
and superseded attempts are excluded. The 38 new engine cases and 28 new editor
cases are included in the broad Zotero rows, not added again. The three Zotero
rows total **1,007 cases**.

| Gate | Executed suites | Passed | Executed source |
| --- | ---: | ---: | --- |
| [Zotero engine](final/engine/receipt.json) | 21 | 620 | `6ba219a` |
| [Zotero editor](final/editor/receipt.json) | 18 | 347 | `6ba219a` |
| [Zotero Studio](final/studio/receipt.json) | 3 | 40 | `918e7dd` |
| [Incoming Word VBA](final/word/receipt.json) | 8 | 397 | `6ba219a` |
| [Incoming Mail core](final/mail-core/receipt.json) | 4 | 115 | `6ba219a` |
| [Incoming Mail store, full VM suite](final/mail-store/receipt.json) | 43 | 1,010 | `6ba219a` |
| [Incoming Mail providers](final/mail-transport/receipt.json) | 3 | 250 | `6ba219a` |
| [Incoming Mail UI](final/mail-ui/receipt.json) | 4 | 97 | `918e7dd` |
| [Incoming Mail Studio](final/mail-studio/receipt.json) | 10 | 508 | `918e7dd` |

Every accepted gate records exact commands, source hashes, dependency evidence,
runtime identity, raw reporter output and test identities. Inputs stayed
unchanged during execution. The
[engine/Word applicability receipt](final/engine-word-applicability.json),
[editor applicability receipt](final/editor-applicability.json), and
[Mail applicability receipt](final/mail-applicability/receipt.json) prove the
relevant earlier-source inputs are identical at `918e7dd`. The late production
changes are confined to the two Studio Mail host files; their affected Flutter
tests and the Zotero Studio routes ran on the updated source.

The store command selects 44 files: 43 VM suites execute, including the native
process/crash fixtures. `browser_problem_test.dart` is Node-only and its three
browser cases are outside this VM gate, separately from skipped test events.

[Static coverage](final/static/final-coverage.json) covers all **67 unique Dart
files** changed from original main to `918e7dd`. Fatal-info analysis and
read-only formatting pass in the final state. The two gates cover 58 initial
paths and 13 late paths with four overlaps; the other 54 initial files are
byte-identical at the final source. Dependency and toolchain snapshots stayed
unchanged.

The [portable Word routes](final/word/portable/receipt.json) execute the exact
workflow commands locally: the BAS example on the native Dart VM and compiled
JavaScript under Node, plus the 32-case conformance corpus on both runtimes.
The BAS results are equal as parsed JSON; five integral paragraph-spacing
values have `6.0`/`3.0` versus `6`/`3` spelling differences. Conformance outputs
are byte-identical. Portable checks are reported separately and are not added
to the unit/widget test counts.

### Regression scope

The new suites cover invalid/truncated/empty metadata, raw native payloads,
exact temporary reset codes, valid completion, unresolved-completion refusal,
selected-field context, rich unlinking after `setText`, explicit deletion,
body/table/authored-note ownership, multipart bibliographies, DOCX reopening,
undo and stale selection/lifecycle. Negative cases exercise missing boundaries,
locks, nested/opaque content, shared aliases, cross-owner ranges and stale
low-level handles.

Broader Zotero checks cover citation editing, preferences/refresh, adjacency,
writing-position preservation, note/research insertion, bibliography layout,
selection/prompt rendering, unlinking, transfer and ODT export. Incoming gates
cover Word cell paragraph compilation/formatting and document ownership,
provider outcomes, durable Mail migrations/journaling, crash recovery and
foreground controls, including membership-only adapters and unknown flags.

### Preserved non-final attempts

- `attempts/pre-integration/` retains the earlier broad runs. The engine found
  an inherited constructor-rejection assertion that was obsolete under
  detached recovery. Its replacement checks that damaged fields reach Zotero
  but prevent publication until resolved. The entire corrected engine gate
  passes. Overlapping earlier successes are not added to final totals.
- `attempts/pre-late-mail/` retains 11 Mail UI errors from the first captured
  branch and the earlier successful Studio run. The new incoming checkpoint
  updates move/delete tests for explicit controls; the final UI gate passes.
- `attempts/word-portable-byte-comparison/` retains the BAS comparison failure
  before the incoming workflow switched to parsed JSON equality. The numeric
  spelling difference above explains it; no semantic failure is suppressed.
- `final/static/` retains the initial formatting failure in incoming
  `studio_mail_flag_journal_test.dart`, its diff and a clean-original-main
  comparison. The updated incoming file passes in the final state.

## Runtime provenance

The [runtime receipt](runtime/runtime.json) records genuine Flutter **3.47.8**
and Dart **3.13.7**. The official SDK archive SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
All 204 downloaded hosted-package archives were hash-verified. Offline
`pub get --enforce-lockfile` resolved 166 workspace packages without changing
any of the 23 captured manifests/locks. Executable hashes, release metadata,
dependency receipts and setup logs are retained under `runtime/`.

Flutter tests ran from their actual package directories with the real engine
and bundled fonts. Focused analysis used the SDK's `dart analyze`; no analyzer
or SDK behavior was patched to obtain a passing result.

## Remaining parity acceptance

This qualifies bounded metadata recovery. Local protocol, serializer,
controller, widget and VM/JS results do not establish installed Zotero repair
dialogs, Word/LibreOffice application round trips, live Mail account behavior
or full desktop-platform acceptance.

Next, use identified Zotero/application/plugin versions and a synthetic library
to exercise damaged-reference prompts, actual delete/unlink callbacks,
cancellation, rich bibliography repair, body/table/note locations, undo,
saved-file reopening and return-to-writing focus. Retain original damaged
inputs and result files. Zotero's native corrupt-reference **No** choice must
not be promised to preserve text regardless of the callback it sends; Quds'
explicit Convert to text is the preservation path.

Modern supported comparison targets are Word and LibreOffice.
[Zotero's official troubleshooting guidance](https://www.zotero.org/support/word_processor_plugin_troubleshooting)
excludes Apache OpenOffice. A historical OpenOffice-plugin target requires
separate identified application, Zotero and plugin versions. The
[HTTP integration protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
and [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) provide the
next acceptance/implementation sequence, including release-host editable ODT,
separator compatibility and remaining bounded content limits.

## Final main reconciliation

After the qualification checkpoint, PRs #362 (Word) and #363 (Mail) merged
into main at ec09fdccf95eb3072b4cfe4da3608f8d9b13eb75. The
[publication receipt](final/publication-premerge.json) records the refreshed
branch tips and confirms that all are contained by the merge parents. Those
late main commits add qualification documentation only; every tested source,
fixture and dependency input remains unchanged. The sole merge conflict was
removal of a terminal empty line from the preliminary version of this README.
The complete accepted report is retained, along with the incoming histories
and their own qualification evidence.
