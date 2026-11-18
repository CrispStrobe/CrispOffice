# Native spelling quality — 18 November 2026

PR [#155](https://github.com/CrispStrobe/quds_office_suite/pull/155) is merged
at `1ffcf91a3443caf9a6e8b45a3e6cab3f041831ae`. This continuation improves
native spelling suggestions and German shortlist quality on top of that
integrated baseline. The qualified product is
`a8075778e2d1136b4e62e14eb42bcfd426e2a2b6`, saved incrementally on
`codex/native-spelling-quality-20261118`.

All **1,229 substantive tests** in the selected engine/editor cohorts pass,
with zero failures or skips. The same **25 smoke cases** produce identical
complete result objects in Dart VM, native AOT and compiled JavaScript.
[Machine-readable verification](verification.json),
[independent review](review.md), and the [evidence index](evidence-index.json)
bind those results to the delivered source.

## User-visible improvements

### Native system suggestions

- Filter unusable entries before the eight-choice display limit, preserving
  backend ordering. Empty, blank-looking, unchanged and duplicate replacements
  no longer occupy slots or produce an accidental Delete action.
- Reject malformed UTF-16, line/control characters and bidi embedding,
  override or isolate controls. Preserve legitimate multiword corrections,
  decomposed accents, supplementary letters, ordinary RTL text and internal
  ZWJ/ZWNJ used by real scripts.
- Inspect at most 64 candidates and reject replacements over 256 UTF-16 units
  before scanning their content. An unknown word with no usable replacement
  remains reviewable through Ignore or Add to dictionary.
- Protect partial edits to identifiers such as `Feler42` and `Feler_name`.
  Numeric/connector edges with combining marks and supplementary digits are
  handled through one grapheme traversal. Corrections to hyphen constituents
  and native CJK word segmentation remain supported.

The real Word review dialog is exercised through Flutter's default spelling
service and controlled native-channel responses. It finds the valid `a lot`
correction after unusable suggestions, applies it to `🙂 alot.`, and preserves
the exact source through undo/redo. A second scenario adds an unknown word to
the English personal vocabulary without modifying the document or undo history.

### German visible-choice shortlists

Dictionary lowercase/titlecase variants previously occupied separate internal
slots and then collapsed after applying source casing. The shortlist now
counts distinct displayed corrections, retaining the existing candidate order
and bounded search budget.

| Input | Suggestion limit | Previous result | Current result |
| --- | ---: | --- | --- |
| `LERNNEN` | 2 | `LERNEN` | `LERNEN`, `LERNTEN` |
| `Lernnen` | 2 | `Lernen` | `Lernen`, `Lernten` |
| `Lernnen` | 5 | Four distinct choices | Five distinct choices |

Exact declared personal spelling remains authoritative. Mid-sentence noun and
verb casing stays distinct, Swiss corrections retain their locale behavior,
and compound suggestions keep source separators. Continuing past duplicate
display forms can use more of the existing candidate budget; it does not
increase that budget or establish exhaustive suggestion recall.

## Incoming work and remote checkpoints

The [reconciliation](reconciliation.md) and [exact inventory](refs.json)
account for all captured fork and upstream branches and PR heads. The combined
inventory contains 359 refs identifying 233 distinct commits. Completed
Office work, Zotero #156, optional spaCy #139 and W7 #153 are contained in the
baseline; historical equivalent and superseded branches are documented.
All eight live upstream branch/PR heads are already baseline ancestors.
The concurrent Zotero tags checkpoint is recorded separately as ongoing work.

Main advanced while #155 was being merged. Only the engine/editor changelog
additions conflicted with #156; both sets of entries were retained in remote
commit `536ee2086ce46ab629d4d77144d1ca22a43e3c19` before the successful merge.

| Remote checkpoint | Saved work |
| --- | --- |
| `86b8b7a394759a72540b05d2ec40f412c1902485` | Native shortlist filtering and initial identifier guards |
| `deb6b06975db80ee7eb1e6a762edfa20fba80654` | German shortlist fix, native review tests, portable cases and reconciliation |
| `a8075778e2d1136b4e62e14eb42bcfd426e2a2b6` | Reviewed invisible-text and combining-mark edge fixes |

Every new checkpoint uses `[skip ci]`, a non-forced remote update and an
expected-head guard. Complete tree/blob identities were checked during remote
publication. No GitHub Actions, workflow, check or CI-status endpoint was
queried, awaited, dispatched or rerun.

## Local validation

| Final cohort | Files | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Engine proofing | 28 | 1,078 | 0 | 0 |
| Editor proofing | 9 | 151 | 0 | 0 |
| **Disjoint total** | **37** | **1,229** | **0** | **0** |

The 25 new regression tests are included once in those totals. Focused runs,
prior accepted checkpoints and hidden loading events are not added again.

| Identical final controls on baseline `1ffcf91a` | Baseline passed | Baseline failed | Final passed |
| --- | ---: | ---: | ---: |
| German shortlist | 8 | 6 | 14 |
| Platform adapter | 23 | 7 | 30 |
| Native review dialog | 0 | 2 | 2 |

These paired runs reproduce **15 baseline failures**, all repaired in the
final source. Baseline runs use isolated source/configuration or a separate
worktree; production source in the active workspace was not swapped.

Strict analysis with `--fatal-infos` passes for engine proofing, its tests and
the runner, plus the entire editor library and the nine selected editor test
files. All six changed Dart files format with zero changes; whitespace checks
pass. The 354 engine and 413 editor input bindings remain stable during their
accepted runs. Their 442 distinct combined inputs were rechecked against
delivery, including the pinned workspace dependency lock.

The portable runner passes 25 cases on each of three targets, or 75 case
executions. Full VM/native/JavaScript JSON bytes share SHA-256
`1ff7a2777f42e09da6919024f3e915b13b0519a740a71221f4c5d457b193bf9e`.

Flutter 3.47.8 / Dart 3.13.7 was restored from the hash-verified official
archive. All 162 hosted package archives matched their pinned hashes; no
tracked SDK constraints, dependency manifests or dictionary data changed.

## Reproduction and saved evidence

Resolve the workspace with the pinned Flutter SDK and dependency lock. Run
editor tests from its package directory so font assets resolve. In restricted
environments, point `TMPDIR` at a writable directory.

```sh
# packages/quds_office_engine
dart test test/proofing --reporter json --concurrency=2
dart analyze --fatal-infos lib/src/proofing test/proofing \
  tool/check_native_spelling.dart
dart run tool/check_native_spelling.dart
dart compile exe tool/check_native_spelling.dart -o /path/to/spelling-smoke
dart compile js -O2 tool/check_native_spelling.dart -o /path/to/spelling-smoke.js

# packages/quds_office_editor
flutter test --no-pub --concurrency=2 --reporter json \
  test/platform_spelling_provider_test.dart \
  test/platform_spelling_dialog_test.dart \
  test/word_manual_proofing_test.dart test/word_proofing_context_test.dart \
  test/word_proofing_correction_test.dart test/word_proofing_dialog_test.dart \
  test/word_proofing_geometry_test.dart test/word_proofing_navigation_test.dart \
  test/word_proofing_session_test.dart
```

[evidence.tar.gz](evidence.tar.gz) preserves 73 members: raw accepted and
baseline test events, source bindings, analysis/format results, full smoke
outputs, compiler receipts, runtime restoration records, source snapshots and
earlier attempts. Its members were reread and checked against the index after
creation. Earlier platform runs and the initial dialog fixture's missing
scroll-pump attempt remain attributed separately; they do not count toward
final qualification. Generated SDKs, executables and compiler caches are omitted.

## Scope and limits

The native adapter checks use controlled system-service/channel responses.
They do not newly qualify installed Android/iOS dictionaries, device-specific
accuracy or target-device latency. The finite German examples establish
regression behavior and cross-target parity, not general spelling accuracy.
No full application build or new external-native/model acceptance is claimed.
The existing AOT/RML removal and optional/default-disabled spaCy boundary are
preserved. Previously sealed native/model panels were not rerun for tuning.
