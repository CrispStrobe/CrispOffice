# Completed Office recovery — 17 November 2026

The stalled continuation is recovered and locally qualified at published source
**`966196f386ec1776c836664b3eb7c93e8e92605c`**, tree
`4287330a433e915d58ca779adfacb75942c6ab04`. The complete 180-file Dart/Flutter
selection passes **3,320 substantive cases**. Fourteen Node suites repeat
**282** of those cases with matching identities and outcomes. Independent
office-consumer checks pass **26 fixtures / 104 ODF XML-part validations**.

The branch is `codex/office-continuation-20261117`, associated with draft PR #113.
The recovery point was `104b239c971ef3b2d62495a27ad04b519398a1fc`. The attached
earlier handoff described completed fidelity checkpoint `d1738017`; the later
continuation had combined more Office, Zotero and proofing work and corrected
four formatting mismatches, but its product tests had not run.

## Incoming work was integrated first

The [fixed snapshot](incoming-snapshot.json) contains **258 named references /
173 distinct commits**: 136 fork branches, 114 fork PR heads, four upstream
branches and four upstream PR heads. Observation completed on 17 November at
**16:58:36 Berlin time / 15:58:36 UTC**. Every captured head is included by
ancestry; all objects were fetched successfully.

The inventory was published before source changes at `1c79a086`. Completed
fidelity evidence, morphology/page-field work, captured main, structured frame
reconciliation, and original/vendor shading histories were then saved in
separate checkpoints. All-ref integration was published at **`f29373cf`**
before the new writer repairs. The [publication ledger](publication/source-checkpoints.json)
records exact remote commits, trees and parents.

The [ancestry record](integrated-ancestry.json) and independent
[integration audit](integration-audit.json) account for the captured heads.
[Source reconciliation](source-reconciliation.json) records the single ODP
assertion relocation, exact shading mirror differences, and explicit correction
of the duplicate empty-document assertion. German quality evidence was retained.

## Product repairs

### Structured text boxes

Frame tables remain structured tables, while extraction and search retain their
visible cell content. Linked drawing frames, nested text boxes, authored empty
paragraphs and explicit whitespace remain supported. Empty and table-only
text-box anchors introduce no synthetic blank paragraph. Annotation, note,
covered-cell and hidden inline stories stay suppressed in the reconciled paths.

Both incoming regression suites remain active. The
[frame reconciliation](frame-reconciliation.md) records two intentional
expectation changes without changing original fixture XML or nonempty text.
Three added controls cover linked table-only frames and hidden-wrapper budgets.

### Paragraph decoration

Distinct shading and border colors now participate in paragraph-style identity,
preventing adjacent paragraphs from inheriting the first decoration. The writer
accepts exactly six hexadecimal `RRGGBB` digits, normalizes valid colors, and
omits invalid values without modifying the source model. The incoming fixed
`0.5pt solid` border mapping remains bounded to that supported representation.

### Page-number fields

Simple PAGE paragraphs retain run formatting, the model's supported ` | title`
suffix (including separately styled suffix runs), links, bookmark endpoints and
comment ownership. Empty PAGE paragraphs and empty bookmark ranges retain the
generated field without adding model runs. Note-reference spacing belongs to
the first PAGE paragraph and cannot leak into its successor.

Explicit field instructions take precedence over the compatibility flag.
Non-PAGE instructions and mixed/atomic inline fields keep their cached content.
This does not add arbitrary native Word field semantics or switches. The
[writer repair report](writer-repair.md) defines these boundaries.

These changes add **45 regression cases**: three frame controls, 20 decoration
cases and 22 PAGE cases. The 42 writer cases pass on both VM and Node. An initial
40-case baseline produced 31 failures, four errors and five successes; its raw
events remain in [writer-baseline](writer-baseline/receipt.json).

## Fresh local qualification

The unchanged locked workspace uses genuine **Flutter 3.47.8 / Dart 3.13.7 /
Node 24.22.1**. Lock SHA-256 remains
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.

