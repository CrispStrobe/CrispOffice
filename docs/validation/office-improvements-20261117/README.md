# Office export and visible-text improvements — 17 November 2026

**Accepted canonical source:**
[`7fd2030fd39a2b0bbdb1b1e778840c332ae6bbc3`](https://github.com/CrispStrobe/quds_office_suite/commit/7fd2030fd39a2b0bbdb1b1e778840c332ae6bbc3),
tree `a2be1d4f1a871f68bc9986f0e2032ad3484d5212`.
The final source-specific qualification passed **1,543 unique Dart/Flutter cases
across 72 files**, plus **99 AOT cases repeated on Node** and **five separately
counted Python controls**. All 12 command gates passed, with zero test failures
and zero skips. Only the completed retry, `qualified-canonical-7fd2030f-r2`,
supplies these final results.

The review target is the dedicated branch
[`codex/office-fidelity-improvements-20261117-e1978379`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/office-fidelity-improvements-20261117-e1978379).
The shared continuation behind PR #116 continued to advance during this work;
its later head is not interchangeable with this qualified source. The earlier
[Office continuation report](../office-resume-20261117/README.md) and incoming
validation histories retain their original source attribution.

## Confirmed repairs and retained behavior

| Problem | Result and regression evidence |
| --- | --- |
| Stored deleted paragraphs, previous spreadsheet values and change comments entered current extraction/search. | Exclude namespace-qualified text and spreadsheet revision stores, including the history-only fallback. Preserve current inserted text, foreign lookalikes and raw package XML. The controls cover ODT, ODS and ODP behavior. |
| ODS cells duplicated anchored frame paragraphs and exposed note/ruby annotation payload. | Decode each paragraph's own inline text, followed by its anchored text-box stories once, including nested frames. Retain comment ownership, authored whitespace, ruby base text and XLSX save/reopen behavior. |
| Standalone default header/footer pictures disappeared on ODT export. | Emit the modeled visual lists through the existing story writer and media registry, including image-only stories and textual visual fallbacks. A real authored DOCX story-media fixture exercises import followed by export. |
| Equivalent run-color spelling could force a continuous section onto another master page. | Normalize foreground/highlight colors in style identity consistently with emitted XML. Different colors and picture geometry remain distinguishable. The prior paragraph shading/border cache repair is retained. |
| Native DOCX bookmark ends were dropped because an imported end carries an ID without a name. | Pair ends with starts by canonical numeric ID within the same logical story. Overlapping ranges and cross-paragraph ranges retain endpoints. Body, header, footer, note, comment, frame and covered-cell stories keep independent maps; source boundary objects remain unchanged. |
| Different tab stops reused paragraph styles or continuous-section masters. | Include normalized emitted positions, alignment and leader identity in the relevant cache keys. Equivalent emitted positions reuse styles; different tab semantics remain distinct. |
| Incoming section-column attributes were placed directly on `style:section-properties`. | Put count/gap attributes on its `style:columns` child. Preserve distinct section styles for different settings and the ordinary unwrapped body for a single column. |

The revision distinction follows
[ODF 1.3 Part 3, sections 5.5 and 9.9](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html):
revision containers store content and metadata, while current insertions remain
in the live document between change markers. Excluding the stored containers
therefore preserves current inserted text.

The ODS importer retains its existing **1,048,576 UTF-16-code-unit cell limit**,
including paragraph separators. The shared decoder also has a UTF-8 byte bound.
Exact-limit non-ASCII and over-limit controls verify the preserved contract.

The final merge retains the captured table/tab improvements: invalid numeric
table properties are omitted without losing table structure or text; row height
is emitted as a minimum; table-cell RGB values are validated and normalized;
tab positions are filtered and ordered; and distinct leader text is preserved.
It also retains incoming ODT page fields, ODP chart data as tables, German noun
agreement, the optional AOT package and Studio integration. Their relevant local
tests are included in the final selection below.

## Bounded source integration

This work starts from canonical checkpoint
`7a9702c3b74e0e905c76fcf467d608bbb852d004`. Concurrent work was incorporated in two
recorded captures, then frozen on the dedicated branch:

| Captured source | Treatment |
| --- | --- |
| Shared head `b9bfe664a4efe4128a47792a1ea2cce16c7dd2c8` and main `edd023c3505942cd2433bfa6c815a7d009432a3c` | Preserve the captured Office/proofing/AOT/Studio work, ODT columns and ODP chart tables. Reconcile tab-style identity and correct the section-column XML nesting before qualifying `e1978379`. |
| Subsequent shared head `f9cc1c003892944881bab3699ba6b76620dc2f07` | Preserve its table/tab semantics and incoming qualification/consumer evidence. Resolve the single writer conflict while retaining the repairs above, producing final source `7fd2030f`. |

These are fixed captures. The report does not claim to include an indefinitely
moving shared branch. Incoming consumer runs and the captured 3,494-case report
remain evidence for their own recorded sources and runtimes; they are not
reattributed as fresh runs of `7fd2030f`.

### Controlled regressions and the tab-leader correction

The original four new regression files contain **23 cases**. Their final
old-source controls produced **18 failures: 17 matcher failures and one
hidden-whitespace expansion error**, with **five clean control passes**. All 23
pass in the final qualification. The accepted original negative/positive
controls use identical final probe bytes; those files remain unchanged in the
final source.

The later tab investigation preserved two failing controls followed by two
passes on the corrected earlier writer. The columns investigation preserved
one failing case and one clean single-column control, followed by two passes.
Their exact source maps, writer snapshots and probes remain archived. The
reconstruction script verifies all four before/after library cohorts against
their recorded **319-file** maps using retained Git ancestors and snapshots;
no local-only merge commit or transient isolated checkout is required.

One tab expectation was deliberately updated when retaining incoming
`style:leader-text` support. In the earlier writer, hyphen and underscore leaders
emitted the same XML; their archived equality expectation and passing controls
remain attributed to that earlier source. The final writer preserves `-` and
`_`, so the final test requires separate masters for them. It still requires
hyphen leaders at `72` and `72.004` to reuse the same master after serialization,
then checks the underscore master and the distinct `144`-point right/dotted
master, including their emitted positions, styles and leader text. The case
count remains two. The original/new probe bytes, exact patch, conflict
reconstruction and rationale are preserved; the final test passes in the frozen
run below.

## Accepted final qualification

| Cohort | Passes | Files | Attribution |
| --- | ---: | ---: | --- |
| Engine ODT/ODF/ODS/ODP, search, isolate open/save, bookmarks, sections, story media and proofing | 1,271 | 53 | Unique cases |
| Editor bookmark/note and German/manual-proofing integration | 160 | 11 | Unique cases |
| Optional AOT package on Dart VM | 99 | 6 | Unique cases |
| Studio analysis dialog and configured workspace widgets | 13 | 2 | Unique cases |
| **Unique Dart/Flutter total** | **1,543** | **72** | **Final source only** |
| Same AOT package cases on JavaScript/Node | 99 | Same 6 | Repeat cohort, excluded from the unique total |
| Candidate-admission Python controls | 5 | Separate Python module | Separately counted |

The Node run has exactly the same substantive case identities as AOT VM.
Loading and lifecycle events are excluded from the case counts. The 23 original
controlled cases and the later tab/column cases are already included above;
they are not added again.

All **12 commands** passed: the five Dart/Flutter execution cohorts; Python
admission controls; strict analysis of the complete engine, complete AOT
package, selected editor proofing source/tests and Studio source/tests;
formatting; and whitespace. Analysis treats informational diagnostics as fatal.
Formatting covered **41 changed package Dart files** at language version 3.12
with zero changes. The Python wrapper binds the exact module path/hash and
requires five unique case IDs, five completed tests and zero skips.

The [qualification receipt](qualification.json) and
[independent review](independent-review.json) record the exact commands and
scope. The reviewer recounted raw JSON events independently, verified complete
start/completion pairs, actual suite paths, source URLs and test hashes, and
checked all command-log hashes. It did not rerun product tests or use the
runner's summary to compute the counts.

### Frozen inputs

The independent reviewer rebuilt the following inventories and compared them
with both recorded maps and the live readback:

| Input inventory | Verified entries |
| --- | ---: |
| Materialized source in the recorded scopes, including Git blobs and modes | 2,946 |
| Dependencies and manifests | 5,369 |
| SDK, Node and Python runtime files | 518 |
| Workspace manifests and package graphs | 20 |
| Actual package library/resource routes | 110 |

All before/after maps match. Generic local package libraries, assets, fonts and
build-hook/native source directories are bound where materialized, alongside
the selected source scopes. External font/hook/resource inputs and actual
wrapper destinations are recorded. These inventories do not imply that every
bound source path was executed or that native backends were accepted.

The pinned runtime is **Flutter 3.47.8 / Dart 3.13.7, Node v24.22.1 and Python
3.12.14**. The canonical workspace retains its **110-package graph** and the
unchanged locked dependency versions. The runner SHA-256 is
`8a70306501527cd61dc38fab5f94b06593ef3a5d9ef4cc5023104e8214f281c7`.

### Exact third-party whitespace exceptions

The two incoming OASIS schemas each retain a trailing space in their license
header. Their authentic bytes were preserved. The canonical whitespace gate
excludes only these two literal paths under
`docs/validation/office-reconcile-20261117/consumer/schemas/`, after authenticating
their committed blobs against captured `f9cc1c00`:

| File | SHA-256 |
| --- | --- |
| `OpenDocument-v1.3-manifest-schema.rng` | `8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17` |
| `OpenDocument-v1.3-schema.rng` | `40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6` |

The runner authenticates them before execution, immediately before the
whitespace gate and in the final input snapshot. The independent review also
checks their frozen Git modes. They are omitted by this sparse worktree; the
receipt records that fact, and materialized copies would also require exact
byte equality. Every other changed path remains subject to the whitespace
check. There is no schema exception in the host gates. The original failed
whitespace output and the exception rationale remain preserved.

## Companion CrispCloud acceptance

The companion dedicated branch is also
`codex/office-fidelity-improvements-20261117-e1978379`. Its qualified source
[`f08035db691d5a1fe7299ad3608b626ab6202d27`](https://github.com/CrispStrobe/CrispCloud/commit/f08035db691d5a1fe7299ad3608b626ab6202d27)
pins canonical `7fd2030f` through the guarded sync. The host retains matching
revision visibility, namespace-aware ODT preview parsing, note paragraph
boundaries and bounded cell whitespace decoding.

At that same host source, **107 core service/widget cases and 28 Python controls**
passed all nine core gates. A separate graph qualified **10 production
menu/export widget cases** through all six workflow gates. The workflow
exercises the actual host editor/menu/ribbon and ODT/ODP export paths with
authored fixtures, deterministic cloud state and a substituted copy destination;
it preserves source bytes and checks output content and ownership. These are
distinct host cohorts and are not added to the canonical total. The two host
graphs and their input/restoration evidence remain separate.

See the [companion host report](https://github.com/CrispStrobe/CrispCloud/blob/codex/office-fidelity-improvements-20261117-e1978379/docs/validation/office-improvements-20261117/README.md)
for its detailed acceptance, preservation audit, workflow graph and dependency
asset verification. Passing these widgets does not establish a live operating
system save dialog, cloud transport or external application interoperability.

## Preserved attempts and historical attribution

| Retained evidence | How it is used |
| --- | --- |
| Earlier 3,280-case Office continuation and incoming broader qualification/consumer reports | Preserved under their own source/runtime attribution; not repeated or added to this final selection. |
| Focused qualification at `fb502f612da6e87184e3025fdb379ba02fac1aab` | Historical **606-case** result. Its original runner, receipt and controls remain preserved. |
| First integrated qualification at `e19783792ef09744f0ec4b3403b44570dd7f6922` | Historical **1,533 unique cases**, 99 Node repeats and five Python controls. Its independent audit remains unchanged. |
| First execution at final source `7fd2030f` | Externally interrupted during Node startup, before a terminal receipt. Node logs were empty. The interruption record and original partial logs remain preserved; no final count is taken from this attempt. |
| Completed retry `qualified-canonical-7fd2030f-r2` | Sole source of the **1,543 / 99 repeat / five Python** final results above. Same frozen product source and runner as the interrupted attempt. |

Early writable-temporary-directory setup failures, initial probe construction
errors, negative controls and precise lint/probe corrections remain recorded.
The three original extraction-test interpolation changes retain final-byte
negative and positive reruns. The first independent audit's `file:`-only URL
assumption was corrected to resolve legitimate Flutter `package:` source URLs
through the frozen graph; both reviewer attempts and the rationale are retained.
No product test was changed for that reviewer correction.

## Evidence and reproduction

The [executed runner](run_validation.py), [qualification receipt](qualification.json),
[independent review](independent-review.json), [evidence archive](evidence.tar.xz)
and [complete member index](evidence-index.json) bind the commands, raw logs,
source maps, locked inputs, control snapshots, bounded merge decisions and
preserved attempts. The archive index identifies exact members, sizes and
SHA-256 values. Its readback verification is separate from product execution.
Transient compiler caches and reconstructible isolated control checkouts are
not required to preserve the underlying evidence.

To reproduce, use a clean checkout at the accepted source and restore the
archived pinned SDK/cache, Node/Python runtimes and canonical locked graph.
Preserve the production manifests and the 110-package resolution; relocate
only local path references as documented in the setup evidence and resolve
offline with `--enforce-lockfile`. Put the pinned Node executable on `PATH`.
Then run the archived runner with a fresh output directory:

```sh
python3 run_validation.py --kind canonical \
  --repo /path/to/quds --harness /path/to/quds \
  --sdk /path/to/flutter-sdk --cache /path/to/pub-cache \
  --expected-head 7fd2030fd39a2b0bbdb1b1e778840c332ae6bbc3 \
  --baseline 7a9702c3b74e0e905c76fcf467d608bbb852d004 \
  --output /path/to/new-evidence-directory
```

The runner refuses existing output directories and uncommitted program inputs,
checks actual test/source routing, authenticates the two exact schema blobs,
and verifies all recorded inputs after execution. The archived independent
reviewer can recount logs without running product tests. The control
reconstruction script reproduces the recorded tab/column library inputs from
retained ancestors and archived writer snapshots.

Publication is documented by [source-equivalence.json](source-equivalence.json)
and [verify_delivery.py](verify_delivery.py): documentation/evidence checkpoints
must preserve every non-documentation Git blob and mode of the qualified source.
The dedicated branch isolates this result from continued shared-branch work;
updates use the observed destination head and do not overwrite concurrent work.

## Coverage limits

This final qualification covers the selected local engine, editor, proofing,
AOT and Studio unit/widget behavior, with separately recorded host service and
menu/export widget acceptance. It does not constitute fresh live
Word/LibreOffice/Zotero interoperability, operating-system export-dialog or
cloud-transport acceptance, native proofing/model quality, Wasm acceptance, or
the complete application/viewer test surface. Incoming live-consumer and model
reports retain their original source attribution. The header/footer repair
covers default modeled stories; first/even-page and opaque preserved story
variants were not expanded.

Commit messages retain `[skip ci]`. No GitHub Actions, workflow, check-run or
CI-status endpoint was queried or awaited.
