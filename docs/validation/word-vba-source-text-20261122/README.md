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

## Authored coverage and reproduction

The new files cover:

- shared compiler results and refusals in Word, Excel and PowerPoint;
- String/Variant/Empty/Null, typed helpers, local arrays and optional parameters;
- UTF-16 units, combining marks, surrogate inspection and native refusals;
- once-only operand evaluation, inactive-source checks and work limits;
- 26 independent Word corpus cases with full plans or positioned diagnostics;
- a complete seven-edit Word table import, DOCX/DOCM ownership, detached
  validation, repeated save/reopen, recording/replay and MCP;
- native policy refusal, whole-run rollback, CLI compilation/publication and
  preservation of an existing output file after a source diagnostic.

The complete BAS intentionally restores the same four labels as the existing
delimited-report fixture. Its established oracle checks the full document and
opaque package parts, so the new intrinsic is tested against an independent
expected document rather than a newly generated snapshot of its own output.

After workspace capacity and the pinned Flutter/Dart toolchain are available,
run from the repository root:

```sh
flutter pub get
cd packages/quds_office_engine
dart test test/office_vba_strreverse_test.dart \
  test/office_vba_strreverse_conformance_test.dart \
  test/office_vba_word_strreverse_integration_test.dart \
  test/office_vba_string_intrinsics_test.dart \
  test/office_vba_text_intrinsics_test.dart \
  test/office_vba_split_test.dart
dart analyze lib/src/automation/office_vba_language.dart
dart format --output=none --set-exit-if-changed \
  lib/src/automation/office_vba_language.dart \
  test/office_vba_strreverse_test.dart \
  test/office_vba_strreverse_conformance_test.dart \
  test/office_vba_word_strreverse_integration_test.dart \
  tool/macros/web_vba_strreverse_conformance.dart
```

The portable corpus runner is
`tool/macros/web_vba_strreverse_conformance.dart`; it accepts the exact corpus
bytes in the existing `VBA_CONFORMANCE_BASE64` compile-time define. The
existing `web_vba_word_split_smoke.dart` runner can also consume the new BAS
through `WORD_SPLIT_BAS_BASE64`, because both examples intentionally share the
same independent output oracle. VM/JavaScript execution remains pending.

The read-only reviewer caught one incorrect test assumption before final
publication: Empty is not supported as a constant optional default in the
existing compiler. The test now uses an empty String default and separately
checks direct Empty values and truly missing Variants. No pre-existing Const
or default-expression rules were changed.

## Final review and concurrent work

Feature checkpoint: `74189751ccf18843e149c78be1199858dc5a92fb`.
Example/test checkpoint: `a713970fdab473b6fb74c34287fac91ff34153b1`.
Runtime blob: `c25ed6226689a6533315410ace4fc3246350b7f3`.
[PR #389](https://github.com/CrispStrobe/quds_office_suite/pull/389) carries the
complete change. The final correction only adjusts omission-test expectations:
the existing argument checker reports `vba_unsupported` at the first comma
before checking argument count. The 18-line runtime change is unchanged.

[review.json](review.json) records remote content readbacks, independent source
review, fixture structure/position checks and a small JavaScript check of
hardcoded UTF-16 expected strings. These checks are deliberately distinguished
from execution of the Dart implementation.

The final inventory captured 51 branches. All 48 heads from the initial intake
are preserved through the reconciliation checkpoint. Two independent branches
were created during this task:

- `codex/zotero-continued-parity-20261122` adds ongoing ODT hyperlink work.
- `work/mail-local-tags-20261122` adds ongoing Mail search work.

Their exact captured heads are in the review snapshot. They remain intact on
their own branches. They are active continuations outside the initial intake,
and their runtime changes were neither transplanted nor falsely recorded as
merged through an ancestry-only commit. Remote main is refreshed again at the
actual merge; any concurrent main change must be preserved.

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
