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

Modules can share source logic through local `Sub` helpers and scalar
`Function` procedures. Calls are evaluated during compilation with isolated
local variables and explicit `ByVal` arguments; they do not introduce a second
document execution path. Conditional `Do`/`While` loops and `Select Case`
selection use the same source values and aggregate compilation budgets. Fixed
one-dimensional local arrays and `For Each` loops support bounded source-data
processing and explicit cell-range iteration within those same budgets.
Dynamic local arrays add `ReDim`, `ReDim Preserve`, and `Erase`; module
`Option Base` controls omitted lower bounds for both fixed and dynamic arrays.
String expressions can use `Len`, `Left$`, `Right$`, and `Mid$` with explicit
UTF-16 indexing, strict argument types, and the shared compilation work budget.
Scalar Variants now distinguish `Empty` and `Null`, with state predicates,
explicit bounded conversions, and an explicit native-publication contract.
Module helpers also accept named arguments and optional scalar `ByVal`
parameters, including an explicit omitted-Variant state checked by `IsMissing`.
The [shared argument contract](VBA_ARGUMENTS.md) applies to all three adapters.

This increment targets the spreadsheet family (`xlsx`, including macro-enabled
and template workbook packages admitted by the existing runtime). Embedded VBA
projects are preserved as opaque bytes. Opening a workbook never loads or runs
those projects. Word VBA, PowerPoint VBA, forms, events, COM, and general VBA
compatibility are outside this dialect. The
[VBA parity roadmap](VBA_PARITY_ROADMAP.md) separates the delivered subset from
the language, document-aware runtime, and Word/PowerPoint adapter milestones.

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

## Reusable procedures and functions

The entry point remains a parameterless `Sub`. It can invoke other procedures
in the same source module, including procedures declared later in the file:

```vb
Option Explicit

Sub Main()
    Dim amount As Long
    amount = 21
    Call PutResult(Worksheets(1).Range("A1"), Twice(amount))
    Worksheets(1).Range("B1").Value2 = amount
End Sub

Private Sub PutResult(ByVal target As Range, ByVal amount As Long)
    target.Value2 = amount
    target.Font.Bold = True
End Sub

Private Function Twice(ByVal amount As Long) As Long
    amount = amount * 2
    Twice = amount
    Exit Function
End Function
```

This emits `42` for `A1` and `21` for `B1`: reassigning a `ByVal` argument does
not change the caller's variable. A `Worksheet` or `Range` argument retains its
explicit target binding, so helper property writes still target that worksheet
or range. Rebinding an object parameter with `Set` changes only that helper's
binding. A scalar `Variant` cannot carry object bindings.

The compiler accepts `Call Helper(argument1, argument2)` and
`Helper argument1, argument2`. Use `Helper` or `Call Helper()` for a helper
without arguments. Functions used in expressions require parentheses, such as
`Twice(amount)` or `DefaultAmount()`. A function may also be called as a
statement, in which case its result is discarded. Names are case-insensitive,
and `Public`/`Private` do not change access within this single-module dialect.
Line labels such as `Helper:` are rejected, including when the name matches
a helper. To place a parameterless call before a colon statement separator,
write `Call Helper: ...` or `Helper(): ...` explicitly.

Every declared parameter must explicitly say **`ByVal`**. VBA normally defaults
to `ByRef`; this compiler rejects an omitted passing mode rather than silently
changing its meaning. Required parameters can be supplied positionally or by
name (`name:=expression`). Optional scalar parameters use `Optional ByVal`
and may declare constant defaults. Parameter
types are `Long`, `Double`, `String`, `Boolean`, scalar `Variant`, `Worksheet`,
and `Range`; an omitted `As` means scalar `Variant`. `ByRef`, optional object
parameters, array parameters, and `ParamArray` remain unsupported.
Individual scalar array elements can be passed to scalar `ByVal` parameters.
See [named arguments, omissions, defaults, and IsMissing](VBA_ARGUMENTS.md)
for the exact binding and refusal rules.

Functions return one supported scalar, using assignment to their own name.
An omitted return type means scalar `Variant`; object return types are not
supported. Typed functions begin with the same default value as typed local
variables: zero, an empty string, or `False`. An unassigned `Variant` function
returns `Empty`; its return slot can be read before assignment. Statement calls
may discard a result, including `Empty` or `Null`. A function's
return variable may be read after initialization or assignment; its name with
parentheses denotes a call and is subject to recursion checking.

Arguments are evaluated once, from left to right, in the caller's context.
Each call receives fresh local variables, local constants, and its own `With`
context. Caller locals and active loop counters are not visible inside the
callee. Functions can emit the same explicit worksheet writes as Subs; those
writes appear in the generated plan in evaluation order. Source functions
still cannot read workbook values.

`Exit Sub` and `Exit Function` return from the containing procedure.
`Exit For` exits the innermost counted `For` or `For Each` in that procedure
and leaves its control variable at the current value or binding. `Exit Do` exits the innermost `Do` in that procedure.
Each loop exit passes through other loop kinds and nested `If`, `Select Case`,
and `With` blocks until it reaches its own loop kind. The enclosing object
context is restored when control returns. An exit cannot terminate a caller's
loop. Exit kinds are checked even in unused procedures and statements following
an earlier exit. `Exit While` and `Exit Select` are unsupported.

The entire module's call graph must be acyclic and fit the 32-frame limit,
including calls in inactive branches and unused procedures. Local variables,
parameters, and module constants cannot shadow procedure names. These rules
keep the supported binding model explicit. There are no cross-module calls,
dynamic dispatch, external procedures, or recursion.

The committed [procedural report](../packages/quds_office_engine/example/macros/procedural_report.bas)
uses reusable heading and row helpers plus nested price/discount functions.
It generates six rows of synthetic sales data, emits **46 native operations**,
and calculates a net total of **2,117.50** through a worksheet formula. Run it
with the same CLI:

```bash
dart run tool/macros/office_macro.dart compile-vba \
  example/macros/procedural_report.bas report.qudsmacro.json
dart run tool/macros/office_macro.dart run-vba \
  input.xlsx example/macros/procedural_report.bas output.xlsx
```

## Conditional loops and Select Case

Conditional loops recheck a Boolean expression built from source values.
The body can update local variables used by the next check. `Empty` and `Null`
conditions are false. Other conditions require actual Booleans; numeric or
string truthiness and reading a condition from the workbook remain unsupported.

| Loop form | Condition timing |
| --- | --- |
| `Do While condition` … `Loop` | Check before each iteration; run while `True` |
| `Do Until condition` … `Loop` | Check before each iteration; run while `False` |
| `Do` … `Loop While condition` | Run once, then check after each iteration; continue while `True` |
| `Do` … `Loop Until condition` | Run once, then check after each iteration; continue while `False` |
| `Do` … `Loop` | Continue until an enclosing-procedure return, `Exit Do`, or the compilation work limit |
| `While condition` … `Wend` | Check before each iteration; run while `True` |

A `Do` may have a condition at its beginning or its end, never both. Helpers
in a condition run once per check, including the final failed check. A loop
exit or procedure return that leaves a `Do` skips its remaining body and
trailing condition.
Every loop attempt consumes the shared work budget, including an empty
unconditional loop; exceeding the budget fails compilation without returning
a partial plan. A `While` loop has no dedicated early-exit statement, but an
`Exit Do` or `Exit For` inside it can leave a matching enclosing loop.

