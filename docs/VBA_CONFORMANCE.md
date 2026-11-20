# VBA conformance cases, version 1

The `vba-excel`, `vba-word`, and `vba-powerpoint` compilers share a versioned, document-independent
corpus for supported language behavior and deliberate refusals. The suites
cover String intrinsics, explicit Variant states/conversions, and the bounded
Word paragraph and PowerPoint shape adapters. Each executes the public compiler, compares
the complete native operation list or a positioned diagnostic, and checks
native-plan JSON round trips for every successful case.

The canonical fixtures are:

| Suite | Cases | Scope |
| --- | ---: | --- |
| [`string_intrinsics_v1.json`](../packages/quds_office_engine/test/fixtures/vba_conformance/string_intrinsics_v1.json) | 69 | Strict String intrinsics, UTF-16 and publication boundaries |
| [`variant_conversions_v1.json`](../packages/quds_office_engine/test/fixtures/vba_conformance/variant_conversions_v1.json) | 120 | Empty/Null lifecycle, operators, explicit conversions and deliberate limits |
| [`variant_composition_v1.json`](../packages/quds_office_engine/test/fixtures/vba_conformance/variant_composition_v1.json) | 38 | Nested nullable results, unchanged strict operands and static scalar/object boundaries |
| [`word_paragraphs_v1.json`](../packages/quds_office_engine/test/fixtures/vba_conformance/word_paragraphs_v1.json) | 44 | Word object bindings, prefix insertion, font/paragraph formatting, shared language behavior and deliberate refusals |
| [`powerpoint_shapes_v1.json`](../packages/quds_office_engine/test/fixtures/vba_conformance/powerpoint_shapes_v1.json) | 20 | PowerPoint selectors and typed bindings, text/font/alignment/geometry mappings, explicit collection guards and positioned refusals |

The same fixture bytes are consumed by each VM test and the portable
JavaScript runner; there is no separately maintained copy of expected results.

These cases distinguish three kinds of evidence. A passing case derived from
Microsoft documentation does not establish that an installed Office application
produced the result. No case in any delivered corpus claims Office host execution.

## Case format

The root object contains exactly `schemaVersion`, `suite`, `dialect`, and
`cases`. Version 1 uses `schemaVersion: 1`, a dialect of `"vba-excel"`,
`"vba-word"`, or `"vba-powerpoint"`, a suite identifier, and a nonempty array of cases. Case identifiers
must be unique. A suite admits only native operations for its selected format.
Every case contains `id`, `feature`, `source`, `expected`, and `provenance`.

```json
{
  "schemaVersion": 1,
  "suite": "vba-string-example",
  "dialect": "vba-excel",
  "cases": [
    {
      "id": "len-basic",
      "feature": "Len",
      "source": "Sub Main()\n  Worksheets(1).Range(\"A1\").Value2 = Len(\"abc\")\nEnd Sub\n",
      "expected": {
        "steps": [
          {
            "tool": "xlsx.cellValue",
            "arguments": {"sheet": 0, "cell": "A1", "value": 3}
          }
        ]
      },
      "provenance": {
        "kind": "spec-derived",
        "references": [
          "https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/len-function"
        ],
        "note": "Expected from the published String contract; no Office host was executed."
      }
    }
  ]
}
```

The runner compiles every case as module `Conformance`, entry point `Main`,
using the suite's dialect and the corresponding native format:

| Dialect | Native format | Required operation prefix |
| --- | --- | --- |
| `vba-excel` | `xlsx` | `xlsx.` |
| `vba-word` | `docx` | `docx.` |
| `vba-powerpoint` | `pptx` | `pptx.` |

Worksheet selectors in VBA source and supported Word paragraph selectors are
one-based; native integer sheet and paragraph selectors are zero-based. Word
selectors follow the documented Quds recursive body traversal, with actual
paragraph existence checked only at execution. The expectation includes the
entire ordered list of native steps, including operations emitted while
evaluating helper arguments.

