# PR-base reconciliation after rendering qualification

Creating [draft PR #72](https://github.com/CrispStrobe/quds_office_suite/pull/72)
returned main revision `ed5facb4bd503667749ed3d13378da6a1b34738b` at
2026-11-16 15:59:30 UTC. Main had advanced after the 138-ref inventory with
ODS PRs #69–71: conditional formatting and validation export, worksheet
pictures, and acceptance documentation. That exact observed base was merged
and saved remotely as `6e0e010f15667072f90728732708192f3d72cd3a`.

## Source preservation

The [machine-readable receipt](pr-base-reconciliation.json) verifies that the
only package paths changed since rendering-qualified source `4c1d71a` are:

- `packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_writer.dart`
- `packages/quds_office_engine/test/ods_sheet_writer_test.dart`
- `packages/quds_office_engine/CHANGELOG.md`

The writer blob is `5e9c1cd9ef29aebc8bdb54c3622c05b8f989b2ff`, exactly matching
the observed main revision. The changelog was the sole merge conflict; both
the contextual-rendering and incoming ODS entries were retained. The complete
editor package and all font/text production sources are unchanged. The writer
test merge retains the earlier lint cleanup and all incoming assertions.

The earlier 138-ref inventory remains a pinned historical observation. The
additional main merge is recorded separately instead of rewriting that
inventory or claiming that remote branches stopped changing.

## Local qualification of the new delta

At source `6e0e010f15667072f90728732708192f3d72cd3a`:

- **110 tests passed** across the existing ODS reader and writer files, with no
  skips, hidden failures, runner errors or missing suites.
- All **764 input hashes** were stable before/after the run and tracked inputs
  matched the published source.
- Formatting made **zero changes** and strict analysis reported **no issues**
  in the two changed Dart files.

See the [test summary](engine-pr-base-summary.json),
[executed runner](engine-pr-base-run.py), and
[static-check receipt](pr-base-static-checks.json). Original event/log archives
and input manifests are retained beside them. The rendering cohorts and CLI
regression remain correctly attributed to `4c1d71a`; they were not rerun after
this ODS-only production delta. No GitHub Actions were queried or awaited.

## Inspection-only follow-ups in incoming ODS code

These findings concern code already present in the observed main revision,
which this integration preserves. They were identified by source inspection;
no additional reproducer tests were executed for them in this font/text pass.

| Area | Source observation | Follow-up |
| --- | --- | --- |
| Custom validation | `_validationCondition` returns `of:is-true-formula([.A1]>0)` for every custom rule. | Preserve the authored `formula1` through a supported conversion, or reject unsupported rules explicitly. |
| Sparse drawing/validation targets | `_writeSheet` enumerates cells only to `usedExtent()`, whose model implementation considers content and merges. | Check pictures and validation references outside that extent; they may have no emitted cell anchor/reference. |
| Raw XML addresses | Conditional-format address strings and the validation base-cell address enter raw XML attributes without `_escapeAttr`; sheet-name quoting alone is not XML escaping. | Cover sheet names containing ampersands and double quotes and escape the complete attribute value. |

Relevant source: [ODS writer](../../../packages/quds_office_engine/lib/src/sheet/legacy/ods_sheet_writer.dart)
and [worksheet extent](../../../packages/quds_office_engine/lib/src/sheet/model/sml_workbook.dart).
The existing new writer tests exercise an A1 picture, list validation over
populated A1:A2, and one numeric conditional rule. Their success does not
establish support for the inspection-only cases above.
