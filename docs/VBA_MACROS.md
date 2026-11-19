# Excel VBA macros: the `vba-excel` dialect

The engine can compile an explicitly selected `.bas` module into its native
Office macro format. `OfficeVbaMacroLanguage` implements the same language
interface as native JSON and is installed in `OfficeMacroLanguages` by default.
The dialect is named **`vba-excel`** to make its supported subset explicit.

Compilation reads only the supplied source. It evaluates supported scalar
expressions and conditions, expands bounded loops and ranges, and returns an
immutable sequence of ordinary spreadsheet operations. The resulting plan can
be inspected, saved, validated, or executed through the existing transactional
runtime. It has the same tool permissions, document admission, cancellation,
and publication behavior as handwritten or recorded native macros.

This increment targets the spreadsheet family (`xlsx`, including macro-enabled
and template workbook packages admitted by the existing runtime). Embedded VBA
projects are preserved as opaque bytes. Opening a workbook never loads or runs
those projects. Word VBA, PowerPoint VBA, forms, events, COM, and general VBA
compatibility are outside this dialect.

## Run a source file

From `packages/quds_office_engine`, with the repository dependencies resolved:

```bash
# Compile only: inspect the generated native plan before execution.
dart run tool/macros/office_macro.dart compile-vba \
  example/macros/monthly_totals.bas monthly.qudsmacro.json

# Execute against a detached workbook, with no published changes.
dart run tool/macros/office_macro.dart validate-vba \
  input.xlsx example/macros/monthly_totals.bas

# Publish the complete result after every step succeeds.
dart run tool/macros/office_macro.dart run-vba \
  input.xlsx example/macros/monthly_totals.bas output.xlsx
```

The optional final argument selects a parameterless `Sub`; its default is
`Main`. For example:

```bash
dart run tool/macros/office_macro.dart run-vba \
  input.xlsm report.bas output.xlsm BuildReport
```

Input and output must retain the same filename extension. A compilation or
execution failure leaves an existing output file untouched. Source files are
UTF-8 and limited to 1 MiB. The source filename supplies the diagnostic module
name; source envelopes and Dart callers can set `moduleName` explicitly.

The committed monthly example generates synthetic data for twelve months,
calculates net amounts and totals, and styles the header and total row. It
demonstrates the compiler and does not read revenue data from the workbook.

## Example

```vb
Option Explicit

Sub Main()
    Dim row As Long
    With ThisWorkbook.Worksheets("Summary")
        .Range("A1").Value2 = "Amount"
        .Range("A1:B1").Font.Bold = True
        .Range("A1:B1").Interior.Color = RGB(230, 240, 250)

        For row = 2 To 4
            .Cells(row, 1).Value2 = row * 10
        Next row

        .Range("B2").Formula = "=SUM(A2:A4)"
    End With
End Sub
```

The compiler emits values `20`, `30`, and `40` for `A2:A4`. The formula remains
a workbook formula, calculated by the existing spreadsheet engine when the
native plan runs. This distinction matters: source expressions are evaluated
during compilation, while worksheet formulas are evaluated against the detached
workbook during execution.

## Object model and operation mappings

| Source construct | Behavior |
| --- | --- |
| `Worksheets(1)` | First worksheet in the explicitly opened workbook; lowered to native sheet index `0` |
| `ThisWorkbook.Worksheets(1)` | Same explicitly opened workbook binding |
| `Worksheets("Summary")` | Name is retained in the native plan and resolved case-insensitively at execution |
| `worksheet.Range("A1")` | One cell in A1 notation |
| `worksheet.Range("A1:B3")` | Contiguous rectangle, expanded into bounded per-cell operations |
| `worksheet.Cells(row, column)` | One-based integer coordinates converted to A1 notation |
| `range.Value2 = scalar` or `range.Value = scalar` | `xlsx.cellValue`; supported scalar values only |
| `range.Formula = "=..."` | `xlsx.cellFormula` |
| `range.Font.Bold = True` | `xlsx.cellFormat` with `bold` |
| `range.Font.Size = 14` | `xlsx.cellFormat` with `size` |
| `range.Font.Color = RGB(r, g, b)` | `xlsx.cellFormat` with a normalized RGB hex color |
| `range.Interior.Color = RGB(r, g, b)` | `xlsx.cellFormat` with `fill` |
| `range.ClearContents` | `xlsx.cellValue` with null, removing value/formula and retaining formatting |

