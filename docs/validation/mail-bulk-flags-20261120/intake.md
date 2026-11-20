# Foreground bulk flags: incoming source audit

Status: **PASS** for `3645e8a4db535fc0ab5ab0923ee7385e5c4e5195` with tree `0df4f1db0f920cf3adf3c5abcf8e22abdd8ee007`.
The frozen source inventory has **zero uncovered references** and **zero
unavailable objects**. This is an ancestry and historical-equivalence check;
[reconciliation.md](reconciliation.md) records deliberate choices between
overlapping implementations, and [README.md](README.md) owns runtime acceptance.

## Captured scope and cutoff

The fork is `CrispStrobe/quds_office_suite`; the upstream repository is
`MohammedAsaadAsaad/quds_office_suite`. The final complete API capture, v6, is
fixed at **2026-11-20T20:58:00.677Z**. No continuously advancing branch is described
as permanently current. Later publication-time checks of `main` belong in the
publication supplement, without rewriting this captured evidence.

| Source category | Captured heads | Direct ancestors | Verified historical equivalents |
| --- | ---: | ---: | ---: |
| Fork branches | 38 | 29 | 9 |
| Fork PR heads | 274 | 260 | 14 |
| Upstream branches | 4 | 4 | 0 |
| Upstream PR heads | 4 | 4 | 0 |
| **Total** | **320** | **297** | **23** |

Branch pagination returned 38 fork and four upstream entries. Fork PR
pagination returned 100, 100 and 74 entries; upstream PR pagination returned
four. Every final page was shorter than the requested 100 entries, and each
category's page total equals its unique ref count. The complete inventory,
open-PR metadata and v5-to-v6 head changes are preserved in
[remote-refs.json](remote-refs.json). The machine result in
[intake.json](intake.json) binds its exact bytes, the normalized inventory and
the historical proof source with SHA-256 digests.

The original intake checkpoint
`0cc6316c61efd8b39a9cb0cfed6b2879f7865d48` integrated the then-current main,
Word measurement and continuation work, and the concurrent mail intake history
before the new bulk implementation. Remote work continued during implementation;
the final source reconciliation includes the later captured heads below.

| Ref at the fixed cutoff | Captured commit |
| --- | --- |
| `main` | `b6657785b9de0943d2008b4883187a94f05bc514` |
| `codex/word-vba-compatibility-20261120-continuation` | `8c54d5283804099f9c9023540921f2410b878eb1` |
| `codex/word-vba-measurements-20261120` | `cd306bdea352c6f6400b5d1af7cc33e737004462` |
| `codex/word-vba-unit-conversions-20261120` | `ba6b170c1e011853128af6dcb9333ae9e22e79a1` |
| `codex/zotero-parity-20261120-next` | `835b8019cbb873c72424e63d4df292174edd3c3e` |
| `work/mail-bulk-actions-20261120` | `639ea75a813d558cb5a1a848a6242fbf17bcf0c3` |
| `work/mail-bulk-flags-20261120` | `3b753b0251d5dffe1b5b3e1496748f39caba8587` |

The frozen PR inventory includes PR #271's final compatibility head
`8c54d5283804099f9c9023540921f2410b878eb1`, PR #272's measurement head
`6d370884cd2b62ae83e627d9e71809ae9d795684`, PR #273's concurrent mail head
`639ea75a813d558cb5a1a848a6242fbf17bcf0c3`, and PR #274's continuation head
`cd306bdea352c6f6400b5d1af7cc33e737004462`. Branch and PR heads are audited even
when another branch already contains the same work. Captured PR state is
historical metadata; it is not a claim about a later publication state.

## Recent work reconciled

- **Main and maintenance history.** The starting `c954d00d` continued the prior
  header-search milestone (`0ff83fd3`) with Word validation evidence. The retained
  maintenance history was joined without restoring the deliberately retired
  temporary golden-regeneration workflow. Later main advances through
  `b6657785` are ancestors of the checked target.
- **Word measurement continuations.** Physical-unit conversions, official named
  arguments, finite-result handling, large-scalar regression cases, examples,
  independent test suites, portable drivers and qualification records from the
  concurrent branches are retained in the reviewed union. Retained reports are
  evidence of their authors' runs; the acceptance record separately identifies
  tests actually rerun for this integration.
- **Zotero preparation.** The captured `835b8019` is a reconciliation checkpoint,
  with Zotero intake records and known Word/mail histories. It adds no new Zotero
  runtime capability. Its renamed/combined Word evidence is accounted for in
  [zotero-intake-mapping.json](zotero-intake-mapping.json).
- **Concurrent mail bulk work.** Review began at `b60c0ec2`, continued through
  `9109fcc6`, and includes the final captured `639ea75a`. One coherent dispatch
  engine, typed mutation evidence, single-use compatibility coordinator, frozen
  menu selection, refresh rules and host-owned receipts are retained. The
  selected public UI contract remains `selectionRevision`, `bulkEnabled` and
  `bulkStatus`. Incoming aliases were adapted at call sites instead of creating
  competing contracts. Exact retained core test blobs and the intentional UI
  assertion changes are documented in [reconciliation.md](reconciliation.md).
- **Useful incoming acceptance cases.** Peer tests added real open-popup
  invalidation, popup direction/scale assertions, reader-preserving subset
  dispatch, caller-list mutation, stale identity and lifecycle cases, explicit
  no-mutation outcomes, and localized selection/progress visual probes. The RTL
  popup and disposed native callback cases exposed real defects before their
  bounded fixes; the original failed logs remain in the acceptance evidence.

An incoming head's ancestry means its history was brought into the integration.
It does **not** mean every overlapping source line was retained unchanged. The
reconciliation record explains replacements, compatible APIs, independently
preserved tests and stronger accepted behavior. This avoids reintroducing a
second command engine or silently attributing another branch's validation to the
final implementation.

## Historical replacements

All **14** existing replacement proofs were independently recomputed from Git
objects at the checked target. Thirteen pairs have identical complete trees.
The remaining pair is the prior ODT continuation
`c34945761e7991f5fe49037d79529acdd260b31c`, whose exact 37 changed paths match the
accepted ancestor `2c47165d01d01cc883135a434ac9f6591ce6e770`.

For every proof, the checker rederives the changed-path inventory from its
comparison base, compares mode/type/object IDs, verifies each recorded entry and
tree ID, and requires the replacement to be an ancestor of the target. Those
older branches need no replay. The 14 proofs account for 23 captured refs because
some replacement heads appear in both branch and PR inventories.

## Replay

From the repository root:

```sh
python3 docs/validation/mail-bulk-flags-20261120/verify_intake.py
```

The command replays the committed inventory against the bound target and checks
that the result exactly matches `intake.json`. It queries no network service,
changes no Git refs and disables Git lazy fetching. Missing ancestry objects or
uncovered heads fail the audit rather than being assumed included.

For a later explicit intake, obtain a new complete paginated snapshot and fetch
its objects first, then run:

```sh
python3 docs/validation/mail-bulk-flags-20261120/verify_intake.py \
  --capture --snapshot /absolute/path/to/remote-snapshot.json \
  --target <reviewed-commit> --output-dir /absolute/path/to/new-report
```

Capture writes only `remote-refs.json` and `intake.json`; human reconciliation
notes remain separate. The v6 inventory in this milestone is intentionally fixed.
**GitHub Actions, workflow runs and status endpoints were neither queried nor
awaited.** Local acceptance and source inclusion are the publication evidence.
