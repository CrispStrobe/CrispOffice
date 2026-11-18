# Incoming review/proofing qualification plan

This cohort qualifies the editor changes brought in from document-review head
`58058b1b750b3a71d0602af897eaa790400e878b` after the initial Zotero base. Incoming
main `60be935c98fae9035e717699cacc1c9a9096c47f` contributes documentation only.
The merge was clean. The incoming implementation changes three editor files
and three editor test files; it introduces no engine or Studio source change.

This file describes the selection and controls, not a passing result. Execution
starts only after the integrated source is committed and frozen. The full Zotero
cohort runs first. Both runners use the same `zotero-toolchain/flutter-cli.lock`.

## Selected suites

The prior 17-suite live-review editor cohort is retained except for its two
Zotero suites, which belong to the separate full Zotero run. Add the two new
incoming suites and the changed review-controller suite, producing **18 distinct
editor suites**:

| Group | Suites |
| --- | --- |
| Incoming changes | `word_incremental_proofing_test.dart`, `word_live_review_changes_test.dart`, `word_review_controller_test.dart` |
| Live review consumers | `word_live_proofing_session_test.dart`, `word_live_review_selection_test.dart`, `word_live_review_surface_test.dart`, `word_review_pane_test.dart` |
| Proofing consumers | `word_proofing_session_test.dart`, `word_manual_proofing_test.dart`, `word_proofing_dialog_test.dart`, `word_proofing_context_test.dart`, `word_proofing_geometry_test.dart`, `word_proofing_navigation_test.dart` |
| Change review and story consumers | `word_review_dialog_test.dart`, `word_revision_story_test.dart` |
| Editor interaction consumers | `word_input_focus_test.dart`, `office_input_ownership_test.dart`, `editor_test.dart` |

All paths are relative to `packages/quds_office_editor/test/`. The runner asserts
that every selected suite exists, contains no duplicate path, and is disjoint
from `word_zotero*_test.dart`. Prior runs, focused development tests, engine and
Studio cohorts are not added to this result.

## Static checks and formatting normalization

Strict analysis (`--fatal-infos --fatal-warnings`) and a nonmutating formatter
check cover these six incoming Dart files plus the repaired selection consumer
test, **seven targets** in the final run:

- `lib/src/embed/office_controller.dart`
- `lib/src/embed/word_review_pane.dart`
- `lib/src/proofing/word_proofing.dart`
- `test/word_incremental_proofing_test.dart`
- `test/word_live_review_changes_test.dart`
- `test/word_review_controller_test.dart`
- `test/word_live_review_selection_test.dart`

Paths are relative to `packages/quds_office_editor/`. The integration owner
normalized formatting only in `word_review_pane.dart`,
`word_incremental_proofing_test.dart` and `word_live_review_changes_test.dart`
before freezing the initial source. This runner makes no source, manifest, lock or
dependency changes. A subsequent analysis/formatting failure is retained and
reported for an explicit repair rather than silently changing inputs.

The first full run is retained in [attempt-1](attempt-1/) with its exact executed
six-target runner. It found seven failures, documented in
[first-run.md](first-run.md). After the guarded run finished, the integration
owner authorized two test-only repairs: the change-filter helper requires
hit-testable controls; the selection consumer now checks immediate
rebinding to the untouched paragraph/current revision, stable caret and rejection
of the stale original issue. Existing cases and later safety assertions remain.
Only these two tests were formatted. No product behavior was changed to make
the tests pass. The second full run, preserved in [attempt-2](attempt-2/),
confirmed the selection assertions but found eight helper failures while trying
to reveal a collapsed child before expanding its parent; see
[second-run.md](second-run.md). The corrected helper first reveals the filter
header, reads the public `Expansible.controller.isExpanded` state and taps that
header only when collapsed, then reveals and taps the dropdown. It never
changes expansion through the controller. A real tap now starts its transition
with an initial frame before the existing bounded duration drain. The final
focused development attempt passed all 13 cases; both development attempts are
[preserved separately](development/README.md) and excluded from acceptance
totals. A fresh committed source binding is required before the final full rerun.

## Source and execution bindings

`run_incoming_editor.py` requires a `--source-commit` argument. After acquiring
the shared runtime lock, it checks that all recorded product and test inputs
match that commit's Git blobs and that the checkout descends from it. A mismatch
fails preflight before running checks or tests. Later evidence-only commits can
advance HEAD without weakening the product/test source binding.

The runner records the selected suite paths, exact command, runtime paths,
process exit, timeout state, and before/after inventories of source, dependency,
runtime and workspace inputs. Inputs include reachable package libraries and
declared assets/fonts, all workspace manifests, the resolved lock and graph,
relative test imports, editor fixtures, and the engine frame-wrap XML fixture
read by `editor_test.dart`. The genuine SDK Material Icons font is explicitly
pinned and hashed for the review-surface test; screenshot output is disabled.

Output retains raw JSON events in `events.jsonl.gz`, the input inventories in
`inputs.json.gz`, and `summary.json` containing static-check output, commands,
guards, suite results, stderr and artifact hashes. Counting excludes loading,
hidden and lifecycle cases while retaining their failures as gate failures.
Every test start must finish exactly once; all selected suites must execute;
zero skips, errors, parser failures and layout/missed-tap diagnostics are
required. The actual Flutter process and both static checks must exit zero.

## Invocation after source freeze

From the task root, using a fresh output directory:

```bash
python quds_office_suite/docs/validation/zotero-citation-workflow-20261118/incoming/run_incoming_editor.py \
  --source-commit FROZEN_COMMIT_SHA \
  --output incoming-editor-validation
```

Default sibling directories are `quds_office_suite`, `zotero-validation` and
`zotero-toolchain`; explicit `--repo`, `--workspace` and `--toolchain` arguments
are also supported. No GitHub Actions, workflow or CI-status endpoint is used.
