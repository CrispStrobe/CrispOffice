# Zotero import search and stored-reference copying

## Qualified result

Product source: **`b2bcfc23e692476d16d9a7a534ea95a93ae94cd3`**.
Delivery branch: **`codex/zotero-continuation-20261118`**.
Pull request: [#164](https://github.com/CrispStrobe/quds_office_suite/pull/164).

All **1,409 substantive tests across 74 distinct suites pass**, with zero skips
or errors. This includes the complete **741-test Zotero cohort** and fresh local
checks of the incoming comparison, review and spelling changes. A separate
48-case Dart VM panel also passes and is excluded from the test total.
Later commits add evidence and documentation only.

[Machine-readable status](status.json) · [Source bindings](source-commit-binding.json)
· [Evidence index](index.json) · [Independent review](independent-review.md)

## User-visible changes

### Search a large CSL import locally

After loading CSL JSON, search immediately across titles, creator names, years
and DOIs. Every whitespace-separated term must match; punctuation is literal
and matching ignores case. Creator/year labels, match counts and the count of
selected references outside the current results help identify sources.

Filtering preserves selection order and hidden selections. Original import
indices remain part of each selection key, so repeated IDs or titles cannot
silently select a different record. **Review selected** still reorders or
removes sources across filters. A successful reload resets the search and
replaces only imported selections; failed imports retain the earlier state.
The existing 1 MB / 500-record import and 20-source selection limits remain.

### Copy the current selection without a connection

**Copy stored CSL JSON** is available in Import and the Library export menu.
It copies stored snapshots from offline, personal, group or local Zotero
references in their reviewed order, including hidden sources. It retains
unknown metadata and URI aliases, makes no network request, and does not change
the document or its history. The output can be pasted into the existing import.

Repeated records and IDs are retained. Citation-specific locators and affixes
are not reference metadata. Missing/malformed snapshots or output exceeding the
1 MB import limit stop the complete copy with an explanation. Clipboard failure
leaves selections intact and permits retry. Connected export choices continue
to use their existing library checks and transport.

### Keep the workspace usable with enlarged text

Import uses naturally sized scrolling content with bounded paste and result
areas. Library height reservations account for text scaling. The heading has a
two-line display bound; status/error/read-only messages retain their full text
inside a bounded scroll area. The full import/search/select/copy path passes at
320 × 480 pixels with doubled text, and at 320 × 640 with normal text. Final
cohorts contain no overflow or missed-tap diagnostics.

The [user guide](../../zotero-support.md#search-imported-references-and-copy-stored-data)
and editor changelog describe these workflows.

## Recovery and incoming work

The prior interrupted Zotero increment was already completely saved at
`acfa3c2b` and merged as **PR #161**. Its 720-test report remains separately
preserved under [zotero-workspace-20261118](../zotero-workspace-20261118/README.md).
PR #160 was the spelling continuation; no missing Zotero PR was recreated.

The [initial audit](RECONCILIATION.md) covered 372 incoming refs. The
[final fixed snapshot](reconciliation-final.md) covers **373 refs / 241 distinct
heads**: 345 exact-ancestor refs, ten unchanged historical equivalent/no-op refs,
and 18 unchanged historically landed refs. No observed head is unaccounted for.
The unchanged historical mappings retain their earlier evidence; this report
does not claim to have repeated those old trial merges.

The branch includes main `f383c826`, the golden-path fix `ca42a7fa`, the final
document-review head `3840e19f`, and the incoming spelling head `f482b06f`.
That spelling head appeared during this turn and was only an implementation
checkpoint at the recorded cutoff. Its development counts were not accepted
as combined validation: the affected code was checked locally here. The only
merge conflict was in the editor changelog; both sets of entries were retained.
All nine incoming production/test/tool blobs match their recorded source head.

## Accepted local checks

| Cohort | Suites | Passed | Skips / errors |
| --- | ---: | ---: | ---: |
| Engine Zotero | 22 | 445 | 0 |
| Editor Zotero | 20 | 278 | 0 |
| Studio Zotero transport | 1 | 18 | 0 |
| **Zotero subtotal** | **43** | **741** | **0** |
| Incoming engine comparison | 2 | 39 | 0 |
| Incoming editor review | 2 | 31 | 0 |
| Incoming Studio comparison/parser | 1 | 8 | 0 |
| Incoming German spelling/normalization consumers | 19 | 526 | 0 |
| Incoming native-provider/Word spelling | 7 | 64 | 0 |
| **Disjoint total** | **74** | **1,409** | **0** |

The Zotero subtotal includes **21 new cases once**: eleven stored-CSL snapshot
tests and ten imported-reference tests. They cover duplicate IDs, original
selection keys, cross-filter review/order, 500-record imports, Unicode queries,
failed/successful reloads, preserved catalog selections, mixed/offline copying
in read-only mode, unknown nested metadata, URI aliases, byte/count limits,
clipboard retry and closing a route during an outstanding clipboard operation.

All actual test processes exit zero. Every selected suite executes and every
started event finishes once. Source, dependency/runtime and workspace guards
pass. The [binding verifier](verify.py) confirms that **701 unique recorded
inputs** match the qualified product's Git blobs and that selected suites do
not overlap. Strict fatal-info analysis, Dart 3.12 formatting and whitespace
checks pass for all **18 targets** in [checks/summary.json](checks/summary.json).

The incoming spelling panel passes **48/48 cases on Dart VM**. It is neither an
extra test suite nor an AOT/JavaScript qualification. Seven Linux golden helper
routes were checked against their existing image files and Git blobs; no golden
images were rendered or changed. See [incoming checks](incoming/README.md) and
[spelling qualification](incoming/spelling/README.md).

## Runtime and reproduction

The [runtime receipt](runtime/runtime-ready.json) records genuine Flutter
**3.47.8** / Dart **3.13.7**, the verified official SDK archive, matching runtime
executables, 162 hash-verified hosted package archives, 11 unchanged manifests
and the 110-package graph. Both offline enforced-lockfile resolutions succeeded
without changing the workspace or Flutter-tools locks. Setup scripts and logs
are retained in [runtime/setup.tar.gz](runtime/setup.tar.gz), with its index.

Each cohort's `run.json` / `summary.json` records the exact command, cwd and
actual process exit. Zotero uses the retained engine and Flutter cohort runners
under `../zotero-workspace-20261118/`; incoming runners are retained alongside
their results. Use a fresh output directory when reproducing a test run.
Paths in the original setup receipts identify this execution workspace and
must be adjusted when restoring on another machine.

To verify the saved results and source bindings without executing tests:

```bash
python docs/validation/zotero-continuation-20261118/verify.py
```

## Preserved attempts and receipt correction

Development attempts are retained in [development](development/README.md).
They exposed the real enlarged-text layout failures before the final complete
run. An ambiguous search fixture, a pending-focus-scroll test helper, an
oversized snapshot fixture and a test-only null-aware-element lint were also
corrected. No warning or test assertion was disabled. Earlier complete cohorts
and pre-frontier checks remain under `attempts/` and are excluded from totals.

The incoming spelling engine test process passed all 526 cases, but its wrapper
initially resolved relative suite paths against the repository directory. The
derived suite-coverage guard was corrected using the immutable raw stream and
the recorded test cwd. The original summary, executed runner and explicit
[correction receipt](incoming/spelling/engine/suite-path-correction.json) remain
available. No product edit or test rerun was needed for that correction.

## Remote checkpoints and limits

Changes were saved incrementally with verified tree identities, non-forced
expected-head updates and `[skip ci]`:

| Commit | Saved checkpoint |
| --- | --- |
| `80168fd5` | Reconcile current main, review and golden-helper histories |
| `805414d7` | Initial import search and stored-snapshot implementation |
| `6d19f988` | Initial ref audit and user guidance |
| `604fa004` | Preserve newer main with an identical product tree |
| `df7265b8` | First engine/incoming checks and runtime receipts |
| `6aa6ffb5` | Complete interaction tests and accessible layouts |
| `0d549fde` | Final snapshot-test lint/formatting |
| `b2bcfc23` | Preserve the final observed spelling/comparison frontier |
| `d395de7c` | Save complete combined Zotero/comparison qualification |

Final delivery commits add this report, remaining evidence and its index.
No GitHub Actions, workflow, check or CI-status endpoint was queried, awaited,
dispatched or rerun. No dependency manifest or workflow was changed.

Acceptance covers controlled Zotero transports, real Flutter widgets, local
HTTP transport, synthetic document files and controlled native spelling-channel
responses. It does not claim a fresh live Zotero account/session, installed OS
dictionary or device behavior, full application build, or new Word/LibreOffice
interoperability acceptance. Existing historical acceptance retains its own
original scope and source identity.
