# Word qualification after the publication-time main update

Status: **PASS** for the source recorded by [final-main-word-validation.json](final-main-word-validation.json). The incoming main commit is `e975cec13b289fe067ef406cd3044701ecc44744`, a direct child of the earlier captured main `b6657785`. This is a separate qualification of that update and its corrective changes; earlier evidence and the frozen 320-ref inventory are retained unchanged.

## Fresh executed gates

| Gate | Result |
| --- | --- |
| Word VM, 26 suites | **961 passed**, zero failures/skips |
| JavaScript/Node, seven suites | **758 passed**, zero failures/skips |
| Changed-source formatting and strict analysis | Clean |
| Committed line-spacing BAS | VM and compiled JavaScript/Node passed; semantic JSON identical |
| Committed measurements BAS | VM and compiled JavaScript/Node passed; semantic JSON identical |
| Committed named-measurements BAS | VM and compiled JavaScript/Node passed; semantic JSON identical |
| Source binding | **492** scoped engine, test, helper, fixture and BAS inputs unchanged |

The VM cohort contains the nine earlier VBA suites plus the new picture/style regressions and relevant existing table, border, header, paragraph-mark and incremental-layout suites. All eleven focused picture tests and the full five-suite deserializer cohort are included. The Node cohort contains the five earlier portable compiler suites and the two new model/XML suites. These counts come from fresh complete runs; the VM and Node coverage overlaps.

The [portable qualification record](final-main-portable-compiler-applicability.json) explicitly replaces applicability assumptions with new JavaScript execution. The five original compiler test files are unchanged, but the two transitive engine files changed, so no claim about unused imports was needed. The actual committed BAS bytes were passed to each driver, compiled with `dart compile js -O1`, and run using the asynchronous Node bootstrap; parsed VM and Node JSON results were compared.

## Picture corrections

The incoming layout used dimensions and image-byte lengths to infer duplicates. The focused incoming probe recorded **two passes and nine failures**: shared inline/floating nodes disappeared, distinct same-sized images were lost, continuous sections paginated incorrectly, and tall inline logos overlapped body content. That nonaccepted result is preserved in [the initial receipt](final-main-layout-initial-validation.json).

The correction keeps the new inline header/footer picture rendering and uses exact `WmlVisual` node identity only when the same placement also appears in the floating list. Distinct placements can share dimensions or the same image asset. Continuous sections carry only the recorded body-frame prefix and calculate their body bottom from that same prefix; header/footer artwork is rebuilt once. The global picture-removal heuristic is gone, and inline header pictures participate in existing body-clearance calculations.

The incoming **4.25-point** table-cell padding remains. Its obsolete 108-twip comment was corrected. Full/incremental layout equivalence and table boundaries are covered by the fresh VM cohort.

## Table-style corrections

The existing style cascade retains direct run color and explicit bold-off, child style overrides and nested-table boundaries. The incoming redundant post-cascade first-row overwrite was removed. Automatic/omitted border color may inherit from the table style while explicit direct border width is preserved. The compact cell-spacing fallback remains, with its imported-value snapshot updated so untouched export does not stamp inherited presentation as direct spacing and block later style changes.

The focused XML tests exercise import/export, direct and inherited formatting, disabled first-row styling, border widths, sparse spacing and subsequent style changes. They are included in both fresh VM and Node cohorts. Editor font aliases are qualified by the separate font receipt; this document makes no installed Microsoft Word or browser/WASM claim.

## Source identity and boundaries

- Started: `2026-11-20T21:40:40.831116+00:00`.
- Completed: `2026-11-20T21:44:33.702861+00:00`.
- Initial checkout: `3f9d3647a20b06c73f5bfd0ade2846e7859e4502`.
- Final checkout: `3f9d3647a20b06c73f5bfd0ade2846e7859e4502`.
- Word layout SHA-256: `ec820bd02b287b7f1ef109248d7336e243f436c0206eedb4982631b6855e690e`.
- Word deserializer SHA-256: `4a5a9b69e45f3f6123103f98f31623b55892e3b2dfce8283322bacc9c9d5244b`.

The receipt records commands, raw log hashes, exit codes, terminal test-runner results, runtime versions and before/after source hashes. Later main changes require their own applicability check; this receipt is not automatically relabeled for a later tree. GitHub Actions, workflow runs, checks and status endpoints were neither queried nor awaited.
