# Final canonical qualification after concurrent integration

Published implementation: `8e017e8c148517fea61f8d55eaafc7f070b82bba`.
Qualified tree: `17eecf8b8c8558c78dbbefe9ffc9b1249e2455cf`.
The locally executed checkout `6d73ecf109e3d8a95c0e9d8ae5219bf77cee59ff`
has this exact tree. Source files were also checked individually against the
published commit before and after qualification.

## Current disjoint results

| Cohort | Test files | Passed | Skipped |
| --- | ---: | ---: | ---: |
| All canonical engine Zotero suites | 19 | 390 | 0 |
| All canonical editor Zotero suites | 13 | 186 | 0 |
| Incoming engine proofing and hyphenation | 4 | 59 | 0 |
| Incoming ODS reader integration | 1 | 99 | 0 |
| Word layout and style integration | 2 | 31 | 0 |
| Editor proofing and platform spelling | 4 | 49 | 0 |
| Editor hyphenation, painting and caret integration | 2 | 11 | 0 |
| **Total** | **45** | **825** | **0** |

The Zotero cohorts contribute **576 distinct passing tests**. The separately
identified integration cohorts contribute **249**. The runner verifies that no
test file appears in more than one cohort. In particular, Zotero bibliography
layout tests belong only to the engine Zotero cohort.

The earlier 636-test qualification at `039c1e29` remains preserved separately
as evidence from before the concurrent integration. Its counts are excluded
from this run. Setup smokes, repeated development runs, behavioral controls,
and companion CrispCloud host checks are also excluded from the table above.

Strict analysis with `--fatal-infos` passes for **4 engine targets and 8 editor
targets**. The editor selection includes the directly ported caret engine,
paint-run helper and hyphenation-caret regression tests. Declared Dart **3.12**
formatting passes for all **12 targets, with 0 changes**.

## Integrity and provenance

All **1,505 canonical source and dependency-manifest inputs** matched the
published commit's Git blob IDs. Their before/after SHA-256 inventories remain
identical. All **3,857 external dependency and runtime inputs** also remain
identical, as do every enforced harness manifest, lockfile, package
configuration and package graph.

The genuine engine/editor harness links resolve to canonical production
libraries and tests. Runtime pins are Flutter **3.47.8**, Dart **3.13.7**,
framework `737ba8f885dc774b53b442759999a312c9461e4e`, and engine
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`.

The temporary root analysis package configuration uses absolute paths from
the same locked graph. It was removed afterward, restoring its original
absent state. Qualification changed no tracked repository files or production
dependency manifests. Concurrent documentation/audit edits are outside the
compiled-input inventory.

`receipt.json` records exact commands, working directories, exit codes,
counts, test selections, source pins and integrity results. `source-before`
and `source-after` JSON files contain the full canonical inventories;
`dependencies-before` and `dependencies-after` contain the external inventories.
Their `.json.gz` copies preserve the exact same JSON bytes for compact archival.
`artifact-inventory.json` records evidence and runner hashes. The historical
`prepared-plan.json` records selection before the final pin; the execution
receipt contains the actual final selection and results.

## Scope

Qualification covers local canonical Zotero behavior, the integrated proofing
and ODS changes, and the narrow caret/RTL hyphen rendering fixes using the
listed synthetic fixtures and mocked-service test suites. The incoming-ref
audit records branch disposition separately. Full application builds, live
Zotero account interaction, Word/LibreOffice acceptance and platform-specific
native spelling-provider acceptance retain their separate scope.

No GitHub Actions, workflow jobs or CI status checks were queried, awaited or
rerun. The only qualification-related fetch retrieved the explicitly named
continuation branch to obtain the published source object.

## Reproduction

Reconstruct the existing genuine runtime and enforced harnesses with
`docs/validation/zotero-continuation-20261116/setup/bootstrap-local-tests.sh`.
Use the published implementation commit above for the canonical checkout.
Place this runner in `zotero-toolchain/expanded-canonical-qualification`, with
`zotero-toolchain` beside `quds_office_suite`. Then run:

```bash
source zotero-toolchain/env.sh
python3 zotero-toolchain/expanded-canonical-qualification/run-qualification.py \
  --source-commit 8e017e8c148517fea61f8d55eaafc7f070b82bba \
  --extra-analysis-target packages/quds_office_editor/lib/src/editor_word/caret_engine.dart \
  --extra-analysis-target packages/quds_office_editor/lib/src/editor_word/paint_run_text.dart \
  --extra-analysis-target packages/quds_office_editor/test/word_hyphenation_caret_test.dart
```

The runner discovers the full Zotero test selections, preserves disjoint
integration cohorts, checks the twelve exact analysis/format targets, and
restores the temporary analysis configuration in a `finally` block. A failed
command stops further execution while still recording after-state integrity.
