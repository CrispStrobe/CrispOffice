# CrispOffice Layout, document modes and dark appearance — 19 November 2026

Tracked in [PR #211](https://github.com/CrispStrobe/quds_office_suite/pull/211).
Implementation and integration checkpoints are preserved on
`codex/crispoffice-layout-theme-20261119`. GitHub Actions are not queried or
awaited, as requested by the repository owner.

## User-visible changes

The Layout ribbon uses compact menus for margins, orientation, paper size,
columns, breaks, paragraph presets, headers and paragraph appearance. Current
choices are marked; full command labels appear inside the menu. Existing
per-application tab/group customization and persisted preferences remain in
place. Large equation, spreadsheet function, slide shape and motion galleries
also use menus. Slide duration, delay, direction, trigger and automatic advance
show explicit choices rather than cycling through hidden values.

**Page Layout** has Margins, Paper, Layout and Columns tabs, a geometry preview,
measurement units and section/document scope. It supports custom paper size,
all four margins, header/footer distances, one to four equal columns with exact
spacing and a separator, section starts, first-page/odd-even headers and line
numbers. It validates geometry and applies a captured draft in one Undo step.
Opening the dialog, switching display units, or cancelling does not round or
change the model. Continuous sections retain shared page geometry; odd/even
headers follow their document-wide OOXML setting. Unrelated imported section
properties remain intact.

**Paragraph** is reachable from Home and Layout. It provides exact before/after
spacing, multiple/exact/minimum line spacing, left/right and first-line/hanging
indents, and page/column breaks. Mixed selections preserve untouched fields.
Stale document, selection, story and formatting targets are rejected before the
single undoable application. Existing note typing is committed separately before
opening a modal. Quick spacing presets restore the multiple-line rule after an
exact-point setting and preserve custom paragraph spacing above 72 pt. Header
and footer menu selections describe their actual active variant, not body text.

**Document mode** moves from Settings to File and View:

| Mode | Interaction |
| --- | --- |
| Edit document | Text, formatting and object changes. |
| Read and copy | Selection/copy without document mutation. |
| Preview only | Scroll/zoom without selection or editing. |

**Dark appearance** now themes Material dialogs, menus, fields, combos and tab
labels as well as rulers/readouts. The Word, Sheet and Slide canvases adapt
low-contrast authored ink only during painting, using known backgrounds.
Light fills retain their readable ink, image pixels are not inverted, and
model/export colors remain unchanged. Ambiguous image or mixed slide backdrops
retain authored ink. Hosts can disable adaptation through
`OfficeTheme.adaptDocumentColors`. Arabic Settings updates its direction while
open; tab height accounts for real font metrics and enlarged text.

The image-editor work in this change is a source-backed
[integration design](../../IMAGE_EDITOR_INTEGRATION.md), not a new runtime.
It recommends the exact maintained BSD-licensed `pro_image_editor` vendor from
CrispCloud, an independently written native Flutter CrispOffice host, validated
image bytes, and one undoable replacement of the originally selected picture.

## Integration and review

The starting source was mail restoration tip
`37ac6ea8a08225a42098c455deb5375837912eec`, including main
`cf59efa99232a3fd26cf21ce7f2382402e576f9b` and the earlier GUI/desktop work.
Source checkpoints include:

- `4fd010fcae209b6ea033828d76908508b7327b9f`: Page Layout transactions and core
  Word/Sheet/ruler dark rendering, plus the image-editor investigation.
- `288b493ee5891ba3abc44c37584c7517f46a6a5c`: Studio menus, dialogs, Material
  appearance, modes and their regression coverage.
- `466d757fef48df5541b37f06fffbc2efbb62a848`: precise Paragraph follow-ups,
  Slide dark rendering and Arabic Settings.

Integration commits preserve the new VBA arrays/For Each contribution, its
bare-call parser correction, and the mail restoration validation evidence.
The exact refreshed tips are VBA
`ae4c8223d1814df4a500518c8b223831cbb0b51f` and mail
`1a99845fe628c9e539d4bca7e7c586c5616da267`; both are ancestors of integration
checkpoint `2d7360a217b51c34ccf72eb5ed78c82ccd20bae5`.

The final GUI source and twelve visually reviewed screenshots are preserved in
`2dbd1c58dd724bb2208e06c43a835b220484b1e1`. The publication integration
`8d9d1fe77284f76e71fbd6cb2718d3f6cfb636af` also preserves VBA tip
`f6b8638d5c78a2d17e5e1c2fb43620c63a23b90c`, mail resume tip
`85c8c55186b8eefd242159ee606b2ad1fa61038f`, and published main
`caf378f40fd5bda50f504a6816404d01d8bbb8f8`. The additional functional changes
are confined to thirteen mail-specific library files. The GUI product files
and complete engine library, test and tool trees are unchanged from the
accepted GUI checkpoint. The one test conflict retained the accepted Slide
contrast, light-cell raster-equivalence and saved-XML assertions.

[Incoming audits](incoming/README.md) distinguish functional changes from
formatting and evidence. The retained remote capture covers 231 fork branch/PR
and upstream branch references. At the integrated checkpoint, 208 are ancestors
and 23 have verified historical equivalents; all 14 complete historical proofs
pass, with no unaccounted references. See
[reconciliation-integrated.json](reconciliation-integrated.json). A publication
refresh is recorded separately so the original capture remains reproducible.
Its 233 captured references classify as 210 ancestors and 23 historical
equivalents, with all fourteen proofs passing and no unaccounted references;
see [reconciliation-publication.json](reconciliation-publication.json).
The [publication audit](incoming/publication-audit.json) additionally binds the
inspected mail resume snapshot and explains its fresh acceptance requirements.

## Local acceptance

Acceptance receipts, precise source identities and the final result summary are
recorded beside this document. Local checks use the repository-pinned Flutter
3.47.8 and Dart 3.13.7 runtime, the unchanged dependency lockfile, the normal
SQLite native hook, actual raster captures and Node execution of the web smoke
programs. Corrected reruns count each behavior case once; development failures
remain identified separately.

The GUI portion contains **144 distinct accepted behavior cases**, plus one
separate screenshot-generation case:

| Area | Distinct cases |
| --- | ---: |
| Page Layout API, Word/Sheet dark rendering and rulers | 17 |
| Page Layout and Paragraph dialogs | 27 |
| Workspace modes, precise presets and other compact menus | 10 |
| Existing Zotero, comments, keyboard, Review, customization and preferences | 84 |
| Slide dark rendering and saved color preservation | 6 |
| **GUI total** | **144** |

The incoming VBA qualification also passed **395 cases** across eleven suites,
including real CLI subprocesses. Its engine source, tests and tools remain
byte-identical across the publication integration, so that gate remains bound
to the integrated code. Incoming mail resume, Studio restore and embedding
fixtures receive their own final-source qualification.

The full suite and native macOS/AppKit execution are outside this focused Linux
qualification. The earlier desktop/native-menu wiring and its focused tests are
preserved from [PR #206](https://github.com/CrispStrobe/quds_office_suite/pull/206).

## Visual review

[render_previews.dart](render_previews.dart) creates actual Flutter-rendered
screenshots with the bundled fonts. Ruler labels and readouts now use the same
explicit font resolution as document text, avoiding implicit platform/test
fonts. No SDK patch or test-font substitution is used. Dialog visibility and
dark appearance are asserted before capture. The final screenshots are under [screenshots](screenshots/).
All twelve distinct images were directly reviewed; the
[visual review](visual-review.json) records their hashes, viewport dimensions,
reviewer observations and scope. The narrow German and Arabic views use a
900 × 760 viewport; the desktop and dialog views use 1440 × 960.
