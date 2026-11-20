# CrispOffice Studio

Host example for `quds_office_editor`: a Documents / Spreadsheets / Presentations workspace
with ribbons, sample documents, and the custom RenderBox canvases.

## Run

```bash
cd packages/quds_office_editor/example
flutter run
```

## Mail composition

In native **Mail**, Compose, Reply, Reply all and Forward use the shared Word
body editor. Enter bare addresses separated by commas or semicolons, reveal
**Cc / Bcc** when needed, and choose **Attach files** to add up to ten files
totaling 10 MiB. Remove attachments individually before sending. The same draft
and MIME builder serve SMTP, Exchange EWS, Gmail and Microsoft 365.

Failed or uncertain submissions retain their immutable draft and attachment
bytes only for the current account session. An uncertain retry requires the
delivery-check acknowledgement; there is no autosave or automatic resend.
The [attachment guide](../../../docs/roadmaps/mail/attachments.md) records exact
limits, Bcc handling, validation and remaining document-to-mail/VBA work.

## Ribbon and desktop menus

The ribbon starts with compact icon buttons. Hover a button for its full name;
accessible labels also identify every command. Insert groups related commands under Pages, Table, Chart, Diagram,
Text, Links, Notes, Fields, Contents, References and Zotero tools; common Picture
and Equation commands remain directly accessible. Tables, pictures and diagrams
use the same undo history as other document edits.

Choose **Customize Ribbon** (the sliders button beside the ribbon tabs) to:

- Show, hide and reorder tabs and groups separately for Documents,
  Spreadsheets, Presentations and PDF.
- Switch between compact and comfortable spacing, and show or hide command
  and group labels.
- Restore all default layouts. File and the main editing/viewing tab stay
  available so editing and customization remain reachable.

Changes apply immediately and are saved for the next desktop launch. The
chevron beside Customize Ribbon collapses or expands the ribbon; selecting a
tab expands it again. Narrow windows show scroll arrows and a scrollbar for
commands that do not fit.

The title bar uses icon switches for Documents, Spreadsheets, Presentations,
PDF and Mail, with tooltips and accessible names. Desktop Undo and Redo appear
once in the title bar's quick access controls.

Desktop **File** provides New, Open, Save, Save As, Export PDF and Close Window.
Use Ctrl+N/O/S/W on Windows/Linux, or Command+N/O/S/W on macOS; add Shift to
the Save shortcut for Save As. New, Open, Close and Quit ask about unsaved work.
Cancelling Save As keeps the current file path.

macOS uses its native red/yellow/green window controls and application menu
bar, including File, Edit, View and Window. Closing the window keeps the app
available from the Dock; Quit checks all open workspaces before exiting.

## Precise layout and appearance

**Layout** uses menus for margins, orientation, paper size, columns, breaks,
paragraph presets, headers and paragraph appearance. Menus mark the current
choice and keep their full labels available without expanding the ribbon.

Open **Layout → Page Layout…** for a staged, precise draft:

- Custom paper width/height and portrait/landscape presets.
- Independent top, bottom, left and right margins and header/footer distances.
- One to four equal columns, exact spacing and an optional separator.
- Section start, first-page and odd/even headers, and line numbers.
- Current-section or whole-document scope, with a live geometry preview.

Enter lengths in millimetres, centimetres, inches or points. An explicit suffix
such as `2.5 cm` overrides the displayed unit; decimal commas and Arabic digits
are accepted. Changing units alone preserves the original model precision.
Apply creates one Undo step; Cancel leaves the document untouched. The dialog
rejects impossible geometry and a draft whose document changed while open.
Continuous sections that share a physical page retain shared page geometry;
the odd/even header setting applies to the entire document, as shown in the
dialog. Imported properties outside these supported settings are preserved.

**Home → Paragraph…** (the sliders icon in the Paragraph group), or
**Layout → Paragraph → Paragraph…**, provides exact spacing before/after,
multiple/exact/minimum line spacing, left/right indentation, first-line or
hanging indents, and page/column breaks. Mixed selections preserve each
paragraph's values unless that field is edited. Apply uses a single Undo step.

Large equation, spreadsheet function, slide shape, transition and animation
galleries also use compact menus. Slide direction, trigger, duration, delay
and automatic advance use explicit choices, with actual timing values.

Choose **Settings → Appearance → Dark** for matching dark chrome, menus,
dialogs, fields, rulers and document surfaces. The canvas adapts low-contrast
ink against known dark backgrounds while preserving authored colors in the
model and exports. Images are not inverted. Light filled objects keep their
original readable ink; text over unknown image or mixed slide backgrounds
retains its authored color. Hosts needing exact on-screen color reproduction
can set `OfficeTheme.adaptDocumentColors` to `false`.