A refusal case instead uses exactly one diagnostic expectation:

```json
"expected": {
  "diagnostic": {"code": "vba_type_error", "line": 2, "column": 47}
}
```

Line and column are one-based UTF-16 positions in that case's source. The
validator rejects positions outside the source, malformed native steps,
duplicate identifiers, missing/unknown fields, invalid provenance, and unknown
schema versions. Message prose is intentionally excluded from expectations;
the diagnostic code and position provide the stable contract. Unexpected
exceptions and native-plan round-trip changes fail the run.

## Provenance

| Kind | Meaning | Required evidence |
| --- | --- | --- |
| `spec-derived` | Expected behavior derived from a published language/function contract | Nonempty HTTPS `references` and a descriptive `note` |
| `dialect-contract` | Intentional subset restriction, resource limit, or explicit portability choice | Contract/reference links and a note stating the restriction |
| `office-host` | Result actually observed from an Office host | References, note, and a `host` object with application, version, platform, observation time, and evidence URL |

For `office-host`, `host` has exactly `application`, `version`, `platform`,
`observedAt`, and `evidence`. The timestamp must include a timezone; evidence
must be an HTTPS URL to the actual observation. This metadata is validated for
shape, not authenticated by the test runner. Reviewers must inspect the
referenced capture before accepting a host-compatibility claim. Never relabel
a specification-derived expected value as an observed Office result.

