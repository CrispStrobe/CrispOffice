# Reuse cited Zotero references and edit citation source lists

[PR #166](https://github.com/CrispStrobe/quds_office_suite/pull/166) continues the
Word/LibreOffice-style citation workflow on
`codex/zotero-citation-workflow-20261118`. The PR is stacked on #162, whose
history already contains the earlier Zotero increments #164 and #165.

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

## Completed local validation

Qualified final source: **`40e92e5222a26db132f8be05126df285b4227a86`**.
The [independent evidence audit](qualification-audit.md) verifies the two
completed local runs against this source and independently recounts their raw
events. Their suite sets are disjoint.

| Accepted cohort | Suites | Passed | Failed / skipped | Actual process exit |
| --- | ---: | ---: | ---: | ---: |
| Complete editor Zotero | 26 | 348 | 0 / 0 | 0 |
| Incoming editor review and proofing | 18 | 269 | 0 / 0 | 0 |
| **Disjoint total** | **44** | **617** | **0 / 0** | |

The **49 new Zotero cases** are included once in the 348. All 374 Zotero and
297 incoming machine starts finish exactly once. The totals exclude 26 Zotero
and 28 incoming loading/lifecycle cases, plus Flutter process notifications.
Both final streams end successfully with zero error events, parse failures,
overflow or missed-tap diagnostics. Strict analysis and nonmutating formatting
pass all **15 distinct Dart targets**: eight Zotero and seven incoming.

The complete Zotero run executed on integration
`3668ed92829dfa012ec5b129943a86738ebb7992`. All **562** of its recorded source
inputs also match the final source. The incoming run executed on
`40e92e5222a26db132f8be05126df285b4227a86` and records **550** source inputs.
Their union contains **581 distinct paths**, all matching the final Git tree;
shared records agree. Product code has not changed since the Zotero run.
The later source changes only repair two incoming review test expectations and
interaction helpers, which the final incoming cohort exercises.

Source, dependency, runtime and workspace before/after guards pass. Executed
runner and artifact hashes match the receipts. The runtime is genuine Flutter
3.47.8 / Dart 3.13.7, with 162 SHA-256-verified hosted archives, 11 unchanged
manifests and the exact locked 110-package graph. The incoming inventory also
records the SDK's MaterialIcons font; the shared executable, dependency and
workspace identities agree between runs.

### Retained attempts and test repairs

Two earlier full incoming runs failed and remain available in
[attempt 1](incoming/attempt-1/summary.json) and
[attempt 2](incoming/attempt-2/summary.json), with their exact runners, raw
events and input fingerprints. Neither contributes to the passing total.
The first recorded 262 passes and seven failures; the second recorded 261
passes and eight failures. Both exited with code one.

The incoming incremental proofing now rebinds a selected issue immediately when
another paragraph changes. Its test now verifies the current revision, correct
paragraph and stable caret, while retaining rejection of the stale issue.
The filter test helper now opens a collapsed tile through its visible header,
starts and advances the expansion animation, and requires hit-testable controls
before each real tap. It reads expansion state but never forces the controller
open. The filter suite retains every case and assertion; only the selection
expectation changes as described above. No product code was changed to repair
these tests. The final affected suites pass 9/9 and 13/13 respectively.

Focused [helper development](incoming/development/README.md) preserves both the
failed intermediate attempt and the successful 13-case attempt. Earlier
[Zotero development](development/README.md), all focused runs, historical
results and source review are excluded from the final acceptance totals.

## Incoming work and saved checkpoints

The final fixed incoming snapshot closed on **18 November 2026 at 17:03:14
Europe/Berlin (16:03:14 UTC)**. It accounts for **377 incoming refs / 244 distinct
heads**: 204 fork branches, 165 fork PR heads, four upstream branches and four
upstream PR heads. Our output branch and later PR #166 are excluded.

| Classification | Refs |
| --- | ---: |
| Exact ancestors of the integration | 349 |
| Verified historical equivalents | 28 |
| Unaccounted | **0** |

The initial base includes #164 and #165, native spelling and the prior live
review implementation. The subsequent merge preserves the newly observed
review head `58058b1b` and main `60be935c`. All ten incoming changed files are
preserved: seven exact byte identities and three exact outputs of Dart's
formatter. The [fixed final audit](reconciliation-final.md) explains the
ancestry, historical equivalence proofs and manifest/lock checks. It makes no
claim about later concurrent remote activity.

| Remote checkpoint | Purpose |
| --- | --- |
| `ee88b8f8` | Initial reconciliation, runtime recovery and cited-source selection |
| `d0598533` | Complete Zotero implementation, 49 regressions and user guide |
| `3668ed92` | Three-parent merge of new review/main work and formatting normalization |
| `00ac2edf` | Complete Zotero evidence, independent source review and initial incoming test repairs |
| `40e92e52` | Final incoming helper repair and preserved failed/focused evidence; qualified source |

The final evidence checkpoint adds the passing incoming run, independent
qualification audit, this report and the artifact index. It changes no product
or test source. The commit containing this report identifies that evidence
checkpoint; the tested source remains the explicit commit above.

Checkpoint updates are non-forced and require the expected remote branch head.
Every checkpoint message carries `[skip ci]`. No GitHub Actions, workflow,
check or CI-status endpoint was queried, awaited, dispatched or rerun.

## Evidence and reproduction

- [Zotero machine summary](editor/summary.json), [raw events](editor/events.jsonl.gz)
  and [input fingerprints](editor/inputs.json.gz).
- [Incoming machine summary](incoming/editor/summary.json),
  [raw events](incoming/editor/events.jsonl.gz),
  [input fingerprints](incoming/editor/inputs.json.gz) and
  [runner output](incoming/runner.log).
- [Independent qualification audit](qualification-audit.md), its
  [machine-readable checks](qualification-audit.json),
  [completed status](status.json) and [artifact index](index.json).
- [Executed Zotero runner](editor/run_editor_zotero.py), selecting all
  `word_zotero*_test.dart` suites and requiring the four new suites.
- [Incoming selection and controls](incoming/plan.md),
  [incoming runner](incoming/run_incoming_editor.py),
  [first-run diagnosis](incoming/first-run.md) and
  [second-run diagnosis](incoming/second-run.md).
- [Runtime recovery](runtime/README.md) and verified setup bundle.
- [Independent review](independent-review.md), including the resolved error
  boundaries for oversized alias catalogs and oversized combined citations.
- [Development attempts](development/README.md), preserved separately and
  excluded from final qualification counts.
- [Initial reconciliation](reconciliation-initial.json),
  [later incoming snapshot](reconciliation-prevalidation.json), and
  [final integration binding](reconciliation-final.json).

After restoring the documented runtime, run the Zotero cohort from the task
root with a fresh output directory:

```sh
python quds_office_suite/docs/validation/zotero-citation-workflow-20261118/editor/run_editor_zotero.py \
  --output fresh-zotero-results
```

The incoming runner additionally requires
`--source-commit 40e92e5222a26db132f8be05126df285b4227a86` for its frozen
qualification source. Both runners preserve existing output directories,
capture actual process exits and raw events, require complete suite/start/end
accounting, and guard source, dependency, runtime and workspace inputs.

This is real Flutter editor/controller qualification with controlled transport
and clipboard channels. Engine and Studio product code are unchanged by this
increment and their older results are not added here. No new installed-device,
live-account, full application build or Word/LibreOffice interoperability
acceptance is claimed.
