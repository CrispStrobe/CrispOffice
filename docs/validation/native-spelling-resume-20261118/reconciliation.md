# Incoming work reconciliation for native spelling resume

Spelling work starts from remotely saved integration
`4dceb86e9fae51877bb5b7dc01e7a8bc721cb6ea`, with tree
`d25edc0bad66e22074aa23f84f3ace5839222ec5`. It preserves current fork main
`517f6d10f0ec2509b1381b3cf23807645bba4f92` and both remaining incoming branch
heads as merge parents. The local two-step merge tree was identical to the
remotely saved tree.

## Recent changes brought in first

| Incoming work | Exact head | Initial disposition |
| --- | --- | --- |
| Prior native spelling continuation, PR #160 | `8cbdb9d9a05ff7f0e795efe0ee7848b196f424a3` | Already merged into current main; retained. |
| Zotero reference details and selection review, PR #161 | `acfa3c2bf543debd2fff518304ab514ab677418b` | Already merged into current main; retained. |
| Native spaCy/NER and published macOS capsule follow-up, PR #163 | `ce4d3d19a21eae96a473291ffb9f47ac3be6a74c` | Already merged into current main; retained. |
| Final document review hardening and evidence, draft PR #162 | `9ecf4c420f6b4251744308530f0934f8cd5f3b37` | Integrated into the spelling task branch before spelling edits. |
| Working-directory-independent golden host selection | `ca42a7fa3947d0b59b9b2d3e14e807116327d714` | Integrated into the spelling task branch before spelling edits. |

PR #162's remaining implementation delta shares paragraph-target lookup while
rendering review previews. Its remaining changes also preserve an export-order
cleanup, five adversarial comparison tests, changelogs and validation records.
Its existing evidence reports 358 selected tests and 47 supplemental field
tests; those are inherited results, not newly executed spelling acceptance.

The macOS integration branch adds one test-helper repair: Linux golden reference
routing uses the seven explicit Linux reference names, independent of the
invoking working directory. Existing Linux and macOS image references are
preserved. Integrating this helper does not claim a fresh macOS visual run.

## Complete initial reference inventory

[refs.json](refs.json) accounts for **372 branch and PR references representing
241 distinct commit heads**:

| Repository | Branch heads | PR heads |
| --- | ---: | ---: |
| `CrispStrobe/quds_office_suite` | 201 | 163 |
| `MohammedAsaadAsaad/quds_office_suite` | 4 | 4 |

The inventory uses all pages of GitHub's branches and pull-request collections,
including closed PRs. It was captured before creating this task's new remote
branch. The requests form a short observation window rather than an atomic
server snapshot. Symbolic refs and PR test-merge refs are excluded.

| Disposition against the saved integration | References |
| --- | ---: |
| Exact ancestor | 344 |
| Historical patch equivalent already accepted on main | 22 |
| Historical exact integration-tree equivalent already accepted on main | 6 |
| Unresolved incoming reference | 0 |

All 241 distinct heads were checked against the saved integration with local
Git ancestry queries. The 22 patch-equivalent references represent 11 historical
branch/PR pairs. Their stable patch IDs were independently recomputed and matched
their accepted counterparts. PR #140 spans two commits, so its aggregate diff
from the common ancestor is compared with the accepted squash commit; the other
ten pairs match their final commit diffs directly. The six tree-equivalent refs
represent three historical integration heads; all three root tree IDs match.
Every accepted counterpart is an ancestor of the saved integration.

Upstream main remains `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`; all upstream
branch and PR heads are included by ancestry. Retained historical branches are
accounted for without replaying their old changes over later accepted fixes.
The intentionally removed `packages/quds_proofing_aot` package remains absent.

The recomputation script is [reconcile_refs.py](reconcile_refs.py). The output
binds each reference to the exact saved integration commit and tree. The saved
JSON includes both the current inventory and the equivalence mapping, allowing
the audit to be reproduced without obtaining older report files:

```sh
python reconcile_refs.py --repo path/to/quds_office_suite \
  --refs refs.json --prior refs.json \
  --target 4dceb86e9fae51877bb5b7dc01e7a8bc721cb6ea \
  --output recomputed-refs.json
```

## Scope and later changes

This record establishes initial source integration and historical equivalence.
Fresh runtime acceptance is recorded separately by the spelling validation
report. It does not recertify inherited native models, installers, physical
platforms or full application builds.

Any branch that advances after this initial observation belongs in a separate
final frontier record. It must not be silently described as part of the source
tested at the fixed integration checkpoint.

No GitHub Actions, workflow, check-run or CI-status endpoint was queried,
awaited or rerun. The integration checkpoint uses `[skip ci]`.
