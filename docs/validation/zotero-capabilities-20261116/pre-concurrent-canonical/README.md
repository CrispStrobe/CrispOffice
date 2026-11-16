# Final canonical Zotero qualification

Published implementation: `039c1e293052f548367f9ea3b0fa5ff56949ccaa`.
Qualified tree: `14c6c4f3ffcd212703a4fb24b93e6bc26c001a21`.

| Disjoint cohort | Test files | Passed | Skipped |
| --- | ---: | ---: | ---: |
| All canonical engine Zotero suites | 19 | 390 | 0 |
| All canonical editor Zotero suites | 13 | 186 | 0 |
| Retained engine proofing integration | 4 | 56 | 0 |
| Retained editor platform-spelling integration | 1 | 4 | 0 |
| **Total** | **37** | **636** | **0** |

The Zotero cohorts contribute 576 distinct passing tests. The separately
identified incoming-proofing cohorts contribute 60. Setup smokes, earlier
overlapping runs, before/after behavioral controls and companion host tests
are excluded from these totals.

Strict analysis with `--fatal-infos` passes for four changed engine targets
and five changed editor targets. The exact source/test list is in
`receipt.json`. Formatting with the declared Dart 3.12 language version passes
for all nine targets: **9 files, 0 changes**.

## Integrity and provenance

The runner verified all **1,497 canonical source/dependency-manifest files**
against the published commit's Git blob IDs before testing and checked them
again afterward. Their SHA-256 inventory is unchanged. The **3,857 external
dependency/runtime source inputs** also have identical before/after hashes.
Every original enforced harness manifest, lockfile, package configuration and
package graph remains unchanged.

Tests run through genuine harness links to current canonical production
libraries and tests. The runtime is Flutter **3.47.8**, Dart **3.13.7**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`, engine
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`.

For analysis only, the root ignored package configuration temporarily used
absolute package paths derived from the same locked graph. The runner removed
that temporary configuration afterward, restoring the original absent state.
No production dependency manifests or tracked repository files were modified
by qualification. Concurrent documentation edits are outside the compiled-input
inventory. Both recorded Git heads are the published implementation above.

`receipt.json` includes the complete disjoint test lists, exact commands,
working directories, exit codes, counts, log hashes and final integrity checks.
The source and dependency JSON maps retain full before/after inventories.
`artifact-inventory.json` hashes the evidence and runner. The corresponding
`.json.gz` copies preserve the same JSON bytes for compact archival.

No GitHub Actions, workflow jobs or CI status checks were queried, awaited or
rerun. Qualification covers local engine, editor and retained proofing behavior
using synthetic fixtures and mocked service responses. Full application builds
and live Zotero/Word acceptance retain their separate scope.

## Reproduction

Reconstruct the existing genuine runtime and enforced harnesses with
`docs/validation/zotero-continuation-20261116/setup/bootstrap-local-tests.sh`.
Use the published implementation commit above for the canonical checkout.
Place this runner in `zotero-toolchain/final-canonical-qualification`, with
`zotero-toolchain` beside `quds_office_suite`. Then run:

```bash
source zotero-toolchain/env.sh
python3 zotero-toolchain/final-canonical-qualification/run-qualification.py
```

The runner discovers all engine/editor `*zotero*test.dart` files, runs the
separate proofing cohorts, executes the nine strict-analysis and formatting
targets, and restores the temporary analysis configuration in a `finally`
block. It stops on a failed command and still records after-state integrity.
