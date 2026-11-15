# Zotero rich formatting and preservation — 15 November 2026

The final canonical implementation at
`b09537fb34dd711118ae6df5872184b6e813d2df` passed all **313 selected tests**,
both strict analyzers, the changed-file formatter check and the Git whitespace
check. The tracked library/test source fingerprint was unchanged during this run.

| Executed check | Result | Evidence |
| --- | ---: | --- |
| Engine/client/parser/Word field and related import regressions | 232 passed | [engine-tests.log](final/engine-tests.log) |
| Shared Flutter controller/format-helper/dialog regressions | 81 passed | [editor-tests.log](final/editor-tests.log) |
| Changed engine paths, `dart analyze --fatal-infos` | Clean | [engine-analysis.log](final/engine-analysis.log) |
| Changed editor paths, `dart analyze --fatal-infos` | Clean | [editor-analysis.log](final/editor-analysis.log) |
| All 11 changed Dart files, format check | Unchanged | [format-check.log](final/format-check.log) |
| Complete incremental diff, whitespace check | Clean | [diff-check.log](final/diff-check.log) |

Exact commands, paths, source commit/tree/fingerprints, manifest/lockfile text,
exit codes and log hashes are in [final/receipt.json](final/receipt.json).
The companion CrispCloud PR records its separate actual host transport,
credential, target and ribbon tests and its vendor verification.

## Baseline and new regression inventory

The preceding remote source `0d9b008720b01371bc9db498efd063e3077be279` was first
tested from a frozen Git archive: **103 engine + 68 editor = 171 passes**.
This includes **all 39 cases previously committed but unexecuted**. Those are
baseline results, not extra tests added to the final 313 total. See the exact
runtime/setup receipt and logs under [baseline](baseline/README.md).

This continuation adds **63 regression cases**:

| Area | Added cases |
| --- | ---: |
| Bounded inert XHTML formatting parser | 21 |
| Rich bibliography fields, direct/isolate DOCX saves and guarded updates | 11 |
| Imported simple fields, numeric caches, native PAGE and tracked-field preservation | 18 |
| Controller history, refusal atomicity and save/reopen/update | 6 |
| Review UI, plain-text choice, cancellation, stale target, narrow viewport and imported cache | 7 |
| **Total** | **63** |

The final selection also includes related Word field, revision, footer,
content-control and trailing-section-break regressions affected by import.
Counts are per actual executed case, not a sum of development reruns.

## Runtime and reproduction

Official Flutter **3.47.8**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`, engine
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`, and Dart **3.13.7** were used.
The Dart archive SHA-256 was verified against its official sidecar. Flutter
source was checked out at the official tag and its ordinary tooling fetched
the matching artifacts. No SDK implementation was patched.

Genuine Pub resolution with enforced lockfiles ran in disposable package
harnesses linking the actual source and tests. Only scratch manifests removed
workspace resolution and rebased package paths. Repository manifests and
production dependency constraints were not changed. The baseline receipt
contains the complete four-package reconstruction data; the final receipt
contains the exact engine/editor manifests and locks used for this source.

Reconstruct those harnesses for the certified commit, set `PATH` to the pinned
Flutter SDK and provide writable `TMPDIR`/`PUB_CACHE`. Resolve with
`flutter pub get --enforce-lockfile`. Then run:

```sh
python3 docs/validation/zotero-rich-text-20261115/run-focused-checks.py \
  --source /absolute/path/to/quds_office_suite \
  --engine-harness /absolute/path/to/staging/quds_office_engine \
  --editor-harness /absolute/path/to/staging/quds_office_editor \
  --output /absolute/path/to/results
```

For canonical-file analysis, normalize the actual Pub package-config URIs to
absolute paths and map the four Quds package roots to the checkout in its
ignored `.dart_tool/package_config.json`. This reuses the genuine resolved
graph; it is not a dependency or source substitution. The historical
[setup guide](../zotero-20261115/SETUP.md) describes the same technique.

## Integration and scope

[branch-audit.json](branch-audit.json) accounts for all 15 Quds and 30 CrispCloud
branch heads and their recent PRs. Quds main through #42 and CrispCloud main
through #152 were already included. Three newer terminal #140 commits were
merged with both parents preserved before feature work. Five retained Quds
squash branches are exact-tree equivalents of their merged commits.

Checkpoints were saved remotely with `[skip ci]`. No GitHub Actions were polled,
awaited or rerun. This is focused source qualification, not a full application
build, live private-account or Zotero desktop test, OS-keychain acceptance,
native Word/Zotero refresh certification or ODT active-citation transfer test.

See [REVIEW.md](REVIEW.md) for fixes, safeguards and remaining formatting limits.
