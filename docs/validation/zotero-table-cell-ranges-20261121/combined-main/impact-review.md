# Dependency impact of the combined main

**Status: applicability pending targeted runs.** This review identifies which
existing Zotero qualification populations are affected by the incoming Word,
Mail and saved-message Close changes. It is not a test execution or acceptance
of the combined main. The separate execution receipts must establish the
targeted results on an immutable source checkpoint.

## Captured source identities

- Original Zotero implementation: `a6095c304ad2d6935f2ae6f8b74412038d19f142`.
- Incoming main after PR #291: `4a1eaa69e7a068e354bdd851ec9b0323b89ae300`.
- Captured saved-Mail Close fix: `9cfad3920f9afb3ca1620df429fa41e33f3db8e6`.
- Reviewed combined checkpoint: `5289b90a83ce9042a4f4cfb73ba8115fe501513a`.
- Reviewed Git tree: `15165a1c510f68de244f36286c3268d8cd8b43ed`.
- The source identity digest, per-file identities and complete path deltas are recorded in
  [impact-review.json](impact-review.json).

The original receipt remains **2,551 passing cases in 119 suites** at its
recorded source. Its broad capture has 2,978 inputs. Relative to that capture,
incoming main changes **15 existing paths**, leaves **2,963 existing paths
unchanged**, and adds **16 paths**. The Close fix modifies an already changed
Studio Mail implementation file. The added saved-Mail regression changes
`studio_saved_mail_test.dart`, outside the original 119 suites. The reviewed
combined checkpoint therefore has **2,994 captured inputs: 2,962 unchanged
original paths, 16 changed original paths and 16 added paths**, with no removed
paths. Compared with incoming main, only `studio_mail_native.dart` and
`studio_saved_mail_test.dart` differ within this inventory. The earlier
screenshot-only exception is not the applicable description of this tree.

No Zotero library/test path, engine Word model/library path, or editor library
path changes. All 119 selected test files preserve their qualified bytes.

## Concrete dependency impact

The replay resolves repository package URIs, relative imports, exports and
parts, including every conditional alternative, across 2,537 tracked Dart files
and 20 actual repository package roots. Historical pubspec copies retained in
documentation are not package roots. The replay compares each selected
suite's repository dependency identities with the original qualification tree.
This is a conservative lexical source review, not a compiler dependency trace.
External dependencies are not traversed; their manifests remain captured in
the source delta. Both complete selected transitive closures are checked:
**1,056 original inputs and 1,061 combined inputs**, with **zero** unresolved
local directives, unsupported URI escapes/schemes or possible same-line
directives that the line-based recognizer would omit.

| Original cohort | Suites | Suites reaching changed production source |
| --- | ---: | ---: |
| Engine Zotero | 41 | 0 |
| Engine ownership/fidelity | 27 | 2 |
| Editor Zotero | 49 | 0 |
| Studio Zotero | 2 | 1 |

The affected engine suites are `word_table_grid_addressing_test.dart` and
`word_bookmark_fidelity_test.dart`. Both import the fidelity operation
dispatcher, which reaches the modified native Word operation dispatcher and
its new header/footer guard. The guard changes header/footer paragraph
resolution; body, comment, footnote and endnote branches retain their previous
resolution paths.

`studio_zotero_shortcuts_test.dart` imports the shared Studio workspace, which
reaches the changed Mail implementation and synchronization libraries. The
saved-Mail Close fix is in that same dependency closure. It omits the command
bar Close while the saved-message view supplies its own Close.

The other 116 selected suite closures retain their qualified repository source
identities. The JSON maps all 119 suites and retains paths from each affected
suite to its changed dependencies.

The complete combined transitive closure is also scanned for process,
isolate-URI and deferred-library loading. Seven matching lines were reviewed:
one comment mentioning `Process.run`, plus six OS link launchers in
`suite_workspace.dart` and `office_uri_io.dart`. The launchers call `cmd/start`,
`open` or `xdg-open` for a hyperlink or PDF URI; they do not load repository Dart
source. All three source files remain byte-identical to the original
qualification. The replay preserves their identities and dispositions and
rejects an unexpected loader source set, count or source change.

## Minimum meaningful repeat population

| Existing suite | Original passing cases | Purpose |
| --- | ---: | --- |
| `word_table_grid_addressing_test.dart` | 22 | Native Word operation dispatcher integration |
| `word_bookmark_fidelity_test.dart` | 17 | Native Word operation dispatcher and bookmark preservation |
| `studio_zotero_shortcuts_test.dart` | 15 | Zotero commands in the shared Studio workspace |
| `studio_zotero_citing_transport_test.dart` | 18 | Preserve the existing complete Studio Zotero cohort |
| **Total** | **72** | Existing cases repeated on combined source |

The first three suites account for the changed dependency closures. The
unchanged transport suite completes the existing two-suite, 33-case Studio
cohort. Additional saved-Mail regression and targeted Mail executions address
the captured Close fix separately. Their results belong in their own receipts;
they do not change the original 119-suite population.

No new pass is asserted here, and repeat executions must not be counted as
additional unique coverage. The source impact supports this bounded repeat
population rather than requiring all 119 suites to run again.

## Node portability applicability

The earlier two-suite Node execution passed **121 cases**, overlapping the VM
population. Its broad 356-input capture has two changed existing automation
files, `office_vba_language.dart` and `operations/word_steps.dart`, and 354
unchanged existing inputs. The new header/footer guard adds one engine library
input to the corresponding inventory.

Neither changed automation file nor the new guard is reachable from the two
selected Node test libraries. Their repository dependency closures remain
identical. The original Node results therefore retain source applicability to
those Zotero tests; the entire broad engine capture is not described as
identical. No additional Node execution is claimed by this review.

## Replaying the review

[replay_impact_review.py](replay_impact_review.py) reads committed Git objects
and the retained original evidence archive. It verifies that the original
commit reproduces all 2,978 archived source identities and that the reviewed
commit contains all three captured frontiers. It does not edit source, refs or
the index, query CI, or run tests.

From the repository root:

```bash
python3 docs/validation/zotero-table-cell-ranges-20261121/combined-main/replay_impact_review.py \
  --repo . --target-ref 5289b90a83ce9042a4f4cfb73ba8115fe501513a \
  > /tmp/impact-review-replayed.json
```

The replay output is deterministic for those Git/archive/script bytes. Its
status remains pending by design: acceptance is established by separate
targeted execution and publication receipts, without rewriting the original
qualification evidence.
