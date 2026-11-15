# Complete canonical parser mirror sync plan

Read-only audit of Quds commit `dc613179cdc67adf3c477271346f8b75c2394837` / `packages/legacy_doc_parser` against standalone parser commit `08296edbee08da013a8ff718798972552ccd03f7`. No repository was changed by this task. The plan uses Git objects at these immutable commits, independent of newer qualification-only heads.

## Result

- **53 additions, 3 modifications, zero deletions.**
- Current mirror: **1,780 tracked files**. Desired mirror: **1,833 files**, consisting of all **1,832 upstream tracked files** plus the maintained local `UPSTREAM.json`.
- All 1,832 upstream files and all 56 operation outputs have exact Git mode **100644**. There are no mode differences to reconcile.
- Planned payload total: **4,685,588 bytes**. Binary/archived evidence is copied from exact Git blobs without decoding or newline conversion.
- `pubspec.yaml` remains byte-identical. Its verified adaptations remain `resolution: workspace`, `lints: ^6.0.0`, and `xml: ^7.0.1`.
- `UPSTREAM.json` retains all existing keys and patches text; only its commit changes from `ea82b13dcb0abbd151995cb7d2881789ed137286` to `08296edbee08da013a8ff718798972552ccd03f7`.

| Operation | Product or modified path | Git mode |
| --- | --- | --- |
| add | `test/compound_directory_recovery_test.dart` | `100644` |
| modify | `UPSTREAM.json` | `100644` |
| modify | `doc/evidence/storage-carving-reconcile-20261115/qualification-status.md` | `100644` |
| modify | `lib/src/conversion.dart` | `100644` |

The other additions are 52 files under `doc/evidence/storage-carving-reconcile-20261115/`. `inventory.tsv` is the complete operation list with exact old/new blob identities, modes, byte sizes and SHA-256 values. `plan.json` contains the same structured operations and explicit payload provenance. Full before, upstream, and desired manifests are supplied separately.

## Existing local customization audit

Relative to the currently declared parser pin, there are **no undeclared modified files, product source changes, or mode changes**. The only modified file is exactly the documented package declaration adaptation. `UPSTREAM.json` is the sole extra tracked local metadata file.

There is one completeness exception: the current mirror omitted six historical tracked `.log` evidence files already present at its declared upstream pin. These omissions are not product changes, but they must be restored for a complete source/docs mirror. Their paths are:

- `doc/evidence/storage-carving-reconcile-20261115/baseline/stderr.log`
- `doc/evidence/storage-carving-reconcile-20261115/dependency-setup/stderr.log`
- `doc/evidence/storage-carving-reconcile-20261115/dependency-setup/stdout.log`
- `doc/evidence/storage-carving-reconcile-20261115/focused-fixed/stderr.log`
- `doc/evidence/storage-carving-reconcile-20261115/strict-analysis/stderr.log`
- `doc/evidence/storage-carving-reconcile-20261115/strict-analysis/stdout.log`

`omitted-log-ignore-rules.txt` records that the mirror's inherited `*.log` rule ignores those paths. The plan restores them; staging therefore uses explicit forced addition of only the 56 planned paths when `--stage` is requested.

## Apply after canonical qualification releases its source freeze

The guarded script defaults to read-only validation:

```bash
python3 /workspace/scratch/0b93849cdeb9/parser-mirror-plan/apply_plan.py
```

The read-only checks passed against the current working tree. It verifies the mirror's current HEAD subtree still matches the audited anchor; rejects staged or untracked source changes; verifies every tracked preimage byte and mode; refuses occupied additions; and validates each payload against the pinned source Git blob, byte size and SHA-256. This allows unrelated Quds commits while rejecting any intervening parser-mirror edit.

When the parent is ready to apply and stage this exact plan:

```bash
python3 /workspace/scratch/0b93849cdeb9/parser-mirror-plan/apply_plan.py --apply --stage
```

The script changes only the planned mirror files, preserves source modes, leaves ignored package caches/locks intact, and verifies all 1,833 desired file identities. It does not resolve dependencies, run tests, commit, push, or alter other Quds paths. Follow with the intended canonical validation/commit process.

After application, read-only full-tree verification is also available:

```bash
python3 /workspace/scratch/0b93849cdeb9/parser-mirror-plan/apply_plan.py --verify-after
```