`Select Case` compares one source expression against ordered clauses:

```vb
Select Case amount
    Case 0, 75
        label = "Small"
    Case 76 To 225
        label = "Standard"
    Case Is < 400
        label = "Large"
    Case Else
        label = "Review"
End Select
```

The selector is evaluated once. Clauses and comma-separated alternatives are
checked in source order until the first match; only that clause's body runs,
with no fallthrough. Later alternatives and clauses are not evaluated after a
match. An optional `Case Else` must be last. Empty bodies are allowed; without
a match or fallback, execution continues after `End Select`.

Each alternative can be a scalar expression, an inclusive `lower To upper`
range, or a comparison with `=`, `<>`, `<`, `>`, `<=`, or `>=`. The `Is` keyword
before a comparison is optional. Ranges accept matching numeric or string
values, use binary string ordering, and evaluate both endpoints even if the
lower comparison fails. Reversed ranges do not match. Boolean equality and
relational cases retain the dialect's `True`-before-`False` ordering, but
Boolean ranges are unsupported. `Empty` compares as zero against numbers,
`False` against Booleans, or `""` against Strings. `Null` comparisons do not
match, including `Case Null` against a `Null` selector. A range still evaluates
both endpoints when a comparison yields `Null`. Other scalar types must match;
no implicit string/number/Boolean conversion is introduced.

Static checking visits every condition, Case expression, and body, including
unselected clauses and code after an exit. Unsupported calls, object reads,
invalid exits, declarations inside blocks, and known type mismatches still
fail there. Values carried by `Variant` are also checked when evaluated.

The committed [control-flow report](../packages/quds_office_engine/example/macros/control_flow_report.bas)
combines `Do … Loop Until`, `While … Wend`, reusable helpers, and `Select Case`
to generate six synthetic rows with amount bands. It emits **35 native
operations** and calculates a worksheet formula total of **1,575**. Its input
workbook needs a worksheet named `Summary`:

```bash
dart run tool/macros/office_macro.dart compile-vba \
  example/macros/control_flow_report.bas control-flow.qudsmacro.json
dart run tool/macros/office_macro.dart validate-vba \
  input.xlsx example/macros/control_flow_report.bas
dart run tool/macros/office_macro.dart run-vba \
  input.xlsx example/macros/control_flow_report.bas output.xlsx
```

## Fixed arrays and For Each

Local procedures can declare fixed one-dimensional arrays of `Long`, `Double`,
`String`, `Boolean`, or scalar `Variant` elements:

```vb
Option Explicit

Const FirstRow As Long = 2

Sub Main()
    Dim amounts(FirstRow To FirstRow + 2) As Long
    Dim item As Variant, total As Long, row As Long
    Dim cell As Range

    amounts(2) = 125
    amounts(3) = 250
    amounts(4) = 475

    For row = LBound(amounts) To UBound(amounts)
        Worksheets("Summary").Cells(row, 1).Value2 = amounts(row)
    Next row

    For Each item In amounts
        total = total + item
    Next item
    Worksheets("Summary").Range("A5").Value2 = total

    For Each cell In Worksheets("Summary").Range("A2:A5")
        cell.Font.Bold = True
    Next cell
End Sub
```

This writes three source-defined amounts and their total, **850**, and formats
four explicitly bound cells. No cell values are read from the input workbook.
The committed [array report](../packages/quds_office_engine/example/macros/array_report.bas)
combines typed label and amount arrays, scalar helper calls, both `For Each`
forms, and an independently calculated worksheet formula total.

Array declarations must precede executable statements, just like scalar
`Dim` declarations. `Dim values(3) As Long` declares indices **0 through 3**;
`Dim values(-2 To 2) As Long` declares indices **-2 through 2**. Explicit bounds
are inclusive, must be signed 32-bit integers, and may use literals, supported
constant expressions, and previously declared module or local constants.
An upper bound below the lower bound is invalid. Bounds are checked even in
unused procedures; source functions and variable-dependent bounds are not
allowed. An omitted lower bound is zero unless the module specifies
`Option Base 1`; an explicit `lower To upper` always takes precedence.

Every typed element starts with its scalar default: zero, an empty string, or
`False`. Each `Variant` element starts as `Empty` and can be read or visited
by `For Each` without a prior assignment. Reads and writes use one
integer index, as in `amounts(row)`; fractional indices and out-of-bounds
indices produce structured compiler diagnostics. Element assignments retain
the scalar type, finite-number, `Long`, and string limits. `Let` is optional.

`LBound(values)` and `UBound(values)` return the declared bounds. Both accept
an optional second argument specifying dimension **1**. Other dimensions are
rejected. These intrinsics require a local array variable; array elements are
ordinary scalar expressions and can be passed to existing scalar helpers.
Arrays cannot be assigned, passed, returned, or placed inside another
`Variant` as whole values. Multidimensional arrays, arrays of objects, `Array`,
and `Split` remain outside this dialect. Dynamic array allocation and erasure
are described below.

For an array, `For Each item In values` requires a `Variant` control variable.
Without `Option Explicit`, an undeclared control variable may be introduced as
an implicit scalar `Variant`. Elements are visited in ascending index order.
The loop reads each slot when that iteration begins, so writing a later slot
inside the body changes the value seen later. Assigning the control variable
itself changes only that scalar variable; it does not write back into the
array. On normal completion, the control variable retains the value left by
the final body execution.

For an explicitly bound rectangular `Range`, `For Each cell In target` requires
a `Range` control variable. The collection expression is evaluated once at
loop entry; subsequent rebinding of `target` does not change that iteration.
Cells are visited from left to right, then top to bottom, with one single-cell
binding per iteration. Rebinding the control variable changes only the current
body's binding. The next iteration receives the next cell from the original
range. `range.Row` and `range.Column` return the one-based top-left coordinates
of any supported range. They are read-only source metadata, so they work during
compilation without document access. Cell `.Value`, `.Value2`, and `.Formula`
reads remain unsupported.

`Next` may omit its control variable; when present, it must match the loop.
Nested counted or collection loops cannot reuse an active control variable.
`Exit For` leaves the nearest `For` or `For Each`, including through nested
`Do`, `While`, `Select Case`, and `With` blocks. Procedure returns and matching
loop exits restore enclosing object contexts. Loop bodies and collection
expressions are checked even in inactive branches and unused procedures.

Each array is limited to **4,096 elements**. The total across simultaneously
active procedure frames is limited to **16,384 array slots**; slots are released
when a procedure returns. Strings stored in all active array slots together
are limited to **1,048,576 UTF-16 code units**. Each occupied slot counts its
string length, including slots sharing equal or identical strings; replacing a
slot or returning from a procedure releases its contribution. Allocation, bound
evaluation, indexing, and iteration
consume the shared compilation work budget. Large range collections are checked
against the remaining work budget before iteration, including loops with empty
bodies. Arrays do not increase the existing operation or encoded-plan limits.

## Dynamic arrays, ReDim, Erase, and Option Base

Declare a local dynamic array with empty parentheses, then allocate its bounds
using source expressions. All five supported scalar element types work;
omitting `As` declares an array of scalar Variant elements:

