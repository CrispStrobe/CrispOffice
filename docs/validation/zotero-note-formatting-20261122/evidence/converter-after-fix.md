# Zotero note formatting: LibreOffice converter cohort after direction IO fix

## Qualified source and unchanged expectations

This cohort ran on published source `d68df6d625d7f81163c502ed46dcfd97a806e95a`. The tracked tree was clean before and after; the head remained unchanged. All 22,035 source, manifest, package-configuration, Pub dependency, generator, and Dart runtime fingerprints were identical before and after execution. The input manifest SHA-256 is `02ac0222ceadae2316440251a4168e7801666f1b86317df1a13722e023fa8930`.

The fixture generator and the primary native, XML, conversion, and geometry scripts are byte-identical to the frozen before-fix archive. All three regenerated expected snapshots exactly match their frozen originals. No native assertion was removed or changed to accept the existing guards.

The exact converter was `LibreOfficeDev 26.8.0.0.alpha0 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. This is a development-build file-converter qualification. An installed Zotero or Word integration plugin was not exercised.

## Results

| Check | Result |
| --- | --- |
| Actual LibreOffice saves, three stories × two formats × two cycles | 12 of 12 succeeded |
| Independent XML checks, six originals plus twelve converted files | 18 of 18 passed |
| Foreground RGB and nonstandard opaque RGB highlight preservation in XML | 18 of 18 passed |
| Citation data, story ownership, ordered reference marks, and preferences in XML | 18 of 18 passed |
| Original native files, both formats | 6 of 6 passed the unchanged strict snapshot |
| Native DOCX content and the scoped formatting/metadata snapshot | 9 of 9 matched, excluding only the separately reported editability flag |
| Strict native checks of six LibreOffice DOCX files | 6 different: only both citation editability flags remain false |
| Native reopening of six LibreOffice ODT files | 6 refused by existing outline-style guards |
| Actual centered RTL TAIL horizontal geometry | Original DOCX and cycle-two DOCX both differ from ODT by only 0.018 pt |

The scoped native snapshot checks story text; selected paragraph direction, alignment, physical indentation and heading level; empty paragraph formatting; foreground/highlight; citation payloads and story ownership; balanced field markers; and document preferences. It does not assert complete typography, spacing, or pagination equivalence.

## Corrected interoperability failures

The original failing DOCX export rendered a centered RTL TAIL run at x=312.581 pt, whereas the intended corresponding ODT geometry centered it at x=282.599 pt. After the IO correction, both original DOCX and cycle-two DOCX center it at x=282.581 pt. That 30 pt correction places the indent on the intended side. All nine DOCX files now pass independent physical indentation inspection.

LibreOffice writes the empty explicitly LTR paragraph's right alignment as `jc=end`. Native reopen now resolves that logical value using the effective paragraph direction and preserves the expected right alignment. No other strict native snapshot differences remain in the converted DOCX files apart from citation editability.

## Retained boundaries

LibreOffice adds run properties to the instruction/separate/end boundaries of DOCX fields. The existing opaque-metadata guard blocks native field-result editing for those packets. The data remains valid, ordered, balanced, and in the same story. The new paragraph IO work does not relax this guard, and the raw native verdict remains `different` for all six converted DOCX files. The frozen before-fix cohort includes the field-boundary diagnosis and exact XML demonstrating the cause.

The ODT cycle-one files are refused with `Numbered or positioned ODT outlines are not supported.` Cycle two is refused with `Unsupported ODT outline-level-style attribute: loext:num-list-format`. Their independent XML inspection verifies the requested paragraph formatting, colors, two balanced reference-mark ranges with exact metadata, and raw `ReferenceMark` document preferences, but this is not native reopen or plugin-refresh acceptance.

## Evidence and reproduction

`summary.json` contains the component scores while `native-results.json` and all per-file reports preserve the unchanged strict native failures. `xml-results.json`, `geometry-results.json`, `conversion-results.json`, and their logs retain the observations and exact commands. `expected-snapshot-comparison.json` records equality with the original assertions. `inputs-before.json`, `inputs-after.json`, source-head receipts, and `artifact-index.json` provide attribution. All original and converted files are retained, as are the actual rendered geometry PDFs.

With the exact workspace/toolchain paths restored, `bash run_cohort.sh` reproduces the sequence. The core Python scripts also resolve their data directory from their own location. Transient LibreOffice profiles and the compiled Dart kernel are excluded from the compact archive; the generator/checker source and compilation log are included. The initial failing cohort and separately named direction/first-line probes are preserved in their own archives.
