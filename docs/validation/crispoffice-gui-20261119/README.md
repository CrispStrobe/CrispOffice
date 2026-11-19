# CrispOffice GUI and desktop acceptance — 19 November 2026

This work is tracked in [PR #206](https://github.com/CrispStrobe/quds_office_suite/pull/206).
Implementation, integration, previews and acceptance evidence were saved in
incremental commits on `codex/crispoffice-gui-20261119`. GitHub Actions were not
queried or awaited, as requested by the repository owner.

## User-visible changes

- The Word Insert ribbon presents 18 primary buttons and menus. Related page,
  table, chart, diagram, text, link, note, field, reference and Zotero commands
  remain available inside their menus. The default uses icons with tooltips and
  accessible names; optional command labels fit within two lines.
- **Customize Ribbon**, beside the tab strip and in Settings, controls tab and
  group visibility/order separately for Documents, Spreadsheets, Presentations
  and PDF. It also controls compact spacing, command/group labels and restoring
  defaults. Layout changes apply immediately and persist between desktop
  launches. Essential editing/viewing tabs remain available.
- The ribbon can collapse, and narrow windows expose a scrollbar and arrows.
  Menu focus supports Escape, arrow keys and Enter; switching to another ribbon
  control works on the first click.
- Desktop Undo/Redo occur once, in the title bar. Application switches use
  icons with localized tooltips instead of long document-type labels.
- macOS is wired to AppKit's left-hand red/yellow/green window controls and its
  native application, File, Edit, View and Window menus. Windows/Linux have an
  accessible File menu in the title bar. File actions include New, Open, Save,
  Save As, Export PDF and Close Window, with OS-appropriate shortcuts.
- New/Open/Close/Quit protect unsaved work; cancelled Save As retains the
  previous path. macOS keeps the application available after closing the last
  window, restores it from the Dock or native About/Settings commands, and
  checks all dirty workspaces before quitting.
- New review/comment authors, initials, producer metadata and sample branding
  use CrispOffice/CO. Existing imported author values and upstream legal
  attribution are preserved.

Supporting correctness changes route inserted tables, pictures and diagrams
through document undo history. PDF saving now tracks revisions, preserves undo,
avoids marking later edits clean, and restores temporary PDF writer allocations
so repeated encodings do not mutate the live document.

Usage guidance is also in the [Studio README](../../../packages/quds_office_editor/example/README.md).

## Source and integration

- Original `main`: `304d4bff45da24f22cee420ec464882d7c7ce516`.
- Final product source checkpoint: `f489cefe48e6fd4b0dcbada8fc4025682733a118`.
- Refreshed integration checkpoint: `ecdc74d87e71f7a1d7c542f8877911a5ffbee014`,
  tree `6f4ee2e82cbad23f4b2a759b0cafac8bfdccc915`.
- The final refresh preserves `main` at `0c29b5d8a0a92148dcd95f3282b4d43c462be20d`,
  VBA at `ca536ee071ff27dd88e574dac1fbc5fe08d1437e` and MacBook integration at
  `515d960fc5ea83787659f4c773d793a8b7e9f05f`. The mail portability tip
  `82b20dc8b52d0b95efeff590c6023ed84704fa7a` is an ancestor of that `main`.
- The 231 paths added or changed by that last integration are documentation,
  evidence and changelog content. Product source is identical to the tested
  product checkpoint. The only conflict was resolved by retaining both
  independent Unreleased changelog entries.
- A fresh audit covers all 235 advertised fork branch/PR heads and upstream
  branch heads: 212 are ancestors and 23 historical references have verified
  integrated equivalents. All 14 historical equivalence proofs pass; there are
  no unaccounted references. See [reconciliation.json](reconciliation.json).

Test-only follow-ups improve native-plugin mocks, migrate icon-button finders,
exercise the new save confirmation, and isolate unrelated proofing providers.
They preserve the original document, navigation and mail assertions.

The publication refresh at `df7f4b4c8df63cbcf80d9087d06707d166a2c678`
also preserves VBA tip `bba77ddc1a40d5cdb5e8859744306fd3792db996` and the
updated MacBook tip `de9d21f9014060c14263ce17fe323d5fdb063d11`. Its only
test change resolves the system temporary directory before creating the
directory-import fixture, accommodating macOS's `/var` symlink. Its only
documentation change adds a blank line between changelog paragraphs. Product
source is unchanged. The affected 30-case suite and its strict analysis are
recorded separately in the acceptance data; reruns do not increase the total.
See [reconciliation-final.json](reconciliation-final.json) for the fresh
publication-frontier audit.

## Local acceptance

The actual repository-pinned Flutter **3.47.8** / Dart **3.13.7** runtime was
used. The official SDK archive hash and 194 hosted dependency archives were
verified; offline dependency resolution enforced the existing lockfile.
`pubspec.lock` remained unchanged. SQLite tests used the package's default native
hook, including the archive crash/recovery fixture on the Dart VM.

The acceptance record distinguishes initial failures from corrected reruns.
Counts below count each test case once, even when a suite ran more than once.

| Area | Accepted cases | Coverage |
| --- | ---: | --- |
| Editor Review | 36 | Review dialogs, default authors, imported-author preservation |
| Engine comments/revisions/ODS | 165 | Comment/revision fidelity, story handling and metadata defaults |
| Archive store | 109 | Export plans, manifests, native export/import and recovery |
| Studio archive UI | 57 | Directory import and archive workflows |
| Ribbon, desktop menus and workspace | 27 | 10 preference cases, 6 customization cases, 4 desktop-menu cases, 4 File-lifecycle cases, 3 existing workspace cases |
| PDF | 16 | 4 save-state cases and 12 existing surface regressions |
| VBA control flow | 86 | Compiler/runtime limits, atomicity, MCP and actual CLI processes |
| Existing Studio workflows | 87 | Zotero, worksheet navigation, saved Mail, Review, comment context and keyboard/IME handling |
| Word automation | 51 | Structural operations and atomicity |
| **Total** | **634** | **Unique focused test cases** |

Additionally, the new VBA JavaScript smoke compiled and ran successfully in
Node, including cold maximum-depth cases. Strict scoped analysis passed with
fatal warnings and infos. The preview harness passed and produced the six
images below; the layouts were visually inspected. Ribbon widgets also passed
the narrow Arabic case at 160% text scaling.

These are focused local checks, not a claim that every test in the repository
or every operating-system build was run. The desktop test channel verifies
native-menu serialization, command dispatch, window lifecycle decisions and
fullscreen events. This Linux environment cannot execute AppKit or build the
macOS application; a real Mac smoke check of native traffic lights, menu
placement, Dock reopen and Quit remains necessary.

See [acceptance.json](acceptance.json) for the exact commands, outcomes and
retained log hashes. Logs are gzip-compressed without modifying their content.
Superseded failures are retained and explained there, including old label
finders, the native `isMinimized` mock response and proofing timeout isolation.

## Visual review

These are genuine Flutter widget renders of the implemented Studio, using its
host fonts and Material icons. They are not mockups or native AppKit captures.

| View | Preview |
| --- | --- |
| Compact desktop Insert | [insert-desktop.png](screenshots/insert-desktop.png) |
| Insert Text menu | [insert-text-menu.png](screenshots/insert-text-menu.png) |
| Customize Ribbon | [customize-ribbon.png](screenshots/customize-ribbon.png) |
| Optional command labels | [insert-labels.png](screenshots/insert-labels.png) |
| Narrow German layout | [insert-narrow-german.png](screenshots/insert-narrow-german.png) |
| Narrow Arabic layout | [insert-narrow-arabic.png](screenshots/insert-narrow-arabic.png) |

The first four images use a 1440×960 viewport; German/Arabic use 900×760.
To reproduce, copy [render_previews.dart](render_previews.dart) into
`packages/quds_office_editor/example/test/_gui_previews_test.dart`, set
`FLUTTER_ROOT` to the pinned SDK and `CRISPOFFICE_GUI_SCREENSHOTS` to an absolute
output directory, then run from the example:

```sh
flutter test --no-pub --concurrency=1 --reporter=expanded test/_gui_previews_test.dart
```

Remove the temporary test copy afterward. The preview fixture is kept separate
from the ordinary behavior tests so routine test runs do not generate images.
