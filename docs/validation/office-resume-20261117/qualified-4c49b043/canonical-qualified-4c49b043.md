# Accepted canonical qualification of `4c49b043`

The complete recorded scope passed on canonical source
`4c49b0435bc6611221bc49b58b15e735059467ff`, tree
`b098f1fb6ae8ab7b4a0614d6a2c25b1623bab1de`.
This is an accepted source-specific checkpoint. Later amendments retain their
own source identities and qualification records.

## Fresh local results

The 17 November run completed from 16:23:37 to 16:26:58 UTC. It selected
**179 unique package/test-file pairs**, retaining all 144 files from the prior
accepted broad scope and adding 35. The six cohorts are disjoint within this
run. Their results are not added to earlier qualification stages or negative
controls.

| Cohort | Files | Raw successes | Private-fixture exclusions | Substantive passes | Skips |
| --- | ---: | ---: | ---: | ---: | ---: |
| editor-integration | 37 | 396 | 0 | 396 | 0 |
| editor-zotero | 13 | 186 | 0 | 186 | 0 |
| engine-integration | 96 | 2,088 | 2 | 2,086 | 0 |
| engine-zotero | 19 | 390 | 0 | 390 | 0 |
| gector-contract | 11 | 193 | 0 | 193 | 1 |
| harper-contract | 3 | 29 | 0 | 29 | 0 |
| Total | 179 | 3,282 | 2 | **3,280** | 1 |

The full **576-test Zotero scope** passed: 390 engine cases and 186 actual
Flutter editor cases, matching the retained expected counts. Separately,
**107 authored Python tooling controls passed**; one optional tiny ONNX
converter case was skipped because its development dependencies were absent.
No Python skip is counted as a success.

All five strict analysis scopes passed: engine, editor, Harper, GECToR, and the
single newly arrived evaluation-only ONNX Dart tool. All 76 handwritten Dart
format targets passed with explicit language version 3.12. The new Python ONNX
bridge received an AST/syntax check without import or execution; that check
is recorded separately from product tests.

## Fixture and acceptance limits

Two inherited `pdf_file_test.dart` cases return before assertions when the
private PDF is absent. Their exact names and successful runner events are
retained, and both are subtracted from substantive coverage. Every required
Linux and bundled font fixture was present and hash-bound.

The single GECToR skip is the explicitly named real-native dual-head fixture
case: its four pinned model/library variables were absent. The remaining 193
GECToR contract cases passed. This run covers the authored synthetic decoder,
tokenizer, provider, worker, lifecycle and integrity tests. It does not add a
model-inference, model-quality, native-library or Wasm acceptance claim. Full
application/viewer/export-dialog acceptance and live Word/LibreOffice/Zotero
interoperability remain outside this local qualification.

## Regression controls and current positive coverage

The separately retained annotation control has 11 cases. With the three old
reader files it records six matcher failures, one output-limit
`FormatException` caused by hidden annotation content, and four passes. All 11 pass with the corrected source.
The two note/comment ownership cases fail on the old writer and pass after
the correction. The two paragraph decoration-cache cases fail on the incoming
writer and pass with the corrected cache identity.

Independent review proves that all **15 controlled case names pass in this
current full run**. The note and decoration tests are byte-identical to their
controls. The annotation comparison accounts explicitly for extraction of an
unchanged 4,096-character fixture into a local variable. Current positive
coverage also includes frame extraction (12 cases), section integration (14),
German lexical gaps (6), quotation handling (18), both retained section suites
(26 and 14), and the ODT writer suite (12). These cases are already inside the
3,280 substantive-pass count.

## Input integrity and generation provenance

All six before/after maps are equal: 3,448 tracked non-evidence source files,
5,099 resolved dependency files, 13 runtime artifacts, 118 workspace paths and
links, six system-fixture entries, and eight harness inputs. Every source blob
and mode matches the frozen commit. There are no untracked non-evidence inputs,
HEAD remained at the source commit, and the analyzer configuration was restored.

The official toolchain identities remain Flutter 3.47.8 at
`737ba8f885dc774b53b442759999a312c9461e4e`, engine
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`, and Dart 3.13.7. Dart and
`flutter_tester` executable hashes match the earlier recorded pins. The actual
locally generated Flutter-tool snapshot has its own unchanged recorded hash.
The isolated workspace resolved 109 packages offline while retaining lock
SHA-256 `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.

Generated lexical and morphology output bytes match their respective committed
manifests. Generator-owned encoded-string indentation is explicitly outside
handwritten formatting scope. The new lexical supplement adds only `Grüezi`,
`Hof` and `grüezi`; it removes no forms. The unchanged morphology manifest
retains its original lexical-input attribution. No Unicode-source regeneration
is claimed by this run.

## Evidence and reproduction

The adjacent summary, independent review, positive-coverage review, archive and
index bind exact source identities, selected suites, commands, exits, timings,
raw/compressed log hashes, runner versions and setup receipts. Every archive
member was read back and verified. The previous failed formatting preflight,
its four-test formatting correction and the regression-control archives remain
unchanged in the repository; the current archive records their exact paths and
hashes. Reviewer-only failed attempts are retained with their corrected reviews.

For reproduction, restore the pinned SDK/cache and locked external workspace
using the executed setup scripts and receipts under `setup/` in the archive.
Keep `scripts/run_qualification.py` and `scripts/python_controls.py` together,
activate the recorded environment, and run from a clean source checkout:

```sh
python3 run_qualification.py \
  --repo /path/to/clean/quds \
  --source-commit 4c49b0435bc6611221bc49b58b15e735059467ff \
  --flutter-root /path/to/pinned/flutter-sdk \
  --workspace /path/to/locked/external-workspace \
  --output /path/to/new/evidence-directory
```

Use `--plan-only` to inspect selection without executing tests. Every attempt
requires a fresh output directory. No GitHub Actions, CI-status or workflow
endpoint was queried, awaited or rerun.