```vb
Option Explicit
Option Base 1

Sub Main()
    Dim amounts() As Long, amount As Variant, total As Long
    ReDim amounts(2)
    amounts(1) = 125
    amounts(2) = 250
    ReDim Preserve amounts(3)
    amounts(3) = 475

    For Each amount In amounts
        total = total + amount
    Next amount
    Worksheets("Summary").Range("A1").Value2 = total

    Erase amounts
    ReDim amounts(-2 To 0)
    Worksheets("Summary").Range("A2").Value2 = amounts(-2)
End Sub
```

This writes **850** and **0**. The array starts without allocated storage;
indexing, `LBound`, `UBound`, and `For Each` before allocation or after dynamic
`Erase` fail with `vba_subscript_out_of_range`. Declaring an unused dynamic
array and erasing it repeatedly are valid.

`ReDim data(lower To upper)` allocates or replaces a declared dynamic array,
resetting every element to its typed default. It can change both bounds.
`ReDim Preserve` retains elements at their original indices, initializes new
slots to their defaults, and discards values outside a smaller upper bound.
Regrowing the array does not restore discarded values. Once allocated, the
lower bound must stay the same with `Preserve`; changing it produces
`vba_subscript_out_of_range`. `Preserve` on an unallocated array allocates it.
Variant slots that have not been assigned contain `Empty`, including after
growth, reset, or fixed-array erasure. Existing `Empty` and `Null` values are
preserved at their indices by `ReDim Preserve`.

Bounds are evaluated once, from left to right, and may use variables, bound
intrinsics, or supported scalar functions. A comma-separated `ReDim` list
processes its targets in source order: a later target can read the bounds
established by an earlier one. Each bound must be an integer in the signed
32-bit range; the upper bound must be at least the lower bound. There is one
dimension and at most 4,096 elements. These value-dependent checks run only
when the selected entry executes that statement. Unsupported target shapes,
known type mismatches, and bound function calls are checked throughout the
module, including unused procedures and dead branches.

An optional `As` clause on each `ReDim` target must repeat its declared element
type exactly. A fixed array cannot be resized. Unlike full VBA's declarative
form of `ReDim`, this dialect requires a preceding local `Dim name()`;
implicit arrays and scalar Variants holding whole arrays are unsupported.

`Erase first, second` processes each named array in order. A fixed array keeps
its original bounds and allocated slots while resetting every element. A
dynamic array releases its slots and becomes unallocated. Both release their
stored string occupancy. Array-element targets such as `Erase data(0)` are
unsupported.

An array being visited by `For Each` is locked against `ReDim` and `Erase`,
with a structured `vba_array_locked` diagnostic. Element writes keep the
existing behavior: a later iteration sees its slot's latest value. Each nested
enumeration holds its own lock. Completion, matching loop exits, and procedure
returns release the locks they leave; exiting an inner enumeration does not
unlock an outer enumeration over the same array. A helper's same-named local
array is independent.

`Option Base 0` or `Option Base 1` may occur once before any procedure, in either
order with `Option Explicit`. It applies throughout that one module to omitted
lower bounds in both `Dim` and `ReDim`, including `ReDim Preserve`. It does not
change explicit lower bounds or worksheet/cell indexing. The default is zero.

Allocation, retirement, preserved copying, fixed-array resetting, and each
`Erase` target consume the shared 100,000-visit budget. All simultaneously
active fixed and dynamic arrays share the 16,384-slot and 1,048,576-string-unit
limits. A resize accounts for the resulting active slots; shrinking, erasing,
overwriting, and returning from a procedure release the appropriate quota.
Resizing repeatedly cannot reset the work budget. Native operation and plan
byte limits are unchanged.

The committed [dynamic array report](../packages/quds_office_engine/example/macros/dynamic_array_report.bas)
grows source data, discards an extra item, writes a styled four-row report,
calculates matching source and worksheet totals of **850**, and demonstrates
the zero default after erasure and reallocation. It emits **24 native
operations** through the same compile/validate/run CLI and MCP paths.

## Object model and operation mappings

| Source construct | Behavior |
| --- | --- |
| `Worksheets(1)` | First worksheet in the explicitly opened workbook; lowered to native sheet index `0` |
| `ThisWorkbook.Worksheets(1)` | Same explicitly opened workbook binding |
| `Worksheets("Summary")` | Name is retained in the native plan and resolved case-insensitively at execution |
| `worksheet.Range("A1")` | One cell in A1 notation |
| `worksheet.Range("A1:B3")` | Contiguous rectangle, expanded into bounded per-cell operations |
| `worksheet.Cells(row, column)` | One-based integer coordinates converted to A1 notation |
| `range.Value2 = scalar` or `range.Value = scalar` | `xlsx.cellValue`; Strings, numbers and Booleans; `Empty` clears and `Null` is refused |
| `range.Formula = "=..."` | `xlsx.cellFormula` |
| `range.Font.Bold = True` | `xlsx.cellFormat` with `bold` |
| `range.Font.Size = 14` | `xlsx.cellFormat` with `size` |
| `range.Font.Color = RGB(r, g, b)` | `xlsx.cellFormat` with a normalized RGB hex color |
| `range.Interior.Color = RGB(r, g, b)` | `xlsx.cellFormat` with `fill` |
| `range.Row` / `range.Column` | Read-only one-based top-left coordinates from the explicit source range |
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
`FormulaR1C1`, worksheet dynamic spill formulas, named ranges, whole rows/columns, discontiguous
ranges, and default members are not translated into approximate operations.

## Numeric intrinsics

The shared Word, Excel and PowerPoint source dialects support `Abs`, `Int`,
`Fix`, and `Sgn` in source expressions. Each accepts exactly one positional
argument, evaluated once before the result is used. Names are case-insensitive
and reserved for these functions. Named/omitted arguments, `$` aliases and
module-qualified calls are not supported. Existing restrictions on calls in
`Const` expressions and optional parameter defaults remain in effect.

| Function | Result | Example |
| --- | --- | --- |
| `Abs(number)` | Nonnegative magnitude | `Abs(-8.4)` is `8.4` |
| `Int(number)` | Greatest integer no larger than the input | `Int(-8.4)` is `-9` |
| `Fix(number)` | Integer portion, truncating toward zero | `Fix(-8.4)` is `-8` |
| `Sgn(number)` | `-1`, `0`, or `1` according to the input's sign | `Sgn(-8.4)` is `-1` |

Actual numbers, numeric scalar Variants and `Empty` are accepted; `Empty`
contributes zero. `Abs`, `Int` and `Fix` propagate `Null`, including nested
calls and nullable helper results. Test such a result with `IsNull` before
assigning it to a typed scalar or a document property. `Sgn(Null)` produces
`vba_invalid_use_of_null` in this bounded dialect. A missing optional Variant
must still be handled with `IsMissing` before reading it.

Strings and Booleans require an explicit conversion, even when a Variant
contains them: `Abs(CDbl("-12.5"))` and `Abs(CDbl(True))` are supported,
while `Abs("-12.5")` and `Abs(True)` are refused. Locale-dependent implicit
conversion and the complete VBA numeric subtype/overflow system are not
implemented. In particular, the shared numeric envelope allows
`Abs(CLng(-2147483648))` to produce `2147483648`; assigning that result to
a declared `Long` still fails its signed 32-bit bound.

