# Security, parser-robustness and format-coverage gaps (November 2026)

Status: 24 November 2026. This is the shared Quds/CrispOffice register for
untrusted document, archive and PDF input. The host-side companion is
CrispCloud's `docs/security-gaps-2026-11.md`.

This document replaces “we do not know where the gaps are” with a prioritized,
testable register. It does **not** claim parity with HarfBuzz, Acrobat, Word,
Excel or PowerPoint. A row is only `closed` when the implementation, a bounded
regression test and (where relevant) a fuzz reproducer exist at the cited
source revision.

## Source pins

| Repository | Revision | Role |
| --- | --- | --- |
| `quds_office_suite` | `f13e934d2` plus this register's follow-up commit | Engine/editor audit branch |
| `pdf/codec-expansion-20261124` | `a54b34422` | Draft PR #392, merged into the audit branch for qualification |
| `CrispCloud` | `ae968f74` | Host archive, provider and viewer paths |
| `covfuzz` | `715a0cd` | Fuzz runner and reproducer tooling |

The exact source revision of any future claim must be recorded with the test
receipt. A green local run is not hosted, installed or live-provider evidence.

## Severity scale

| Level | Meaning |
| --- | --- |
| **S0 Critical** | Code execution, sandbox escape, credential/key disclosure, or a signature/trust bypass that can be used without a local user mistake. |
| **S1 High** | Small untrusted input can exhaust memory/CPU or terminate the app; a malformed document silently produces a trusted-looking result; public-key signature is presented as verified when it is not. |
| **S2 Medium** | Reliable wrong output, silent data loss, UI freeze, or accessibility/security-relevant subset gap with a bounded workaround. |
| **S3 Low** | Cosmetic or rare fidelity gap with no trust boundary impact. |

## Gap register

