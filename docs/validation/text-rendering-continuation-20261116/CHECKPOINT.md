# Rendering continuation checkpoint

## Saved work and final pinned integration

The resumed rendering implementation and its completed 171-test engine and
66-test Flutter editor cohorts were saved remotely in `f23675a` and `bc195165`.
Their exact source inputs, logs, rendering artifacts and static checks are in
`engine-final/` and `editor-final/`. Both cohorts passed with unchanged inputs.
These counts overlap earlier qualification and are not added to it.

A final snapshot at **2026-11-16 20:10:54.959 UTC** pinned 185 fork/upstream
branch and pull-request heads. Pinned main `63194d8e` and the English, German,
Zotero-recovery and en-de/Harper tips merged cleanly using real Git merges.
All 185 pinned heads are included by ancestry. Later arrivals are outside
this frozen cutoff. See `integration-185/` for the snapshot, merge receipt,
license/source reviews, exact duplicate-patch evidence and ancestry audit.

The incoming work adds ODS page setup/header-footer support, English automatic
hyphenation, German advisory proofing refinements and Harper soft-hyphen source
projection. It retains the historical rendering evidence from `5ed98a` under
its original `editor/` and `runtime/` paths. Nine incoming Dart files received
formatter-only normalization, preserved in the integration evidence.

## Final combined qualification pending

The expanded runner retains the incoming progress reporting and bounded
process cleanup. The final gates cover 27 engine test files, 17 editor test
files and three pure-Dart Harper contract files, with strict changed-file
analysis, formatting and before/after input hashes. New receipts will be
written to `qualified-engine/`, `qualified-editor/` and `qualified-harper/`.
They supersede the overlapping earlier cohorts for the final combined source.

Harper contract tests use injected transport. They do not constitute a fresh
native/Wasm backend acceptance run. The genuine restored Flutter/Dart runtime
and locked dependency provenance are preserved in `runtime-resume/`.

## Evidence already established

The recovered baseline probes produced ten assertion failures, nine errors
and one success on baseline `0d19b16`; these expected failures establish the
previous defects. The independent Poppler recheck produced zero differing
pixels against the identity-glyph reference and exact authored scalar
extraction, with its original source binding in `resume-audit/`.

The rendering delta preserves distinct PDF character codes for Unicode aliases,
explicit CID-to-glyph mapping, valid TrueType glyph layout and font metadata.
The actual Flutter rendering tests passed against reopened embedded fonts.
The fixtures use synthetic Latin outlines under supplementary Unicode scalars;
they do not establish real emoji/CJK coverage or cross-cmap raster parity.

The new English GB patterns carry MIT terms; US patterns retain the explicitly
identified Kuiken permissive grant. The restricted underlying OUP word list is
not shipped. Existing MIT FontTools attribution is preserved. No new native
shaping backend or GPL dependency is introduced by the reviewed incoming delta.
Shared editor/headless shaping remains a future integration.

GitHub Actions are not queried, awaited, polled or rerun. Remote checkpoints
use `[skip ci]`; qualification is local.
