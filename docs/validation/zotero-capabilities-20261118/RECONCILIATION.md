# Zotero incoming reconciliation — 18 November 2026

**The Zotero continuation starts from current main `c8eca37d1639ac1d20efb83ba2e9da51981a3ad4`.** All incoming fork and upstream branch and PR heads were fetched and accounted for in this starting-point audit. No incoming Zotero implementation remains outside main.

## Inventory

| Source | Incoming refs |
| --- | ---: |
| Fork branches | 191 |
| Fork PR heads | 154 |
| Upstream branches | 4 |
| Upstream PR heads | 4 |
| **Total** | **353** |

These refs contain **230 distinct heads**. The newly created `codex/zotero-capabilities-20261118` branch is recorded separately, not counted as incoming work. All exact SHAs, tree identities and per-ref dispositions are in [reconciliation.json](reconciliation.json).

## Dispositions

| Disposition | Refs |
| --- | ---: |
| Alternate Office source; historical evidence preserved | 1 |
| Ancestor of a history with an exact full-tree equivalent in main | 35 |
| Direct ancestor of current main | 252 |
| Exact full-tree equivalent in main history | 56 |
| ODT fields retained by reviewed later spreadsheet successor | 2 |
| Separate alternate Office/spaCy continuation | 1 |
| Separate native spaCy draft branch/PR pairs | 4 |
| Union source superseded; historical evidence preserved | 2 |

## Product decisions

- All five older Zotero branches are direct ancestors of main: support (15 and 16 November), optimization, capabilities and recovery. Their source and history are already present.
- Office qualification #154 is merged into current main. Its civil-date repair, local evidence and historical recovery archives are included.
- Draft #139 (`6df76a0d`) and stacked draft #153 (`2e013f26`) remain separately owned optional native spaCy work. Their histories are fetched and preserved; this Zotero increment does not activate or merge their experimental product trees.
- The ODT field branch / #140 matches integrated successor `2c47165d` in all Word source and evidence. Its eight differing paths are later spreadsheet additions plus the corresponding backlog note.
- Office union branch / #150 has the same corrected Word/frame source as integrated successor `da9c956e`. Seven differing package paths are later spreadsheet changes. Its complete historical evidence directory is byte-identical on current main.
- `codex/office-resume-20261118` retains an older spaCy integration and alternate frame implementation. Its entire historical evidence directory is byte-identical on main. `codex/office-continue-20261118` remains a separate combination of guarded spaCy and the alternate frame implementation; its 22 evidence files remain on the original remote branch with their original source attribution.

The alternate Office decisions were already reviewed in [the prior source review](../office-local-20261118/remote-review.md) and [the prior branch reconciliation](../office-retry-20261118/reconciliation/reconciliation-branches/README.md). This audit rechecked exact refs, predecessor equality and preserved evidence instead of restoring obsolete product snapshots.

## Validation boundary

This is a Git source/history reconciliation, not a fresh product test pass. The new Zotero increment records its own local validation separately. No GitHub Actions, workflow, check or status endpoint was queried, waited on, rerun or dispatched. No existing branch was rewritten or deleted.