| ID | Severity | Area | Finding and evidence | Status |
| --- | --- | --- | --- | --- |
| SEC-001 | S1 | DEFLATE | `RawDeflate.inflate` had an optional-only output cap and accumulated decoded bytes in a growable `List<int>` (about 8 bytes per byte on a 64-bit VM). A future caller could omit the cap. | **Closed** in this branch: default 256 MiB bound, explicit PDF/OPC/ZIP recovery bounds, and a growable `Uint8List` buffer. |
| SEC-002 | S1 | PDF Flate | `PdfFlate.decompress` inflated without a decoded-size bound. It is reached by content streams, xref streams and object streams during `PdfFile.open`. A small Flate bomb could demand tens of GiB. | **Closed**: 64 MiB per-stream bound with a typed `PdfOpenError.limit`; regression test. |
| SEC-003 | S1 | OPC/ZIP parts | `OpcPackage.openBytes`, `OfficeRepair` and report packages read members with `zip.read(name)` without `maxBytes`, so the ZIP-declared size was not an actual-output bound. Repair then re-read every member. | **Closed**: 256 MiB per-part decoded bound, 100,000-entry package bound, bounded report reads. |
| SEC-004 | S1 | ZIP recovery | `readRelaxed`, `openStream` and `ZipRecovery.scanLocalMembers` inflated hostile fallback input without a bound; `readRelaxed` could return compressed bytes as content. | **Closed**: 256 MiB actual-output bound for relaxed/stream reads and recovery; stored bytes still fall back only for malformed members. |
| SEC-005 | S1 | DEFLATE header | A dynamic-Huffman code-length repeat could write past the `hlit + hdist` table and raise `RangeError`, bypassing typed rejection. | **Closed**: repeat bounds and “no base length” checks throw `ZipDeflateException`; fuzz target added below. |
| SEC-006 | S1 | PDF page interpretation | `PdfFile.displayList` caught every object and returned an empty page. The interpreter also swallowed every `Do` XObject failure. A malformed page could look legitimately blank. | **Closed (diagnostic path)**: recoverable failures keep already-produced ops and set `PdfDisplayList.error`; `Error` subclasses are no longer swallowed and are left to fuzzing. Host blank-page messaging remains S2 below. |
| SEC-007 | S1 | Image allocation | `PdfImageCodec.decodePng` trusted IHDR dimensions and inflated IDAT without a bound; the package fallback decoded the same bytes after the core rejected them. JPEG dimensions were also unbounded. | **Closed**: 32 MP source-pixel bound before decode, expected-raw Flate bound, and header checks before the package fallback. |
| SEC-008 | S1 | PDF signatures | A matching CMS `messageDigest` was exposed as `PdfSignatureStatus.valid`, although RSA/ECDSA, certificate chain, revocation and system trust were not checked. A digest match does not prove signer possession. | **Partially closed**: API now exposes `digestMatches`, `signatureVerified == false` and `trusted == false`; UI/documentation must not call this “verified”. Real PKIX verification remains open. |
| SEC-009 | S1 | PDF image codecs | JBIG2 arithmetic/symbol/text/refinement and JPX advanced color/Part 2 paths are not complete; unsupported streams can become placeholders. Draft PR #392 adds bounded JP2/J2K core decoding, JBIG2 generic/symbol-dictionary/MMR and packed predictors. | **Integrated on audit branch**: PR tests pass; advanced paths remain S2/S3. |
| SEC-010 | S1 | PDF color | `/ICCBased` uses `/N` as Gray/RGB/CMYK and ignores the profile. ICC rendering intents, overprint, transfer functions and full CMS are absent. CMYK output is an ICC-less approximation. | **Open** — fidelity and print-trust gap; no color-managed certification claimed. |
| SEC-011 | S2 | OpenType shaping | GSUB ligatures and GPOS MarkToBase are implemented; other GSUB/GPOS lookups, variable fonts, mark-to-mark/mark-to-ligature, kerning subtables and complex-script features are approximated or ignored. | **Open** — register in `text-rendering-strategy.md`; no HarfBuzz-parity claim. |
| SEC-012 | S2 | Word layout | Footnotes, tables, frames, sections, fields, revisions and TOCs have deep subsets; exotic wrap, anchoring, vertical text, math, drawing and field-update semantics remain. | **Open** — see `office-remaining-gaps.md` and `office-fidelity-gaps.json`. |
| SEC-013 | S2 | Excel formulas | Formula coverage is a documented subset; unsupported functions may become errors or blanks. Calculation is not an Excel-compatible security boundary. | **Open** — no formula-accuracy parity claim. |
| SEC-014 | S2 | PowerPoint drawing | Custom geometry, preset breadth, gradients, effects, 3D, SmartArt, animations and embedded objects remain subsets. | **Open** — see `office-remaining-gaps.md`. |
| SEC-015 | S2 | PDF interpreter breadth | Type 1/2/3 patterns, axial/radial shading beyond Type 2/3 strips, transparency groups, blend modes beyond Normal/Multiply/Screen and some font programs remain approximated. | **Open** — typed unsupported where possible; no Acrobat parity claim. |
| SEC-016 | S2 | Host blank-page/error surfacing | The engine exposes `PdfDisplayList.error`; the editor/viewer has not yet rendered a user-visible “page could not be interpreted” notice for every surface. | **Open** — UI follow-up. |
| SEC-017 | S2 | Archive CPU on UI isolate | CrispCloud archive readers are memory-bounded but several run synchronously on the UI isolate up to the 64 MiB viewer limit. | **Open** — host register. |
| SEC-018 | S2 | Legacy DOC | The vendored legacy parser is bounded and only produces a preview; it is not a full Word binary layout engine. | **Open by design** — explicit preview notice, not a fidelity claim. |
| SEC-019 | S2 | XLSB | No BIFF12 reader/writer; preview only. | **Open by design** — never route BIFF12 through BIFF8. |
| SEC-020 | S1 | Fuzz coverage | No committed, reproducible fuzz campaign covered DEFLATE, ZIP/OPC, PDF COS/filters/interpreter, XML and legacy Office at every revision. | **In progress** — `covfuzz` harnesses and bounded CI job. |
| SEC-021 | S1 | Excel open-path budget | `decodeOfficeOpen` recalculated formulas without a work budget; the dependency builder expanded every coordinate of a whole-sheet range, and `REPT` built unbounded strings. A 1 KB workbook could hang or exhaust memory at open. | **Closed**: shared `FormulaBudget`, 1,000,000 dependency-cell cap, 2,000,000 range-cell cap, 1,000,000 evaluation cap, 1,000,000-character text cap, `REPT` capped at Excel's 32,767. |
| SEC-022 | S1 | Nested Word tables | `_readTable` and `_layoutContainedBlock` recursed without a depth limit; a small nested-table DOCX could overflow the stack. | **Closed**: XML table depth 128 and contained-layout depth 64/128 limits; deserializer regression test. |
| SEC-023 | S1 | OpenType table amplification | GSUB/GPOS read lookup and subtable counts without totals, GPOS coverage-2 could iterate billions of ranges, and composite glyph outlines recursed through self-references. | **Closed**: 4,096 lookup/subtable caps, 4,096 coverage-glyph cap, composite depth 16 + active-glyph set, `loca` bounds. Differential shaping remains SEC-011. |
| SEC-024 | S1 | PDF image dimensions | Image XObject width/height were trusted before `w*h*4` allocations; an empty ImageMask could request gigabytes. Inline images multiplied width/height without a budget. | **Closed**: 32 MP and 65,535-dimension caps before decode; placeholder on rejection. |
| SEC-025 | S1 | JBIG2 error escape | `jbig2 1.0.0` can throw `UnsupportedError` for legal unknown-length segments; the adapter did not catch that `Error`, so the image vanished and the page could abort. | **Mitigated**: `UnsupportedError` maps to typed `PdfFilterUnsupported`; the dependency's 32-bit allocation fields still need a fork/budget (SEC-009). |
| SEC-026 | S1 | Glyph outline bounds | `GlyphOutlineDecoder` trusted each glyph's contour count, non-monotonic endpoints, instruction length and repeat flags. A font with a valid SFNT directory but hostile `glyf` data escaped `RangeError` from the byte cursor (fuzz: 160 escapes, minimal 319,622-byte font). | **Closed**: contour/endpoint/instruction/repeat bounds are checked before allocation; `decode` converts any residual cursor `RangeError` to an empty outline. Regression `glyph_outline_bounds_test.dart`; `fuzz_font.dart` covers SFNT/CFF/cmap/GSUB/GPOS/outlines. |
| SEC-027 | S1 | CFBF stream sectors | `CfbfFile._readFatStream` and `_readFat` used an untrusted directory start sector or DIFAT/FAT index to call `ByteSource.view` before checking the FAT/container bounds. A small mutated MSG escaped `RangeError` from the Outlook MSG preview (fuzz: 10 escapes in 50,003 runs). | **Closed**: FAT size, FAT index, mini-FAT index and every sector view are checked before allocation/read; typed `CfbfException` is returned. Regressions `cfbf_reader_bounds_test.dart`; CrispCloud `fuzz_mail.dart` is clean over the same MSG seed. |
| SEC-028 | S1 | OPC recovery aggregate | `OfficeRepair` and ZIP recovery bounded individual member reads but could still decode an unbounded number of stored/relaxed members in one recovery pass. | **Closed**: recovery and repair carry an aggregate decoded-byte budget; stored/relaxed reads reject when the remaining budget is exhausted. Regressions in `office_repair_test.dart` and `zip_bounded_read_test.dart`. |
| SEC-029 | S2 | Inline JPEG framing | Inline DCT image data was sized by the generic inline-image byte count; malformed or adjacent operators could be consumed as JPEG payload. | **Closed**: inline JPEG uses its codestream markers to find the exact frame boundary. Regression in `pdf_filter_expansion_test.dart`; browsers/VM tests are unchanged. |

