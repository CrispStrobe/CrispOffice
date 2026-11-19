# Independent array boundary review

The independent reviewer owns
`packages/quds_office_engine/test/office_vba_arrays_boundaries_test.dart` and
did not edit the compiler. The suite contains **144 tests** covering:

- Exact signed 32-bit bounds, nonconstant/dead-path declaration rejection,
  one-dimensional scalar storage and explicit subscript diagnostics.
- Whole-array/object escapes, invalid call and return shapes, readonly Range
  coordinates and the existing prohibition on document-value reads.
- Live future array slots, copied controllers, captured Range traversal,
  mixed-loop exits, procedure isolation and scope cleanup.
- The 4,096-slot per-array and 16,384-slot aggregate active-frame boundaries;
  sequential allocation release and cumulative compilation work.
- Exactly 1,048,576 UTF-16 units in active array slots and one unit over,
  including String/Variant arrays, surrogate pairs, same-value replacement,
  release on replacement, and accounting across active procedure frames.
- Empty-body work consumption, oversized range preflight, emitted-operation,
  per-string and encoded-plan limits, and 32 active procedures with 32 nested
  For Each blocks plus 63 unary operators.

## Development finding and disposition

The [initial output](development-boundaries-initial.stdout) records 142 passing
tests and one failed expectation. The test initially assumed an uninitialized
Variant slot could be visited when the body did not use its controller. A
For Each binding itself reads that slot, so the existing Empty-value boundary
intentionally rejects this operation. The compiler owner and integration owner
confirmed that contract. The test now expects `vba_unsupported`; an additional
positive case verifies that Exit For avoids reading later uninitialized slots.
No production change was needed for this expectation correction.

An earlier command included the unsupported `dart test --no-pub` flag and exited
64 before loading tests. The retry used the supported command shown in the log.

The [corrected JSON reporter](boundaries-corrected.jsonl) and
[receipt](boundaries-corrected-receipt.json) record **144 passed, zero failed,
zero skipped**, with unchanged compiler and test hashes during execution.
The compiler SHA-256 was
`04233b63db9b18b892b4b665334e950d15481282b4641c7b6946d685a5dadbee`.

Two string-concatenation style findings were then corrected to interpolation
without changing generated VBA. The final test file passes `dart analyze
--fatal-infos` and `dart format --output=none --set-exit-if-changed`; its SHA-256
is `3395b07781c6fea8d2b602e5b3ab05c303ca2f34fd7ca11c24052c09776fa706`.
The complete frozen publication harness repeats this final test source; these
development runs must not be added to its distinct-test count.

## Source review

The reviewer also inspected the production diff for array declarations,
constant-bound resolution, collection typing, indexed writes, loop continuation
frames, procedure cleanup, and aggregate string accounting. Static checks keep
arrays out of scalar/Variant/object APIs; array allocation and range traversal
are bounded before expansion; indexed string writes check replacement deltas
before storage; procedure cleanup restores the caller's array counters. No
additional production defect was identified in that review.

These are focused development and source-review results. They do not qualify
native Microsoft Office interoperability or the entire repository. Final
publication evidence is recorded by the parent acceptance harness.
