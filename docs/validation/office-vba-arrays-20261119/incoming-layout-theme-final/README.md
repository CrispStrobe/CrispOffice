# Expanded layout/theme qualification — retained failed attempt

This directory retains the complete first expanded qualification at published
checkpoint `596430dcb816dd418204d62e78f4dc518afdc0e1`, including current main
`caf378f40fd5bda50f504a6816404d01d8bbb8f8` and GUI publication
`2d7360a217b51c34ccf72eb5ed78c82ccd20bae5`. **This attempt failed**; it is not
the final accepted gate. Corrected acceptance is recorded separately in
`../incoming-layout-theme-accepted/`.

## Complete observed result

| Gate | Result |
| --- | --- |
| Ten editor suites | **212 passed, 1 failed**, 213 distinct cases, no skips |
| Three repeated Studio mail suites | **18 passed**, no failures or skips |
| Eleven Studio GUI suites | **115 passed**, no failures or skips |
| Strict editor source/test analysis | Exit **0**, no issues |
| Strict Studio source/test analysis | Exit **1**, one missing-braces info |
| Recorded input stability | All **2,495 inputs unchanged** |
| Copied full-workspace manifests | All **20** match repository counterparts |

All original command receipts, JSON reporters, stderr, before/after snapshots,
and the overall failed `receipt.json` remain at their original paths. No
GitHub Actions were queried or awaited. The official Flutter 3.47.8 SDK and
its bundled Dart were used with `--no-pub`, serial execution and JSON reporters.

The input snapshot includes all tracked editor and Studio test/support files,
along with repository library sources, shared configuration, relevant assets,
workspace manifests/lock/configuration, dependency manifests, and SDK binaries.
The expanded test/support snapshot explicitly binds imported helper fixtures.

## Dark Slide pixel failure

The single failing case is
`office_dark_slide_test.dart` →
`dark Slides adapt explicit ink and preserve automatic and exported colors`.
At line 215, the first white table cell expected more than 15 pixels within
RGB tolerance 3 of black; it observed **3**. The original assertion and failure
are preserved in `editor-tests.stdout.log`. The other five dark Slide cases
passed, as did all **88** embed cases, including the eight earlier host/lifecycle
corrections.

Read-only inspection identified this as the black-on-white table sample,
painted at the expected crop origin with 13-point text. The independent raster
diagnostic retains the original assertion and compares enabled versus disabled
document color adaptation. Its separate evidence establishes that the white
cell is identical in both modes, while the small font has many antialiased
pixels rather than fully opaque black pixels. That diagnostic and any test
correction are not used to turn this failed attempt into a pass.

## Strict Studio analysis failure and separate correction

`studio-analysis.stdout.log` records one info at
`lib/suite_workspace.dart:1421:31`:
`curly_braces_in_flow_control_structures`. The incoming GUI layout change
reformatted the measurement-unit callback from a one-line conditional into a
multiline body without braces. Strict analysis treats this info as a failure.

After the full run and unchanged-input snapshot completed, only opening and
closing braces were added around that existing null-guarded callback. The
`braces-correction/` subdirectory retains the incoming baseline/current diff,
the exact corrective diff, before/corrected file hashes, and recorded format
and strict single-file analysis commands. Its receipt verifies that the
correction changes only braces and that the source stayed unchanged during
those checks. These later targeted checks are separate from the original
failed full run.

## Coverage and counting

The Studio GUI cohort contains the new layout/theme, Page Layout, Paragraph,
and Slide/Sheet menu suites; adapted comment keyboard/review, review-pane and
Zotero suites; and existing File, desktop and ribbon customization suites.
Its **115** cases all passed. The **18** mail restore/portability cases repeat
the earlier mail UI qualification and must be counted once across runs.
Historical initial and corrected repeats do not add distinct final cases.

`qualify.py` is the exact executed runner. `finalize.py` is a prepared
acceptance binding helper; it deliberately refuses this unsuccessful receipt
and was not used to manufacture accepted evidence for this attempt.
