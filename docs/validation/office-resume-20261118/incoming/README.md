# Incoming reference audit

This fixed snapshot captures 183 fork branches, 149 fork PR heads, four upstream branches and four upstream PR heads from local refs. The new continuation branch created by this session is excluded from incoming counts and recorded separately. No network or CI endpoint is used.

## Exact principal heads

| Source | SHA |
| --- | --- |
| main | `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` |
| gector_office | `205e913ec1525b5e5157a6f6d7ff84c883217e48` |
| office_union | `16c7b0fb48c72527645678b76e25b5c5cb7b9c22` |
| native_spacy | `e7c67f29b34f1c1909e51aa25997fc774bb8ac80` |

## Accounting

| Classification | References |
| --- | ---: |
| ancestor | 316 |
| exact_tree_equivalent_in_history | 22 |
| reviewed_later_spreadsheet_successor | 2 |

Total: **340 refs**, **222 distinct heads**.

The 22 equivalent refs are 11 branch/PR pairs with exact full-tree equality to commits in the integrated histories. The two reviewed exceptions are the branch and PR #140 at `c3494576`: their successor `2c47165d` differs only in seven later spreadsheet files plus the corresponding backlog documentation. All Word source and its evidence are identical. Exact paths and all per-ref proofs are in the JSON report.

All four principal product trees retain the AOT/RML removal. Native spaCy is a separate optional, default-off analysis package, with no registered grammar provider.

## Reproduction

```sh
python3 audit_incoming.py --repo /path/to/quds_office_suite --out /path/to/new-audit
python3 audit_incoming.py --repo /path/to/quds_office_suite --out /path/to/recheck \
  --inventory /path/to/new-audit/incoming-refs.json --integrated-head EXACT_COMMIT
```

The recheck uses frozen SHAs even when remote-tracking refs have advanced. It fails on missing objects, changed inventory counts, unaccounted refs, an unexpected successor delta, revived AOT product files, or absent principal ancestry in an explicit integrated head.
