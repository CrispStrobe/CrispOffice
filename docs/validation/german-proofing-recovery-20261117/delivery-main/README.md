# Delivery-main field amendment — 17 November 2026

**Accepted product source:** `898c4c07f421d86a8cea460b13fd3e136088b553`.
**Incoming main:** `13e7172977d671190ba8c3cf964deec4d7473090`.
**Raw merged baseline:** `024ff173edfce136cd7788484a58233468a68387`.

The final PR readback found main had landed the earlier Office qualification and continuation plus #124 inline field conversion after the first completed evidence seal. The histories were reconciled, preserving the already-qualified grammar, AOT, column, tab, paragraph and chart fallback changes. The new production difference was confined to the ODT writer. Its field conversion required this bounded repair before delivery. [Integration decisions](integration.json)

## Resulting export behavior

The imported code emitted a native field as soon as an instruction fragment was recognized, then suppressed later runs through shared state. That lost the cached display and could hide later text when a field was malformed or nested.

The writer now validates a complete, balanced, unnested field packet in one paragraph before converting it. Instruction fragments are concatenated first. Native conversion accepts only `PAGE` or `NUMPAGES`, optionally followed by `MERGEFORMAT`, with unlocked metadata and exactly one ordinary cached run. The native element contains that cached text once, with the existing style, hyperlink and attached-comment handling retained.

Unsupported instructions or formatting switches, locked fields, malformed metadata, missing separators, nested fields, atomic results, multiple cached runs and mixed inline content retain ordinary cached serialization. XML parsing, invalid numeric entities and out-of-range character entities return to that fallback safely. Hidden field instructions remain metadata.

There is no text-suppression state. A depth guard only prevents promotion inside an outer field spanning paragraphs. Independent headers, footers, comments, notes, frames and hidden cell stories reset and restore that guard. It cannot consume cached runs or following text. The existing paragraph-level PAGE support and earlier column, tab, paragraph-break, keep-together, note, table and page-suffix implementations remain intact.

The incoming PAGE/NUMPAGES test was deliberately updated: parsed XML now checks one native field per instruction, each containing its cached display exactly once. The previous assertion required empty native tags and deletion of the cache.

## Local qualification

| Check | Result | Source |
| --- | ---: | --- |
| Final 22-case regression file on imported writer | 20 assertion failures, one missing-element exception, one passing control | Raw baseline `024ff173` |
| Identical regression file on repaired writer | **22 passed** | Inputs match `898c4c07` |
| Existing writer tests in the paired positive run | **16 passed** | Inputs match `898c4c07` |
| Focused six-file ODT cohort, Dart VM | **113 passed** | `898c4c07` |
| Portable four-file ODT cohort, compiled JavaScript/Node | **88 passed** | `898c4c07` |
| Strict analysis of writer and two changed test files | **No issues** | `898c4c07` |

All accepted positive checks have zero skips and unchanged source inputs during execution. The cohorts overlap. VM includes the existing writer and header/footer files that import `dart:io`; the Node cohort covers the portable field, page-field, paragraph and section cases.

The final regression file is byte-for-byte identical in the accepted before/after pair: SHA-256 `128182bc61e84f3b6e95ce1d717103372f54fff132647efe1a7dec7d970ce2fe`. Only the writer differs among their 323 common scoped inputs. The positive comparison additionally runs the existing writer test file. Before the product checkpoint, receipt `head` identifies the raw baseline while its recorded input hashes identify the repaired working tree; the final VM/Node/analysis receipts bind directly to the saved product commit.

The initial positive attempt had five test-helper failures because plain XML text extraction omitted ODF space elements. Its helper was corrected to decode spaces, tabs and line breaks, and the corrected tests were repeated on both writers. A subsequent out-of-range numeric-entity guard was added and the final identical pair repeated. Every earlier attempt remains archived; the accepted pair is `delivery-field-before-final` / `delivery-field-after-final`.

An independent read-only review found no blocking issue. The final writer is Git blob `22587d35eeb304d46a82094098db32842964902f`, SHA-256 `1a444fa754277a1fbb9840542b7a9d28eb76bb2d768a032279e8bbaae81bd873`. [Regression and final-run summary](../evidence/delivery-field-summary.json) · [Peer review](../evidence/delivery-field-peer-review.json) · [Verified gates](verification.json) · [Independent receipt/regression audit](regression-audit.json)

## Evidence continuity and limits

The original 167-member recovery archive is unchanged at SHA-256 `176fe525b22833eb238f493275059c999ddf9bbb286ccb6af3538316b5f33f9f`. This amendment has its own **38-member**, **258,100-byte** [archive](evidence.tar.xz) and [member index](evidence-index.json), SHA-256 `c35ec8d7c1b85495c948aea530522da50bd4eb7598729017e49036bb2fa88526`, preserving exact receipts, compressed logs, before/after source maps, earlier failed attempts and the readable summaries. Archive members restore under `evidence/`; summary mirrors remain one directory above in the parent report's `evidence/` directory.

[Source continuity](source-continuity.json) verifies that proofing, GECToR, Harper, AOT implementation, editor, Studio and tooling objects remain identical to the fresh proofing source `8d640302`. The prior German quality, morphology and native measurements keep that original attribution. The earlier closing-main Office qualification remains at `7002d750`; only the ODT writer changed afterward.

This is conservative ODT export support. DATE/TIME/TITLE, unsupported switches, nested/multi-run fields and arbitrary editable Word field metadata are not promoted to native ODF fields; their visible cached results remain. No new language-quality or performance claim is introduced by this amendment. No GitHub Actions workflow was dispatched or awaited.
