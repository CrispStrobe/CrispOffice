# Final canonical qualification of `def52d84`

The complete recorded canonical scope passed freshly on source
`def52d84f3c3c5ce22c44d2620ecfa08d77780a7`, tree
`2c85776b996e04c8e6e3350c956b01eb730aba24`: **3,280 substantive Dart/Flutter
passes across 179 test files, plus 107 separately counted Python controls**.
Every analysis and formatting gate passed, and every recorded input map was
unchanged through execution. Independent review accepted the raw logs, suite
coverage, counts, exclusions, skips, and source identity.

This final run followed the host lint correction that added one `const` keyword
to the private immutable `_OdtListMarker.bullet('•')` construction. Independent
comparison proves that all 3,448 non-evidence input paths match the earlier
accepted `4c49b043` run except that exact writer change. All test files and
runner bytes are identical; the entire selection plan is identical except its
source commit. The earlier accepted run has its own archive and attribution.
Its passes are not added to this final run.

## Fresh local results

The final run completed on 17 November 2026 from **17:35:05 to 17:38:11 CET**
(Europe/Berlin; raw records use 16:35:05–16:38:11 UTC). It selected 179 unique
package/test-file pairs, retaining all 144 files from the prior accepted broad
scope and adding 35. The six cohorts are disjoint within this run.

| Cohort | Files | Raw successes | Private-fixture exclusions | Substantive passes | Skips |
| --- | ---: | ---: | ---: | ---: | ---: |
| Engine Office/ODF/proofing integration | 96 | 2,088 | 2 | 2,086 | 0 |
| Flutter editor integration | 37 | 396 | 0 | 396 | 0 |
| Engine Zotero | 19 | 390 | 0 | 390 | 0 |
| Flutter editor Zotero | 13 | 186 | 0 | 186 | 0 |
| Harper contracts | 3 | 29 | 0 | 29 | 0 |
| GECToR contracts | 11 | 193 | 0 | 193 | 1 |
| **Total** | **179** | **3,282** | **2** | **3,280** | **1** |

The complete **576-test Zotero scope** passed: 390 engine cases and 186 actual
Flutter editor cases, matching the retained expected counts. Separately,
**107 authored Python tooling controls passed**; one optional tiny ONNX
converter case was skipped because its development dependencies were absent.
No Python skip is counted as a success.

All five strict analysis scopes passed: engine, editor, Harper, GECToR, and the
single newly arrived evaluation-only ONNX Dart tool. All 76 handwritten Dart
format targets passed with explicit language version 3.12. The new Python ONNX
bridge received an AST/syntax check without import or execution; that check
is recorded separately from product tests. These gates and the six test cohorts
make 13 recorded commands, all with exit code zero.

## Fixture and acceptance limits

Two inherited `pdf_file_test.dart` cases return before assertions when the
private PDF is absent:

- `TrueType subsets without cmap get ToUnicode cmap for the host`.
- `JPEG with DCT SMask attaches softMaskJpeg for the host`.

Their exact successful runner events are retained, and both are subtracted
from substantive coverage. Every required Linux and bundled font fixture was
present and hash-bound. Selected suite sets match the actual loaded suites,
all started test IDs completed, and independent review found no hidden load
errors or unaccounted skips.

The single GECToR skip is
`real native dual heads own their output and reject use after dispose`:
its four pinned model/library variables were absent. The remaining 193
GECToR contract cases passed. This run covers the authored synthetic decoder,
tokenizer, provider, worker, lifecycle, and integrity tests. Real model inference,
model quality, native-library acceptance, Wasm acceptance, full application
or viewer/export-dialog behavior, and live Word/LibreOffice/Zotero
interoperability are outside this local qualification.

The Python skip is exactly
`test_qualification.TinyConverterTests.test_real_quantizer_preserves_both_head_matrices`.
The optional `onnx` and `onnxruntime` modules were absent. NumPy was available;
its runtime files and the relevant tooling inputs were recorded. The converter
skip does not remove other authored Python controls from the run.

## Regression controls and current positive coverage

