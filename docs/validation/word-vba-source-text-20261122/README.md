# Word VBA source-text continuation — 22 November 2026

## Scope

Add `StrReverse(expression)` to the shared compiler used by `vba-word`,
`vba-excel` and `vba-powerpoint`. This is a document-independent source
operation. Its output enters the existing native operation catalog and
detached publication transaction.

The callable accepts one positional String or scalar Variant. String payloads
are reversed, Empty becomes an empty String, and Null produces the existing
`vba_invalid_use_of_null` diagnostic. Numeric and Boolean payloads require
an explicit `CStr` conversion. The result is typed String. The function name
is reserved just like the other intrinsics.

Quds reverses UTF-16 code units. This choice is explicit: it does not reverse
grapheme clusters or apply bidirectional display layout. Combining marks and
surrogate pairs can change their relative order. Malformed intermediate UTF-16
can be examined or reversed again in source, but the existing native output
guard refuses to publish it. Source text length cannot grow, and every output
unit is charged to the shared work budget before allocation.

There is no `StrReverse$` alias, named/omitted argument support, implicit
numeric/Boolean conversion, live document read or embedded-project execution.

## Intake and preservation

Initial main: `ea7ae724bea2f1e9052aa17f9926eb0659ae4262`.
The remote inventory contained 48 branch heads and no open PRs.
All Word/VBA heads were already ancestors of main. The only remaining head
was `work/mail-connected-navigation-20261122` at
`a59e986a12d50c0d115b99c14cd8f746921c6f44`.

Reconciliation checkpoint:
`340f44335cf2777d2d881e2c8e21b4780fbef36b`.
Its parents are the initial main and the remaining Mail head, preserving all
captured ancestry. The integrated tree retains main's newer Mail lifecycle,
adds two independent assertions, and references historical receipts through
their original commit/blob identities rather than duplicating over 7 MB of
logs. No Mail application source changed.

## Validation status

**No Dart or Flutter execution, analyzer, formatter, JavaScript compilation,
or installed Microsoft Office differential run has completed for this
increment.** The initial clone exhausted workspace capacity during checkout.
Subsequent sandboxed commands failed before shell startup:

```text
bwrap: Can't create file /workspace/scratch/f13177789685/.git: No space left on device
```

The environment rejected elevated cleanup because its granular policy forbids
sandbox approval. Native recovery was also unavailable. Work continued through
GitHub's Git data API with expected-head, non-forced branch updates. GitHub
Actions was neither queried nor awaited.

Source review checked the intrinsic registration, whole-module type checking,
once-only argument evaluation, Variant initialization, preallocation charging,
and existing native UTF-16 guards. Regression tests are committed as authored
coverage, not passing evidence. Historical receipts from other sources do not
qualify this source revision.

## Primary sources and qualification boundary

- [Microsoft VBA StrReverse](https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/strreverse-function):
  reversed character order, empty input, and Null error.
- [Dart String.fromCharCodes](https://api.dart.dev/dart-core/String/String.fromCharCodes.html):
  16-bit input values are retained as code units.
- [Microsoft Visual Basic .NET StrReverse](https://learn.microsoft.com/en-us/dotnet/api/microsoft.visualbasic.strings.strreverse):
  its grapheme-oriented behavior is a different API and is not the contract
  claimed here.

Ordinary ASCII expectations are specification-derived. UTF-16 edge behavior,
strict coercion, diagnostic codes, resource limits, and callable restrictions
are explicit Quds dialect expectations. None are presented as observations
from an installed Office process.
