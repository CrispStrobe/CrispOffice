# VBA macros — overview

Quds Office compiles an explicitly selected `.bas` module into an immutable
native operation plan. Compiled source does not execute embedded VBA projects,
launch Microsoft Office or expose the complete VBA object model.

This page is the index. The full shared-language reference is preserved in
[VBA language details](vba-macros-details.md).

## Dialects

| Dialect | Document family | Adapter |
| --- | --- | --- |
| `vba-excel` | XLSX / XLSM / XLTX | `OfficeVbaMacroLanguage` |
| `vba-word` | DOCX / DOCM / DOTX | `OfficeVbaWordMacroLanguage` |
| `vba-powerpoint` | PPTX | PowerPoint adapter |

Each dialect exposes only its own document members. Excel members are
unavailable in a Word macro and vice versa. Handwritten JSON plans, recorded
plans and compiled source share the same permission, admission, cancellation,
transaction and publication rules.

## Run a source file

From `packages/quds_office_engine`:

```bash
# Inspect the generated plan without changing a document.
dart run tool/macros/office_macro.dart compile-vba \
  example/macros/monthly_totals.bas monthly.qudsmacro.json

# Execute against a detached workbook; nothing is published.
dart run tool/macros/office_macro.dart validate-vba \
  input.xlsx example/macros/monthly_totals.bas

# Publish only after every step succeeds.
dart run tool/macros/office_macro.dart run-vba \
  input.xlsx example/macros/monthly_totals.bas output.xlsx
```

The optional final argument selects a parameterless `Sub`; the default is
`Main`. Input and output must keep the same extension. A failure leaves an
existing output untouched.

## Minimal Excel module

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

Source expressions are evaluated during compilation. Worksheet formulas remain
formulas and are calculated by the spreadsheet engine when the native plan
runs.

## Shared language

The supported subset includes:

- local `Sub` and scalar `Function` helpers;
- `If`, `Select Case`, `Do`, `While`, `For` and `For Each`;
- fixed and dynamic one-dimensional arrays, `ReDim`, `Erase`, `Option Base`;
- `Variant` states including `Empty`, `Null` and `IsMissing`;
- numeric and string intrinsics;
- strict argument types, named arguments and optional scalar `ByVal` values;
- bounded compilation and execution budgets.

Unsupported constructs fail with a diagnostic. The compiler never silently
drops a statement or applies a best-effort rewrite.

## Source and safety

- Source files are UTF-8 and limited to 1 MiB.
- Embedded VBA projects are preserved as opaque bytes and never loaded.
- Macros cannot open/read another document, discover a focused application or
  bypass document admission.
- Execution publishes saved bytes only after the complete plan succeeds.
- Permissions, tool allowlists, step limits and cancellation are shared with
  native JSON macros.
- There is no forms, events, COM or arbitrary VBA compatibility layer.

## Reference

- [Shared language and Excel reference](vba-macros-details.md)
- [Word dialect](VBA_WORD_MACROS.md)
- [PowerPoint dialect](VBA_POWERPOINT_MACROS.md)
- [Argument contract](VBA_ARGUMENTS.md)
- [Conformance](VBA_CONFORMANCE.md)
- [Parity roadmap](VBA_PARITY_ROADMAP.md)

## Limits

The dialects are deliberately bounded. Source that depends on unimplemented
members, runtime type discovery, user forms, events or COM is refused. A
successful local compile or plan does not claim compatibility with every macro
that Microsoft Office accepts.
