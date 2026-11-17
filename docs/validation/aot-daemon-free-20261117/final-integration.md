# Final captured-reference integration

The immutable `incoming-final.json` snapshot contains **277 exact branch/PR
references**. After the eight sequential merges below, all 277 captured revisions
are ancestors of integration head `0f422cecd3cd12ffb27b6f33818fe4198b593c68`; none are missing. The
[evidence record](evidence/final-integration-ancestry.json) includes every exact
SHA, the snapshot hash, and the ancestry verification command. No fetch or CI
check was used during this reconciliation.

## Merge decisions

- **Main columns and chart data (`edd023c3`)**: retain multi-column ODT sections
  and ODP chart values represented as tables, together with the existing ODP
  hyperlink assertion. Each feature block and chart fixture occurs once.
- **German publication inventory (`52e548bd`)**: retain the incoming recovery
  inventory and validation history without changing current feature code.
- **Office resume (`60a116d2`) and consolidation (`f5021f1c`)**: retain exact ordered
  emitted tab stops in paragraph style identity, including decimal alignment,
  explicit leader characters, and invalid-position omission. Use the same
  serialized representation for identity and output. Keep validated positive
  table-column widths, nullable/nonnegative minimum row heights, valid cell
  colors, independent borders, and canonical emitted-value cell style keys.
  Preserve the original tab-cache regressions. The independently authored
  resume fidelity suite is retained as `odt_table_tab_resume_test.dart`; the
  consolidation suite keeps `odt_table_tab_fidelity_test.dart`.
- **German predicate and evaluator work (`f5021f1c`)**: accept the bounded linear
  predicate scan and its regressions, plus execution of the exact admitted
  publisher-source bytes rather than unverified Python bytecode.
- **GECToR continuation (`d4b6e5b4`)**: accept irregular-participle precedence,
  guarded per-request prediction reuse, regression tests, and evidence history.
  Retain the stronger merged ODT leader serialization. Update the incoming
  equivalence regression so rounded hyphen stops reuse a style while an
  underscore stop remains distinct and keeps its authored leader text.
- **Equivalent feature/vendor heads (`2c7d58d2`, `a86a4ec6`, `66273aa2`)**:
  preserve their ancestry, applying the columns/chart implementation once.
- **Cross-cutting conflicts**: retain the frame-aware `readOdfParagraphTexts`
  compatibility alias, both sets of paragraph decoration coverage, the current
  daemon-free proofing documentation, and all current native/client/CLI/Studio
  source. No AOT or Studio source changed from the pre-incoming checkpoint.

## Local merge commits

- `401b59dbf432840e377e1537ed5dec8b6dd07793` — Merge final main columns and chart data while preserving links [skip ci]
- `3c66d5c0e29a1e3461106847231031bba5750ae0` — Merge final German proofing publication inventory [skip ci]
- `4d0b2c61e09db460e2be3325f547a35bb235fbd5` — Merge Office fidelity continuation with daemon-free AOT retained [skip ci]
- `ae6a7701e44ad7e96c606df55e9427baf89b7557` — Merge final Office consolidation with canonical tab and cell styles [skip ci]
- `82079302eddae3dbc38077d5e7f7bdf6fe7f00f9` — Merge GECToR reuse and participles while preserving precise ODT leaders [skip ci]
- `7c37fb6972b09ed0d3f513c94f218fbbff25f65b` — Record equivalent captured ODT column feature ancestry [skip ci]
- `ace7e15b166ebd521112a6f791bfdf51865a1eb5` — Record equivalent ODP chart feature and retain hyperlink assertion [skip ci]
- `0f422cecd3cd12ffb27b6f33818fe4198b593c68` — Record equivalent vendor column and chart histories without duplication [skip ci]

## Production and test changes since `eaac7081`

The following list is the package/tool diff used to select final local
revalidation. Documentation and historical evidence added by the incoming
branches remain in the commit history as well.

```text
M	packages/quds_office_engine/CHANGELOG.md
M	packages/quds_office_engine/lib/src/proofing/german_grammar.dart
M	packages/quds_office_engine/lib/src/proofing/german_spelling.dart
M	packages/quds_office_engine/lib/src/slide/serial/odp_presentation_writer.dart
M	packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart
M	packages/quds_office_engine/test/odp_presentation_writer_test.dart
M	packages/quds_office_engine/test/odt_document_writer_test.dart
A	packages/quds_office_engine/test/odt_paragraph_decoration_fidelity_test.dart
M	packages/quds_office_engine/test/odt_paragraph_decoration_test.dart
A	packages/quds_office_engine/test/odt_tab_stop_fidelity_test.dart
A	packages/quds_office_engine/test/odt_table_tab_fidelity_test.dart
A	packages/quds_office_engine/test/odt_table_tab_resume_test.dart
M	packages/quds_office_engine/test/proofing/german_noun_agreement_test.dart
A	packages/quds_office_engine/test/proofing/german_participle_suggestions_test.dart
M	packages/quds_proofing_gector/README.md
M	packages/quds_proofing_gector/lib/src/backend.dart
M	packages/quds_proofing_gector/lib/src/decoder.dart
M	packages/quds_proofing_gector/lib/src/native_backend.dart
M	packages/quds_proofing_gector/lib/src/segmentation.dart
A	packages/quds_proofing_gector/test/inference_reuse_test.dart
M	packages/quds_proofing_gector/test/native_backend_test.dart
M	tools/proofing/german_model/evaluate_candidate.py
M	tools/proofing/german_model/test_candidate_admission.py
```

Targeted revalidation covers the prior ODF/search cohort plus the incoming
fidelity suites and chart/column cases, changed writer/source analysis, German
proofing, GECToR contracts, and Python admission guards. Its results are recorded
separately after this checkpoint; this integration record makes no claim that
those final-tree runs have already completed.
