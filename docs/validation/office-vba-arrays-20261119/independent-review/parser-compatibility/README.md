# Preserve existing parenthesized bare-call arguments

The initial array implementation passed its 612-test frozen acceptance run.
Subsequent code review found a missing compatibility case in the new indexed
assignment lookahead:

```vb
Sub Main()
    Helper (1) = 2
End Sub

Sub Helper(ByVal flag As Boolean)
    Worksheets(1).Range("A1").Value2 = flag
End Sub
```

The existing dialect interprets this statement as a bare call whose single
argument is the comparison `(1) = 2`. It emits a write of `False` to `A1`.
The initial array implementation incorrectly interpreted the same tokens as
assignment to an array named `Helper`, then rejected the unknown variable.

## Reproduced before correction

The committed compiler at `cf59efa99232a3fd26cf21ce7f2382402e576f9b`
emits the expected Boolean write. The array implementation at
`ac9de9e000274718145659da0abc7c8cadb9e8c3` emits a structured
`vba_name_error`. Both were run in one isolated Dart process using their exact
Git blobs. Their three relative imports were rewritten to package URIs so
they share dependency type identities; the receipts retain both original and
loaded hashes. No implementation statements were rewritten.

See [before stdout](before-stdout.log), [before receipt](before-receipt.json),
and the reproducible [comparator](reproduce.py). An earlier exploratory harness
using file URI imports failed to compile because package and file URI imports
created distinct type identities; it produced no compiler behavior result and
was replaced with the package URI comparator recorded here.

## Correction and verification

The parser now records fixed array declarations within the current procedure
and clears that set before parsing the next procedure. It uses the indexed
assignment lookahead only for those array names. Other identifiers retain the
existing bare-call grammar, including forward-declared helpers. Explicit
`Let` assignments still take their existing assignment path.

Two new core regressions verify the original Boolean call syntax and array
assignment with nested parenthesized subscripts. The targeted core suite has
32 passing tests; its [JSON reporter output](core-after.jsonl) is retained.
The corrected committed compiler is
`c3eaf57c85d363b1453f2a3407ba62768b0e2c08`; the same comparator checks it
against the original baseline. Both now emit the same `False` write, as shown
by [after stdout](after-stdout.log) and its [receipt](after-receipt.json).
The complete corrected macro acceptance run is
recorded separately in [engine-final](../../engine-final/receipt.json).

The initial acceptance remains in [engine](../../engine/receipt.json) as an
honest record of the tested snapshot before this extra case was found. Repeated
checks are not added to the final distinct test count.
