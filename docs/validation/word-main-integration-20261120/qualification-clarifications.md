# Clarifications for the affected Word qualification

This note supplements the unmodified raw qualification receipt for remote commit cdd98460c2eed261719c660351f11adc962e2ca5 (tree aee18e93719bc51dcd94c003ac9dfab3c0851bdc).

Raw receipt SHA-256: 66edc44f8ced980ece429fd630a717202938248944bb511af3f7410bcca4ef6f.

## Results and case accounting

- The 23 affected macro files passed all 709 cases. Their identities exactly match the corresponding subset of the earlier accepted 3,598-case corpus; see macro-case-overlap.json. These reruns are not additional macro cases. The other 2,889 historical identities were not rerun in this affected check.
- The 26 native/layout files completed 312 cases: 311 passed and one failed on the fixture geometry assumption described below.
- The five editor files completed 111 cases: 103 passed, none failed, and eight were explicitly skipped because their image-only floating DOCX fixtures contain no editable paragraphs. These skips are not passes or missing-file errors.
- Strict whole-engine analysis and analysis of the changed editor font source plus the five editor test files both passed.
- Both actual BAS examples, supplied byte-identically as base64 compile-time input, passed on the Dart VM and optimized dart2js/Node. Their results matched for eight and thirteen native operations respectively.

The raw receipt remains success=false. Its success predicate rejects both the one failed native case and any skipped editor case. This note does not change that predicate or rewrite the original result. A later focused receipt must qualify the authorized fixture correction; the eight inapplicable editor scenarios remain explicitly outside passing coverage.

## Correction to the font selection rationale

The editor selection_rationale field in qualification.json overstates alias-specific coverage when it says the existing tests exercise the filename aliases with real font fixtures. The existing office_system_fonts_test.dart uses display-style filenames, including Arial.ttf, Arial Bold.ttf and Arial Italic.ttf. It tests valid font metadata, limits, precedence, rejection and fallback with licensed Liberation-based fixtures carrying synthetic family names.

The eight new lowercase mappings (arial.ttf, arialbd.ttf, ariali.ttf, arialbi.ttf, times.ttf, timesbd.ttf, timesi.ttf and timesbi.ttf) were source-reviewed and statically analyzed; no separate alias probe was run. Default host discovery on macOS, Windows or Linux was not executed by these explicit-directory fixtures. Do not infer cross-platform installed-font validation from this run.

## Original Indic fixture failure and narrow correction

The failing case is test/word_contained_text_wrap_test.dart: Indic cell clusters keep their owners through direct and isolate saves. It expected logical-index lines [[0], [1, 2, 3], [4, 5, 6]] but observed [[0, 1, 2, 3], [4, 5, 6]]. The earlier containment/ownership check passed; the changed line breaks retain every codepoint and both complete conjunct clusters.

The fixture hardcoded a 42-point outer cell. With the earlier 5.4-point padding on each side, its text area was 31.2 points. Incoming main intentionally changed each pad to 4.25 points, increasing that same cell text area to 33.5 points and allowing A plus the first Indic conjunct on the first line.

The authorized test-only correction defines contentWidth = 31.2 and derives the outer grid width as contentWidth + 2 * LaidOutLine.tableCellPad. It preserves every exact glyph-index, fit, text, direct-save, isolate-save and repeated-roundtrip assertion. Production behavior and incoming padding remain unchanged. The original failure stays in the raw event log.

## Source and runtime boundaries

All 1117 captured source inputs and captured runtime inputs matched before and after the frozen run. HEAD was unchanged and the worktree was clean when the run ended. Compared with 85f4ef96ab4def73b68eccbc82105d89ae5f943b, the only engine/editor production changes were Word layout, Word deserialization, and the editor font filename table. The VBA compiler, automation sources and macro test source files were unchanged.

These are local native document/layout/editor results. They do not constitute a Microsoft Word or COM execution test, or a cryptographic validation of preserved DOCM signatures.

## Explicit editor skips

- incremental layout equals full layout fixture legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-both.docx — no paragraphs to edit.
- incremental layout equals full layout fixture legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-control.docx — no paragraphs to edit.
- incremental layout equals full layout fixture legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-horizontal.docx — no paragraphs to edit.
- incremental layout equals full layout fixture legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-margin-quarter.docx — no paragraphs to edit.
- incremental layout equals full layout fixture legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-negative-quarter.docx — no paragraphs to edit.
- incremental layout equals full layout fixture legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-outline-shadow.docx — no paragraphs to edit.
- incremental layout equals full layout fixture legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-quarter.docx — no paragraphs to edit.
- incremental layout equals full layout fixture legacy_doc_parser/test/fixtures/fidelity/image-appearance/authored/floating-vertical.docx — no paragraphs to edit.
