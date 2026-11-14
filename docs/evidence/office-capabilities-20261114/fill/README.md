# Native spreadsheet fill validation — 14 November 2026

The [validation receipt](validation.json) and [indexed evidence archive](evidence.tar.gz)
preserve the exact spreadsheet bytes used by the independent schema and rendering
checks. The fill implementation and reference corpus are saved at
`2182916ec1ecca84832194e6f49f7ae94b703aa7`. This archive's generated outputs come
from `f531c98d4a4e05146a9b89dfd5570cc43ba5537c`, which adds one mandatory test-gate
entry after that checkpoint. The fill implementation, fixtures and producer test
are unchanged between those commits.

## Scope and results

Two workflows each have three saved XLSX files and one independently authored
expected XLSX. One applies bold formatting while retaining native theme,
indexed, patterned, gradient, direct-solid and gray125 fills. The other applies
explicit solid-color and no-fill commands, including equal-color replacements
and clearing a gradient whose modeled RGB is already empty.

- **Eight exported/reference files:** six saved outputs and two expected
  references. All eight pass the Open XML SDK validator with zero errors.
- **Eight native renders:** both complete three-save series match their expected
  references in page count, extracted text and rendered RGB fingerprints,
  including the first save. There are two independent first-save comparisons
  and no rendering failures.
- **Three committed native fixtures:** the original workbook and both expected
  references pass a separate schema check with zero errors. The two expected
  references overlap the eight-file group above, so this is **nine unique
  Office inputs**, not eleven.
- **Eighty renderer control tests pass.** Their full process output is retained;
  deliberate failure messages inside these tests are negative controls.
- Regenerating the three native fixtures from their committed Python builder
  produces byte-identical files. The builder authors OOXML independently of
  Quds and uses the existing native workbook's complete theme part.

The large swatches have readable labels outside the filled cells. Representative
saved images were visually inspected. LibreOffice's appearance comparison is
separate from exact native fill-XML assertions; it does not establish gradient
painting support in the Quds editor.

## What is preserved

The single deterministic archive contains the nine unique Office inputs; the
eight-file render report, PDFs, PNGs and extracted text; both raw schema reports;
schema and renderer-control logs; fixture regeneration hashes; a scoped source
inventory; dependency/runtime identities; and validator build provenance.

`index.json` inside the archive gives the byte length and SHA-256 of every
payload entry. It excludes itself; `validation.json` binds the index and the
complete archive. All entries and input-to-schema-to-render hash links were
verified after archive construction. Tar entries are sorted and have fixed
ownership, modes and timestamps; gzip has no filename or timestamp metadata.
Rebuilding the archive from the same payload bytes produces identical bytes.

The outputs were copied into an immutable capture directory before their
schema and rendering checks. Source identity was collected against the stated
commit. This is not presented as a retroactive start-of-run manifest for the
earlier full test gate.

## Validator and renderer

The validator uses the repository's `tool/office-validation/Program.cs`,
Open XML SDK **3.3.0**, .NET SDK **8.0.428** and runtime **8.0.34**. The standard
.NET CLI could not create its `NuGet-Migrations` mutex in this environment, so
the official SDK's Roslyn compiler was invoked directly. The archive preserves
the original CLI failure separately, the successful build receipt and compiler
response file, the small compiled validator, and verified hashes and download
URLs for the official NuGet packages. Its positive/negative package self-tests
passed. SDK binaries, dependency DLLs and caches are omitted.

The recorded renderer is **LibreOfficeDev 26.8.0.0.alpha0**,
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. Runtime details and the exact source
of the validator, renderer, producer test and fixture builder are in the archive.

To rerun the declared workflows, use the saved source with its supported Dart
dependencies, execute `test/sheet_fill_fidelity_test.dart`, validate the resulting
`build/fidelity-sheet-fill` directory with `tool/office-validation`, and run
`tool/office-validation/render.py` on that directory. The manifest requires all
eight outputs, and the renderer requires both independent references even when
that corpus directory is supplied as the input root.

This evidence covers the two fill workflows. Full engine/editor/application
gates, browser/device acceptance and in-memory lock/PDF-border state have their
own scope and receipts.
