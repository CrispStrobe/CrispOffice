# VBA compatibility roadmap

The long-term target is Microsoft Office VBA compatibility across Word, Excel,
and PowerPoint. Compatibility is measured separately for the language, each
application's object model, document/package fidelity, and the host experience.
Passing one layer does not establish parity in the others.

## Current baseline

As of 20 November 2026, native JSON macros and the shared operation catalog
cover all three document families. The `vba-excel` source compiler supports a
bounded, document-independent subset: scalar expressions, typed locals,
explicit worksheet/range bindings, reusable `ByVal` procedures and scalar
functions, conditions, loops, fixed and dynamic one-dimensional arrays, `ReDim`/`Preserve`,
`Erase`, module `Option Base`, `For Each`, and the bounded String intrinsics
`Len`, `Left$`, `Right$`, and `Mid$`.
It generates an immutable native plan; runtime policy, detached validation,
and atomic publication apply after compilation. Embedded VBA projects are
preserved as opaque package parts and are never executed on document open.

Word and PowerPoint native operations are **not** VBA object-model adapters.
There is no live document-value evaluation, VBA project loader, editor-host
macro UI, or general VBA runtime. See [the exact current dialect](VBA_MACROS.md)
and [the native macro contract](MACROS.md).

## Ordered milestones and acceptance

| Stage | Concrete deliverable | Acceptance required before claiming support |
| --- | --- | --- |
| 1. Source-data array lifecycle | Local dynamic arrays, `ReDim`, `Preserve`, `Erase`, `Option Base`; reuse fixed-array indexing and iteration | Typed defaults, preserve/shrink/regrow semantics, unallocated diagnostics, enumeration locks, shared resource budgets, CLI/MCP transaction tests, VM/JavaScript agreement |
| 2. Shared language semantics | String/numeric intrinsics, explicit Variant states and coercion rules, optional/named arguments, multidimensional arrays and array parameters | A versioned feature matrix tied to Microsoft language documentation; positive and refusal cases; differential fixtures from a real Office host for behavior claimed as compatible |
| 3. Document-aware execution | Separate a checked program from execution; resolve reads/writes against one detached transaction | Read-after-write and data-dependent branches, cancellation, instruction/resource limits, stale-document checks, whole-run rollback; no partial publication on error |
| 4. Application adapters | Excel workbook/sheet/range reads and collections; Word documents/stories/ranges/paragraphs/tables; PowerPoint presentations/slides/shapes/text ranges | One-based selectors, default members, collection order, object identity, explicit active-document context, precise range offsets/units, correct native serialization, format-specific conformance fixtures |
| 5. Procedures and projects | `ByRef`, modules/classes, properties, scoped globals, error handling, events and project references | Binding and aliasing tests, recursion/call budgets, error propagation, lifecycle tests, multi-module compatibility corpus; controlled host entry points |
| 6. Project interchange and authoring | Read/write project streams, explicit import/export, source editor, diagnostics, debugging and macro recording | Round-trip preservation, module/source provenance, source maps, breakpoints, consistent undo/history integration; successful Office open/edit/save checks |
| 7. Host integration and qualification | Common Office workflows and explicit platform integrations | Real Word/Excel/PowerPoint differential runs, version/platform matrix, supported workflow corpus and documented residual gaps; external automation stays subject to host capability grants |

Stage 1 was delivered in the prior array-lifecycle increment. Its source, CLI/MCP transaction and
VM/JavaScript checks are recorded in the
[local validation record](validation/office-vba-dynamic-arrays-20261119/README.md).
This establishes the documented bounded dialect, not differential qualification
against an installed Microsoft Office host. Stage 2 now has its first bounded
slice: a [versioned conformance format](VBA_CONFORMANCE.md) and these four
String intrinsics, with explicit type restrictions, UTF-16 units, copy-work
accounting, transactional integration, and VM/JavaScript agreement. Remaining
Stage 2 semantics and Stages 3–7 remain planned work.
Small tested adapter slices may run alongside shared language work when their
prerequisites exist.

### Next increment

Add explicit Variant `Empty`/`Null` states and conversion rules before
claiming default Variant behavior or accepting broader array/value coercion.
Use the delivered versioned conformance format to distinguish specification
expectations from intentional dialect restrictions. Record actual Office
host/version/platform provenance separately when differential fixtures become
available; the delivered corpus does not claim Office host qualification.
Keep multidimensional arrays and array parameter passing as separate increments
with their own shape, ownership, aliasing and resource tests. Stage 3 is the
architectural prerequisite for macros that branch on existing workbook data;
additional source-only syntax does not supply that capability.

## Architecture decisions

- Keep a single shared language parser, binder, diagnostics model and resource
  accounting. Host object models supply typed members and native operations;
  avoid three independent language implementations.
- Preserve the existing source-to-plan API for static macros. Document-aware
  programs need a distinct execution representation: extending the static
  compiler with live reads would erase its current no-document-access contract.
- Model VBA behavior explicitly. Refuse an unsupported construct with its
  source position rather than silently borrowing Dart behavior. Numeric
  subtypes, `Empty`/`Null`/`Nothing`, locale rules and Unicode indexing need
  their own compatibility fixtures.
- Treat Word ranges and PowerPoint text as application-specific objects.
  A Word paragraph range includes a paragraph mark; mapping it blindly to a
  plain-text replacement can change document structure. Rich-text formatting,
  table cells, stories and slide shape collections need explicit contracts.
- Continue to use the shared native operation catalog and detached publication
  boundary for every adapter. Macro syntax cannot grant itself filesystem,
  network, shell, COM or application-event access.

## Working protocol

Begin each increment by refreshing remote main, current branches and recent
PR heads. Classify each head as contained, equivalent with recorded evidence,
or needing integration. Preserve newer independent work and real Git ancestry.
Save small remote branch checkpoints with expected-head, non-forced updates.
Run targeted local gates and record actual commands/results and the source
they cover. GitHub Actions are not a gate for this work. Refresh main again
before the final merge and rerun checks affected by any concurrent source.

Do not report a percentage of VBA parity from test counts or operation counts.
Report supported features, tested hosts and explicit missing behavior instead.

## Primary references

- [Microsoft VBA language specification (MS-VBAL)](https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/)
- [ReDim statement](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/redim-statement)
- [Erase statement](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/erase-statement)
- [Option Base statement](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/option-base-statement)