| Primary cohort | Files | Substantive passes | Explicit limit |
| --- | ---: | ---: | --- |
| Engine Zotero, VM | 19 | 390 | None |
| Editor Zotero, actual Flutter | 13 | 186 | None |
| Engine integration, VM | 97 | 2,126 | Two private-PDF early returns excluded |
| Editor integration, actual Flutter | 37 | 396 | None |
| Harper contracts | 3 | 29 | None |
| GECToR contracts | 11 | 193 | One missing native-fixture case skipped |
| **Primary total** | **180** | **3,320** | **No failures or errors** |
| Node repetitions | 14 | 282 | Same case identities/outcomes as VM |
| Ancillary Python controls | — | 107 | One optional converter-dependency skip |

All **174 originally selected files remain covered**, with six additional
files. Node repetitions are not additional unique cases. Combined Dart/Flutter
execution count is 3,602 substantive passes; Python controls remain separate.
Four strict analysis scopes and all 77 handwritten formatting targets pass.
Source, dependency, selected-runtime, workspace, system-fixture and harness maps
are unchanged, and the analyzer configuration was restored.

The [qualification report](qualification/README.md) includes reconstruction
commands, exact selection, raw events, source/runtime maps and the archive index.
Development failures and corrections remain separately preserved in
[integration-checks](integration-checks/index.json) and
[writer-development](writer-development/index.json); they are not counted as
fresh qualification passes.

## Independent office consumers

All **24 historical fixture specifications and original check assertions remain
unchanged**. A fresh run adds two independent recovery fixtures for decoration
and live styled footers: **26/26 fixtures and 104/104 XML parts pass** against
the official OASIS ODF 1.3 schemas.

LibreOffice/PDF checks confirm distinct red/green backgrounds and blue/magenta
0.5-point borders, an undecorated plain paragraph, and actual footer page numbers
1 and 2 followed by the complete title. Reopened DOCX retains a real PAGE field
and bold, blue, 14-point formatting on the result and suffix. The prior 540-point
RTL edge, 18-point line step and frame geometry expectations still pass.

The run binds 395 source inputs and 10,420 runtime inputs, including 557 font
files, unchanged before and after. Its 344 archived members were restored and
hash-verified. See the [consumer report](consumer/README.md) for tolerances,
per-fixture assertions, raw PDFs/DOCX/ODT files and independent measurements.

## Preserved evidence and later arrivals

The structural audit verifies exact equality for completed fidelity evidence
(51 files), prior resume evidence (83 files), selected engine proofing source,
data, manifests, generators and tests (71 files), and the optional GECToR package
(40 files). It attributes inherited GECToR tooling and four newer morphology
paths to their respective donors, without claiming whole historical import-closure
equivalence. Historical runtime results retain their original source attribution.

The [later observation](later-ref-observation.json) completed at **17:21:18
Berlin time / 16:21:18 UTC** while this source was frozen. It records new AOT
proofing work, table-border/row-height PR #115, parallel Office qualification
PR #116, and later morphology/GECToR evidence. These heads are separately
identified in [later-arrivals.json](later-arrivals.json); they are outside the
initial integration cutoff and the qualified source above.

## Independent final audit and publication

The [independent final audit](independent-review/README.md) reconstructs raw
case outcomes, exact suite coverage, before/after input identity, and saved
consumer measurements without importing either qualification harness. It
accepts the reported totals with no discrepancies or pending evidence. Both
archives have exact indexed member sets: **447 members across two archives**.
The audit's evidence checks are not additional application-test passes.

The complete evidence was published at **`b0f6d806a8ce3869c5a52e51bc7fed2bd4dbdbba`**.
The [published-tree review](publication/published-evidence-review.json) verifies
the fetched remote tree, both archive hashes, unchanged qualified product source,
and ancestry of every captured incoming head. Subsequent publication receipts
change documentation only.

No GitHub Actions, workflow, check-run or commit-status endpoint was queried or
awaited. Incremental commits use `[skip ci]`. Git CLI write credentials were
unavailable, so publication used connected GitHub Git-data operations with exact
tree checks and non-force expected-head updates. Each saved checkpoint was
fetched back; original and parallel branches were retained.
