# Mail reader implementation and local qualification

This checkpoint implements the shared, account-free saved-message reader
foundation from M00–M04. It includes the reviewed portable MIME fork, typed
Mail core, bounded EML codec and Flutter reader. It does not implement the
later mailbox store, live accounts, composer, standalone Office application
or CrispCloud migration. The [implementation status](../../roadmaps/mail/status.md)
and [ordered plan](../../roadmaps/mail/implementation-plan.md) retain those tasks.

All implementation work is on `codex/mail-reader-20261118` in
`CrispStrobe/quds_office_suite`. No GitHub Actions job was queried, awaited or
rerun. The checks below ran locally with the recorded Flutter/Dart toolchain.

## Reconciliation and remote checkpoints

The initial capture accounted for 207 existing branches and 169 PR heads.
The review/Zotero and offline thesaurus heads required a real merge; six
overlapping files were reconciled while preserving both feature sets.
The [initial audit](initial-reconciliation.md) links the exact inventories and
historical-equivalence proofs.

A later full fetch captured work published during this implementation. Its
inventory contains **209 external branch heads and 170 PR heads**. Of those,
195 branches and 156 PR heads are ancestors of the integrated branch; the
remaining 14 in each inventory are the unchanged, verified historical
equivalents. **No captured head is unaccounted for.** The updated review head
`b9728ea1` contains all four new or changed external heads and 26 additional
commits, including Zotero note workflows, review-draft proofing, thesaurus
continuation and English/French analysis support.

The [final reconciliation receipt](final-reconciliation.json) preserves the
capture time, full identities, incoming delta, pre-merge audit and subsequent
remote merge proof. The current task branch is excluded from external-branch
counts. These counts describe the captured refs, not a promise that other
contributors have stopped publishing.

| Saved checkpoint | Purpose |
| --- | --- |
| `6db30ea1` | Initial review/Zotero integration |
| `0e07d247` | Initial offline-thesaurus reconciliation |
| `9232b056` | Typed core and recovery contracts |
| `9ee120bd` | Portable fork and bounded exact-byte MIME codec |
| `86d6f507` | Account-free reader and actual MIME example |
| `46d7422d` | Independently reviewed MIME/date/charset corrections |
| `6c728e1a` | Native/web qualification, visual evidence and workspace lock |
| `c473a25f` | Captured late review, Zotero, thesaurus and EN/FR integration |
| `e727204c` | Captured-head accounting, pinned local runner and language checks |
| `67a6efd2` | Draft-feedback, compact-navigation and proofing regression repairs |
| `0d1f699b` | Independent compact/inline PDF scroll state with explicit Linux resize coverage |

Each remote write used the expected previous branch head and preserved normal
history. The corresponding local and fetched remote trees were verified equal.
Main was not updated by these writes. Commit subjects include `[skip ci]`.

## New Mail implementation

| Component | Implemented behavior | Source |
| --- | --- | --- |
| Core | Immutable owned bytes and DTOs; scoped account/IMAP identities; budgets, capabilities, cancellation, typed ports; atomic sync-page contract; recoverable immutable outbox state machine | [quds_mail_core](../../../packages/quds_mail_core/README.md) |
| MIME | Original-octet preservation; bounded byte ranges and strict decoding; cumulative quotas; deterministic alternatives/CID metadata; immutable attachments; explicit malformed/unsupported results | [quds_mail_mime](../../../packages/quds_mail_mime/README.md) |
| Reader | Full/compact view; custom RenderBox selection; decoded search/copy; bounded static HTML; local raster CID images; host-approved links; exact read-only attachment/source callbacks | [quds_mail_ui](../../../packages/quds_mail_ui/README.md) |
| Portable fork | Public socket-free `mime_core.dart`; content-redacted diagnostics; reviewed charset admission, RFC2231 continuations and strict dates; preserved native APIs and MPL notices | [fork patches](../../../third_party/enough_mail/QUDS_PATCHES.md) |