The separately retained annotation control has 11 cases. With the three old
reader files it records six matcher failures, one output-limit
`FormatException` caused by hidden annotation content, and four passes. All 11
pass with the corrected source. The two note/comment ownership cases fail on
the old writer and pass after the correction. The two paragraph-decoration
cache cases fail on the incoming writer and pass with corrected cache identity.

Independent review proves that all **15 controlled case names pass freshly in
this final run**. The note and decoration tests are byte-identical to their
controls. The annotation comparison accounts explicitly for extraction of an
unchanged 4,096-character fixture into a local variable. Current positive
coverage also includes frame extraction (12 cases), section integration (14),
German lexical gaps (6), quotation handling (18), both retained section suites
(26 and 14), and the ODT writer suite (12). These cases are already inside the
3,280 substantive-pass count.

The exact table writer test blob matches the bounded incoming main checkpoint,
including all five added test lines. Source reconciliation,
incoming inventories, patches, and control provenance remain in
`docs/validation/office-resume-20261117/`.

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
The isolated workspace resolved 109 packages offline with `--enforce-lockfile`,
retaining lock SHA-256
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.

Generated lexical and morphology output bytes match their respective committed
manifests. Generator-owned encoded-string indentation is explicitly outside
handwritten formatting scope; the exclusions are restricted to exact
manifest-authenticated generated paths. The new lexical supplement adds only
`Grüezi`, `Hof`, and `grüezi`; it removes no forms. The unchanged morphology
manifest retains its original lexical-input attribution. No Unicode-source
regeneration is claimed by this run.

## Preserved stages and evidence

The adjacent summary, independent review, positive-coverage review,
post-const equivalence review, archive, and index bind the exact source,
selected suites, commands, exits, timings, raw/compressed log hashes, runner
versions, and executed setup receipts. Every archive member was read back and
verified. The current archive has 129 members and is 886,556 bytes; its SHA-256
is `a58a73166a36d36223e7cc215dd6b32caa27e5e6d268fe1b91d0b2323f6f9a5b`.

The earlier accepted `4c49b043` archive remains separately attributed, with
129 members, 887,836 bytes, and SHA-256
`384c9a9405f40e0b3a668b0afad3d8a414da60a539352f32e14fd24c019c433e`.
Its reviewer-only initial path-normalization failure and corrected review are
both retained; the final `def52d84` review passed without changing the runner,
tests, or source.

The original failed `b32dee6f` formatting preflight ran no product tests. Its
archive preserves setup, successful analysis logs, the failed format gate,
the four-test formatting correction, and both the initial overstrict token
verifier and the accepted AST/token-equivalence proof. It remains available at
the original published checkpoint `104b239c971ef3b2d62495a27ad04b519398a1fc`,
under `docs/validation/office-continuation-20261117/resumption/`, with SHA-256
`38b96302069d2ea970d0002a761d114eee7df4776ac540ca550278b6840895ec`.
Exact Git-object readback also verified its presence, size, archive members,
and index at both later qualified commits. The original control archives were
verified in the same way at each recorded commit/path/hash.

The shared delivery readback report records these checks independently of the
product-run receipts. The final archives reference already retained prior
archives explicitly, avoiding replacement or reattribution of their evidence.

## Reproduction

Restore the pinned SDK/cache and locked external workspace using the executed
setup scripts and receipts under `setup/` in the archive. Keep the adjacent
`run_qualification.py` and `python_controls.py` together, activate the recorded
environment, and run from a clean source checkout:

```sh
python3 run_qualification.py \
  --repo /path/to/clean/quds \
  --source-commit def52d84f3c3c5ce22c44d2620ecfa08d77780a7 \
  --flutter-root /path/to/pinned/flutter-sdk \
  --workspace /path/to/locked/external-workspace \
  --output /path/to/new/evidence-directory
```

Use `--plan-only` to inspect selection without executing tests. Every attempt
requires a fresh output directory. The archived independent review scripts can
recount the retained logs and confirm source/control identities without running
product tests. No GitHub Actions, CI-status, or workflow endpoint was queried,
awaited, or rerun.
