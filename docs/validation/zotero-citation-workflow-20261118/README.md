# Reuse cited Zotero references and edit citation source lists

[PR #166](https://github.com/CrispStrobe/quds_office_suite/pull/166) added the
Word/LibreOffice-style citation workflow on
`codex/zotero-citation-workflow-20261118`. Its implementation was merged into
the active document-review branch in `40790cb2` while local validation was
running. That branch is reviewed in #162 and already contains #164 and #165.

The completed follow-up integrates the fixed review head `ecbb1e0b`, retains
both sides of one selection-test conflict, and saves fresh qualification on
combined source **`8002b6748deec2be7b7527d2bab8810d8ec54d05`**. Relative to that
review base, the follow-up changes two review regression tests and validation
documentation/evidence. Incoming product files remain byte-identical to the
captured base, and all Zotero source/test paths retain the implementation from
PR #166.

## Implemented behavior

- **Document → Cited references…** searches stored document sources by title,
  creator, year and DOI. It shows occurrence counts, stored details and explicit
  missing-metadata labels, without network requests.
- Selection is staged across filters and joins selections from Library and
  Import. Document offers selection review, stored CSL copying, basic insertion
  and, for linked selections in native hosts, insertion with Zotero.
- Declared, validated URI aliases identify repeated linked sources. Equal IDs
  or item keys from unrelated libraries remain separate. Distinct offline
  snapshots remain separate even when their CSL IDs match. The first available
  snapshot and all declared aliases are retained.
- Reusing a source resets the earlier citation's locator, label, prefix, suffix,
  author mode and processor-position options. It preserves the source metadata
  and leaves the original citation unchanged.
- The citation composer can add, remove, reorder and inspect sources. Stable
  occurrence keys preserve entered options, including for duplicate IDs. The
  local source chooser searches cited references, current selections and loaded
  imports; filtering retains staged selections and starts at the first result.
- A citation must contain at least one source. Additions are limited to 20;
  larger imported clusters retain all their existing sources for editing.
- Basic text follows the source list. Changing source membership/order in custom
  mode requires editing or explicitly reviewing the visible text, and discards
  the former processor-specific formatted cache. A style preview always uses
  the current validated singleton.
- Cancellation, preview failure and metadata-size errors preserve the draft.
  Stale document/caret results are rejected. Applying a citation remains one
  undoable operation, with metadata retained through DOCX save/reopen.

Inspection and copying remain available in read-only documents and with Track
changes enabled; insertion is gated separately. New flows have local widget
coverage at 320 × 480 with doubled text in both LTR and RTL layouts.

See the [user guide](../../zotero-support.md#cite-a-stored-document-reference-again)
for the complete flow and its distinction from native document-wide CSL
formatting. These additions complement the existing Zotero desktop picker,
style, bibliography and refresh integration.

## Completed local qualification

Both fresh runs executed on **`8002b6748deec2be7b7527d2bab8810d8ec54d05`**.
The [independent audit](post-merge/qualification-audit.md) checks their raw event
streams, actual process exits, complete start/end accounting, source identities,
static targets and runtime/dependency/workspace guards.

| Accepted final cohort | Suites | Passed | Failed / skipped | Actual process exit |
| --- | ---: | ---: | ---: | ---: |
| Complete editor Zotero | 26 | 348 | 0 / 0 | 0 |
| Incoming editor review and proofing | 20 | 278 | 0 / 0 | 0 |
| **Disjoint total** | **46** | **626** | **0 / 0** | |

The **49 new Zotero cases** are included once in the 348. All 374 Zotero and
310 incoming machine starts finish exactly once. The totals exclude 26 Zotero
and 32 incoming loading/lifecycle cases, plus Flutter process notifications.
Both final streams end successfully with zero error events, parse failures,
overflow or missed-tap diagnostics. Strict analysis and nonmutating formatting
pass all **17 distinct Dart targets**: eight Zotero and nine incoming.

All **562 Zotero** and **552 incoming** recorded source inputs match the frozen
merge. Their union contains **583 distinct paths**, with agreeing shared
records. Source, dependency, runtime and workspace before/after guards pass;
both runs start and finish at the exact frozen commit. Executed runner and
artifact hashes match the receipts.

The runtime is genuine Flutter 3.47.8 / Dart 3.13.7, with 162 SHA-256-verified
hosted archives, 11 unchanged manifests and the exact locked 110-package graph.
The incoming inventory also records the SDK's MaterialIcons font. Shared
executable, dependency and workspace identities agree between runs.

The expanded incoming selection retains the original 18 suites and adds
`word_incremental_proofing_menu_test.dart` and
`word_proofing_capture_cache_test.dart`. It also exercises the additional
review cases incorporated from the base. No historical result is added to this
fresh total.

## Earlier results and retained repairs

The first complete qualification passed **617 tests across 44 suites**, bound
to `40e92e52` and saved at `82224f23`. Its [independent audit](qualification-audit.md),
[Zotero summary](editor/summary.json) and
[incoming summary](incoming/editor/summary.json) remain unchanged. Because the
captured review base subsequently changed editor product code, both full
cohorts were rerun on the combined source. The earlier 617 is excluded from the
626 above.

Two earlier full incoming attempts also remain available:
[attempt 1](incoming/attempt-1/summary.json) recorded 262 passes and seven
failures; [attempt 2](incoming/attempt-2/summary.json) recorded 261 passes and
eight failures. Both exited one and contribute nothing to current acceptance.

The selected-issue test now checks immediate rebinding at the current revision,
unchanged finding text/span, the correct paragraph, stable caret and rejection
of the stale issue. The filter helper opens the visible header, starts and
advances its expansion animation, and requires real hit-testable controls.
It reads public expansion state without forcing the controller open. The final
merge retains both branches' assertions and all incoming cases; no product
behavior was changed to repair tests.

Focused [helper development](incoming/development/README.md) and earlier
[Zotero development](development/README.md) preserve unsuccessful and successful
attempts separately. All focused runs, historical engine/Studio/spelling results,
static preflight and source-review-only work are excluded from current test
counts.

## Incoming work and saved checkpoints

The original fixed incoming snapshot closed on **18 November 2026 at 17:03:14
Europe/Berlin (16:03:14 UTC)**. It accounts for **377 incoming refs / 244 distinct
heads**: 204 fork branches, 165 fork PR heads, four upstream branches and four
upstream PR heads. Our output branch and later PR #166 are excluded.

| Classification | Refs |
| --- | ---: |
| Exact ancestors of the integration | 349 |
| Verified historical equivalents | 28 |
| Unaccounted | **0** |

The [original final audit](reconciliation-final.md) preserves the ancestry,
historical-equivalence proofs and manifest/lock checks. A targeted delivery
check then found PR #166 merged into document-review at **17:17 Europe/Berlin**.
The [post-merge reconciliation](post-merge/reconciliation.md) records the fixed
`ecbb1e0b` base, main `556c55c0`, both merge parents, exact incoming-product
preservation and the combined test assertions. It locally rechecks the original
377-ref inventory against the new merge. It makes no claim to inventory later
concurrent remote activity.

| Remote checkpoint | Purpose |
| --- | --- |
| `ee88b8f8` | Initial reconciliation, runtime recovery and cited-source selection |
| `d0598533` | Complete Zotero implementation, 49 regressions and user guide |
| `3668ed92` | Three-parent merge of incoming review/main and formatting normalization |
| `00ac2edf` | Complete Zotero evidence, source review and initial incoming test repairs |
| `40e92e52` | Incoming helper repair and preserved attempts; pre-merge qualified source |
| `82224f23` | Audited historical 617-test evidence and complete artifact index |
| `8002b674` | Fixed newer review base integrated; both test assertion sets retained; freshly qualified source |

Final evidence checkpoints add the two fresh passing runs, the independent
qualification audit, targeted reconciliation and this report. They change no
product or test source after `8002b674`. The commit containing this report
identifies the evidence checkpoint.

Checkpoint updates are non-forced and require the expected remote branch head.
Every checkpoint message carries `[skip ci]`. No GitHub Actions, workflow,
check or CI-status endpoint was queried, awaited, dispatched or rerun.

## Evidence and reproduction

- Fresh Zotero [summary](post-merge/zotero-editor/summary.json),
  [raw events](post-merge/zotero-editor/events.jsonl.gz),
  [input fingerprints](post-merge/zotero-editor/inputs.json.gz) and
  [runner output](post-merge/zotero-runner.log).
- Fresh incoming [summary](post-merge/incoming-editor/summary.json),
  [raw events](post-merge/incoming-editor/events.jsonl.gz),
  [input fingerprints](post-merge/incoming-editor/inputs.json.gz) and
  [runner output](post-merge/incoming-runner.log).
- [Final independent audit](post-merge/qualification-audit.md), its
  [machine-readable checks](post-merge/qualification-audit.json),
  [completed status](status.json) and [artifact index](index.json).
- [Executed Zotero runner](editor/run_editor_zotero.py), selecting all
  `word_zotero*_test.dart` suites and requiring the four new suites.
- [Executed 20-suite incoming runner](post-merge/run_incoming_editor.py),
  [selection and controls](post-merge/plan.md),
  [merge review](post-merge/merge-review.md) and
  [static preflight](post-merge/static-preflight.json).
- [Runtime recovery](runtime/README.md) and verified setup bundle.
- [Original independent source review](independent-review.md), including
  recoverable oversized alias-catalog and combined-citation error boundaries.
- [First failed-run diagnosis](incoming/first-run.md),
  [second failed-run diagnosis](incoming/second-run.md) and historical raw
  evidence retained alongside them.
- [Initial reconciliation](reconciliation-initial.json),
  [later incoming snapshot](reconciliation-prevalidation.json),
  [original integration binding](reconciliation-final.json) and
  [targeted post-merge binding](post-merge/reconciliation.json).

After restoring the documented runtime, run from the task root with fresh
output directories:

```sh
python quds_office_suite/docs/validation/zotero-citation-workflow-20261118/editor/run_editor_zotero.py \
  --output fresh-zotero-results
python quds_office_suite/docs/validation/zotero-citation-workflow-20261118/post-merge/run_incoming_editor.py \
  --source-commit 8002b6748deec2be7b7527d2bab8810d8ec54d05 \
  --output fresh-incoming-results
```

Both runners preserve existing output directories, capture actual process exits
and raw events, require complete suite/start/end accounting, and guard source,
dependency, runtime and workspace inputs. The incoming runner requires a
checkout whose product/test bytes still match the specified frozen source.

This is real Flutter editor/controller qualification with controlled transport
and clipboard channels. Engine and Studio product code are unchanged by this
increment and their older results are not added here. No new installed-device,
live-account, full application build or Word/LibreOffice interoperability
acceptance is claimed.
