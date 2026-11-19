# Layout/theme integration — accepted local qualification

The corrected, expanded GUI qualification **passed** at published source
checkpoint `61bb3ee42a385c5ffaffa44047693a6f378a8424` (tree
`c812fb1f2d1156099f50313390346b98f8f3d56a`). This checkpoint includes GUI head
`8c6acd04637ef627959fe40f518254ed538ab087`, preserved remote main
`caf378f40fd5bda50f504a6816404d01d8bbb8f8`, and planning-only draft head
`9d6cd0504094632825d3a0990a37fffd5c1b2c05`, together with the reviewed fixture
and PPTX table-color corrections.

The tests ran locally on the official **Flutter 3.47.8** SDK, its bundled Dart,
and the Linux Flutter tester. GitHub Actions were neither queried nor awaited.

## Results

| Gate | Accepted result |
| --- | --- |
| Ten selected editor suites | **213 passed**, zero failures or skips |
| Eleven selected Studio GUI suites | **116 passed**, zero failures or skips |
| Three repeated Studio mail suites | **18 passed**, zero failures or skips |
| Total distinct cases in this run | **347 passed** |
| Strict editor source/test analysis | Exit **0**, no issues in 14 selected items |
| Strict Studio source/test analysis | Exit **0**, no issues in 20 selected items |
| Source/runtime input stability | All **2,495 hashes unchanged** |
| Copied full-workspace manifests | All **20** match repository counterparts |
| Repository source binding | All **2,312 recorded repository inputs** match the tested Git checkpoint |

All three test commands exited **0** and each raw JSON reporter ended with
`success: true`. The 18 mail cases repeat the earlier mail UI qualification and
must be counted once across retained runs. This run contributes **329** passing
editor/Studio GUI cases beyond those repeated mail cases. Counts are based on
repository suite path plus test name, rather than adding historical attempts.

## Selected coverage

The editor cohort includes the new chrome/theme, dark Word/Sheet, dark Slide,
and page-layout suites, alongside existing embedding/controller, tab-stop
ruler, conditional Sheet rendering, Word selection paint, header/footer
navigation, and general editor tests. It checks atomic page-layout updates and
undo, default and authored document colors, text backing during Slide painting
and transitions, and the existing embedding behaviors.

The Studio cohort covers layout commands and dialogs, paragraph drafts and
mixed formatting, unit precision and cancellation, stale targets, active
header/footer formatting and undo, Slide/Sheet commands, dark chrome, narrow
Arabic layout, comments and review keyboard behavior, Zotero shortcuts, and
File/Desktop/Ribbon behavior. The newest incoming GUI case verifies the
first-page header independently of standard-header and body formatting. New
assertions also verify inactive-tab contrast and unclipped Arabic tab glyphs.

The repeated mail cohort has 12 restore widget cases, one native MIME/archive
round trip, and five localized portability layout cases. Its optional PNG
generator was disabled; all five layout cases executed and **none was skipped**.
The native round trip used the default SQLite 3.9.1 hook with empty user defines;
the actual hook input/output and library hash are retained in
`native-runtime.json`.

This is a deliberately selected integration cohort, not a claim that every
editor or Studio test in the repository was executed. Macro/JavaScript and mail
store qualification have their own retained acceptance records.

## Corrections qualified by this run

The existing embedding fixtures now provide a standard application Overlay
and dispose their externally owned Word controllers before Flutter checks
pending timers. The pre-GUI failure reproduction remains in
`../incoming-layout-theme/`. All 510 existing assertion expressions were
retained byte-for-byte, default review/proofing stayed enabled, and all 88 embed
cases pass here.

The dark Slide test now measures antialiased black glyph coverage on white,
retaining the original threshold and the other exact-color assertions. It
also compares the white-cell raster exactly against adaptation disabled and
rejects both incorrect light ink and a blank cell. The initial pixel failure,
diagnostic crops, and correction evidence remain separate in
`../incoming-layout-theme-final/` and
`../final-review/dark-slide-corrected/`.

Once that raster assertion was corrected, its unchanged PPTX export assertion
exposed a concrete parser omission: explicit table-cell text color was assigned
to the enclosing shape rather than the current cell. The parser now assigns
that color to the current table cell when present. Focused parser round-trip
evidence is retained in `../independent-review/slide-table-color/`. All six dark
Slide cases, including the original exported/reopened color assertions, pass
in this fresh full editor run.

Strict Studio analysis also passes after the incoming measurement callback's
multiline null guard was enclosed in braces. That correction preserves its
behavior. Its exact diff and focused checks remain with the prior failed
attempt. Neither failed full attempt was overwritten or recast as accepted.

The latest draft mail-resume branch contains planning and reconciliation files
only. Durable-resume runtime behavior is not claimed as implemented or accepted
by this GUI qualification; `frontier-review.json` records that distinction.

## Source and runtime binding

The full 19-member Flutter workspace uses copied manifests and live links to
the repository's current library, test and asset sources. Its complete package
configuration was used with `--no-pub --concurrency=1`; the repository's separate
macro validation configuration was not changed. The engine link points at the
current source, including the PPTX parser correction.

Before and after snapshots include repository library sources and shared
configuration, all tracked editor/Studio test and support files, relevant assets
and fonts, the full workspace manifests/lock/package configuration, dependency
manifests, and SDK runtime binaries. `source-binding.json` verifies every
recorded repository input against the exact tested Git commit. The distinct
counts and artifact manifest are independently reproducible from the retained
raw reporters and files.

## Evidence

- `receipt.json`: all five exact commands, environments, exit codes, log hashes,
  test summaries and unchanged-input result.
- `editor-tests.stdout.log`, `studio-theme-tests.stdout.log`, and
  `repeated-studio-tests.stdout.log`: original JSON reporters, with separate
  stderr and command receipts.
- `*-summary.json`, `suite-counts.json`, and `distinct-tests.json`: completed
  visible cases and deduplicated counts.
- `inputs-before.json`, `inputs-after.json`, and `input-stability.json`: all
  2,495 recorded execution input hashes.
- `source-frontier.json`, `source-binding.json`, and `frontier-review.json`:
  tested commit, incoming frontier, exact Git blob comparisons and coverage
  review.
- `qualify.py`: the exact executed qualification runner.
- `finalize.py`: source/count/artifact binding helper; it refuses a failed
  qualification receipt.
- `artifacts-sha256.json`: hashes and sizes of the complete retained evidence
  set, excluding the manifest itself.