The example parses one original multipart EML snapshot through `QudsMimeCodec`.
It does not construct a separate display-only message or require an account,
database or provider connection. The desktop and enlarged narrow RTL fixtures
exercise the same source snapshot.

The [independent review](independent-mime-review.md) found and corrected four
concrete defects: leading escaped Q words, render quotas resetting per part,
invalid dates normalized into different instants, and undefined single-byte
character slots silently replaced by question marks. Regression evidence is
included in the facade and fork results below.

## Local results for the new Mail code

| Check | Result | Evidence |
| --- | --- | --- |
| Core VM tests | 28 passed | [workspace receipt](checks/core-workspace-receipt.json) |
| Core JavaScript/Node tests | Same 28 passed | [core summary](checks/core-integration-summary.json) |
| Core public entry | Native executable and JavaScript compile/run passed | [workspace receipt](checks/core-workspace-receipt.json) |
| MIME VM and JavaScript/Node tests | 32 passed on each runtime | [final output](checks/mime-final-tests.txt) |
| Fork native regressions | 170 passed across 14 files | [fork receipt](../../../third_party/enough_mail/verification/receipt.json) |
| Fork portable public entry | JavaScript compile and equal native/Node projection passed | [fork verification](../../../third_party/enough_mail/verification/README.md) |
| Reader functional tests | 30 passed, none failed or skipped | [final UI summary](ui/native-final-summary.json) |
| Native visual fixtures | 2 passed, captured and inspected | [UI report](ui/README.md) |
| All three Mail package analyses | No issues with fatal infos | [analysis output](checks/mail-final-analysis.txt) |
| Reader release web build | Passed with local renderer assets and same-origin fallback configuration | [UI receipt](ui/receipt.json), [artifact inventory](ui/web-artifacts.json) |
| Browser guard helper | JavaScript compilation passed | [compiler output](ui/browser-guard-compile-final.txt) |
| Actual browser execution | **Not qualified** | [environment limitation](browser-limitations.md) |

These are per-cohort counts. Native and Node executions are identified
separately; earlier repeated runs and framework-internal loading events are
not added to the final functional counts.

The initial incoming Office merge passed 190 focused local executions:
24 engine, 128 editor and 38 Studio cases. Those results are bound to the
earlier source in [their receipt](checks/core-integration-summary.json).
The late merge is checked separately under `checks/late-*`:

| Late-source cohort | Result | Evidence |
| --- | --- | --- |
| Engine: Zotero caret/note insertion and thesaurus | 74 passed | [initial late receipt](checks/late-engine-editor-receipt.json), whose engine cohort passed without changes |
| Editor: notes, draft proofing, priority and thesaurus | 148 passed | [final engine/editor receipt](checks/late-engine-editor-final-receipt.json) |
| Studio: draft replies, keyboard review, Zotero, analysis/setup and compact PDF navigation | 71 passed | [final Studio receipt](checks/late-studio-receipt.json) |
| Engine/editor touched-source analysis | 10 paths clean with fatal infos | [final engine/editor receipt](checks/late-engine-editor-final-receipt.json) |
| spaCy language/catalog/install/worker contracts | 51 passed; library analysis clean | [spaCy summary](checks/late-spacy-summary.json) |

The initial late editor run exposed one stale test expectation: the fixture
expected lowercase `comment`, while the existing production label was
`Comment 8`. The repaired test asserts that exact existing label. Two
mechanically equivalent proofing syntax changes resolve fatal-info lint
findings without changing the priority order. The targeted case was repeated
separately and is not added to the 148-test count.

The initial Studio run passed 68 cases and exposed two real problems: missing
numeric feedback for an oversized reply and overflow in enlarged narrow
Arabic chrome. Those failures and subsequent targeted runs are preserved.
The final Studio receipt records the repaired cohort and compact PDF navigation
interaction, including a desktop resize while its modal sheet remains open.
These results are separate from the earlier 190-case integration receipt.
The late-source cohorts total **344 distinct tests**. Targeted reruns and
the earlier 190 cases are not added to that total. The final compact-PDF
regression explicitly uses Linux with normal Material scrollbars; separate
workspace-owned thumbnail controllers avoid attaching two desktop views to
one scrollbar controller during a resize.

