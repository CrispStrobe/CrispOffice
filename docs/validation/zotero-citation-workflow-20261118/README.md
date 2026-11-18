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

## Local validation status

Zotero integration source: **`3668ed92829dfa012ec5b129943a86738ebb7992`**.
All **348 editor Zotero tests across 26 suites pass**, including **49 new cases**
counted once. Actual Flutter exit is zero. Strict analysis and formatting pass
for all eight Zotero Dart targets. All 374 machine starts finish once; 26
loading/lifecycle cases and Flutter notifications are excluded from the total.
There are no skips, failures, error events or overflow/missed-tap diagnostics.

All **562** recorded source inputs match the committed integration. Source,
dependency, runtime and workspace before/after guards pass. The runtime is
genuine Flutter 3.47.8 / Dart 3.13.7, with 162 SHA-256-verified hosted archives,
11 unchanged manifests and the exact locked 110-package graph.

The separately selected incoming review/proofing cohort is undergoing its final
rerun after two test-only repairs. Its first 18-suite attempt is retained under
[incoming/attempt-1](incoming/attempt-1/summary.json): 262 passed, seven failed,
zero skipped, actual process exit one. Six failures came from a helper trying
to tap controls retained inside a collapsed filter tile. The seventh expected
a temporary null selection that the new incremental proofing no longer needs.
The repairs require real hit-testable interaction and verify immediate current
revision/paragraph/caret binding while retaining rejection of the stale issue.
No product implementation was changed to repair those tests. That unsuccessful
attempt contributes nothing to the final passing count.

The report will be updated with the completed incoming result and a final
source/evidence binding before the PR is marked ready. Passing development
runs overlap the final Zotero cohort and are not added to its count.

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

Checkpoint updates are non-forced and require the expected remote branch head.
Every checkpoint message carries `[skip ci]`. No GitHub Actions, workflow,
check or CI-status endpoint was queried, awaited, dispatched or rerun.

## Evidence and reproduction

- [Zotero machine summary](editor/summary.json), [raw events](editor/events.jsonl.gz)
  and [input fingerprints](editor/inputs.json.gz).
- [Executed Zotero runner](editor/run_editor_zotero.py), selecting all
  `word_zotero*_test.dart` suites and requiring the four new suites.
- [Incoming selection and controls](incoming/plan.md),
  [incoming runner](incoming/run_incoming_editor.py), and
  [retained first-run diagnosis](incoming/first-run.md).
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

The incoming runner additionally requires `--source-commit` for its frozen
qualification source. Both runners preserve existing output directories,
capture actual process exits and raw events, require complete suite/start/end
accounting, and guard source, dependency, runtime and workspace inputs.

This is real Flutter editor/controller qualification with controlled transport
and clipboard channels. Engine and Studio product code are unchanged by this
increment and their older results are not added here. No new installed-device,
live-account, full application build or Word/LibreOffice interoperability
acceptance is claimed.