Names and keywords are case-insensitive. Worksheet names retain their original
text in the emitted plan. Unknown names and ambiguous case-insensitive matches
fail during document validation or execution; no fallback worksheet is used.
Native JSON integer sheet selectors remain zero-based. VBA numeric worksheet
selectors and `Cells` coordinates are one-based.

There is no active-selection binding. Unqualified `Range`, `Cells`,
`ActiveSheet`, `Selection`, and external workbook access are rejected. Use an
explicit worksheet qualifier or a supported `With`/`Set` binding. This avoids
guessing which sheet a user had selected in another application.

Only supported member names are admitted. `Merge`, `ColumnWidth`, `NumberFormat`,
`FormulaR1C1`, dynamic arrays, named ranges, whole rows/columns, discontiguous
ranges, and default members are not translated into approximate operations.

## Supported language constructs

| Construct | Supported behavior and restrictions |
| --- | --- |
| Module structure | Optional `Attribute VB_Name = "..."`, optional `Option Explicit`, module constants, and parameterless `Sub` procedures with optional `Public`/`Private` |
| Entry selection | Case-insensitive selection by `entryPoint`; all procedures are parsed and checked, but only the selected procedure is evaluated |
| Declarations | `Dim` and `Const`, including comma-separated declarations; declarations must precede executable statements and remain outside control-flow blocks |
| Scalar types | `Long`, `Double`, `String`, `Boolean`, and scalar `Variant`; omitted `As` means `Variant` |
| Object types | `Worksheet` and `Range` variables, assigned with `Set`; object default members are unsupported |
| Constants | Literals, supported unary/binary expressions, and previously declared constants; function calls in constant initializers are unsupported |
| Assignment | Scalar assignment, optional `Let`, and explicitly supported writable object properties |
| Arithmetic | Decimal/exponent literals, parentheses, unary `+`/`-`, and binary `+`, `-`, `*`, `/` |
| Text | Double-quoted literals with doubled embedded quotes and `&` concatenation of scalar values |
| Comparisons | `=`, `<>`, `<`, `>`, `<=`, `>=` between matching scalar types; string comparisons use binary ordering |
| Boolean logic | `Not`, `And`, `Or`, `Xor` on Boolean values; operands are evaluated eagerly |
| Conditions | Block `If … Then`, `ElseIf`, `Else`, `End If`; conditions must be Boolean and known from source |
| Loops | Integer `For … To … [Step …]` and `Next [counter]`; bounds are inclusive, default step is `1`, negative steps are supported |
| Object context | Nested `With` blocks for worksheets or ranges; leading `.` refers to the innermost context |
| Source formatting | Apostrophe/`Rem` comments, colon statement separators, whitespace-underscore line continuation, CRLF/LF, and an optional UTF-8 BOM |

Typed variables start at `0`, `0.0`, `""`, or `False`. An uninitialized
`Variant`, `Worksheet`, or `Range` cannot be read; assign it first. With
`Option Explicit`, undeclared variables are errors. Without it, assignment
targets and loop counters can introduce scalar Variant variables, but an
undeclared read still fails. Arrays, `Empty`, `Null`, and `Nothing` are not
implemented.

Assignments and operations use strict types. Arithmetic uses finite binary64
intermediates within the portable numeric bound; integral results are normalized
back to exact integers. This dialect does not emulate every VBA intermediate
numeric subtype overflow rule. `Long` bounds are enforced at assignment and
loop-counter increment. There is no implicit conversion
between strings, numbers, and Booleans, no fractional-to-integer rounding, and
no Date/Currency behavior. `&` deliberately supports scalar-to-text conversion;
numeric text uses invariant Dart formatting and Boolean text is `True`/`False`.
Cell strings remain strings rather than using Excel's locale/format-driven
type guessing. Strings beginning with `=` require an explicit `.Formula`
assignment; formulas must begin with `=` and contain an expression. These
restrictions also apply to the scalar `.Value` alias.

`Long` assignment and increment must fit signed 32-bit bounds. Loop start,
end, and step must also fit signed 32-bit bounds; the counter must be `Long`
or scalar `Variant`. Start/end/step expressions are evaluated once on entry.
`Step 0`, reassignment of an active loop counter, and reuse of that counter
in a nested loop are rejected. The counter retains its post-loop value.

RGB components must be nonnegative integers; values above 255 clamp to 255,
matching the documented `RGB` behavior. Explicit integer colors use VBA's
red/green/blue byte ordering and are converted to the engine's six-digit RGB
hex representation. System colors and palettes are unsupported.

