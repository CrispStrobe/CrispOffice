# Portability attempt at 47ce5f72 — retained, not accepted

Frozen source: `47ce5f726f1a0b1f213b926162528533dc0a3aab`.
Tree: `97cad8c95409bee4af74b57c8e0e90cd4fc43585`.

The complete native/VM plan passed **1,326 cases in 68 suites**, with no
failures or skips. Strict analysis of 35 Dart paths, formatting and whitespace
passed. Source and runtime before/after bindings passed.

The eight-suite Node repeat executed 570 cases: **569 passed, one failed,
none skipped**. The original morphology decoder assertion requires `-99.0`
for an integral numeric feature. On JavaScript, `toDouble().toString()`
produces `-99`. This is a product portability defect, not a test expectation
change. The corrected implementation restores the decimal suffix for finite
plain-integer text, retaining fractions, exponents, negative zero and strings.
The existing assertion remains unchanged; an added regression covers each
numeric representation.

The independent auditor reconstructs **1,896 executions: 1,895 passes and
one failure**, representing 1,326 distinct case identities in 68 suite paths.
It correctly rejects the combined qualification. All 5,164 source records
remain stable; the native phase binds 11,165 runtime entries and the Node
phase binds 11,162.

The indexed archive preserves the original raw reporter streams, failures,
case records, receipts, command output, source/runtime inventories and
independent audit. None of these executions is added to final accepted counts.
