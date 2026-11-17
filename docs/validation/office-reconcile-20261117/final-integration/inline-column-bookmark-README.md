# Imported column breaks and bookmark endpoints

This focused correction is bound to local canonical source `7596af95f763972995403d44dd251a1da22799be` (tree `9bdfed92a0e736ebfbca044e8d87519d9fe93326`). Its accepted focused run contains **518 substantive passes across all 31 current ODT, ODP, and shared ODF test files**, including all **13 final regression controls**, with no failures or skips. All selected files ran, every started test terminated exactly once, and the recorded source/test/configuration inputs were unchanged. Strict analysis of the four changed product/test files, formatting, and whitespace checks passed.

These results qualify this source milestone only. They do not replace the separate full canonical qualification, actual host menu qualification, independent LibreOffice consumers, or qualification of a later generic-field/main merge. Counts from earlier or focused runs must not be added to a full-run count.

## Defects and corrected behavior

The unchanged real CrispCloud menu test imported a normal DOCX run containing `<w:br w:type="column"/>`. The importer correctly retains an inline `WmlBreak.column`, while the former ODT writer consulted only `paragraph.properties.columnBreakBefore` and serialized the inline token as a soft page marker. The authored column break was consequently lost in the ODT layout.

The writer now interprets a leading column token as a paragraph column break. A token after authored content splits the output at that exact inline boundary into an ODT continuation paragraph. Continuations remain inside the same list item and story; they retain run styles, links, text, and endpoint order. Whitespace is not trimmed or treated as absent content. Consecutive and terminal column tokens retain separate boundaries. Only the first fragment owns section/master-page activation and initial page precedence. Split-boundary paragraph margins and continuation first-line/hanging indents are removed so fragmentation does not add paragraph spacing or repeat the first-line indent. The source model remains unchanged. Existing text-wrapping and inline-page encoding is retained.

The paragraph-wide PAGE cache is processed once across all fragments, so segmentation does not duplicate its generated field or lose its title suffix. Comment and note definitions keep their existing ownership. Complex field instructions remain hidden; their cached results and boundary order survive the split.

Raw-DOCX controls then exposed an adjacent existing bookmark gap. Native `w:bookmarkEnd` normally carries only `w:id`; the former ODT writer required a name on both endpoints, so imported ends vanished. `WordBookmarks.pairedEnds` now resolves complete, unique, ordered endpoint pairs using the existing Word story traversal and canonical decimal IDs. Body tables remain part of their body story. Headers, footers, frames, comments, and notes retain separate ownership. Malformed, ambiguous, reversed, or cross-story pairs are not guessed, and one malformed range does not block an unrelated complete pair. ODT only supplies an inferred end name if that exact matching start was actually emitted; an unexported TOC cache cannot create a visible orphan end.

## Controlled observations

| Stage | Source attribution | Observed result |
| --- | --- | --- |
| Original nine column controls | `48b6998bb47ffdf43e95025229dc5a5eab09ee9a`; executed in documentation-only descendant `ad09b5d` | 9 intended assertion failures |
| First column correction | `38dc9b712f3e019d46268e1263206dc1ce489560` | 7 pass; 2 deeper native bookmark-end assertions fail |
| Final four bookmark controls, incoming source | Exact isolated `48b6998b` engine overlay | 4 intended assertion failures |
| Accepted focused source | `7596af95f763972995403d44dd251a1da22799be` | 518 pass, including all 9 column and 4 bookmark controls |

The final nine column test bytes are identical to the original negative run. The final four bookmark test bytes are identical between their final negative run and the accepted focused positive run. Their SHA-256 values are recorded in `final-review.json` and `final-static.json`.

The intermediate `38dc9b712f3e019d46268e1263206dc1ce489560` tree was published remotely as `0a8570464cb30424949e0919fc6fdcdae1611ee7`, with exact shared tree `e19986356ce30cf45bbee3954aef758c9442af13`. The later root publication/merge maps the final source separately; the focused receipt retains its exact local source attribution instead of silently substituting a later commit.

## Preserved probe correction

The first version of the fourth new bookmark probe incorrectly expected raw covered-cell text and its bookmark start to be absent. Existing table and comment regressions explicitly require that raw text to remain in covered-cell XML; note/comment body expansion there is separately suppressed. The corrected probe targets an unexported TOC cache, which exercises a start that this bounded writer truly omits. Body/table ownership and covered-cell behavior were not changed.

The mistaken probe, its negative run, and its 3-pass/1-fail positive attempt are preserved as `bookmark-attempt1-test.dart`, `bookmark-incoming-48b.*`, and `bookmark-corrected.*`. `bookmark-oracle-correction.json` records the precise correction. The final four-control test was rerun against the exact old source before claiming the final passing control pair. No host assertion or original nine-column assertion was weakened.

Two early positive receipts precede a one-line explanatory comment correction. `executed-early-bookmark-writer.dart` reconstructs their exact executed bytes and is verified against those receipts. The final focused run uses the committed final writer bytes.

## Evidence and reproduction

`source-bindings.json` independently verifies every recorded engine library hash against its attributed Git source or the explicitly preserved intermediate writer; it also binds the final test bytes and retains assertion errors. The accepted run verifies 319 library files plus all 31 selected tests. `final-review.json` independently recounts the raw JSON events, verifies exact selected-file coverage and terminal IDs, and separates substantive tests from loader/setup administration.

The raw streams, before/after receipts, exact runners, package configurations, final controls, original corrected probe, source patch, and strict-analysis output are included. `source-correction.patch` reconstructs the product/test correction on the documentation-only `ad09b5d` baseline (whose implementation matches `48b6998b`). Both source commits and the patch are retained so later main integration does not erase the tested milestone.

To reproduce, create an isolated checkout at the recorded source and adapt only absolute scratch/runtime paths in a copy of the recorded runner. Use the archived package configuration with `quds_office_engine.rootUri` pointing to that checkout, keeping the recorded SDK and dependency cache. `run_controls.py` records the chosen source attribution, command, and complete library/test/configuration hashes before and after execution. For the negative controls, use exact engine `lib` and `pubspec.yaml` bytes from `48b6998b` with the final control files; do not run against a map pointing at the corrected engine. The accepted command and all 31 test paths are stored in `final-focused-receipt.json`. `run_focused.py` recounts raw test events and `qualify_static.py` reproduces the four strict-analysis scopes, formatting, and whitespace gates.

No GitHub Actions, workflow, check-run, or CI-status endpoint was queried or awaited for this work.
