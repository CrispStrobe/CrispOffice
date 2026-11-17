# Bounded ODT-list qualification — 17 November 2026

**The bounded amendment passed all 26 selected tests, strict analysis and
formatting.** Its isolated workspace also passed offline enforced resolution
with the unchanged dependency lock. No errors, failed cases or skips occurred.

Qualified source: `2ae8bf3420bd20ec33115c96a44a38a0d3a78df0`, tree
`50283ba638f5d4184f08b8edbd5a9ebe78a4f043`.
This reconciles the saved integration with the captured main's ODT list writer.

## Source relationship

The accepted full qualification remains attributed to
`837d06edbde08a2465e99cbbb15927ee4c87d8ac`: 2,576 substantive passes in 144
files, with two unavailable private-PDF early-return cases excluded.
Compared with that exact source, the bounded candidate changes only:

- `packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart`
- `packages/quds_office_engine/test/odt_document_writer_test.dart`
- `packages/quds_office_engine/README.md`

`source-delta.json` records both commits' Git blobs and modes. Every one of the
other **3,324 tracked non-evidence inputs** matches the accepted full-run map.
Dependency manifests, the dependency lock and the remaining implementation are
unchanged. The full run is not represented as having executed on this later
commit; the narrow delta receives this separate qualification.

## Fresh checks

| Check | Result |
| --- | --- |
| Fresh workspace, offline enforced dependency resolution | Passed; original 108-package graph and lock retained |
| Strict analysis of changed writer and its test | Passed |
| Dart 3.12 formatting of those two changed paths | Passed |
| ODT writer, ODF text fidelity and ODT structure suites | **26 passed in three files** |

The suites include the new flat contiguous list grouping and retained hidden
Zotero-field, visible cached-result, whitespace and paragraph-structure checks.
These 26 executions overlap earlier suites and **are not added to the full
qualification as unique tests**. Cross-component host-reader checks have their
own companion-host evidence.

Before/after source, external dependency, runtime, workspace, system and harness
maps all match. The temporary analyzer package graph was restored to its prior
absence; the exact source commit and working tree remained unchanged.
The test reporter's relative/absolute suite paths are resolved against its
recorded working directory, and every selected physical suite must match.

## Reproduction and evidence

`receipt.json` contains exact commands, terminal outcomes, source identities,
raw-log and compressed-log hashes. The accepted full receipt and source map
are separately hash-bound. `workspace-setup.json` documents a newly created
isolated workspace; the original full-run workspace is not repointed or edited.
All original package manifests are copied unchanged, and implementation links
point to the later canonical checkout.

Use the same restored Flutter 3.47.8 / Dart 3.13.7 runtime and cached locked
dependencies as the full qualification. From the parent evidence directory:

```sh
. /path/to/runtime/env.sh
python3 run_odt_amendment.py \
  --repo /path/to/quds-at-2ae8bf34 \
  --source-commit 2ae8bf3420bd20ec33115c96a44a38a0d3a78df0 \
  --flutter-root /path/to/runtime/flutter-sdk \
  --workspace /path/to/new-odt-workspace \
  --base-evidence /path/to/accepted/run-3 \
  --output /path/to/new-odt-evidence
```

Keep the supplied `run_qualification.py` next to the amendment runner; its exact
helper bytes are also preserved as `shared-helper-used.py`. New attempts need
new workspace and output paths. Runtime preparation contributes no additional
application-test count. No GitHub Actions, workflow or CI-status endpoint is
queried or awaited. This focused local check does not establish external office
application acceptance or general native-ODF roundtrip fidelity.
