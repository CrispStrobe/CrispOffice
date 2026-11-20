# VBA conformance cases, version 1

The `vba-excel` compiler has a versioned, document-independent corpus for
supported language behavior and deliberate refusals. The first suite covers
`Len`, `Left$`, `Right$`, and `Mid$`. It executes the public compiler, compares
the complete native operation list or a positioned diagnostic, and checks
native-plan JSON round trips for every successful case.

The canonical fixture is
[`string_intrinsics_v1.json`](../packages/quds_office_engine/test/fixtures/vba_conformance/string_intrinsics_v1.json).
The same bytes are consumed by the VM test and the portable JavaScript runner;
there is no separately maintained copy of expected results.

These cases distinguish three kinds of evidence. A passing case derived from
Microsoft documentation does not establish that an installed Office application
produced the result. No case in the initial corpus claims Office host execution.

## Case format

The root object contains exactly `schemaVersion`, `suite`, `dialect`, and
`cases`. Version 1 uses `schemaVersion: 1`, `dialect: "vba-excel"`, a suite
identifier, and a nonempty array of cases. Case identifiers must be unique.
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
format `xlsx`, language `vba-excel`. Worksheet selectors in VBA source are
one-based; integer sheet selectors in native operation expectations are
zero-based. The expectation includes the entire ordered list of native steps,
including operations emitted while evaluating helper arguments.

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
work/string budgets. Full VBA coercion, numeric `Len`, `Empty`/`Null`, byte
variants, and unsuffixed substring functions remain outside this slice.
See the [dialect contract](VBA_MACROS.md#string-intrinsics) for precise limits.

## Run and compare the same corpus

Resolve the repository's pinned dependencies first. From
`packages/quds_office_engine`, run the following as a Bash script so a failed
execution cannot be mistaken for two matching empty receipts:

```bash
set -e
dart test test/office_vba_conformance_test.dart \
  test/office_vba_string_intrinsics_test.dart \
  test/office_vba_string_intrinsics_integration_test.dart \
  --concurrency 1 --timeout 4x

mkdir -p build/macros
VBA_CASES_BASE64=$(python3 -c 'import base64; from pathlib import Path; print(base64.b64encode(Path("test/fixtures/vba_conformance/string_intrinsics_v1.json").read_bytes()).decode())')
dart --packages=../../.dart_tool/package_config.json \
  -DVBA_CONFORMANCE_BASE64="$VBA_CASES_BASE64" \
  tool/macros/web_vba_string_conformance.dart > build/macros/strings-vm.json
dart compile js -O1 --packages=../../.dart_tool/package_config.json \
  -DVBA_CONFORMANCE_BASE64="$VBA_CASES_BASE64" \
  tool/macros/web_vba_string_conformance.dart -o build/macros/strings.js
node -e 'globalThis.self = globalThis; require("./build/macros/strings.js")' \
  > build/macros/strings-js.json
cmp build/macros/strings-vm.json build/macros/strings-js.json
```

The portable runner has no `dart:io` dependency. The base64 definition embeds
the exact fixture bytes into the VM/JavaScript programs. It prints a canonical
JSON receipt with sorted object keys, normalized integral numbers, every case's
actual result, and its provenance kind. A mismatch throws instead of producing
a successful receipt. The fixture is deliberately compact enough for a single
compiler-definition argument; split future large suites instead of duplicating
their expectations in generated Dart code.

`office_vba_conformance_test.dart` additionally tests malformed fixture
rejection, provenance requirements, expected-outcome mismatches, and receipt
determinism. `office_vba_string_intrinsics_integration_test.dart` exercises the
same feature through native runtime transactions, MCP, and real CLI processes,
including unchanged outputs after compile failures and whole-run rollback.

The [qualification record](validation/office-vba-string-conformance-20261120/README.md)
records actual commands and source identities. GitHub Actions are not required
for this local qualification.
