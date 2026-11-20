# Final main applicability add-on

**The accepted total remains 2,049 distinct application cases passed, with one optional native case explicitly NOT RUN, across 113 selected test files.** This add-on binds that result to `f8f36eb87b051a0b26ee68747dfd24c4717eaec1`, tree `26f0d546e9d6ef29a3ab90ea0081425cba13c1d4`. All earlier original and supplemental reports remain unchanged.

## Exact source delta

From the preceding qualified source `6184051c75d882cac53be3c1a9384e4556588ad1`, exactly three paths change:

| Path | Change and applicability |
| --- | --- |
| `docs/release/macos-signing.md` | Release guidance; no selected runtime entry point. |
| `packages/quds_office_editor/example/tool/build_macos_app.sh` | macOS signing portability controls. The selected pin test consumes six assignments from this file; its single case was separately requalified at the final source. |
| `packages/quds_proofing_spacy/lib/src/distribution.dart` | Four full-line documentation comments replaced; all non-documentation bytes are identical. |

All file modes and types remain unchanged. No other application source, configuration, workflow or selected test source changes. The existing workflow is separately confirmed unchanged from the preceding captured candidate.

## Consumed build-script input and replacement case

The build script is **read** by the already-selected `studio_spacy_pin_test.dart`. Its consumed values are the six anchored assignments `SPACY_PIN_SHA256`, `SPACY_PIN_REVISION`, `SPACY_PIN_BYTES`, `SPACY_PIN_REPOSITORY`, `SPACY_PIN_CODE_SHA256`, and `SPACY_PIN_UNSIGNED_SHA256`. Every value is identical before and after the change, as are the executable Dart qualification definitions.

The complete pin file was nevertheless rerun on the final source: **1 pass, 0 failures, 0 skips**. Its raw case identity exactly matches the case already counted in the original 20-case Studio spaCy cohort. It is a **replacement qualification and adds zero cases** to 2,049. The independent audit verified its raw event closure, receipt/artifact hashes and full source/dependency/runtime input fingerprints.

None of the 15 recorded original acceptance commands invokes the macOS build script. A review of 327 file/process I/O sites across all 113 selected test files identified the pin read above. Reviewed subprocess targets are Dart mail crash fixtures, the Dart macro CLI, fixture Git operations and `mkfifo`; other reviewed reads use temporary data, committed fixtures/fonts, or injected providers. The remaining literal build-script references in non-document Dart source are comments. This is a source and recorded-command review, not a universal runtime file-access trace.

## Additional evidence checked

The later **62-file format and strict-analysis receipt at `58c6962…`** was independently checked, including exact source hashes, selected command arguments and both log hashes. Formatting reports zero changed files and analysis reports no issues. This evidence is recorded in the add-on without altering the older audit that originally examined the earlier `42aa06f9…` static run. The only later delta within that 62-file scope is the verified documentation-comment change in `distribution.dart`.

The macOS script evidence records a successful `bash -n` check and **eight auxiliary controlled Bash scenarios**, including expected rejection exits for altered code/signature conditions. Their receipts, expected exits and advertised artifact hashes were independently checked. These scenarios execute extracted changed blocks on synthetic, non-executable files using stubs for external signing/digest tools. They add **zero application cases** to the acceptance total and do not establish a real macOS build, signing, native loading, notarization or shipping result. The real-library identity test remains explicitly NOT RUN.

## Immutable evidence and auditor diagnostic

`report.json`, `supplemental-validation-report.json`, and `supplemental-source-applicability.json` retain their prior hashes, recorded in `final-main-applicability.json`. A small supplemental auditor implementation correction is documented in `diagnostics/final-main-counter-constructor.json`: its initial completeness comparison supplied a mapping to Python `Counter` instead of an iterable of ID keys. Correcting that constructor verified the already-successful raw pin events; no product/test failure or raw evidence change occurred.

## Added artifacts

- `final-main-applicability.json`: complete exact-delta, replacement-case, source/input/hash and static/control evidence audit.
- `final-main-source-delta.patch`: exact three-file source delta.
- `final-main-selected-io-sites.json`: preserved selected-test file/process I/O review sites.
- `audit_final_main.py`: reproducible read-only audit; it executes no tests, analyzers or shell scenarios.
- `final-main-summary.json`: compact final counts and source identity.
- `final-main-index.json`: hashes for this add-on only; the prior artifact index is unchanged.

Reproduction expects the **reconstructed original flat `final-validation` evidence layout**, not the differently grouped repository delivery layout. Use the supplied restoration helper to reconstruct that layout first. The recorded Git objects, dependency files and runtime files must also exist; the auditor deliberately retains strict checks and does not substitute missing runtime evidence.

```sh
python /path/to/independent-audit/audit_final_main.py --repo /path/to/clone --evidence /path/to/reconstructed/final-validation
```
