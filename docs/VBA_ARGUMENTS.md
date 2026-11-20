# Named arguments and optional helper parameters

The `vba-excel`, `vba-word`, and `vba-powerpoint` source adapters share support
for named calls to module helpers, optional scalar `ByVal` parameters, and a
bounded `IsMissing` predicate. These are source-language features: helpers
still compile into the existing immutable native plan and use the normal
validation, permission, cancellation, and atomic publication boundary.

## Calling a helper by name

Arguments can be supplied by position or by their case-insensitive parameter
name. Named arguments use `name:=expression` and may appear in a different
order from the declarations. Any positional arguments must precede all named
arguments.

```vb
Sub Main()
    Call Style(target:=ActiveDocument.Paragraphs(1).Range, size:=18)
    Style ActiveDocument.Paragraphs(2).Range, bold:=True
End Sub

Sub Style(ByVal target As Range, _
    Optional ByVal bold As Boolean = False, _
    Optional ByVal size As Double = 12)
    target.Font.Bold = bold
    target.Font.Size = size
End Sub
```

The first call binds `target` and `size` by name and uses `False` for `bold`.
The second binds the required target by position, supplies `bold` by name, and
uses the declared size default. Required object parameters retain their
existing explicit target identity; optional object parameters are outside this
increment.

The existing call syntax remains in effect:

| Context | Supported forms |
| --- | --- |
| Sub or discarded Function result | `Call Helper(...)` or `Helper arg1, arg2` |
| Function result in an expression | `Helper(...)` |
| Call with all optional arguments omitted | `Helper`, `Helper()`, or `Call Helper()` |
| Optional position skipped before a later argument | `Call Helper(target, , 18)` or `Helper target, , 18` |
| Optional trailing position skipped | Omit it, or use its empty position: `Helper(target,)` in a Function expression |

A comma hole occupies its declared position. Named arguments do not need holes
for parameters they skip. Positional values or holes after a named argument
are rejected, as are unknown names, duplicates, a positional and named value
for the same parameter, and omissions of required parameters. Names are
checked even in unused helpers and unreachable branches.

Argument expressions run exactly once in their written order, in the caller's
scope and `With` context. They are then assigned to their checked parameter
positions. For example, `Pair(second:=Mark(2), first:=Mark(1))` evaluates
`Mark(2)` before `Mark(1)`. If those functions emit native operations, the
operations retain that order. The callee receives a new local frame only after
the supplied expressions have been evaluated.

The named-argument syntax applies to declared module helpers in this release.
It does not add named arguments to `RGB`, the String or Variant intrinsics,
array subscripts, or application members such as `Paragraphs`, `Shapes`,
`Range`, or `InsertBefore`.

## Declaring optional parameters

Every parameter still requires an explicit `ByVal`. Both `Optional ByVal` and
`ByVal Optional` are accepted; all parameters following the first optional
parameter must also be optional. The selected entry point remains a
parameterless `Sub`, even if every parameter of another Sub has a default.

Supported optional types are `Long`, `Double`, `String`, `Boolean`, and scalar
`Variant`. Omitting `As` means `Variant`, as in existing declarations.

| Declaration | Value when omitted |
| --- | --- |
| `Optional ByVal count As Long = 3` | The checked `Long` value 3 |
| `Optional ByVal size As Double` | `0.0` |
| `Optional ByVal count As Long` | `0` |
| `Optional ByVal text As String` | `""` |
| `Optional ByVal enabled As Boolean` | `False` |
| `Optional ByVal item As Variant = "default"` | The String value `"default"`; `IsMissing(item)` is false |
| `Optional ByVal item As Variant` | A distinguished omitted value; `IsMissing(item)` is true |

An explicit default is a declaration-time constant expression. It can use
supported numeric, String, and Boolean literals; previously declared module
constants; the current adapter's supported numeric constants; and the existing
pure constant operators. Defaults cannot call helpers or intrinsics, read
document values, access objects, or refer to parameters or local variables.
They are checked and evaluated even when the helper is never called. A bad
default therefore cannot hide in an unused procedure.

The bounded constant contract continues to exclude `Empty`, `Null`, and
`Nothing` as explicit default expressions. `Empty` and `Null` remain valid
explicit scalar arguments. For example, supplying `Empty` to an optional
`Long` with default 8 performs the existing typed conversion to zero; it does
not select the default 8. Supplying `Null` to a typed scalar retains the
existing invalid-Null diagnostic.

Defaults are evaluated in module scope once. Each invocation receives its own
parameter slots; assigning a new value inside one call changes neither the
caller's variable nor the next invocation's default.

## Handling an omitted Variant

An omitted optional Variant has its own private source value. It is distinct
from explicit `Empty`, explicit `Null`, a typed zero, an empty String, and an
uninitialized object. It cannot be encoded into a native macro plan.

