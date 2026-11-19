# Incoming Studio GUI qualification

The incoming GUI work passed targeted executable qualification using the pinned
**Flutter 3.47.8 / Dart 3.13.7** Linux SDK. Across the original acceptance and the
final publication follow-up, **148 distinct behavioral cases passed**, with
**one opt-in screenshot generator skipped**. No GitHub Actions result was needed.

## Accepted runs

| Selection | Passed | Skipped | Evidence |
| --- | ---: | ---: | --- |
| Twelve Studio test files, combined | 114 | 1 | `studio_final_tests.stdout.log` |
| PDF save-state test file | 4 | 0 | `pdf_tests.stdout.log` |
| Final author versions of File menu and worksheet navigation tests | 12 | 0 | `publication-followup/publication_repeated_gui_tests.stdout.log` |
| Additional directory archive-import test file | 30 | 0 | `publication-followup/publication_directory_import_tests.stdout.log` |

The 12 follow-up GUI cases repeat cases in the original 118-pass acceptance and
are **not** added to the distinct total. The earlier 26-case fixture confirmation
is also a subset. The only skip is
`studio_shots_test.dart` / `capture Word, Excel, PowerPoint, and PDF studio frames`:
this screenshot-generation helper requires `QUDS_SHOTS_DIR`, which was unset.

Strict analysis with `--fatal-infos` passed for the incoming Studio product files,
PDF controller, and relevant test files. The changed fixtures passed formatting
checks. Exact commands, working directories, exit codes, and timings are retained
in `commands-results.json` and
`publication-followup/commands-results.json`.

The selected behavior covers ribbon preferences and customization, desktop menus,
modal File actions, sheet navigation, localized Mail access, comment/review and
Zotero interactions, PDF clean/revision state, and directory archive import. This
was targeted Flutter qualification, not a full editor or repository test run.
macOS and Windows widget variants use simulated target platforms and mocked
platform channels on Linux; no native macOS/Windows application build or native
menu execution is claimed.

## Source binding and final publication

The full 118-pass acceptance binds to commit
`bc32a14477c9254d0725eb563410c5c9ea059211`, incorporating incoming GUI head
`f489cefe48e6fd4b0dcbada8fc4025682733a118` and the local fixture corrections.
`source-input-sha256.json` records **5,188 tracked input hashes**. They were all
unchanged in the source checkout during acceptance.

The final follow-up binds to published commit
`dde14aa66d229957352a2f64f77b23d8f91198ae`, tree
`1ee90818295534b203926953d1874e717a0a9d59`. It incorporates the author's final GUI
publication `df7f4b4c8df63cbcf80d9087d06707d166a2c678` and evidence binding
`bba11ff1b23b2e8c0cdc0d872ce31394ada83bf2`.

Within those 5,188 inputs, only the Studio README and three tests changed between
the two acceptance stages. **No product source changed.** The changed tests are
File menu, worksheet navigation, and directory archive import. The final File menu
fixture retains the delayed-show assertions and adds a show-count check. The
worksheet fixture retains save-before-replacement and reset assertions, disables
an unused Word proofreader, and settles dialog frames. The import fixture
canonicalizes the system temporary directory before the path-containment checks.

`publication-followup/changes-from-118-acceptance.json` supplies the four hash
amendments to the original manifest. The resulting complete 5,188-input projection
was checked against the final source checkout. Each amended file was also checked
against its Git blob in `dde14aa6`. The three rerun test files matched their
isolated copies and remained unchanged throughout the follow-up. See the two
`source-binding.json` files for exact counts, hashes, and commit identifiers.

## Initial failures and fixture corrections

The original failed attempts are preserved under `initial-failure/`; they are not
reported as passing acceptance. Four failures led to three test-file corrections:

1. The native-dialog mock returned `null` for `window_manager.isMinimized`.
   Version 0.5.2 calls that Boolean method before sending `show`. The invalid mock
   response threw before the deliberately blocked `show` call, and the product's
   best-effort window wrapper continued into Settings. Returning `false` from the
   mock makes the test exercise its intended delayed show/focus path. The original
   modal and stale-callback assertions remain in place.
2. The localized Mail test looked for visible `E-Mail` text after the application
   switcher became an icon with a tooltip. It now activates that tooltip target.
3. The two worksheet reset cases looked for visible command text even though the
   compact ribbon hides labels by default. They now use command tooltips after
   opening the File tab, verify the old workbook remains at the save prompt, and
   explicitly choose **Don't Save** before the existing reset assertions.

`fixture-corrections.patch` and `fixture-corrections.json` retain the exact local
correction and input hashes. The final author versions preserve these behavioral
assertions and were qualified separately, as described above.

## Reproducible isolated setup

The SDK archive was selected from the official Linux release manifest at
<https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json>.
Its verified SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The framework revision is `737ba8f885dc774b53b442759999a312c9461e4e`.
`flutter-release.json` and `flutter-version.json` preserve the release metadata
and actual SDK report.

Tests ran in an isolated copy of the relevant workspace packages. The reduced
root manifest and resolved dependency lock are retained as
`isolated-root-pubspec.yaml` and `isolated-root-pubspec.lock`. The tracked root
manifest and lock were not changed. Every analysis/test command used `--no-pub`.

The raw copy-equality audit reports the expected isolated `pubspec.lock`
difference from reduced dependency resolution. `input-stability.raw.json`
preserves that raw result; `input-stability.json` records the explicit setup
override and both lock hashes. All other 5,187 copied tracked inputs matched the
accepted source at the full-run stage. The later README-only difference has no
executable effect; all updated test copies were checked independently.

All retained logs are plain UTF-8. `artifact-sha256.json` lists every receipt file
and its SHA-256, excluding the manifest itself. SDK archives, compiled artifacts,
and verbose dependency-download logs are deliberately omitted.