## Closed in this audit wave

### DEFLATE and ZIP

- `RawDeflate` now has `defaultMaxOutputBytes = 256 MiB`. Omitting a tighter
  caller bound no longer means “unbounded”.
- The inflater writes into a doubling `Uint8List`, not a growable `List<int>`.
  The 32 KiB backreference window is unchanged.
- Dynamic-Huffman code-length repeats are bounded and cannot overwrite the
  table or use an undefined previous length.
- PDF Flate streams are capped at 64 MiB of decoded output and fail with
  `PdfOpenError.limit`.
- OPC parts are capped at 256 MiB each, with a 100,000-entry package cap.
  Report packages use their existing 64 MiB entry budget for the actual read.
- Relaxed and streaming ZIP reads are capped at 256 MiB of actual output.

Regression tests:

```bash
cd packages/quds_office_engine
dart test test/deflate_test.dart test/zip_bounded_read_test.dart
dart test test/pdf_file_test.dart test/pdf_filter_expansion_test.dart
```

### PDF image allocation and page diagnostics

- PDF PNG source pixels are limited to 32 MP before any RGB allocation; IHDR
  dimensions are checked before the package fallback.
- JPEG frame dimensions above the same budget are rejected.
- A recoverable interpreter error now preserves the ops already painted and is
  exposed as `PdfDisplayList.error`/`failed`; `Error` subclasses escape to the
  fuzz/regression process instead of being silently converted into a blank page.
- PDF signatures now expose the distinction between a digest match and actual
  signature/trust verification.

### Fonts and compound files

- `GlyphOutlineDecoder` now checks contour count, monotonic endpoint order,
  instruction length, flag repeats and the point budget before allocation.
  Residual cursor range failures become an empty outline.
- `CfbfFile` checks stream size and FAT/DIFAT/mini-FAT sector indices before
  every `ByteSource.view`; hostile MSG/compound streams produce typed
  `CfbfException` instead of `RangeError`.
- `tool/fuzz/fuzz_font.dart` covers SFNT, CFF, cmap, GSUB/GPOS and glyph
  outlines; `cfbf_reader_bounds_test.dart` and `glyph_outline_bounds_test.dart`
  pin the minimized repros.

Regression tests:

