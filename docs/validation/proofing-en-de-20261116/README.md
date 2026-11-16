# English and German proofing continuation: reconciled starting point

This remote checkpoint imports the recent fork and upstream histories before new proofing work.

## Pinned snapshot

- Captured: 2026-11-16T19:59:03.698Z.
- Fork main: `6811f8a7194f8e7b12a34e3c1cf13fd2e3bf7195`.
- Text-rendering PR #72: `6a07cb8f8f7db2007c694c167b861b05d1d58d00`.
- Snapshot: 177 named refs (120 unique heads), comprising 86 fork branches, 83 fork PRs, four upstream branches and four upstream PRs.
- All upstream heads were already present. The refresh also brought in main's newly merged ODS header/footer PR #83.

## Integration decisions

The tree starts from current main and imports 102 exact rendering blob entries. Those paths have no conflicting changes on main since the rendering merge base `be9eeec`. The five proofing recovery files and two unique Zotero recovery files are retained. Main's current ODS page setup and header/footer code remains intact.

The newer rendering continuation checkpoint supersedes the older pending-validation copy in the Zotero recovery branch. Shared production and regression-test blobs on those two branches match exactly.

Fifteen divergent feature, documentation and vendor heads were compared with their canonical main commits. Their incoming per-file patches are identical. Ten feature/documentation heads also have identical complete trees; four vendor heads have identical changed-file blobs. The old vendor filter branch contains one pre-existing unused test binding; current main retains the cleaned test and later features. Histories already included by the rendering head remain included, and the newer equivalent page-setup/header/footer heads are recorded as parents.

The complete inventory, per-path incoming blob identities, comparison dispositions and equivalence checks are in [reconciliation.json](reconciliation.json). This checkpoint does not change `main`.

## Validation scope

The attached execution environment is unavailable. No Dart, Flutter, native-library or browser test was run for this combined checkpoint. Earlier source-bound validation artifacts are retained with their original source attribution. This reconciliation uses GitHub ancestry, exact Git blob/tree identities, per-file patch comparisons and three-way changed-path checks.

No GitHub Actions were queried, awaited, polled or rerun. The commit uses `[skip ci]`. No new dependency, model or dictionary is introduced by this reconciliation. New English/German proofing work and its verification will follow this pinned integration.

## Final refresh before proofing implementation

A final snapshot captured 182 named refs (123 unique heads). It adds main `63194d8` and its exact-tree-equivalent header/footer documentation PR #84, plus rendering continuation `5ed98a0` with editor/runtime evidence. These 59 distinct incoming paths contain documentation, saved validation evidence and validation tooling; no new product source is introduced by this refresh. All incoming paths merge by exact blob identity without conflicts.

Before that refresh, all 120 originally pinned heads were verified as ancestors of `dbf5ff000d66bd6e2833ade990ab84de009e3ad8`. All 5,398 expected repository blob entries matched the merged tree; only the two intended audit files were additional. See [reconciliation-refresh.json](reconciliation-refresh.json) for the final inventory, three-way checks and complete prior-checkpoint verification. Final ancestry/tree verification is recorded separately in [reconciliation-verification.json](reconciliation-verification.json).