## Document modes

Choose **File → Document mode** or **View → Document mode**. These are document
interaction choices, separate from general Settings:

| Mode | Behavior |
| --- | --- |
| Edit document | Edit text, formatting and objects. |
| Read and copy | Select and copy without changing the document. |
| Preview only | Scroll and zoom without text selection or editing. |

The status bar and menu indicate the current mode. Return to **Edit document**
to enable formatting and content changes.

The [image-editor integration design](../../../docs/IMAGE_EDITOR_INTEGRATION.md)
describes a native Flutter picture editor using CrispCloud's maintained vendor
package, an independent CrispOffice host, and one undoable result per picture.
It is a design document; no image-editor runtime dependency has been added yet.

## macOS release app with the native proofing libraries

```bash
packages/quds_office_editor/example/tool/build_macos_app.sh
```

Builds the pinned Hunspell, Arabic morphology (Camel Morph), CLD3 language-ID,
Harper (English) and CrispEmbed spaCy analysis libraries, runs
`flutter build macos --release`, installs
the libraries into `Contents/Frameworks` and their notices into
`Contents/Resources/*-licenses`, re-signs ad hoc with `Release.entitlements`
(sandbox, network client, user-selected files) and checks the signature, the
libraries' load commands and that each library opens from the bundle.
`QUDS_SKIP_HARPER=1` leaves Harper (needs Rust) out and `QUDS_SKIP_SPACY=1`
leaves the spaCy runtime (needs CMake and Git) out. Cargo builds into
`$HOME/.cache/shared-cargo-target` unless `CARGO_TARGET_DIR` is set, and a
Cargo home that is missing or under a temporary directory is replaced for the
build by a persistent cache. The AyaSpell dictionary and the Camel Morph
database are downloaded in the app: Review › Proofing › Dictionaries and
language data.

The spaCy runtime (`packages/quds_proofing_spacy/tool/build.py`, built from
the pinned CrispEmbed v2 runtime source with static PCRE2) is signed inside
the app; its digest is recorded in `Contents/Resources/spacy-native.json`.
Studio then downloads only the verified model files: Review › Analysis setup
› Download and install (German), and the English/French buttons below it.
Start the app with `QUDS_SPACY_BUNDLED=0` to ignore the bundled library and
use the downloadable platform package instead.

`test/studio_macos_bundle_native_gate.dart` is an explicit acceptance gate for
the built app: it boots Studio with the libraries inside the `.app` and the
installed data and checks Arabic (rules, AyaSpell, morphology), German and
English findings plus the detected-language display and Apply action. The
command is in the file header.

## What to try

### Documents
- **Home** — select a range, then bold / italic / underline / strike / superscript /
  subscript / color / highlight / grow-shrink. Alignment, lists, indent.
- **Insert** — heading, paragraph, quote, page break, tables 2×2 / 3×3 / 4×4,
  picture, column / bar / pie / line charts, process / cycle / hierarchy diagrams.
- **Layout** — compact preset menus, precise Page Layout and Paragraph dialogs.
- **Review** — select all / word / paragraph, undo / redo.
- **View** — rulers and zoom. Double-click a word, triple-click a paragraph,
  drag across a table. `Ctrl+Z` / `Ctrl+Y`.

### Spreadsheets
- Three sample sheets: Budget (SUM / AVERAGE / MAX), Roster (COUNTA), Catalog.
- **Home** — F2 edit, clear selection, select row / column, insert column / pie chart
  from the selected cells.
- **Formulas** — SUM, AVERAGE, MIN, MAX, COUNT, COUNTA, IF (uses the current
  selection, or the cells to the left of the focus).
- **Data** — insert / delete sheets; column / pie / line charts. Formula bar above
  the grid. Freeze header row.

### Presentations
- Five-slide tour of the suite tools.
- **Home** — new / duplicate / delete slide, nudge, bring forward / send back.
- **Insert** — card, title, accent, picture, column / pie charts, process diagram.
- **Design** — cycle fill, center on slide, set shape text.
- Drag a card: snap guides appear only when edges align.

### File
New blank document, open / save OOXML, reload the in-memory sample.
Choose Edit document, Read and copy, or Preview only from File or View.

Chrome (ribbons, panes, formula bar) is Material. The page, grid, and stage
are custom `RenderBox` editors — not `TextField` / `ListView`.
