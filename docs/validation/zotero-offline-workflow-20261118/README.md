# Stored Zotero reference details and selection feedback

## Completed result

[PR #165](https://github.com/CrispStrobe/quds_office_suite/pull/165) adds stored
reference details throughout the references workspace and explains the imported
selection limit. It is stacked on the completed
[PR #164](https://github.com/CrispStrobe/quds_office_suite/pull/164), whose entire
combined history remains in this branch.

Qualified integration commit:
**`02da86d9ba82f5d14dc04a3759c247064bcd6a25`**.
Implementation checkpoint: `3ad7c8b6e14ae09985bb58c9c7ce8a25277e056a`.
The integration adds only the subsequently observed document-review audit file;
product and test inputs are identical to the implementation checkpoint.
Later report and evidence commits do not change those inputs.

Branch: `codex/zotero-offline-workflow-20261118`.

## User-visible behavior

- **Stored reference details** is available beside imported results and inside
  **Review selected**. It displays full titles, all supplied CSL creator roles,
  publication/date fields, identifiers, source URI aliases and abstracts.
- **Copy details** copies the readable summary. Fields remain individually
  selectable; a clipboard failure reports a manual-copy fallback and permits
  retry. Closing during a pending copy safely returns to the parent workspace.
- Inspection works offline and in read-only documents. It makes no request,
  launches no stored URL and changes no source, selection or document history.
- Duplicate imported IDs remain separate records. Hidden and mixed-library
  selections retain their identities. Nested details preserve staged reordering
  and removals until **Apply selection** or **Cancel** resolves that review.
- A refused 21st imported selection now explains the 20-source citation limit.
  The limit counts selected references across tabs and filters; deselection
  remains available at the limit.
- Actions wrap in narrow selection reviews. The full import, details, clipboard
  failure/retry and nested-review flows pass at 320 × 480 with doubled text in
  both left-to-right and right-to-left layouts.

Missing or malformed optional metadata is omitted; absent CSL snapshots remain
inspectable by their retained identity. Abstracts preserve literal scientific
comparisons and markup. Citation locators and affixes are not reference fields.
Unknown CSL fields remain available through the existing stored-JSON export.

See the [user guide](../../zotero-support.md#inspect-references-and-manage-a-selection).

## Fresh local validation

| Cohort or check | Result |
| --- | ---: |
| Complete editor Zotero cohort | **299 passes across 22 suites** |
| New presenter cases, included above | 10 |
| New dialog cases, included above | 11 |
| Failed / skipped / error events | 0 / 0 / 0 |
| Actual Flutter process exit | 0 |
| Strict analyzer targets | 5, no issues |
| Formatter targets | 5, zero changes |
| Source inputs bound to the saved commit | 554 |

All 321 machine test starts finish exactly once. The total excludes 22 hidden
loading/lifecycle events and 22 Flutter process notifications. No overflow or
missed-tap diagnostic is present. A separate read of the saved raw stream
independently confirms the 299 substantive successful completions.

All source, dependency, runtime and workspace before/after guards pass. The
source Git blob identities match the qualified integration commit; the exact
suite set was executed. The runtime is genuine Flutter 3.47.8 / Dart 3.13.7 with
162 verified hosted archives, 11 unchanged manifests and the enforced
110-package workspace graph. The cohort fingerprint covers 41 external
reachable dependencies, nine runtime files and 14 workspace inputs.

This increment changes only editor code and tests. Engine, Studio, document
comparison and spelling cohorts were not rerun; their historical results stay
bound to the previous reports and are not added to this total. Current testing
covers real Flutter widgets and controlled transports/clipboard channels. It
does not constitute a new installed-app, live Zotero account or Word/LibreOffice
interoperability acceptance run.

## Incoming work and remote checkpoints

The initial fresh inventory confirmed the previous 373-ref reconciliation was
unchanged. The final fixed snapshot closed on **18 November 2026 at 15:50:48
Europe/Berlin (14:50:48 UTC)**. It captures 377 refs, including this new branch
and PR #165. Excluding those two leaves **375 incoming refs / 241 distinct heads**.

| Final classification | Refs |
| --- | ---: |
| Exact ancestors of the qualified integration | 347 |
| Unchanged historical equivalent/no-op refs | 10 |
| Unchanged historical refs previously landed through reconciled PRs | 18 |
| Unaccounted refs | **0** |

Every distinct incoming head received a local ancestry check. The historical
exceptions retain the exact prior names, SHAs and classifications.

The final refresh observed document-review branch/PR #162 at
`e9dc92798d1c39ac48474d0aa5af7321e75e6bb0`, a child of the existing baseline that
adds only `docs/validation/document-review-live-20261118/incoming-audit.json`.
The ordinary two-parent merge `02da86d9` preserves this head and our
implementation. The spelling branch advanced to the already-included baseline
`fb1fd4dc`; main stayed `f383c826`. This is a fixed observation cutoff and makes
no claim about later concurrent commits.

| Remote checkpoint | Purpose |
| --- | --- |
| `c1922005` | Saved the initial incoming inventory |
| `3ad7c8b6` | Saved implementation, 21 new regressions and user documentation |
| `02da86d9` | Preserved the later document-review audit history |

Updates are non-forced and use the expected branch head. Checkpoint messages
carry `[skip ci]`. No GitHub Actions, workflow, check or CI-status endpoint was
queried, awaited, dispatched or rerun. PR #165 targets the #164 branch so the
new code can be reviewed separately; merge #164 before retargeting #165 to main.

## Evidence and reproduction

- [Final run summary](editor/summary.json): exact commands, check output, process
  exit, per-suite results, timing and every guard.
- [Raw machine events](editor/events.jsonl.gz) and [input fingerprints](editor/inputs.json.gz).
- [Executed runner](editor/run_editor_zotero.py), with arguments for another
  checkout, prepared workspace, toolchain and fresh output directory.
- [Initial inventory](reconciliation-initial.json), [final inventory and ancestry
  binding](reconciliation-final.json), and [independent interaction review](independent-review.md).
- [Runtime setup and receipts](runtime/README.md).
- [Retained development attempts](development/README.md), excluded from the final total.
- [Artifact index](index.json) records the bytes, SHA-256 and Git blob identity
  of the saved evidence files.

After restoring the genuine runtime and locked workspace described in the
runtime notes, reproduce the same checks with:

```sh
python /path/to/run_editor_zotero.py \
  --repo /path/to/quds_office_suite \
  --workspace /path/to/zotero-validation \
  --toolchain /path/to/zotero-toolchain \
  --output /path/to/fresh-editor-results
```

The runner selects every `packages/quds_office_editor/test/word_zotero*_test.dart`
suite, requires both new suites, and analyzes/formats exactly the five changed
Dart targets. It refuses an existing output directory to preserve earlier logs.
