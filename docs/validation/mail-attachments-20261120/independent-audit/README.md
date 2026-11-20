# Independent validation audit

**Accepted result: 2,049 distinct substantive cases passed, 0 failed, and 1 explicitly NOT RUN native case across 113 distinct selected test files.** The count consists of the immutable original **2,034** passes plus **15** cases from the separately executed post-main comment-draft suite. No suite or substantive case is counted twice.

The original audit remains bound to `58c6962ec3ea82811bfcafec42981385f216f892`. The supplemental applicability proof and 15-case suite bind the combined result to `6184051c75d882cac53be3c1a9384e4556588ad1`, tree `b5b9ffdf6f500a9047cd4d01f3aa6c1bf8e91190`. The original `report.json` was not changed by the supplemental audit.

## Independently recounted cases

| Accepted cohort | Selected files | Passed cases | NOT RUN |
| --- | ---: | ---: | ---: |
| quds_mail_core-vm | 6 | 54 | 0 |
| quds_mail_mime-vm | 7 | 84 | 0 |
| quds_mail_store-vm | 22 | 557 | 0 |
| quds_mail_store-node | 1 | 3 | 0 |
| quds_mail_transport-vm | 18 | 373 | 0 |
| quds_mail_transport-node | 3 | 6 | 0 |
| vendor-mime | 3 | 83 | 0 |
| mail-host | 11 | 319 | 0 |
| editor-rendering | 10 | 109 | 0 |
| editor-zotero-materials | 3 | 48 | 0 |
| studio-spacy | 2 | 20 | 0 |
| engine-rendering | 12 | 224 | 0 |
| spacy-package | 11 | 113 | 1 |
| engine-macro-serialization | 3 | 41 | 0 |
| Post-main comment draft | 1 | 15 | 0 |
| **Total** | **113** | **2,049** | **1** |

The four mail packages account for 1,077 passes, the selected vendor MIME suites for 83, the four original Flutter cohorts for 496, engine rendering for 224, the spaCy package for 113, macro serialization for 41, and the new comment-draft suite for 15.

## What was checked independently

The auditor reads the raw Dart/Flutter JSON event streams without importing any validation runner or executing tests. It verifies one completion for every started test, exactly one selected suite execution per file, unique suite IDs and substantive `(repository path, platform, full case name)` identities, no failed completions or error events, and one successful final event. File selections are compared to the complete declared mail-package inventories and the specific frozen Flutter/engine/spaCy/macro selections. The original 112 selected files and the new comment-draft file are disjoint.

**119 loading/setup/teardown events were excluded from pass totals**: 118 in the original acceptance and one in the supplemental suite. A failure in an excluded lifecycle event would still reject acceptance. Preliminary tests, earlier failed assertions, before-repair controls, repeated analysis, and source-applicability audits add no passing cases.

Advertised artifact sizes, SHA-256 hashes and Git blob identities were checked. The full retained input manifests were hashed independently; their canonical digests match the before/after fingerprint claims. Captured source records were matched to the claimed Git commit objects, including historical bytes for the explicitly reviewed source deltas. Available dependency, runtime, workspace and font inputs were independently hashed. The supplementary test and static-check evidence each bind 4,006 source files and 4,502 dependency files to the final source.

The inherited runner retains full before manifests plus after digests, rather than full raw after manifests. The audit cross-checks those after digests against the complete before manifests and independently hashed available bytes. The older mail runner retains and compares both complete before and after manifests.

## Applicability to the final source

The original mail-package source scope remains unchanged. The original Flutter executions ran at `b8686c05e055ca0395726fe528d585379597d628`. Their applicability to `58c6962…` is supported by the retained final-source audit: the only changes are braces around an existing return in a standalone evaluator tool and corrections to the numeric/whitespace assertions in an engine PDF test. Neither file is a selected Flutter entry point; independent source-reference checks found no incoming references. The repaired engine test is separately qualified by the final 224-case engine cohort.