The first suite records clamping, optional length, signed-Long boundaries,
strict actual-String and exact-integer types, eager source-order evaluation,
Unicode BMP/supplementary/combining characters, internal surrogate halves and
recombined-pair round trips, malformed-UTF-16 refusals at native write boundaries,
static checking of unused code, unsupported neighboring syntax, and shared
work/string budgets. Full VBA coercion, numeric `Len`, implicit Empty/Null
coercion in the strict String signatures, byte variants, and unsuffixed
substring functions remain outside that slice. Three existing refusal codes
now reflect that Empty/Null are valid source states rejected by the strict
String argument check; all other original String expectations are retained.
See the [dialect contract](VBA_MACROS.md#string-intrinsics) for precise limits.

The Variant suites independently specify defaults in locals/functions/arrays,
`ReDim`/`Preserve`/`Erase`, `ByVal`, predicates, typed Empty defaults and Null
failures, eager arithmetic/comparison/Boolean semantics, concatenation's Null
exception, conditions/selection, ties-to-even Long boundaries, invariant numeric
input/output (including binary64 subnormals), exact diagnostics, native Empty
clears and Null refusals, Unicode, shared conversion work, compositional nullable
results and static scalar/object boundaries. Expectations
were authored from the cited specification or stated dialect policy before
running the implementation. See [the Variant contract](VBA_MACROS.md#variant-states-and-explicit-conversions).

The Word suite independently specifies `ThisDocument`, Document/Paragraph/Range
aliases and `ByVal`, prefix insertion and evaluation order, nested `With`,
font and paragraph formatting, named alignment constants, exact half-point and
twentieth-point serialization bounds, Unicode/XML publication, and reuse of
shared String, Variant, procedure, array and control-flow behavior. Refusals
cover live reads, whole-range Text replacement, Excel roots, Word Range
iteration, scalar/object mismatches, strict argument types, invalid XML,
attribute-normalization hazards and shared resource limits. Native range
formatting targets the current paragraph text and excludes a Word paragraph
mark; a compile-only case does not claim successful execution on an empty or
missing paragraph. See the [Word dialect contract](VBA_WORD_MACROS.md).

The original three Excel fixture files and canonical receipt bytes remain
unchanged by the Word extension. The portable harness checks their previously
accepted receipt hashes as well as VM/JavaScript equality. The fourth suite
adds 44 Word cases. The PowerPoint suite adds 20 cases, for **291 canonical cases per runtime**. The receipt shape
is unchanged: its existing `dialect` field identifies the selected adapter.

The PowerPoint suite independently specifies explicit presentation/slide/shape
and TextRange bindings, `.Item`, exact names, one-based index conversion,
`ByVal` rebinding, MsoTriState and packed RGB values, point/degree geometry,
all four supported alignments, Unicode, and shared source control flow.
Refusals cover live reads in inactive code, cross-host objects, group paths,
mixed/toggle formatting and unsupported publication values. Complete expected
plans include `topLevel: true`; actual native collection identity and rollback
are exercised separately by runtime tests and the portable transaction smoke.

Fixtures remain schema version 1. New capabilities add suites and cases;
the versioned schema does not promise that an intentionally unsupported syntax
will remain unsupported forever. A deliberate diagnostic change must identify
its corresponding new capability and retain unrelated expectations.

## Run and compare the same corpus

Resolve the repository's pinned dependencies first. From
`packages/quds_office_engine`, run the following as a Bash script so a failed
execution cannot be mistaken for two matching empty receipts:

```bash
set -e
dart test test/office_vba_conformance_test.dart \
  test/office_vba_string_intrinsics_test.dart \
  test/office_vba_string_intrinsics_integration_test.dart \
  test/office_vba_variant_conformance_test.dart \
  test/office_vba_word_conformance_test.dart \
  test/office_vba_powerpoint_conformance_test.dart \
  test/office_vba_variant_conversions_test.dart \
  test/office_vba_variant_conversions_integration_test.dart \
  --concurrency 1 --timeout 4x

mkdir -p build/macros
for suite in string_intrinsics_v1 variant_conversions_v1 variant_composition_v1 word_paragraphs_v1 powerpoint_shapes_v1; do
  VBA_CASES_BASE64=$(python3 -c 'import base64,sys; from pathlib import Path; print(base64.b64encode(Path(sys.argv[1]).read_bytes()).decode())' "test/fixtures/vba_conformance/${suite}.json")
  dart --packages=../../.dart_tool/package_config.json \
    -DVBA_CONFORMANCE_BASE64="$VBA_CASES_BASE64" \
    tool/macros/web_vba_conformance.dart > "build/macros/${suite}-vm.json"
  dart compile js -O1 --packages=../../.dart_tool/package_config.json \
    -DVBA_CONFORMANCE_BASE64="$VBA_CASES_BASE64" \
    tool/macros/web_vba_conformance.dart -o "build/macros/${suite}.js"
  node -e 'globalThis.self = globalThis; require(process.argv[1])' \
    "./build/macros/${suite}.js" > "build/macros/${suite}-js.json"
  cmp "build/macros/${suite}-vm.json" "build/macros/${suite}-js.json"
done
```

The generic `web_vba_conformance.dart` runner has no `dart:io` dependency.
The original `web_vba_string_conformance.dart` entry point delegates to it for
compatibility. The base64 definition embeds
the exact fixture bytes into the VM/JavaScript programs. It prints a canonical
JSON receipt with sorted object keys, normalized integral numbers, every case's
actual result, and its provenance kind. A mismatch throws instead of producing
a successful receipt. Each fixture is deliberately compact enough for a single
compiler-definition argument; split future large suites instead of duplicating
their expectations in generated Dart code.

`office_vba_conformance_test.dart` additionally tests malformed fixture
rejection, provenance requirements, expected-outcome mismatches, and receipt
determinism. `office_vba_string_intrinsics_integration_test.dart` exercises the
same feature through native runtime transactions, MCP, and real CLI processes,
including unchanged outputs after compile failures and whole-run rollback.
`office_vba_variant_conformance_test.dart` executes the Variant suite; the
Variant unit and integration tests additionally cover native cell clearing,
formatting preservation, the runnable report, policies, recording isolation,
real CLI publication and rollback.

The [qualification record](validation/office-vba-string-conformance-20261120/README.md)
records actual commands and source identities. GitHub Actions are not required
for this local qualification.
