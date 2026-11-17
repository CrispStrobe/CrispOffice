# Conditional-format rendering

The worksheet grid and worksheet PDF exporter share
[`SmlConditionalResolver`](../packages/quds_office_engine/lib/src/sheet/model/sml_conditional_format.dart).
It evaluates the supported rule predicates and resolves **solid fill and font
colors**. Conditional bold, borders, number formats, color scales, data bars and
icon sets are not newly painted by this resolver.

## Precedence and property selection

Rules apply only inside their modeled range. Lower positive priorities are
evaluated first. Valid priorities are positive Int32 values; the first occurrence
of an authored priority retains it. Missing, invalid or repeated values receive
unused priorities after the largest reserved value, wrapping to the first free
positive value at the Int32 limit. This is the same normalization used by the
[`XLSX serializer`](../packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart),
so saving does not change the renderer's effective ordering. Resolution does not
reorder the model or assign its `priority` fields.

Each matching rule contributes its nonempty properties independently. For
example, a higher-priority fill-only rule can combine with the font color of a
lower-priority rule. The first supplied value wins for each property. A matching
`stopIfTrue` rule stops evaluation even when it supplies no modeled color; a
nonmatching stopping rule has no effect. An absent conditional property leaves
the ordinary cell property in effect.

## API and lifetime

```dart
final sheet = workbook.firstSheet;
final resolver = SmlConditionalResolver(sheet: sheet, workbook: workbook);
final ref = SmlCellRef.parse('B3');
final conditional = resolver.resolve(ref);
final cell = sheet.cellOrNull(ref);
final fill = conditional.fillRgb ?? cell?.fillRgb ?? '';
final font = conditional.fontRgb ?? cell?.fontRgb ?? '';
```

Create one resolver per paint or export operation and discard it after workbook
edits. Resolved colors, referenced values and aggregate statistics are cached
for that operation. Supply the complete workbook for cross-sheet references and
defined names. Omitting it provides worksheet-only evaluation.

`resolve` checks the applies-to range and works with absent cells without adding
them to the worksheet. `SmlConditionalRule.matches` retains its older
predicate-only API: callers using it directly must check range membership when
that is required. The
[`grid`](../packages/quds_office_editor/lib/src/editor_sheet/render_sheet_grid.dart)
shares one resolver across frozen panes and uses the merged-cell anchor. The
[`PDF exporter`](../packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart)
uses it for cells within the exported region, including blank cells in a selected
print area. Conditional ranges alone do not expand the print area.

## Formula and value policy

Expression predicates and comparison bounds use the existing
[`formula parser`](../packages/quds_office_engine/lib/src/sheet/formula/formula_eval.dart)
and a read-only cell resolver. References shift from the rule range's top-left
cell to the evaluated cell; `$`-anchored rows and columns remain fixed. Quoted
worksheet references, supported named ranges, scoped scalar names and supported
table references retain workbook scope. Defined-name expressions beyond the
existing scalar-name support are not evaluated.

A non-null cached formula value is used when it differs from the formula text.
An uncached formula is evaluated within the same restricted subset, without
writing its result back. Missing cells remain missing, and circular reads
produce errors. Rendering does not recalculate the workbook or validate whether
an imported cache is current.

An expression matches only a Boolean `true` or a finite nonzero numeric scalar.
Malformed input, unsupported functions, unhandled errors, array results and
nonfinite final predicates do not match. Actual errors can be handled explicitly
by supported `ISERROR`, `IFERROR` and related functions; missing evaluator
capability remains distinct from an ordinary formula error. Logical aggregators
inspect range values and propagate errors. Scalar `NOT` and `IF` do not coerce
range containers to true. These behaviors are implemented in
[`formula_functions.dart`](../packages/quds_office_engine/lib/src/sheet/formula/formula_functions.dart).

The conditional function allowlist is:

