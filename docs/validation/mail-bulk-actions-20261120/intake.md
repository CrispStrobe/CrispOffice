# Mail bulk actions: source intake

This is the **pre-reconciliation intake snapshot**, completed at 2026-11-20 20:23:39 UTC. The reviewed remote `main` is `c954d00d2fc85604ae394674bca91ea8a1dede0e`. The report identifies one outstanding branch commit and describes the intended resolution; it does not claim that resolution has already happened.

## Captured references

| Source | Captured heads | Disposition |
| --- | ---: | --- |
| Fork branches | 33 | 23 are main or covered ancestors, 9 retain the prior historical-equivalence proof, 1 requires reconciliation |
| Fork pull requests | 270 | 256 covered ancestors, 14 retain the prior historical-equivalence proof |
| Upstream branches | 4 | Same heads as the previously accepted inventory |
| Upstream pull requests | 4 | Same heads as the previously accepted inventory |

GitHub returned no open pull requests in either repository. The upstream repository is [MohammedAsaadAsaad/quds_office_suite](https://github.com/MohammedAsaadAsaad/quds_office_suite); its four PR heads are #1, #5, #6 and #7.

The complete head inventory, per-reference classification, observed PR metadata, direct comparison results and the exact exceptional patch are preserved in [intake.json](intake.json). Reads were collected over this session rather than atomically.

## What advanced since the handoff

Current main is six commits ahead of the user’s recorded `0ff83fd3647096477a701430d372904ee5b0cdd7`, with zero commits behind. The API comparison reports exactly seven added paths under `docs/validation/word-vba-paragraph-controls-20261120/`: checkpoints, the development evidence archive and its two manifests, publication deferrals, source review and a publication-scope verifier. There is no product or test-file delta in that comparison.

Seven fork branch heads changed relative to the earlier frozen source intake:

| Branch | Observed head | Relation to current main |
| --- | --- | --- |
| `codex/word-vba-paragraph-controls-20261120` | `90ecd41c8a3ef2a6f35967f1219223022e2b0d32` | Ancestor, directly checked through the comparison API |
| `codex/word-vba-paragraph-spacing-20261120` | `d30299dd91634ad7e20c32db5c39a6687fcef4aa` | Ancestor, directly checked |
| `feat/settings-arweb-20261120` | `e8db6b3f21401f8c6ac4dae4c2934edde8699f4b` | Ancestor, directly checked |
| `fix/main-green-20261120` | `332d7b26a320ca560f4f2214e1e63da9392269ab` | One unmerged commit, described below |
| `integrate/recent-pptx` | `c954d00d2fc85604ae394674bca91ea8a1dede0e` | Identical to main |
| `main` | `c954d00d2fc85604ae394674bca91ea8a1dede0e` | Reviewed target |
| `work/mail-parity-20261120` | `540eb7a41554620e1405807ac1db9dc38bd62148` | Ancestor, directly checked |

Five PR heads changed since that frozen inventory: #263, #264, #268, #269 and #270. Every one is directly covered by the new main. PR #264’s merged head remains `1e723bd4bc96e07b1b790daf9b82897a846c6096`; its retained branch has the later WIP commit.

## One explicit reconciliation decision

[Commit 332d7b26](https://github.com/CrispStrobe/quds_office_suite/commit/332d7b26a320ca560f4f2214e1e63da9392269ab), titled “WIP: golden attribution matrix, parent commits”, is exactly one commit beyond merged `1e723bd4`. Its complete delta changes one SHA matrix line in:

```text
.github/workflows/tmp-regenerate-editor-goldens.yml
```

The comparison from `1e723bd4` to current main confirms that main deleted this workflow. The earlier mail milestone explicitly retired that temporary golden-regeneration workflow, and current main’s merge message also records the deletion.

**Recommended resolution:** preserve `332d7b26` as a reconciliation merge parent and retain main’s deletion. The new commit changes only diagnostic inputs to a deliberately retired workflow. Keeping the deletion avoids restoring that workflow or adding queue load while retaining the authored history. No product code is discarded by this resolution. The parent implementation agent must record the actual merge commit and verified tree after performing it.

## Proof boundaries

The earlier accepted [intake record](https://github.com/CrispStrobe/quds_office_suite/blob/c954d00d2fc85604ae394674bca91ea8a1dede0e/docs/validation/mail-header-search-20261120/intake.json) is bound to target `1cf0c8e86403df8e48094cb6275cd697094b8015`. The comparison API now confirms that target is an ancestor of `c954d00d`: 15 commits ahead and zero behind.

The 26 unchanged fork branch heads, 265 unchanged PR heads and eight unchanged upstream heads therefore retain their previously recorded inclusion. The 14 distinct historical replacements—13 complete-tree identities and one exact 37-path ODT continuation—are **inherited evidence** from that prior record. They were **not independently recomputed in this turn**. Nine branch references and 14 PR references use those historical equivalents.

The distinctions in the JSON are deliberate:

- `api_verified_ancestor`: the current session directly compared the observed head to current main.
- `target`: the head equals the reviewed main.
- `inherited_ancestor`: the unchanged head was covered by the prior target, which the current session confirmed is a main ancestor.
- `inherited_historical_equivalent`: the unchanged head retains an earlier recorded exact replacement proof.
- `requires_reconciliation`: the new one-line WIP commit described above.

This source audit is not runtime qualification.

## Environment and instruction checks

The initial full clone transferred its Git objects, but checkout exhausted workspace storage. Fresh command and patch tools subsequently failed during sandbox startup with “No space left on device”. This prevented local Git replay and executable validation. The auditor made no local file or ref changes.

Remote code search for `AGENTS.md` found no results. Direct parent-path reads at the reviewed commit returned 404 for `packages/AGENTS.md`, the mail-core package/lib/src/test parent instruction paths, the mail-UI package instruction path, and `docs/AGENTS.md` plus `docs/validation/AGENTS.md`. The implementation agent separately checked root `AGENTS.md`. These are targeted checks; code-search absence is not an exhaustive recursive-tree proof.

**GitHub Actions, workflow runs, checks and status endpoints were neither queried nor awaited.**

## Publication follow-up

Before claiming complete intake, the implementation agent must record the actual reconciliation of `332d7b26`, refresh any advancing remote heads and retain the preserved-history resolution. The existing replay tool at `docs/validation/mail-header-search-20261120/verify_intake.py` can recheck a fresh Git ref capture in a working executor. This snapshot records the actual API evidence available here and leaves local replay explicitly pending.
