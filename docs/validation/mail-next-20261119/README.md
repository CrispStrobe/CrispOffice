# Mail continuation: branch reconciliation checkpoint

**Date:** 2026-11-19. **Status:** preserved remotely; local qualification blocked.

This checkpoint reconciles the recent draft continuations before the next mail
feature increment. It is not a completed mail feature or an acceptance result.

## Baseline and inventory

Main remained at `5715d56053e93dc11e8b5165bd13f8db2a1f3917` throughout the initial
inventory. Its tree was `c25014b31077691524b5ced90fa1635547f9740a`. The fourteen
pre-existing branch heads and two open draft PR heads were unchanged from the
previous milestone. [remote-inventory.json](remote-inventory.json) records the
fresh observations, including this task's newly created checkpoint branch.

The inventory is a point-in-time observation. Its task-branch SHA records the
first preservation checkpoint and will naturally precede later checkpoints.
Older divergent ODS/ODT heads retain the equivalence disposition documented in
the prior milestone; their proofs were not rerun here.

## Incoming work reconciled

| Source | Captured head | Treatment |
| --- | --- | --- |
| Draft #210 | `3abffb94dcf33a2766a4579d296d0ef09c9e35cd` | Preserve history, add the missing Settings-to-Language-downloads dark-theme regression and 16 previously absent evidence files. |
| Draft #211 | `cacae8569814e4cb81f58d358734d31431f102be` | Preserve history, add the missing dark-theme setup/assertions to the language support review test and 205 previously absent evidence files. |
| Current main | `5715d56053e93dc11e8b5165bd13f8db2a1f3917` | Retain current product implementations, including newer bundled-runtime, NER and first-use verification fixes. |

The two draft histories are recorded as additional parents of the reconciliation
commit. This is a deliberate merge resolution: older draft implementations do
not replace the newer main implementations.

Only these existing test files change:

1. `packages/quds_office_editor/example/test/studio_layout_theme_test.dart`:
   exact incoming blob `d5b8052b8f8f522a0960293af4a18efd7163209c`.
   It adds a Settings-to-Language-downloads dark appearance test and its import.
2. `packages/quds_office_editor/example/test/studio_downloads_manager_test.dart`:
   combined blob `6cdbbb220e84a0e1d35789d6a1856fa93dab47fb`.
   It retains all current-main tests and adds the incoming dark appearance setup
   and assertions to the existing workspace-language support-review test.

The integration tree was reviewed independently by walking its Git tree objects
and checking the exact changed paths and blob identities. Before this report
and inventory were added, its delta from the first checkpoint was exactly
**223 leaves**: two test files and 221 new evidence files totaling 4,340,900
bytes. The root reviewer also retrieved the before/after test blobs and
inspected their line differences. No production source, dependency manifest,
lockfile or existing evidence was changed.

Three conflicting existing evidence paths deliberately retain main's blobs:

- `docs/validation/office-vba-arrays-20261119/.gitattributes`
- `docs/validation/language-downloads-20261119/README.md`
- `docs/validation/crispoffice-layout-theme-20261119/README.md`

The alternative incoming versions remain accessible in the preserved draft
commit histories. Newly included validation files are original author evidence,
not results freshly executed or independently replayed in this continuation.
Their filenames and original contents are preserved.

## Qualification status and recovery

Fresh local test executions: **0**. Static source and remote tree review do not
substitute for Dart/Flutter execution.

The workspace filled during checkout of historical validation payloads.
Subsequent local commands fail before execution, including the narrowly scoped
cleanup command. The environment prohibits sandbox escalation and its native UI
runtime is unavailable. [WORKLOG.md](WORKLOG.md) records the exact failure and
initial preservation checkpoint.

No GitHub Actions were awaited or used as an acceptance gate. This checkpoint
does not claim the previous milestone's 2,243 executions or 50-case continuation
gate as new tests. No final merge to main is included in this checkpoint.

After workspace recovery, use a sparse checkout that excludes unnecessary
historical runtime/evidence payloads while retaining them in Git. Fetch this
branch and current main, verify the restored source identities, and run the two
changed widget suites with the project's pinned Flutter toolchain before
accepting the reconciliation. Then implement and locally qualify the selected
mail milestone, refresh the remote inventory, and merge the finished result
using an expected-head check.
