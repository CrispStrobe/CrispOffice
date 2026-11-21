# Final main follow-up

Qualified source is **`6426d8877d5a7a2405bdd9060a1b6c443a731cb0`**, tree `01152f796d3e1bcc0b7a128433661f2f0d4fc33d`. **76 editor tests across 10 focused suites pass**, with zero failures or skips. Strict analysis and formatting pass the renderer and its new regression test. All 1,251 engine/editor Dart inputs match before/after checks and the qualified Git commit.

Two explicit main continuations arrived after the separate finite 380-ref publication snapshot:

- **`a97295f9734eca570392dfead123bebcc93747cd`**, merging PR #335 / commit `d7c44360304f9f2bb96e021d36da4db4906b4307`, adds bounded proofing/selection path caches in `render_word_canvas.dart`.
- **`3440c90bc63f9d43edb7e64172bfec3d82036fee`** adds only typing-performance documentation. It introduces no further renderer source change.

Both main heads and the incoming implementation are ancestors of the qualified checkpoint. Other branches were not rescanned; the finite 380-ref snapshot remains separate and unchanged.

## Confirmed regression and correction

The new selection cache originally keyed geometry by page, caret endpoints and an always-true selection flag. Selection painting also depends on the active table band. A retained canvas therefore reused old text-selection tint after switching to a row/column band without changing its page or caret.

A new pixel regression compares the retained renderer with a fresh renderer using the same final document, layout and caret. It failed on incoming source (first differing byte 108080: 31 versus 36), then passed after the cache key included `selectedTableBand?.table` instead of the redundant flag. The bounded cache and the incoming optimization remain. No golden references were changed.

The 10-suite final gate covers selection geometry and Linux goldens, the new cache regression, proofing geometry/navigation, header/footer navigation, hyphenation paint/carets, underline paint, live review selection and table-grid history. The initial failing log and corrected one-test pass are retained; the one-test pass overlaps the final 76 cases.

## Source continuity and evidence

Compared with publication checkpoint `964783488cfa8079464e7dc80c1df6bb139323f5`, the only changed input is `render_word_canvas.dart`, and the only added input is `word_selection_path_cache_test.dart`. All engine inputs are unchanged, so the preceding 1,725-case engine qualification was not repeated. Final Studio Mail qualification ran after this renderer gate: all 143 cases pass, as recorded in the [work record](README.md).

The archive contains exact incoming/correction/documentation patches, raw JSON events, commands, analysis/format output, immutable source hashes and `main-followup.json`. No GitHub Actions were queried or awaited.