Inputs and results remain finite and within `±9007199254740991`. The ordinary
arithmetic, evaluation and emitted-operation budgets apply to arguments,
helpers and surrounding loops. Negative zero is normalized to zero. These
functions do not round to a requested decimal precision or relax the exact
point/twip/integer requirements of document properties. A failing argument,
unused statically invalid helper, or invalid native operation cannot publish
a partial macro run.

The [58-case numeric corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/word_numeric_intrinsics_v1.json)
records independently authored arithmetic expectations separately from
deliberate dialect limits. The [Word numeric report](VBA_WORD_MACROS.md#calculating-word-layout-values)
uses the functions through the existing native transaction and policy boundary.
This qualifies source-known calculations; live document-value reads and an
installed Microsoft Office differential run remain separate work.

## String intrinsics

These case-insensitive functions operate on source String values, including a
supported scalar `Variant` currently containing a String. They can be nested,
used with array elements, passed to helpers, or used to compute an explicit
worksheet/range selector. All three VBA adapters share these functions. They
operate on source-known values and do not read document contents.

| Signature | Result and bounds |
| --- | --- |
| `Len(text)` | Number of UTF-16 code units in the String |
| `Left$(text, count)` | First `count` units, clamped to the available text |
| `Right$(text, count)` | Last `count` units, clamped to the available text |
| `Mid$(text, start[, count])` | Units starting at one-based `start`; omitted `count` returns the remaining suffix |

`count` must be an exact integer from `0` through `2147483647`; `start` must be
an exact integer from `1` through `2147483647`. An integral `Double` or assigned
numeric `Variant` can supply these values. A zero count returns `""`; a valid
start beyond the text also returns `""`. All arguments are evaluated exactly
once, left to right, before the intrinsic validates their values. A zero count
or a start past the end does not skip the other arguments or their diagnostics.

```vb
Dim record As String
record = "INV-1042|Paper"
Worksheets(1).Range("A1").Value2 = Left$(record, 8)  ' INV-1042
Worksheets(1).Range("B1").Value2 = Mid$(record, 10)  ' Paper
Worksheets(1).Range("C1").Value2 = Right$(Left$(record, 8), 4)  ' 1042
Worksheets(1).Range("D1").Value2 = Len(Mid$(record, 10))  ' 5
```

The text unit is explicitly UTF-16, matching the compiler's source positions
and String limits. `Len("A😀B")` is `4`, and `Mid$("A😀B", 2, 2)` is `"😀"`.
Combining marks count separately. A one-unit slice can split a surrogate pair;
these intrinsics do not count Unicode scalar values or grapheme clusters.
Such halves may be held in local values, measured with `Len`, and recombined.
Every String emitted into a native operation, including a cell value, formula,
or sheet selector, must contain well-formed UTF-16. A lone surrogate at this
boundary produces a positioned `vba_type_error` before a plan is returned;
the compiler never silently substitutes a replacement character during XLSX
publication. A normal supplementary character or correctly recombined pair is
preserved through the native plan and workbook round trip.

This slice keeps the dialect's strict conversion rules. Numeric/Boolean text
arguments, numeric `Len`, fractional counts, String-to-number conversion,
`Empty`, and `Null` are refused by these strict String signatures. Use
`CStr` or a numeric conversion explicitly where appropriate; `CStr(Null)` is
itself an error. Full VBA also gives `Len` storage-size
semantics for typed non-String variables and applies numeric Let-coercion;
those behaviors are not approximated here. Negative counts, zero/negative
starts, and values outside signed Long bounds produce `vba_type_error` when
evaluated. Wrong arity and statically incompatible types produce `vba_type_error`,
including in unused code. Value-dependent
errors in unexecuted branches are not evaluated.

The original substring slice provides these four signatures; the binary text
functions below extend it. Unsuffixed `Left`, `Right`, and `Mid`,
`LenB`/byte variants, `Len$`, named arguments, VBA qualification, and the
assignable `Mid$` statement remain unsupported. The `$` suffix is recognized
only for the implemented substring and Trim-family names; arbitrary variable and
procedure type suffixes are not enabled. Builtin names cannot be shadowed.
Function calls remain disallowed in constants and fixed-array bounds.

Every returned substring unit consumes one unit of the shared 100,000-work
budget, charged before allocation and after clamping. This charge also applies
when the result is the whole input; a huge requested count does not imply a
huge allocation. `Len` uses constant work in addition to normal argument
evaluation. The 32,767-unit per-string and active-array string limits still
apply. Exhaustion fails compilation without returning a partial native plan.

The runnable [string report](../packages/quds_office_engine/example/macros/string_report.bas)
uses all four intrinsics with dynamic arrays and reusable helpers. It emits 28
native operations, writes three parsed records, obtains matching source and
worksheet totals of **14**, and writes a UTF-16 length of **4** plus the extracted
emoji. Its records are synthetic source data.

```bash
dart run tool/macros/office_macro.dart compile-vba \
  example/macros/string_report.bas string-report.qudsmacro.json
```

[Versioned conformance cases](VBA_CONFORMANCE.md) distinguish documented
behavior, intentional dialect restrictions, and separately recorded Office
host observations. The current string corpus has no Office host execution
provenance; VM/JavaScript agreement establishes portability of this subset.

### Binary search, replacement, and trimming

The shared language also accepts the following case-insensitive names. Optional
arguments can be omitted from the **end** of a call; supply explicit defaults
to reach a later argument. Named arguments and interior omitted positions are
not supported for these intrinsics.

| Signature | Result |
| --- | --- |
| `InStr(text, find)` | One-based position of the first binary match, or zero |
| `InStr(start, text, find[, compare])` | Forward search beginning at one-based `start` |
| `InStrRev(text, find[, start[, compare]])` | Last match whose final code unit is at or before `start`; default `start = -1` means the end |
| `Replace(text, find, replacement[, start[, count[, compare]]])` | Suffix beginning at `start`, with nonoverlapping matches replaced; defaults are `start = 1`, `count = -1` (all) |
| `Trim(text)` / `Trim$(text)` | Remove U+0020 spaces from both ends |
| `LTrim(text)` / `LTrim$(text)` | Remove U+0020 spaces from the beginning |
| `RTrim(text)` / `RTrim$(text)` | Remove U+0020 spaces from the end |

Comparison defaults to binary and accepts only `0` or `vbBinaryCompare`.
`vbTextCompare` (`1`), `vbDatabaseCompare` (`2`) and `vbUseCompareOption` (`-1`)
are recognized constants but are refused as comparison modes. The dialect
does not implement locale-sensitive comparison, LCIDs, `Option Compare`,
`InStrB`, `InStr$`, `Replace$`, or numeric/Boolean-to-String coercion. Trim's
unsuffixed forms retain the same actual-String contract as its `$` forms;
they do not propagate `Null`. An explicit `CStr` may be used where its own
conversion contract permits it.

Search positions and returned offsets count UTF-16 code units. Forward search
and replacement starts are exact integers in `1..2147483647`. Reverse start
is `-1` or an exact integer in that positive range. Replacement count is `-1`
or an exact integer in `0..2147483647`. Actual integral numeric values are
accepted; fractional values, Strings, Booleans, Empty and Null are refused.
All arguments evaluate exactly once in source order before value checks,
including optional arguments on empty-input and no-op paths. Wrong arity and
statically incompatible types are diagnosed even in unused helpers or inactive
branches; value-dependent errors are diagnosed when evaluated.

These examples show details that matter when porting a macro:

```vb
InStr("A😀B😀C", "😀")                    ' 2
InStrRev("A😀B😀C", "😀", 5)              ' 2: the later match ends at 6
Replace("abcabc", "a", "X", 4)           ' "Xbc": the prefix is excluded
Replace("abcabc", "a", "X", 2, 0)        ' "bcabc": count zero still returns the suffix
Replace("aaaa", "aa", "X")              ' "XX": matches do not overlap
Trim$("  Annual report  ")               ' "Annual report"
```

Both searches return zero for an empty haystack or a missing match. For a
nonempty haystack, `InStr` with an empty needle returns the supplied start,
including a start beyond the end. `InStrRev` returns zero when an explicit
start is beyond the end; otherwise an empty needle returns its resolved start.
`Replace` returns an empty String when its start is beyond the input, and the
unchanged suffix for an empty needle or zero count. Empty replacement text
deletes matches. Replacement text is not searched again. Trimming preserves
tabs, nonbreaking spaces, other Unicode whitespace, and interior spaces.
The existing well-formed-UTF-16 publication check still applies to every String
emitted into a native operation.

Search uses a linear, metered code-unit matcher. Pattern storage, inspected
units, retained matches, and copied output consume the shared 100,000-work
budget, including discarded results and unsuccessful repeated searches.
Replacement computes the complete result length and checks the 32,767-unit
String limit and remaining work before constructing output. Exhaustion yields
a positioned diagnostic and no partial plan.

The complete [Word text report](../packages/quds_office_engine/example/macros/word_text_report.bas)
uses these functions to clean a title and extract a filename, then emits six
existing native operations against two body paragraphs and an independent
header paragraph. It is qualified through native transactions, CLI/MCP,
record/replay, DOCM preservation and VM/JavaScript execution in the
[local validation record](validation/word-vba-continuation-20261121/README.md).
The separate [versioned text corpus](VBA_CONFORMANCE.md) retains authored
expectations and explicit subset restrictions.

Primary contracts: [InStr](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/instr-function),
[InStrRev](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/instrrev-function),
[Replace](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/replace-function),
[Trim family](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/ltrim-rtrim-and-trim-functions),
and [String-returning `$` forms](https://learn.microsoft.com/en-us/office/vba/language/concepts/getting-started/returning-strings-from-functions).
The corpus separates specification-derived behavior from deliberate dialect
choices. In particular, combined empty-input/empty-needle/start/count boundary
precedence is recorded as a dialect contract pending Office differential
observation. No installed Office host was run.

### Binary String comparison

`StrComp(left, right[, compare])` is shared by the Word, Excel and PowerPoint
adapters. It compares source values in UTF-16 code-unit order and returns exactly
`-1`, `0`, or `1` for less-than, equal, or greater-than. Comparison is binary by
default; the only explicit mode is an actual exact numeric `0`, including
`vbBinaryCompare` or a Variant carrying that number.

String operands may be actual Strings or scalar Variants holding Strings,
`Empty`, or `Null`. `Empty` is compared as the zero-length String. If either
operand is `Null`, the result is `Null`, after both text operands and the supplied
comparison mode have been validated. Numeric and Boolean text operands require
explicit `CStr`; this restriction also applies when the other operand is Null.
The result has Variant type so a caller can handle Null with `IsNull` before
using it in a numeric condition or a native document write.

```vb
StrComp("ABCD", "abcd")                  ' -1
StrComp("report", "report", vbBinaryCompare) ' 0
StrComp("report2", "report")             ' 1
StrComp(Empty, "")                       ' 0
IsNull(StrComp(Null, "report"))           ' True
```

All supplied arguments evaluate exactly once in source order. A Null Compare
raises `vba_invalid_use_of_null`, even with Null text. Empty, String, Boolean,
fractional, locale/LCID, database and `vbUseCompareOption` modes are refused.
Named arguments, omitted interior arguments, `StrComp$`, qualification with
`VBA.`, and `Option Compare` remain unsupported. Arity and statically invalid
types are checked in unused procedures and inactive branches too.

The comparison stops at the first differing code unit. Each inspected pair
costs two units of the existing shared work budget before either unit is read;
long common prefixes and repeated comparisons cannot bypass that budget.
Empty/prefix results do not allocate a copied String. Unicode normalization,
locale collation and case folding are not performed. Isolated surrogate units
can be compared in source values, while the existing native text publication
guard still rejects malformed UTF-16 output.

The [Word comparison/color example](../packages/quds_office_engine/example/macros/word_comparison_colors.bas)
uses these results to select font colors and fill existing table cells. The
[versioned corpus](../packages/quds_office_engine/test/fixtures/vba_conformance/word_comparison_colors_v1.json)
and [local qualification record](validation/word-vba-comparison-colors-20261121/README.md)
separate tested dialect behavior from installed-Office observations. Microsoft
documents the result values and Null behavior in the
[StrComp reference](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/strcomp-function)
and [MS-VBAL StrComp contract](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/9541f02a-e173-47a7-8c0f-4d91813c1c88).
The explicit coercion restrictions and work accounting are Quds dialect limits;
no installed Microsoft Office differential run is claimed.

### Text construction and Unicode code units

The shared source layer supports `Space`, `Space$`, `String`, `String$`,
`ChrW`, `ChrW$`, and `AscW` in all three adapters. Arguments are positional,
evaluated once in source order, and must have the actual types below. Scalar
Variants carrying those types are accepted. Named/omitted arguments, implicit
coercion, and `Null`/`Empty` operands are refused; use the existing explicit
conversion functions when appropriate. Unsuffixed and `$` variants return the
same bounded String values here, without a VBA Variant subtype identity claim.

| Function | Bounded contract |
| --- | --- |
| `Space(count)` / `Space$(count)` | Produce exactly `count` U+0020 spaces. Zero produces an empty String. |
| `String(count, character)` / `String$(count, character)` | Repeat the first UTF-16 code unit of a nonempty actual String. The remaining units are ignored. Numeric character/code-page conversion is unsupported; use `ChrW` explicitly. |
| `ChrW(code)` / `ChrW$(code)` | Produce one UTF-16 code unit from an exact integer in `-32768..65535`. Negative inputs add 65536. |
| `AscW(text)` | Return the first UTF-16 code unit of a nonempty actual String as a signed integer in `-32768..32767`. |

Counts must be exact nonnegative signed-32-bit integers. Each result is limited
to 32,767 UTF-16 units, and construction charges every output unit against the
shared 100,000-work budget before allocating the result. `ChrW` and `AscW`
charge one unit. Zero-length repetition still validates its character argument.
Negative/fractional/out-of-Long counts are type errors; valid counts that exceed
the output/work bounds are `vba_limit_exceeded` errors.

```vb
Sub Main()
    Dim label As String
    label = String$(3, "-+") & Space(1) & ChrW(8364)
    Worksheets(1).Range("A1").Value2 = label
    Worksheets(1).Range("A2").Value2 = AscW(ChrW(32768))
    Worksheets(1).Range("A3").Value2 = ChrW(55357) & ChrW(56832)
End Sub
```

The outputs are `"--- €"`, `-32768`, and `"😀"`. Units are not Unicode scalars
or grapheme clusters: `String(2, "😀")` produces two high-surrogate units, which
may be inspected by source expressions but cannot be published as native text.
The existing native boundary refuses isolated surrogates and invalid XML
characters. Word insertion continues to permit tabs and refuse paragraph/line
breaks; `ChrW` does not bypass those structural rules.

The full signed lower bound is a deliberate Quds choice: the current MS-VBAL
ChrW page prints `-32767`, whereas AscW can return `-32768`. Accepting `-32768`
preserves the full 16-bit inverse `ChrW(AscW(text))` for its first unit. This
contract is specification-informed and independently tested; it has not been
differentially qualified against an installed Microsoft Office host.

See Microsoft's [Space](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/space-function),
[String](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/string-function),
[MS-VBAL ChrW](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/de4b7500-260f-41c5-b2fd-082eddd5f0b2),
and [MS-VBAL AscW](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/aab8e1d9-287d-4098-bf3a-14271eaa4b8e)
references. The [Word example](../packages/quds_office_engine/example/macros/word_text_construction.bas)
uses ordinary insertion/formatting operations with the existing atomic runtime.

## Variant states and explicit conversions

`Empty` and `Null` are distinct source scalar values. `Empty` is the default of
an unassigned Variant; `Null` represents intentionally missing data. Neither
is an unbound object, an empty String, zero, or `False`. A scalar Variant can
hold either state, and a `ByVal` Variant parameter or Variant function result
preserves it. `IsEmpty(value)` is true only for `Empty`; `IsNull(value)` is true
only for `Null`. All seven intrinsics below require exactly one scalar argument,
evaluated once, and their names cannot be shadowed.

```vb
Dim value As Variant
Worksheets(1).Range("A1").Value2 = IsEmpty(value) ' True
value = Null
If IsNull(value) Then
    Worksheets(1).Range("A2").Value2 = "Missing"
End If
value = "12.5"
Worksheets(1).Range("A3").Value2 = CLng(value)    ' 12: nearest even
```

### Defaults, assignment, and arrays

Fixed/newly allocated Variant array slots start as `Empty`. `ReDim Preserve`
keeps existing states and gives new slots `Empty`; fixed-array `Erase` resets
all slots to `Empty`. Dynamic-array `Erase` still releases allocation: indexing
or enumerating an erased dynamic array remains a subscript error. `For Each`
visits Empty and Null slots normally. Unassigned Variant functions return
`Empty`, including an early `Exit Function`.

Assigning `Empty` to `Long`, `Double`, `String`, or `Boolean` produces `0`,
`0.0`, `""`, or `False`, respectively. This applies to locals, array elements,
function-result assignments, and typed `ByVal` parameters. Assigning `Null`
to any of those typed scalars produces positioned `vba_invalid_use_of_null`.
A Variant assignment preserves either state. Object bindings still require
`Set` and an actual supported object. State literals in `Const` expressions
and fixed-array constant bounds remain explicitly unsupported in this slice.

### Explicit conversion signatures

| Signature | Supported behavior |
| --- | --- |
| `IsEmpty(value)` | Whether the evaluated scalar is `Empty` |
| `IsNull(value)` | Whether the evaluated scalar is `Null` |
| `CVar(value)` | Preserve a supported scalar, including either state; no objects or whole arrays |
| `CBool(value)` | Boolean identity; numeric zero is `False`, other numbers are `True`; `Empty` is `False`; accepted numeric Strings or case-insensitive `True`/`False` Strings |
| `CDbl(value)` | Supported numeric value as binary64; Boolean `True` becomes `-1`, `False` becomes `0`; `Empty` becomes `0`; accepted numeric String parsing |
| `CLng(value)` | The same numeric inputs as `CDbl`, rounded to nearest integer with ties to even, then checked against signed 32-bit bounds |
| `CStr(value)` | String identity; `True`/`False` text for Booleans; `""` for `Empty`; the invariant numeric format described below |

`CBool`, `CDbl`, `CLng`, and `CStr` reject `Null` with
`vba_invalid_use_of_null`. `IsEmpty(Null)` and `IsNull(Empty)` are both false.
Ordinary implicit String/number/Boolean conversion remains unsupported:
`Dim n As Long: n = "12"` fails, whereas `n = CLng("12")` succeeds.
Ordinary Long assignment still requires an exact integer; only explicit
`CLng` adds rounding. For example, `CLng(2.5) = 2`, `CLng(3.5) = 4`,
`CLng(-2.5) = -2`, and `CLng(-3.5) = -4`.

String numeric conversion is deliberately **locale independent**. It trims
only ASCII space and code units 9–13, then accepts an optional sign, ASCII
decimal digits with optional `.`, and an optional `e`/`E` exponent with sign.
At least one mantissa digit is required. Examples include `"  -12.5  "`,
`".25"`, `"12."`, and `"1.25e2"`. Empty Strings, grouping separators, decimal
commas, currencies, dates, hexadecimal/octal prefixes, type suffixes, non-ASCII
digits, `NaN`, and infinity text fail with `vba_type_error`. Finite binary64
results must stay within the dialect's existing absolute `2^53−1` bound;
exceeding it produces `vba_limit_exceeded`. Binary64 parsing can round decimal
text or underflow very small magnitudes to zero. This is not full VBA locale
or Decimal/Currency conversion.

Numeric `CStr` uses a deterministic invariant format for the stored binary64
value: integers have no `.0`, negative zero is `"0"`, and fractional values
use the fewest significant digits that round-trip. Magnitudes at least `1e-6`
use fixed notation; smaller nonzero magnitudes use lowercase `e`, with no plus
sign or padded exponent. Thus `CStr(CDbl("12.500")) = "12.5"` and
`CStr(CDbl("1E-7")) = "1e-7"`. It does not preserve the input's decimal spelling
or reproduce an Office locale's formatting. Existing `&` numeric text behavior
is unchanged; use explicit `CStr` for this canonical representation.

### Operators, conditions, and missing values

Within the existing numeric arithmetic domain, `Empty` acts as zero and
`Null` propagates through unary `+`/`-` and binary `+`, `-`, `*`, `/`.
Non-Null operands must still satisfy the numeric contract; Null cannot hide
unsupported String/Boolean arithmetic. Both expressions are evaluated before
validation or propagation, so a failing helper or `1/0` expression still fails.
String addition and broader implicit arithmetic coercion remain unsupported.

Nullable operator results remain compositional: nesting an expression directly
and passing the same result through a Variant temporary have the same supported
semantics. Known incompatible non-state operands still fail static checks, even
in unused code. Scalar Variants cannot satisfy Worksheet/Range bindings or
parameters, including in unexecuted branches.

All six comparisons return `Null` if either scalar is Null, including
`Null = Null` and `Null <> Null`. Use `IsNull` to inspect the state. Empty
compares as `0` against numbers, `False` against Booleans, or `""` against
Strings; two Empty values compare equal. Other scalar types must still match.

For `&`, Empty contributes `""`. One Null operand also contributes `""`,
but `Null & Null` returns Null. This exception is deliberate.

| Left | Right | `And` | `Or` | `Xor` |
| --- | --- | --- | --- | --- |
| `True` | `Null` | `Null` | `True` | `Null` |
| `False` | `Null` | `False` | `Null` | `Null` |
| `Null` | `True` | `Null` | `True` | `Null` |
| `Null` | `False` | `False` | `Null` | `Null` |
| `Null` | `Null` | `Null` | `Null` | `Null` |

`Not Null` returns Null. Logical operands are eager and restricted to actual
Booleans or Null. Numeric and Empty bitwise forms remain unsupported; write
`Not CBool(Empty)` when Boolean intent is wanted. Full VBA's numeric effective
types for Empty logical operations are not approximated.

In `If`, `Do`, and `While` conditions, Empty and Null are false. Numeric/String
truthiness is still unsupported. This condition rule does not turn typed
Boolean assignment or `CBool(Null)` into a successful conversion. A Null
comparison never matches a `Select Case` clause; range endpoints remain eager.

### Native publication and resource limits

`.Value` and `.Value2 = Empty` emit `xlsx.cellValue` with native JSON null,
clearing both a value and a formula while retaining formatting. `.Value` or
`.Value2 = Null` fails before any native plan is returned. Internal state
objects never appear in native JSON. This is an explicit dialect boundary;
no new installed Excel-host observation is claimed.

Worksheet/range selectors, indices, formatting inputs, RGB and String
intrinsics retain their strict actual-type rules. State values in those
positions produce the existing type diagnostics; convert explicitly where
appropriate. All emitted text still requires well-formed UTF-16. Conversion
work shares the existing 100,000-work limit and never increases the String,
array, operation or encoded-plan bounds.

The runnable [Variant report](../packages/quds_office_engine/example/macros/variant_report.bas)
processes four synthetic records, distinguishing missing from unassigned
amounts. It uses all seven new intrinsics, emits **38 native operations**, clears
four output cells, calculates matching source and worksheet totals of
**375.75**, and demonstrates ties-to-even rounding and reallocated Empty slots.
Its workbook must contain a sheet named `Summary`:

```bash
dart run tool/macros/office_macro.dart compile-vba \
  example/macros/variant_report.bas variant-report.qudsmacro.json
dart run tool/macros/office_macro.dart run-vba \
  input.xlsx example/macros/variant_report.bas output.xlsx
```

## Supported language constructs

| Construct | Supported behavior and restrictions |
| --- | --- |
| Module structure | Optional `Attribute VB_Name = "..."`, `Option Explicit`, `Option Base 0/1`, module constants, `Sub` helpers, and scalar `Function` procedures with optional `Public`/`Private` |
| Entry selection | Case-insensitive selection of a parameterless `Sub` by `entryPoint`; every procedure is checked, and the selected entry plus its invoked helpers are evaluated |
| Procedure arguments | Up to 16 explicit `ByVal` parameters; named/positional helper calls, required supported scalar or object types, optional scalar defaults and comma omissions |
| Omitted Variant parameters | `IsMissing` on a direct optional Variant formal; unhandled omitted values refuse publication and ordinary reads |
| Calls and returns | In-module procedure calls, scalar functions in expressions, return assignment through the function name, and discarded function results in statement calls |
| Early exits | `Exit Sub`, `Exit Function`, innermost `Exit For`, and innermost `Exit Do`, checked against the containing procedure or matching loop kind |
| Declarations | `Dim` and `Const`, including comma-separated declarations; declarations must precede executable statements and remain outside control-flow blocks |
| Fixed local arrays | One dimension of supported scalar elements, constant inclusive bounds, integer indexed reads/writes, `LBound`/`UBound` |
| Dynamic local arrays | `Dim name()`, `ReDim` with source-expression bounds, upper-bound-only `ReDim Preserve`, and the same element/index/bound intrinsics |
| Array lifecycle | `Erase` resets fixed arrays and deallocates dynamic arrays; active `For Each` collections cannot be resized or erased |
| Collection loops | `For Each` over a local array with a `Variant` control variable, or an explicit rectangular range with a `Range` control variable |
| Scalar types | `Long`, `Double`, `String`, `Boolean`, and scalar `Variant`; omitted `As` means `Variant`, whose default is `Empty` |
| Variant states and conversions | `Empty`, `Null`, `IsEmpty`, `IsNull`, `CVar`, `CBool`, `CDbl`, `CLng`, and `CStr`; bounded explicit conversion rules below |
| Object types | `Worksheet` and `Range` variables, assigned with `Set`; object default members are unsupported |
| Constants | Literals, supported unary/binary expressions, and previously declared constants; function calls in constant initializers are unsupported |
| Assignment | Scalar assignment, optional `Let`, and explicitly supported writable object properties |
| Arithmetic | Decimal/exponent literals, parentheses, unary `+`/`-`, and binary `+`, `-`, `*`, `/` |
| Numeric intrinsics | `Abs`, `Int`, `Fix`, `Sgn`; one positional numeric/Variant argument, explicit Empty/Null behavior and bounded portable arithmetic |
| Text | Double-quoted literals with doubled embedded quotes and `&` concatenation of scalar values |
| String intrinsics | `Len`, `Left$`, `Right$`, `Mid$`, binary `InStr` / `InStrRev` / `Replace`, and Trim/LTrim/RTrim with their `$` forms; actual Strings, UTF-16 units, bounded exact integer arguments, no implicit coercion |
| String comparison | Binary `StrComp(left, right[, compare])`, exact `-1`/`0`/`1` results, explicit Empty/Null behavior, strict types and metered UTF-16 comparison |
| Comparisons | `=`, `<>`, `<`, `>`, `<=`, `>=` between matching scalar types, contextual `Empty`, or propagating `Null`; strings use binary ordering |
| Boolean logic | `Not`, `And`, `Or`, `Xor` on Boolean/Null values; operands are evaluated eagerly; numeric/Empty bitwise forms are unsupported |
| Conditions | Block `If … Then`, `ElseIf`, `Else`, `End If`; actual Booleans or false `Empty`/`Null`, known from source |
| Selection | `Select Case` with scalar alternatives, inclusive numeric/string `To` ranges, `[Is]` comparisons, and an optional final `Case Else`; first match wins |
| Counted loops | Integer `For … To … [Step …]` and `Next [counter]`; bounds are inclusive, default step is `1`, negative steps are supported |
| Conditional loops | `Do`/`Loop` with an optional `While` or `Until` condition at either end, and `While … Wend`; Boolean/Empty/Null conditions and budgeted evaluation |
| Object context | Nested `With` blocks for worksheets or ranges; leading `.` refers to the innermost context |
| Source formatting | Apostrophe/`Rem` comments, colon statement separators, whitespace-underscore line continuation, CRLF/LF, and an optional UTF-8 BOM |

Typed variables start at `0`, `0.0`, `""`, or `False`; scalar Variants start as
`Empty`. An unbound `Worksheet` or `Range` cannot be read; bind it with `Set`
first. With `Option Explicit`, undeclared variables are errors. Without it,
assignment targets and loop counters can introduce scalar Variant variables,
but an undeclared read still fails. Multidimensional arrays and `Nothing` are
not implemented.

Assignments and operations use strict types. Arithmetic uses finite binary64
intermediates within the portable numeric bound; integral results are normalized
back to exact integers. This dialect does not emulate every VBA intermediate
numeric subtype overflow rule. `Long` bounds are enforced at assignment and
loop-counter increment. There is no implicit conversion
between ordinary strings, numbers, and Booleans, no implicit fractional-to-
integer rounding, and no Date/Currency behavior. Explicit conversion functions
and the documented `Empty`/`Null` rules are separate. `&` deliberately supports scalar-to-text conversion;
numeric text uses invariant Dart formatting and Boolean text is `True`/`False`.
Cell strings remain strings rather than using Excel's locale/format-driven
type guessing. Strings beginning with `=` require an explicit `.Formula`
assignment; formulas must begin with `=` and contain an expression. These
restrictions also apply to the scalar `.Value` alias.

`Long` assignment and increment must fit signed 32-bit bounds. `For` start,
end, and step must also fit signed 32-bit bounds; the counter must be `Long`
or scalar `Variant`. Start/end/step expressions are evaluated once on entry.
`Step 0`, reassignment of an active loop counter, and reuse of that counter
in a nested loop are rejected. The counter retains its post-loop value.

RGB components must be nonnegative integers; values above 255 clamp to 255,
matching the documented `RGB` behavior. Explicit integer colors use VBA's
red/green/blue byte ordering and are converted to the engine's six-digit RGB
hex representation. System colors and palettes are unsupported.

The compiler rejects other function calls, `ByRef`, recursion, arbitrary
collection enumeration, other exit kinds, `GoTo`, error handlers, conditional compilation,
file/network operations, `Shell`, `CreateObject`, `Application.Run`, and
document-value reads. Unsupported syntax,
unknown names, and unsupported object shapes are checked in inactive branches
and unselected procedures too, including statements after an early exit.
Value-dependent errors are detected when the selected entry and its helpers
are evaluated.

## Compilation limits

The compiler has its own limits before the native runtime receives a plan:

| Limit | Maximum |
| --- | ---: |
| Source UTF-8 bytes | 1 MiB |
| Lexer tokens | 50,000 |
| Statements across procedures, including `Case`/`Case Else` clauses | 10,000 |
| Block nesting | 32 |
| Expression nesting / AST depth | 64 |
| Visible variables per procedure, including constants, parameters, and function return slot | 256 |
| Array elements per fixed or dynamic local array | 4,096 |
| Array slots across active procedure frames | 16,384 |
| String code units stored across active array slots | 1,048,576 |
| Parameters / arguments per procedure call | 16 |
| Procedure frames, including the selected entry | 32 |
| String literal / concatenation / intrinsic result length | 32,767 UTF-16 code units |
| Absolute numeric magnitude | 9,007,199,254,740,991 (`2^53 − 1`) |
| Evaluation/statement visits, array work, substring copies and explicit conversion work | 100,000 |
| Emitted native operations | 10,000 |
| Encoded native plan | 1 MiB |

The numeric bound applies to literals and intermediate results across Dart VM
and JavaScript. Arithmetic must remain finite. The compiler refuses work before
expanding a range that exceeds the remaining operation budget. Each emitted
operation is charged against the aggregate encoded byte budget, and compilation
work is charged even for loops with empty bodies. Strings are bounded before
concatenation allocates a larger result. Substring copies charge their clamped
result length before allocating, even when their result is subsequently discarded.
Explicit conversions charge String input scans/copies before parsing or case
folding. Numeric `CStr` formatting charges each bounded precision candidate
and its result; repeated conversions cannot reset the work budget.

Conditional loops and `Select Case` do not increase these limits. Every loop
attempt and Case alternative consumes work in addition to its expressions and
body statements. All new blocks count toward the same nesting limit, and each
Case clause counts toward the aggregate statement limit even when its body is
empty or never selected.

Procedure calls share the same aggregate work, operation, and encoded-output
budgets. The per-string limit remains in effect inside every helper. Invoking
an empty helper still consumes work. No budget is reset at a procedure
boundary. Call-graph depth is checked before evaluation, and active frames are
also bounded during evaluation.

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
- [Fixed array declarations and default bounds](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/dim-statement)
- [ReDim allocation and Preserve](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/redim-statement)
- [MS-VBAL ReDim semantics](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/22b5d372-0a54-4617-9462-4934b5edc88c)
- [Erase for fixed and dynamic arrays](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/erase-statement)
- [Option Base](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/option-base-statement)
- [Temporarily locked arrays](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/this-array-is-fixed-or-temporarily-locked-error-10)
- [For Each…Next and control-variable types](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/for-eachnext-statement)
- [LBound](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/lbound-function) and [UBound](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/ubound-function)
- [Range.Row](https://learn.microsoft.com/en-us/office/vba/api/excel.range.row) and [Range.Column](https://learn.microsoft.com/en-us/office/vba/api/excel.range.column)
- [For…Next](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/fornext-statement)
- [Do…Loop](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/doloop-statement)
- [While…Wend](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/whilewend-statement)
- [Select Case syntax and ranges](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/select-case-statement)
- [MS-VBAL Select Case evaluation order](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/94a2f0fe-bdbe-4f5d-b3f4-bbf339b0ac65)
- [RGB color values](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/rgb-function)
- [Abs](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/abs-function), [Int/Fix](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/int-fix-functions), and [Sgn](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/sgn-function)
- [Len, including typed-variable storage semantics](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/len-function)
- [Left](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/left-function), [Right](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/right-function), and [Mid](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/mid-function)
- [MS-VBAL Left$](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/5f10a9e1-b6ba-4a92-bd94-c4c99da74ef2)
- [MS-VBAL numeric Let-coercion](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/56fb78c3-a0ea-4bf0-8ee4-eb5f89bda4f7)
- [MS-VBAL value types and nominal String representation](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/c86480b2-aef2-4488-b177-f55e13cc51f2)
- [Variant values and Empty/Null](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/variant-data-type)
- [IsEmpty](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/isempty-function) and [IsNull](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/isnull-function)
- [Explicit type conversions and ties-to-even rounding](https://learn.microsoft.com/en-us/office/vba/language/concepts/getting-started/type-conversion-functions)
- [MS-VBAL Empty assignment](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/e2637723-3010-449d-bead-9f17533dc105)
- [Null/Empty concatenation](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/ampersand-operator)
- [Boolean and Null logic](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/and-operator)
- [MS-VBAL logical effective types](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/2d70780d-6e99-47d6-9759-2b3a46b8e862)
- [Operator precedence](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/operator-precedence)
- [Sub declarations and ByVal/ByRef defaults](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/sub-statement)
- [Function declarations and return values](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/function-statement)
- [Call syntax and discarded function results](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/call-statement)
- [Exit Sub, Exit Function, Exit For, and Exit Do](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/exit-statement)

This is a bounded source-to-plan implementation. It does not claim native Excel
interoperability for arbitrary VBA modules or parity with the full Excel object
model. See [the macro guide](MACROS.md) for document admission, serialization,
formula compatibility, and host-policy boundaries.