```vb
Sub AddCaption(ByVal target As Range, Optional ByVal caption As Variant)
    If IsMissing(caption) Then
        caption = "Untitled"
    End If
    target.InsertBefore CStr(caption)
End Sub
```

`IsMissing` accepts a direct optional Variant parameter of the current helper.
It returns true only while that parameter retains the omitted value. Supplying
`Empty` or `Null`, specifying an explicit default, or assigning a concrete
value inside the helper makes the predicate false.

This release deliberately bounds Missing handling to that predicate and local
assignment. Reading an unhandled omitted value produces
`vba_missing_argument`. This includes passing it to another helper, returning
it, calling `IsEmpty` or `IsNull` on it, converting it, comparing it, using it
as a condition, or publishing it. Test `IsMissing` and assign or select a
concrete value before those uses. This is a dialect restriction, not a claim
to implement VBA's general Variant Error propagation or error code 448.

`IsMissing` on a literal, expression, ordinary local, required parameter, or
typed optional parameter is also outside this bounded slice and is rejected
statically. Existing `IsEmpty` and `IsNull` behavior on supplied values remains
unchanged.

## Limits and diagnostics

The existing limit of 16 declared parameters and 16 supplied argument positions
continues to apply. Optional parameters count toward the declaration limit;
named values and comma holes count toward the supplied-position limit.
Argument binding, omitted positions, default evaluation, and callee setup use
the shared compilation work budget. Reusing a default String charges its code
unit length on each omitted invocation, so repeated large defaults cannot
evade the copy-work bound. Defaults retain the same String length, finite
numeric, exact integer, and signed `Long` checks as ordinary source values.

| Failure | Diagnostic |
| --- | --- |
| Unknown named parameter | `vba_name_error`, at the argument name |
| Duplicate binding, missing required parameter, positional value after a named value, or incompatible type | `vba_type_error` |
| Required parameter after an optional one, duplicate Optional modifier, or default on a required parameter | `vba_syntax_error` |
| ByRef, implicit passing mode, array parameters, ParamArray, optional object parameters, unsupported defaults, or unsupported IsMissing target | `vba_unsupported` |
| Reading an unhandled omitted Variant | `vba_missing_argument` |
| Parameter, expression, String, aggregate work, operation, or output limit | `vba_limit_exceeded` |

The native plan still has no document reads, ambient application lookup,
COM, events, project loading, or automatic execution of embedded VBA.

## Runnable examples and regression coverage

The [Word helper example](../packages/quds_office_engine/example/macros/word_optional_helpers.bas)
expects three existing main-story paragraphs. It emits seven operations,
including a caption prefix, named formatting, an omitted Boolean, and an
explicit `Empty` Variant argument.

The [PowerPoint helper example](../packages/quds_office_engine/example/macros/powerpoint_optional_helpers.bas)
expects two slides, each with a text shape named `Title`. It emits five
operations, replacing the first title while using `IsMissing` to retain the
second title's existing text.

From `packages/quds_office_engine`:

```bash
dart run tool/macros/office_macro.dart run-word-vba \
  input.docx example/macros/word_optional_helpers.bas output.docx
dart run tool/macros/office_macro.dart run-powerpoint-vba \
  input.pptx example/macros/powerpoint_optional_helpers.bas output.pptx
```

The [compiler semantic tests](../packages/quds_office_engine/test/office_vba_arguments_test.dart)
cover calls, defaults, ordering, omissions, Missing states, refusal diagnostics,
and shared budgets. The [integration tests](../packages/quds_office_engine/test/office_vba_arguments_integration_test.dart)
exercise real Word, PowerPoint, and Excel transactions, failure rollback,
recording, permissions, CLI execution, and MCP compilation. The
[portable driver](../packages/quds_office_engine/tool/macros/web_vba_arguments_smoke.dart)
accepts the exact committed example bytes through base64 compile-time defines,
checks both native results after two additional save/reopen cycles, and emits
deterministic semantic JSON for VM/JavaScript comparison.

## Primary references and qualification boundary

The syntax and type-default rules are based on Microsoft's
[MS-VBAL Parameter Lists](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/78bcb344-4966-4401-bb55-72729790ebee),
[named and optional argument guide](https://learn.microsoft.com/en-us/office/vba/language/concepts/getting-started/understanding-named-arguments-and-optional-arguments),
and [IsMissing reference](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/ismissing-function).
The separate Missing domain is described in
[MS-VBAL Data Values and Value Types](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/c86480b2-aef2-4488-b177-f55e13cc51f2).

These references motivate independently authored semantic expectations. Local
engine tests and VM/JavaScript agreement qualify the documented bounded
dialect. They are not differential results from installed Microsoft Word,
PowerPoint, or Excel hosts; full Optional/Variant Error compatibility remains
a separate qualification task.