| Group | Functions |
| --- | --- |
| Logic and errors | `TRUE`, `FALSE`, `AND`, `OR`, `XOR`, `NOT`, `IF`, `IFERROR`, `IFNA` |
| Numeric | `ABS`, `MOD`, `INT`, `ROUND`, `ROUNDUP`, `ROUNDDOWN` |
| Aggregation | `SUM`, `MIN`, `MAX`, `AVERAGE`, `COUNT`, `COUNTA`, `COUNTBLANK` |
| Type checks | `ISBLANK`, `ISNUMBER`, `ISTEXT`, `ISLOGICAL`, `ISERROR`, `ISERR`, `ISNA` |
| Text | `LEN`, `LOWER`, `UPPER`, `TRIM`, `LEFT`, `RIGHT`, `MID`, `EXACT`, `FIND`, `SEARCH` |
| Position | `ROW`, `COLUMN`, `ROWS`, `COLUMNS` |

Ordinary supported arithmetic/comparison operators also remain available. Dynamic
references, volatile functions and array generators are outside this subset.
The resolver enforces these structural limits:

| Input or operation | Maximum |
| --- | ---: |
| Formula source length | 8,192 UTF-16 code units |
| Lexer tokens, including its end token | 1,024 |
| Nested parentheses | 64 |
| Cells in one formula range | 4,096 |
| Referenced-cell reads per evaluation | 8,192 |
| Active recursive cell reads | 64 |

Numeric literals, referenced caches, arithmetic results and scalar function
results must remain finite. Overflow becomes a typed `#NUM!` before a comparison
or `IF` can treat it as a true value. Explicit error handlers can handle that
error. `ROUND`, `ROUNDUP` and `ROUNDDOWN` support decimal precision from **−308 to
308**, after truncating a finite fractional digit count toward zero; larger
magnitudes return `#NUM!`, including digit counts read from cells. Their scaling
and the shared power/logarithm operations use bounded math primitives rather
than loops controlled by the numeric magnitude. The
[formula AST](../packages/quds_office_engine/lib/src/sheet/formula/formula_ast.dart)
and [numeric function implementation](../packages/quds_office_engine/lib/src/sheet/formula/formula_functions.dart)
contain these guards.

Numeric bounds and aggregate inputs must also be finite. The compact model's
numeric conversion accepts numeric strings and Boolean values. Text rules
retain their existing matching behavior. Legacy equality rules accept Unicode
bare text when it has no formula syntax or declared-name meaning; quote text
such as `"SUM("` when it contains formula syntax. This is a supported subset,
not complete Excel formula conformance.

## Sparse aggregate rules

Duplicate, top/bottom, percentage and average rules inspect stored cells inside
their applies-to range. They do not enumerate every coordinate of a sparse
whole-column or whole-sheet range. Errors are excluded from aggregate inputs;
numeric rules use finite converted values, and duplicate rules exclude empty
text. Rank boundaries include ties. The aggregate is cached for the current
resolver operation. Formula ranges inside an expression remain subject to the
separate 4,096-cell limit above.

## Saving edited colors

The XLSX serializer preserves existing differential-format (`dxf`) entries. When
a modeled color changes, it copies the referenced entry, changes the requested
fill/font color and assigns a matching existing or newly appended entry. Other
rules sharing the original entry keep their style. Unmodeled properties such as
bold, border, number format and extension XML remain on the copied entry.
Clearing a fill removes its fill override; clearing font color leaves other font
properties intact. Added rules receive valid style references, and repeated
in-memory saves reuse existing equivalent entries.

Imported font-only and unstyled rules retain an absent fill. The
[`ODS writer`](../packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_writer.dart)
also retains an unstyled expression rather than dropping it. ODS interchange
preserves supported expressions and modeled colors; this does not establish
complete native conditional-rule preservation or XLSX priority/stopping metadata
parity across ODS.

Behavior coverage is maintained in the
[engine conditional tests](../packages/quds_office_engine/test/sheet_conditional_rendering_test.dart),
[native style edit tests](../packages/quds_office_engine/test/sheet_conditional_dxf_edit_test.dart)
and [actual grid raster tests](../packages/quds_office_editor/test/sheet_conditional_rendering_test.dart).