From `58c6962…` to `6184051…`, the entire Git-tree delta is seven added lines in `studio_comment_draft_proofing_test.dart`, accounting for the existing language-download dialog. All application libraries, configuration and other files are identical. The changed test was outside the original 112-file selection. An independent scan of 2,087 tracked non-document Dart files found no incoming import/export/part edges or outside filename references to it. Its complete 15-case suite, unchanged-format check and strict analysis passed separately at `6184051…`.

The original static evidence includes analysis and formatting of 62 changed Dart files at `42aa06f9…`. One of those files—the PDF regression test—was later adjusted. The final 16-target strict engine/spaCy analysis at `58c6962…` includes that corrected test. The incoming comment-draft file has its own final exact-file format and strict-analysis receipts at `6184051…`. Static checks are reported at their actual source revisions and are never counted as test cases.

## Explicit NOT RUN result

The sole allowed skip is:

- File: `packages/quds_proofing_spacy/test/macho_code_identity_test.dart`
- Case: `the qualified macOS library has the recorded code digest`
- Reason: `set QUDS_SPACY_MACOS_LIBRARY to the qualified library`

This is **NOT RUN**, not passed. The raw strict spaCy receipt remains rejected solely by its general no-skips guard; the separate controlled-suite receipt explicitly allows this exact predeclared case while all other guards pass. Both receipts and their hash binding were verified. No real macOS native model or installed application execution is claimed by these Linux controls.

## Diagnostic preservation and audit-tool correction

`diagnostics/auditor-unicode-framing.json` preserves a reproducible audit-tool correction. The first independent reader used Python `str.splitlines()`, which split three valid JSON test names at Unicode NEL (`U+0085`), line separator (`U+2028`) and paragraph separator (`U+2029`). Those characters occur intentionally in unsafe-filename regressions. The erroneous reader rejected the entire 319-case mail-host cohort, temporarily reporting 1,715 accepted passes. This was an auditor parsing error; the product tests and original receipts had succeeded.

The corrected reader splits JSONL records on LF only, preserving those Unicode characters within strings. It independently recounts all 319 mail-host passes. The diagnostic includes the observed interim summary, the six reproducible parser errors, and the three intact start/completion pairs. The intermediate report was replaced and was not retained byte-for-byte; that limitation is explicit. No original test event file or acceptance receipt was edited.

The earlier engine PDF assertion failures, intermediate PPTX repair failures, lock-drift run, broad-package diagnostic analysis and all repeated development runs remain in their own diagnostic/preliminary directories. They are excluded from this acceptance total.

## Artifacts and reproduction

- `report.json`: immutable original 2,034-case independent audit, with per-cohort event guards, selected files, hashes, input checks and static scopes.
- `report-cases.json.gz`: independently reconstructed original substantive cases; includes the one explicitly NOT RUN case.
- `supplemental-source-applicability.json` and `supplemental-source-delta.patch`: exact final-source delta and unchanged-scope proof.
- `supplemental-validation-report.json`: separate 15-case recount, input verification and combined 2,049-case result.
- `summary.json`: compact accepted totals and limitations.
- `audit_validation.py`: original audit implementation. It is preserved unchanged with its recorded hash.
- `audit_supplement.py`: reproducible supplemental source and validation audit.
- `index.json`: hashes of the audit artifacts in this directory.

The scripts read saved evidence and Git objects; they do not run tests, analyzers, builds, CI or remote status checks. Reproduction requires the recorded source Git objects, saved sibling evidence directories, and recorded dependency/runtime files to be available.

```sh
python /path/to/independent-audit/audit_validation.py --repo /path/to/clone --evidence /path/to/final-validation --final-head 58c6962ec3ea82811bfcafec42981385f216f892 --output /path/to/new-original-audit.json
python /path/to/independent-audit/audit_supplement.py --repo /path/to/clone --evidence /path/to/final-validation
```

There are **no unresolved evidence gaps within these selected local acceptance scopes**. This is not a claim that every repository test, live mail provider, installed desktop application, native macOS grammar model or external integration was exercised.
