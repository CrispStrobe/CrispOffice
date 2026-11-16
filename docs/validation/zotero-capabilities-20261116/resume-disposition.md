# Disposition of the alternate proofing resume checkpoint

The incoming `codex/proofing-20261116-resume` head is
[`4d395da7c1253dbebfce4a5065fdfd257939ce1c`](https://github.com/CrispStrobe/quds_office_suite/commit/4d395da7c1253dbebfce4a5065fdfd257939ce1c).
It diverges from the integrated proofing continuation at `fb5f138f`; it is
neither an ancestor nor a patch-equivalent copy of
[`52d6ae43b659875e92b06cbabdd8f206aabbad6c`](https://github.com/CrispStrobe/quds_office_suite/commit/52d6ae43b659875e92b06cbabdd8f206aabbad6c).
The latter was integrated with current main and the Zotero work in
`b6a6b4c42ad03eb8d0f8567e7800bb9e4e038fdb`.

**Keep the coherent `52d6ae43` implementation and adapt only the two demonstrated
caret/direction corrections from the alternate checkpoint.** The alternate
remote branch and its
[incoming-ref audit](https://github.com/CrispStrobe/quds_office_suite/blob/4d395da7c1253dbebfce4a5065fdfd257939ce1c/docs/validation/proofing-20261116/resume-remote-audit.json)
remain available. This disposition does not claim that every `4d395da` change
was merged.

## Feature and source comparison

| Area | Disposition |
| --- | --- |
| Proofing session | `4d395da` adds `lib/src/proofing/word_proofing.dart` and a separate controller integration. Keep `52d6ae43`'s `lib/src/embed/word_proofing.dart` part and its controller-owned session instead. It provides the corresponding checking, caching, vocabulary, rule, correction and document-change handling, integrated with review dialog, context menu, canvas findings and view lifetime management. Its regressions include field exclusion, stale findings and guarded corrections. Do not add the second session API. |
| Layout and selection | Keep `52d6ae43`'s engine-owned discretionary-hyphen presentation mapping, authored-control preservation in logical line text, header/footer source offsets and automatic-hyphen selection coverage. Replacing these files with the alternate versions would discard those changes. |
| Two retained correctness fixes | Adapt the alternate implementation's direction-aware discretionary-hyphen hit testing and caret boundary handling in `PaintRunText` and `CaretEngine`. An authored RTL soft hyphen maps its left half to the source end and its right half to the source start. A generated hyphen's sole source boundary places the caret after its ink in the glyph run's direction. Keep the integrated engine's `displayText`/source-span model. |
| Harper transport | Both continuations address dead-worker reuse, bounded timeout reporting and browser request-posting failures. Keep the integrated implementation and tests. The alternate positive-timeout constructor guard and typed isolate-startup failure conversion remain identifiable on its retained branch; they were not required for the two demonstrated layout defects and were not ported here. |
| Harper packaging and notices | The alternate adds opt-in host installation, source/artifact-bound verification tooling, toolchain working-directory handling and additional source-revision notice metadata. These are distinct optional-backend packaging changes retained on the alternate branch. Keep the integrated license revision checks, compiled-Dart web transport smoke and their evidence; do not replace them with the alternate tooling in this Zotero increment. |

## Why a whole-branch merge was rejected

A diagnostic `git merge-tree --write-tree --name-only --messages b6a6b4c 4d395da`
reported nine conflicts. It did not alter the checkout or index.

- Editor `lib/src/editor_word/caret_engine.dart` and `paint_run_text.dart`.
- Editor `test/word_hyphenation_paint_test.dart` (add/add).
- Harper `lib/src/harper_provider.dart`, `harper_transport_native.dart` and
  `harper_transport_web.dart`.
- Harper `test/harper_native_test.dart` and `harper_provider_test.dart`.
- Harper `tool/license_bundle.py`.

The auto-merged `office_controller.dart` was also incoherent: it retained both
the alternate session import and the integrated session part, with duplicate
`_proofing` fields, `proofing` getters, disposal implementations and language/
hyphenation setters. Resolving only the reported textual conflicts would not
produce a valid integration. The diagnostic tree was not merged.

## Focused validation of the selected fixes

`test/word_hyphenation_caret_test.dart` exercises actual `WordLayoutEngine`
documents and the fitted painter geometry, rather than hand-built glyphs. Its
four cases cover LTR/RTL authored soft hyphens, inside and nearest-run hit tests,
both caret APIs, visual stops, and automatic German breaks inside LTR and RTL
paragraphs while preserving source text and offsets.

Before the fixes, the new cohort compiled and reported one pass and three
behavioral failures: an RTL hit returned source offset `2` instead of `3`, and
the two automatic-break cases placed the caret `3.6630859375` points before the
expected end of the visible hyphen. After the fixes, all four cases and the
seven existing `word_hyphenation_paint_test.dart` cases passed (**11 tests**).
The combined final qualification is recorded separately; this focused count
must not be added again to any cohort that already includes these files.

Reproduction uses the genuine local Flutter dependency graph:

```sh
flutter test --no-pub --reporter expanded \
  test/word_hyphenation_caret_test.dart \
  test/word_hyphenation_paint_test.dart
```

No GitHub Actions jobs were queried, awaited or rerun.