Procedure calls, functions other than `RGB` and object selectors, arguments to
`Sub`, `ByRef`, recursion, `For Each`, `Do`/`While`, `Exit`, `GoTo`, error handlers,
conditional compilation, file/network operations, `Shell`, `CreateObject`,
`Application.Run`, and document-value reads are rejected. Unsupported syntax,
unknown names, and unsupported object shapes are checked in inactive branches
and unselected procedures too. Value-dependent errors are detected when the
selected procedure is evaluated.

## Compilation limits

The compiler has its own limits before the native runtime receives a plan:

| Limit | Maximum |
| --- | ---: |
| Source UTF-8 bytes | 1 MiB |
| Lexer tokens | 50,000 |
| Procedure statements | 10,000 |
| Block nesting | 32 |
| Expression nesting / AST depth | 64 |
| Visible variables per procedure, including module constants | 256 |
| String literal / concatenation length | 32,767 UTF-16 code units |
| Absolute numeric magnitude | 9,007,199,254,740,991 (`2^53 − 1`) |
| Evaluation and statement visits | 100,000 |
| Emitted native operations | 10,000 |
| Encoded native plan | 1 MiB |

The numeric bound applies to literals and intermediate results across Dart VM
and JavaScript. Arithmetic must remain finite. The compiler refuses work before
expanding a range that exceeds the remaining operation budget. Each emitted
operation is charged against the aggregate encoded byte budget, and compilation
work is charged even for loops with empty bodies. Strings are bounded before
concatenation allocates a larger result.

The runtime applies its own policy again. Its default maximum is **1,000
operations**, so a plan can compile successfully and still exceed a host's
execution limit. A trusted host can select limits through `OfficeMacroPolicy`;
source cannot raise them. These cooperative bounds do not establish a hard
process-level CPU or memory sandbox.

## Source envelopes, Dart, and MCP

The general `compile SOURCE.json OUTPUT.json` CLI accepts this source envelope:

```json
{
  "language": "vba-excel",
  "format": "xlsx",
  "moduleName": "Report",
  "entryPoint": "Main",
  "source": "Sub Main()\nWorksheets(1).Range(\"A1\").Value2 = 42\nEnd Sub"
}
```

The Dart API uses exactly the same registry:

```dart
final macro = OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    moduleName: 'Report',
    entryPoint: 'Main',
    source: sourceText,
  ),
);

// Source compilation has no document access or publication authority.
final jsonForReview = macro.encode();
await session.validate(macro);
await session.run(macro);
```

The MCP `office_macro_compile` tool accepts `{"source": <source envelope>}`
and returns `macro` in its structured result. Its default schema advertises
`vba-excel`. Pass that returned object to `office_macro_validate` or
`office_macro_run`. Compilation remains a non-mutating operation even when
the session has a read-only execution policy; the eventual run still requires
permission for every emitted tool.

## Diagnostics and transaction boundaries

`OfficeVbaCompileException` is an `OfficeMacroException` with module name,
entry point, one-based line and column, a stable error code, and an explanatory
message. CLI stderr and MCP tool errors preserve its structured fields. A
source error produces no partial macro or partially edited document.

Runtime errors use the native plan's zero-based `stepIndex` and canonical tool
name. Expanded loops and ranges may produce many native steps from one source
statement; the version 1 plan does not retain a source map. Inspect the compiled
JSON to locate a failing generated operation.

Validation and execution both perform real document operations and serialization
on detached models. Validation publishes nothing. Execution publishes only
after every operation and serialization succeeds. A missing worksheet in a
later step therefore rolls back all earlier writes. Compiler output cannot
bypass a read-only policy, an operation allowlist, or the session's step/byte
limits.

## Compatibility references

The supported mappings are based on Microsoft's documented VBA behavior:

- [Range addressing, qualified worksheets, and Cells](https://learn.microsoft.com/en-us/office/vba/api/excel.range(object))
- [Value2 and its distinction from Value](https://learn.microsoft.com/en-us/office/vba/api/excel.range.value2)
- [Formula assignment to ranges](https://learn.microsoft.com/en-us/office/vba/api/excel.range.formula)
- [ClearContents](https://learn.microsoft.com/en-us/office/vba/api/excel.range.clearcontents)
- [For…Next](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/fornext-statement)
- [RGB color values](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/rgb-function)
- [Operator precedence](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/operator-precedence)

This is a bounded source-to-plan implementation. It does not claim native Excel
interoperability for arbitrary VBA modules or parity with the full Excel object
model. See [the macro guide](MACROS.md) for document admission, serialization,
formula compatibility, and host-policy boundaries.
