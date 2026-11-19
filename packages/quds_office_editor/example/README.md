# CrispOffice Studio

Host example for `quds_office_editor`: a Documents / Spreadsheets / Presentations workspace
with ribbons, sample documents, and the custom RenderBox canvases.

## Run

```bash
cd packages/quds_office_editor/example
flutter run
```

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

## macOS release app with the native proofing libraries

```bash
packages/quds_office_editor/example/tool/build_macos_app.sh
```

Builds the pinned Hunspell, Arabic morphology (Camel Morph), CLD3 language-ID
and Harper (English) libraries, runs `flutter build macos --release`, installs
the libraries into `Contents/Frameworks` and their notices into
`Contents/Resources/*-licenses`, re-signs ad hoc with `Release.entitlements`
(sandbox, network client, user-selected files) and checks the signature, the
libraries' load commands and that each library opens from the bundle.
`QUDS_SKIP_HARPER=1` leaves Harper (needs Rust) out. The AyaSpell dictionary
and the Camel Morph database are downloaded in the app: Review › Proofing ›
Dictionaries and language data.

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
- **Layout** — RTL/LTR, line spacing, A4 / Letter.
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
Switch Edit · Select · View from File or Settings.

Chrome (ribbons, panes, formula bar) is Material. The page, grid, and stage
are custom `RenderBox` editors — not `TextField` / `ListView`.
