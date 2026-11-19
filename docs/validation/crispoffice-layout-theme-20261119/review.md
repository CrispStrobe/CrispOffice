# GUI integration review

Reviewed compact menu command/state preservation, exact and minimum paragraph
spacing, detached dialog targets, Undo and measurement precision, Material theme
propagation, Arabic direction, and the render-only Slide ink policy.

## Findings and disposition

- **Settings direction — resolved.** Settings now wraps its live dialog in the
  current language's `Directionality`. The workspace regression checks Arabic
  immediately after switching language and after reopening Settings.
- **Header/footer menu state — resolved.** The active paragraph helper now reads
  the exact standard, first-page, or even-page header/footer story and caret
  without creating model paragraphs. A first-page header regression checks menu
  state, formatting, Undo, and preservation of body settings.

No further actionable issues were found in the reviewed integration scope.
The compact menus retain command callbacks, selected state and disabled state.
Multiplier presets restore the automatic line-spacing rule, and paragraph
spacing nudges preserve custom values above 72 pt. Dialog drafts retain
untouched precise values and reject stale targets before one undoable commit.

Slide contrast adaptation uses known painted backgrounds, including table cells
and interpolated Morph fills. Unknown picture, chart, partial and rotated
backdrops retain authored ink; automatic colors, light rendering and serialized
document colors remain unchanged.

## Validation disposition

The runtime agent owns serial compilation and the final acceptance receipt.
The first Slide run passed five cases and exposed an over-specific exact-RGB
population assertion for 13 px table text; its failed log is preserved. The
corrected test compares every light-cell pixel with adaptation disabled and
measures glyph pixels at 4.5:1 contrast against each actual cell fill, also
logging exact-RGB and contrast coverage. No renderer change was made for this
test correction. The measured coverage is 85 light-cell pixels and 191 dark-cell
pixels at 4.5:1 contrast, compared with only 3 and 16 near-exact color pixels;
authored black on the dark fill has zero pixels at that contrast. Every
light-cell pixel matches the adaptation-disabled rendering.

The rerun also exposed existing table import behavior: table run colors are
assigned to the shape rather than to the cell. The render-only regression
therefore checks unchanged source cell colors and the actual saved table run
and fill XML, while retaining the ordinary shape-color roundtrip assertions.
The table reader and writer are unchanged from the integration baseline.

The final focused gate passed all six Slide cases and all four ruler/chrome
cases, with strict analysis clean. `final-ruler-slide-2.json` records exit code
zero, ten passed cases, and no source changes during the run. The runtime
agent also reported all seven current workspace integration cases passing.
