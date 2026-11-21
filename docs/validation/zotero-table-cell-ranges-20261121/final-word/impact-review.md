# Follow-up impact: completed Word guard on incoming main

**Pending the targeted 39-case execution and final merged-source receipt.**
This review does not accept the new main or claim another test run.

The prior combined checkpoint is
`5289b90a83ce9042a4f4cfb73ba8115fe501513a`. Incoming main is
`9f23cbd2be72c527829b3990f22b356e5237ed96`, which merges the completed Word
work at `38b07e58`. The comparison against previous main `4a1eaa69` contains
documentation/evidence, the saved-Mail Close change, and two Word files:

- `word_header_footer_guard.dart`: 170 inserted and 23 removed lines.
- `office_macro_word_headers_footers_test.dart`: 270 inserted and one removed
  line. This macro test is outside the original 119-suite population.

The incoming `studio_mail_native.dart` is byte-identical to the prior combined
checkpoint, including the Close fix. Incoming main does not yet contain the
27-line regression added to `studio_saved_mail_test.dart` at our combined
checkpoint. Preserve that test addition in the merge. The replay's optional
`--combined-ref` verification explicitly requires it to remain unchanged.

## Product and dependency impact

The only changed production source relative to the prior combined checkpoint
is the header/footer guard. Its imports are unchanged. It tightens checks for
independent story linkage throughout a document, mutable-model aliases, and
faithful native paragraph/run content. It does not change the Word model,
Zotero engine, editor controller, or Studio application.

The static replay checks all 119 selected test files and their repository
dependency closures. All test files are unchanged. **117 closures are
unchanged**; the remaining two reach the changed guard through the native Word
operation dispatcher:

| Suite | Existing cases to repeat |
| --- | ---: |
| `word_table_grid_addressing_test.dart` | 22 |
| `word_bookmark_fidelity_test.dart` | 17 |
| **Total** | **39** |

The two Node Zotero test closures are also unchanged. The Studio closures are
unchanged, so this delta does not require repeating the Studio cohort or all
119 suites. Earlier results retain their separate identities and counts.

Both complete transitive closures have zero unresolved local directives,
unsupported URI forms, or potentially missed same-line directives under the
reviewed resolver. The changed guard contains no process/isolate/deferred
loader match, and all previously reviewed loader source files are unchanged.

## Retained proof

[impact-review.json](impact-review.json) records exact source hashes, the
three source differences between the prior combined checkpoint and incoming
main, all 119 closure comparisons, and the 39-case repeat plan.
[replay.py](replay.py) reuses the source-bound dependency helper from the prior
review; its hash must match that prior receipt. It reads committed Git objects
and does not edit source, refs, or the index.

Run against the incoming main:

```bash
python3 replay.py --repo /path/to/quds_office_suite --output impact-review.json
```

After root creates the final combined commit, add `--combined-ref COMMIT`. That
mode requires the saved-Mail regression to be retained, exactly the guard and
unselected macro test to differ within the captured source inventory, and the
same two selected suites to be affected. The targeted execution and publication
receipts establish acceptance separately.
