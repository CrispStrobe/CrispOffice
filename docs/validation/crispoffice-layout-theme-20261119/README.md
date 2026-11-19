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

The initial accepted GUI source and twelve visually reviewed screenshots are preserved in
`2dbd1c58dd724bb2208e06c43a835b220484b1e1`. The publication integration
`8d9d1fe77284f76e71fbd6cb2718d3f6cfb636af` also preserves VBA tip
`f6b8638d5c78a2d17e5e1c2fb43620c63a23b90c`, mail resume tip
`85c8c55186b8eefd242159ee606b2ad1fa61038f`, and published main
`caf378f40fd5bda50f504a6816404d01d8bbb8f8`. The additional functional changes
are confined to thirteen mail-specific library files. The GUI product files
and complete engine library, test and tool trees are unchanged from the
accepted GUI checkpoint. The one test conflict retained the accepted Slide
contrast, light-cell raster-equivalence and saved-XML assertions.

Local qualification of the incoming resume code exposed three existing
adversarial-test failures. Follow-up
`ba51c40abc664758df3cfc846625bdeb81e3ac13` makes two targeted corrections:
confirmed restore writes retain the established archive completion diagnostic,
and per-item source/codec failures remain bounded and reportable while actual
destination receipt corruption still stops resumption. Original tests and the
atomic original/index/provenance/receipt transaction are unchanged. The failed
run is retained alongside the corrected acceptance result.

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

Published main subsequently advanced to
`9f41e0427734d815b19149eba5eabef202f78ba6`. Integration
`a93c78032b043c35edd2632ba3ab7a058299926a` preserves its language-review fixes,
explicit language/model download manager and native model removal together with
the accepted GUI. The combined Settings dialog retains live theme and RTL
updates, exposes Language downloads, and keeps document mode in File and View.
The download manager inherits the active themed route. The
[final integration review](integration-review-publication.json) records the
exact source review; the retained merge proof records all twelve resolved paths.

The **tested GUI and language-controls source checkpoint** is published at
`fedabc7079db1c402cadcd9ef15296244979132e`, tree
`ec7fe4262f93698f2a56b2ff334cde7574455fdb`. The frozen 921-case acceptance package
below binds this checkpoint. Later incoming integrations retain their own
source review and targeted acceptance records.

## Local acceptance

The [acceptance summary](local-acceptance/acceptance-summary.json) records
**921 distinct passing behavior cases across 44 test files**. The
[package manifest](local-acceptance/manifest.json) and
[path map](local-acceptance/path-map.json) identify every retained receipt, log,
source manifest, case mapping and merge proof, with original and stored hashes.
Large evidence files use reproducible gzip compression. Failed and superseded
attempts remain available and do not contribute to the accepted total.

Local checks use the repository-pinned Flutter
3.47.8 and Dart 3.13.7 runtime, the unchanged dependency lockfile, the normal
SQLite native hook, actual raster captures and Node execution of the web smoke
programs. Corrected reruns count each behavior case once; development failures
remain identified separately.

| Accepted cohort | Distinct cases |
| --- | ---: |
| GUI continuation: rendering, dialogs, menus and existing regressions | 144 |
| Language downloads manager | 5 |
| Proofing controls and Review | 66 |
| Native NER model removal | 2 |
| VBA VM, including actual CLI subprocesses | 395 |
| Native mail restoration and repository | 181 |
| Portable mail on Node | 9 |
| Studio mail restoration | 31 |
| Editor embedding | 88 |
| **Total** | **921** |

Two compiled JavaScript smoke programs with checked JSON assertions and one
screenshot-generation test producing twelve distinct images are recorded
separately. The earlier 634-case GUI phase is also excluded from this total.

The GUI continuation's 144 cases break down as follows:

| Area | Distinct cases |
| --- | ---: |
| Page Layout API, Word/Sheet dark rendering and rulers | 17 |
| Page Layout and Paragraph dialogs | 27 |
| Workspace modes, precise presets and other compact menus | 10 |
| Existing Zotero, comments, keyboard, Review, customization and preferences | 84 |
| Slide dark rendering and saved color preservation | 6 |
| **GUI total** | **144** |

The incoming VBA qualification covers eleven suites. Its engine source, tests
and tools remain byte-identical across the later integrations. The complete
181-case native mail gate passed after the two restore corrections, with the
original tests unchanged. Portable mail, Studio restoration and embedding
fixtures also passed against the integrated source.

The last main integration passed 45 example cases, 76 core proofing/Page Layout
cases and two native NER-removal cases. Of these, 73 are additional cases and
the remaining reruns replace earlier accepted results. Strict scoped analysis
and nonmutating format checks passed. The summary explains which earlier
results are retained, their source comparisons, and the exact accepted log for
each case; a final manifest binds 1,040 source and configuration files.

The full suite and native macOS/AppKit execution are outside this focused Linux
qualification. The earlier desktop/native-menu wiring and its focused tests are
preserved from [PR #206](https://github.com/CrispStrobe/quds_office_suite/pull/206).

## Visual review

[render_previews.dart](render_previews.dart) creates actual Flutter-rendered
screenshots with the bundled fonts. Ruler labels and readouts now use the same
explicit font resolution as document text, avoiding implicit platform/test
fonts. No SDK patch or test-font substitution is used. Dialog visibility and
dark appearance are asserted before capture. The final merged-source screenshots
are under [screenshots-publication](screenshots-publication/). All twelve
distinct images were directly reviewed; the
[publication visual review](visual-review-publication.json) records their
hashes, viewport dimensions, reviewer observations and scope. They include the
merged Language downloads Settings entry and the updated sample language.
The narrow German and Arabic views use a 900 × 760 viewport; the desktop and
dialog views use 1440 × 960.

The earlier [screenshots](screenshots/) and [visual review](visual-review.json)
remain unchanged to preserve their original source and hash relationship.
