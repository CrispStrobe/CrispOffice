# Zotero alias and dialog behavioral controls

These isolated controls run the same assertions against archived production
sources from two published Quds commits. They are separate from the final
qualification cohort and must not be added to its test count.

| Control | Before `e5e1e9af6beb0972a010d8208c1690a642809113` | After `357f7a3e87d8536c03ecca2a860a0a564b1659f0` |
| --- | --- | --- |
| Existing `WordZotero.embeddedItems(document)` with source aliases `[A]`, `[B]`, `[A,B]` | Compiles, then fails: 2 embedded snapshots instead of 1 | Passes: 1 snapshot, first metadata preserved, field instructions unchanged |
| Open the references dialog for 1,000 citations | Compiles, then fails: 4 field scans instead of 1 | Passes: 1 scan and source actions enabled |
| Open a bibliography-only document | Compiles, then fails: 4 field scans instead of 1 | Passes: 1 scan and source actions disabled |

All four process results match their expected observations: two before-source
processes fail behaviorally with exit code 1; both after-source processes pass
with exit code 0. Neither baseline failure is a missing API or compilation
failure. The alias fixture deliberately uses only the existing public
`embeddedItems` entry point, rather than the new source-deduplication helper.

`source-receipt.json` records source pins, per-file hashes, test hashes and
the enforced genuine harness inputs. `receipt.json` records exact commands,
working directories, exit codes and log hashes. `verification.json` verifies
all 440 before-source and 463 after-source archived files against their Git
blob IDs after the runs, with zero mismatches. All copied manifests, lockfiles
and rebased package configurations remain unchanged, and each version uses
identical control test bytes.

The different source-file counts include already integrated proofing work;
the controls exercise Zotero behavior only. Runtime and external package
dependencies come from the genuine Flutter 3.47.8 / Dart 3.13.7 bootstrap and
its enforced lockfiles. Canonical repository sources and production manifests
were never rewritten for these controls. No GitHub Actions or status checks
were queried, awaited or rerun.

## Reproduction

First reconstruct the existing local runtime and harnesses using the Quds
`docs/validation/zotero-continuation-20261116/setup/bootstrap-local-tests.sh`
script. Place these control files in `zotero-toolchain/behavioral-controls`,
with `zotero-toolchain` alongside the `quds_office_suite` checkout. Ensure both
recorded commits are fetched. Then run:

```bash
source zotero-toolchain/env.sh
python3 zotero-toolchain/behavioral-controls/setup-controls.py
python3 zotero-toolchain/behavioral-controls/run-controls.py
```

The setup archives engine, editor and supporting source libraries at each
pin. It copies genuine harness manifests and locks, rebases package root
locations to the isolated archives, and copies identical control fixtures.
The runner records the expected failed assertions as successful controls,
while retaining their original nonzero process exits and complete logs.
