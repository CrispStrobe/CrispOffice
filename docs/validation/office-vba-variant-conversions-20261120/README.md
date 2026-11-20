# VBA Variant conversion milestone — 20 November 2026

This branch extends the documented `vba-excel` source-to-plan dialect with
explicit Empty/Null states and bounded scalar conversions. It reconciles
recent fork branches with original ancestry and qualifies the combined source
locally. GitHub Actions, workflow runs, checks and commit-status endpoints are
not queried or awaited.

## Work in progress

The compiler, independent conformance corpus, Variant report, transaction
regressions and incoming picture-background repairs are incrementally saved.
Development receipts preserve successful checks as well as superseded failures.
Independent review and reconciliation of new remote advances are still in
progress; these development results are not the final combined-source gate.

The final report will record the accepted source, exact selections, local test
counts, complete portable replay, static checks, review resolutions and final
remote reconciliation before main is updated.

## Reproduction

Use the repository pin in `.fvmrc`, retain the locked dependency versions, and
resolve the workspace before testing. `selection.json` enumerates disjoint
local test files. `run_validation.py` invokes genuine Dart/Flutter runners,
retains raw JSON events and process exits, excludes hidden loader events from
test counts, and verifies source inputs before and after the complete run.
It never queries hosted CI. Set the supported `CI=true` environment and Flutter
analytics suppression so Flutter does not probe cloud-instance metadata.

```bash
python3 docs/validation/office-vba-variant-conversions-20261120/run_validation.py \
  --repo . --sdk /absolute/path/to/flutter \
  --pub-cache /absolute/path/to/pub-cache \
  --selection docs/validation/office-vba-variant-conversions-20261120/selection.json \
  --output /absolute/path/to/new-results --workers 3
```

The shared fixture replay commands are in [VBA_CONFORMANCE.md](../../VBA_CONFORMANCE.md).
The precise language contract and example are in [VBA_MACROS.md](../../VBA_MACROS.md).

## Retained development evidence

`audit-initial.tar.gz` contains the initial exact remote inventories, ancestry
and equivalence classifications, merge-resolution records, test selection,
independently authored fixture script and Microsoft source research. Its index
lists every member's size and SHA-256. The temporary baseline checkout is
excluded; its commit identity and regression receipts reproduce the control.

`development.tar.gz` contains the captured raw development runs and supporting
manifests. Its index gives member and archive hashes. These receipts retain
their original source and selection scope. Later checkpoints may replace this
archive with a superset; Git history retains earlier versions.

No real Microsoft Office host, mail account, Zotero service or native spaCy
model was newly exercised by these local tests. Incoming native qualification
retains its original recorded source/runtime attribution. Source compilation
still has no access to existing workbook values.