```bash
cd packages/quds_office_engine
dart test test/cfbf_reader_bounds_test.dart test/bounded_cfb_reader_test.dart \
  test/glyph_outline_bounds_test.dart
dart run tool/fuzz/fuzz_font.dart 10000
```

## Open work, in priority order

### P0 — real signature trust and color correctness (S1)

1. Parse CMS signer info, certificate sets and signed attributes with strict
   DER bounds.
2. Verify RSA PKCS#1 v1.5/PSS and ECDSA signatures over the signed attributes.
3. Validate certificate validity, key usage, chain and revocation against an
   explicit host trust store. Keep “digest-only”, “cryptographically valid” and
   “trusted” as separate public states.
4. Add ICC parsing/application for Gray/RGB/CMYK and rendering intents, or keep
   an explicit “ICC ignored” state in every API and UI. Do not claim print
   certification.

### P1 — OpenType and layout depth (S2)

1. Publish a feature-by-feature table for GSUB/GPOS, variable fonts, mark
   attachment, kerning, script tags and fallback behavior.
2. Add differential shaping tests against HarfBuzz fixtures for Arabic, Indic,
   Hebrew and Latin kerning/ligatures.
3. Add malformed-font fuzzing for `SfntFont`, CFF and cmap parsers.

### P2 — Office semantics (S2)

1. Make every unsupported Word/Excel/PowerPoint construct fail visibly or
   round-trip as preserved-unknown, never silently approximate.
2. Expand the existing fidelity corpus for drawings, fields, tables, charts and
   formulas.
3. Keep macro/ActiveX execution inert; this register does not make macro
   execution a goal.

### P3 — fuzz program (S1)

See [the fuzz plan](#fuzz-program).

## Fuzz program

The engine is pure Dart, so the high-value targets run without Flutter:

| Target | Entry point | Seed |
| --- | --- | --- |
| Raw DEFLATE | `RawDeflate.inflate` | stored, fixed and dynamic streams |
| ZIP/OPC | `ZipReader.fromBytes`, `OfficeRepair.open` | small DOCX/XLSX/PPTX |
| PDF COS | `PdfFile.open` | writer PDF, encrypted PDF, xref stream |
| PDF filters | `PdfFilters.decodeResult`, `PdfFile.displayList` | Flate, predictor, JPX, JBIG2, CCITT |
| XML/OOXML | `XmlDocument.parse`, `WordDeserializer().read` | minimal package parts |
| Fonts | `SfntFont.parse`, `PdfCffHost.forFlutter`, GSUB/GPOS, `GlyphOutlineDecoder` | bundled Liberation/Noto/Tajawal faces |
| Legacy DOC | `legacy_doc_parser` entry | small binary fixture |

`covfuzz` is the preferred runner because it already provides blind mutation,
minimized reproducers, slow-parse detection and guard verification. For deep
coverage behind format magic, `package:fuzz` (`kevmoo/fuzz.dart`) is a faster
alternative: it rewrites the target to a non-destructive AST overlay and drives
libFuzzer at ~60–105k execs/s with per-input edge/comparison feedback, while
`covfuzz` obtains process-global VM coverage at ~100–1000 execs/s. Use
`covfuzz` for the committed blind campaign and `package:fuzz` only when a
specific magic/precondition needs deep evolutionary search. Do not add both as
a permanent dependency without a measured reason.

Planned gates:

```bash
# blind, bounded and reproducible
dart run tool/fuzz/fuzz_deflate.dart
dart run tool/fuzz/fuzz_zip.dart
dart run tool/fuzz/fuzz_pdf.dart
dart run tool/fuzz/fuzz_xml.dart
dart run tool/fuzz/fuzz_font.dart

# deep target, only when clang/libFuzzer is available
dart run fuzz run --max-total-time=60 test/fuzz/pdf_cos_fuzz.dart
```

No fuzz result is accepted as a fix until the minimized input is a regression
test, the guard is marker-wrapped where appropriate, and
`covfuzz_mutverify` (or an equivalent revert check) proves the test fails
without the guard.

## Verification commands

```bash
cd packages/quds_office_engine
dart analyze
dart test

cd packages/quds_office_editor
flutter test

# focused security regressions
cd ../quds_office_engine
dart test test/deflate_test.dart test/zip_bounded_read_test.dart \
  test/pdf_file_test.dart test/pdf_filter_expansion_test.dart
```

## Non-claims

- The engine is not HarfBuzz, Acrobat, Microsoft Word, Excel or PowerPoint.
- Digest-only PDF signatures are not “verified signatures”.
- ICC profiles are not applied and PDF/X or PDF/A certification is not claimed.
- Unsupported Office constructs are not silently treated as equivalent.
- Local tests are not hosted CI, installed-app or live-provider evidence.