The [consolidated verification receipt](verification.json) binds these results
to the saved source checkpoint and evidence digests. Source hashes establish
identity, not a claim that every file in a package was exercised by these
focused tests.

## Visuals and runtime limits

The reader captures are native Flutter renders, not browser screenshots:

- [Desktop, 1100 × 850](ui/screenshots/reader-desktop.png).
- [RTL preview, 390 × 844, text scale 1.5](ui/screenshots/reader-rtl-narrow.png).

The native network-denial tests include an independent positive control in
addition to the host policy. They prove the exercised native fixture made no
outbound request. The browser denial helper only compiled in this environment.
Chromium could not start under the executor's socket restrictions, and the
available cloud browser could not reach the executor harness. No browser
runtime or zero-fetch pass is inferred from Node or a successful web build.

The example builds with `--no-web-resources-cdn` and sets same-origin CanvasKit
and font-fallback paths. This avoids the default third-party fallback
destination. Hosts must still bundle/cache the fonts required by their
content and qualify actual multilingual offline rendering.

The [native memory baseline](checks/mime-memory.json) parsed a synthetic
16 MiB attachment from 22,369,758 source bytes in 493,958 microseconds, with
112,095,232 bytes whole-process peak RSS. Fixture construction is included in
that peak. It belongs to initial codec checkpoint `9ee120bd` on Linux x64;
it is not a mobile or low-memory-device qualification.

## Licensing and product boundaries

Original Quds core/MIME/UI files remain MIT. The vendored enough_mail source
and adapted files retain MPL, original notices and upstream identity. Its
[dependency inventory](../../../third_party/enough_mail/DEPENDENCIES.json)
and [portable source closure](../../../third_party/enough_mail/PORTABLE_CLOSURE.json)
record the selected files and exact versions.

The portable codec excludes unreviewed legacy CJK mapping modules. GBK,
GB2312, GB18030 and Big5 inputs report unsupported and retain original source
for a host fallback. The selected enough_convert source closure is MPL.

This audit covers the enough_mail runtime dependency graph and selected
portable source closure. It is not full Flutter/host/asset redistribution
clearance. No CrispCloud AGPL implementation, tests or assets were used as
donors. The independently incoming optional French model metadata has its
[own recorded boundary](checks/late-spacy-french-model-boundary.md); no model
payload was added to the Mail packages.

Actual browser execution, low-memory target qualification, host parity,
production accounts, complete product notices and Apple packaging remain
explicit gates in the plan. Store/client/Office/CrispCloud milestones remain
future implementation, not disabled completed features.

## Reproduction and continuity

Use the [recorded toolchain](baseline.md), the committed workspace lockfile,
and Node on PATH. The local runner is
[tools/mail/check_reader.py](../../../tools/mail/check_reader.py):

```sh
python tools/mail/check_reader.py --flutter-sdk /path/to/flutter --web-build
```

On a host that permits Chromium, supply `--chrome /path/to/chrome` to execute
the additional real-browser gates. Without that option the receipt reports
browser execution as NOT RUN. The runner retains command output and source
hashes under `build/mail-qualification`; it uses no GitHub Actions service.
Its receipt handling was separately exercised for stale PASS replacement,
missing SDK, spawn failure, interruption and failed compilation with an old JS
artifact present. Those [synthetic control-flow checks](checks/late-engine-editor-runner-checks.json)
are distinct from the actual component qualification commands above; a full
invocation of the new orchestration script was not added as another duplicate
Mail test run.

Resume from the remote implementation branch and the
[status page](../../roadmaps/mail/status.md). The next functional milestone is
the durable store/recovery journal, followed by native providers, composition
and the shared mailbox workspace, in the dependency order already specified.
