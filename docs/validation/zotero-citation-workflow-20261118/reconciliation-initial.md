# Initial incoming reconciliation

The fixed base `f6c0e167d9c1c7c0f7fc93073f2becacc7a44d48` contains the current observed document-review, Zotero, native-spelling, fork main and upstream main histories.

- **377 incoming refs / 243 distinct heads**: 204 fork branches, 165 fork PR heads, four upstream branches and four upstream PR heads. Our new implementation branch is excluded.
- **349 exact ancestor refs**; 28 legacy equivalent refs, independently reverified by patch equivalence, identical tree, or changed-file blob identity against an integrated ancestor.
- **0 unaccounted refs**, 0 fetched/advertised mismatches. No additional merge is needed at this cutoff.
- Observation started at 2026-11-18T15:53:40.888188+00:00; completed at 2026-11-18T15:53:51.589696+00:00. This is a fixed incoming cutoff, not a claim about later remote activity.

## Included newer work

The base includes PR #165 at `8d74db5d`, PR #164 at `fb1fd4dc`, native-spelling evidence at `04be224b`, and the later document-review work through `f6c0e167`. The newest document-review checkpoint adds its incoming audit only; the prior live-review implementation and validation remain intact. The exact changed refs and commits are in [the machine-readable audit](reconciliation-initial.json).

The 14 nonancestor heads (each represented by a branch and PR ref) are preserved as already integrated equivalents. Their recorded checks were freshly repeated against this base; no historical branch was remerged solely to make its commit ancestry appear complete. In particular, PR #140's 37 changed files match its integrated equivalent and that equivalent is an ancestor.

No GitHub Actions, check, workflow or CI-status endpoint was queried, awaited or dispatched. This audit did not mutate the working branch, product source or remote refs.
