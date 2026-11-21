# Final reconciliation with completed Word main

## Accepted source and bounded repeat

Final source checkpoint `4034c7e7d384ed1f947d1702b4c2cf5231b7d3d1`, Git tree
`1e21f3c97cc7e37ff55f8302f668e05276fe9d6d`, merges the completed Word main
`9f23cbd2be72c527829b3990f22b356e5237ed96` into the already qualified Zotero,
Word and Mail integration.

The only two recorded source differences from the accepted `5289b90` checkpoint
are the header/footer guard and its unselected macro test. Every other one of
the 2,994 recorded source paths remains identical. The Mail Close fix is already
identical on both sides, and our saved-Mail global-Close regression is preserved.

| Repeated original suite | Passed cases |
| --- | ---: |
| Word table grid addressing | 22 |
| Word bookmark fidelity | 17 |
| **Total** | **39** |

The process exited zero, reported one successful terminal event, and completed
every started case exactly once. There were no failures, skips, JSON/runtime
errors or stderr bytes. Loading events are excluded. All 39 suite/name
identities match both the original 2,551-case qualification and the subsequent
151-case combined run; this repeat adds zero new distinct cases.

The [execution receipt](replay-qualification.json), [source-impact proof](impact-review.json),
and [independent acceptance](final-independent-review.md) retain the bounded
acceptance. All 2,994 inputs match the final Git commit, including executable
modes, and their before/after maps are identical. Recorded runtime files also
remain unchanged. The final canonical source-map SHA-256 is
`9ce3a43c7b6708a6f2be62843fc4eb037208a01ec8e2e5d24075eaf1bfb19c42`.

## Relationship to the previous qualification

All 119 originally selected test files remain unchanged. Relative to `5289b90`,
117 selected dependency closures are unchanged; only the two Word fidelity
suites reach the newly changed guard. Its import declarations are unchanged.
Both selected Node closures and the Studio closures remain unchanged, so no
Node, Studio, Mail or full 119-suite repeat is claimed for this last delta.

The earlier qualification remains preserved in two unchanged archives:

- Original 2,551 distinct cases in 119 suites, plus a separate overlapping
  121-case Node execution and 21 independent ownership probes.
- The 151-case combined-source execution, including 72 repeats from the
  original population and 79 saved/workspace Mail cases.

This final 39-case run is a third, explicitly overlapping execution record.
Counts are not added into an inflated grand total. The incoming completed Word
qualification remains in its own main history and validation folder.

## Reproduce the source/evidence verification

[evidence.tar.xz](evidence.tar.xz) retains the final runner, selection, raw events,
process exit, source/runtime snapshots, exact overlap audit, impact review,
independent acceptance and captured-history replay.
[evidence-index.json](evidence-index.json) hashes every archive member.

From the repository root:

```bash
python3 docs/validation/zotero-table-cell-ranges-20261121/verify_evidence.py \
  --repo . \
  --bundle docs/validation/zotero-table-cell-ranges-20261121/final-word
```

This checks the latest complete recorded source map. Use `--archive-only` after
future source changes. The two earlier bundles retain their original source
maps and intentionally do not assert that all bytes stayed identical through
later Word/Mail updates.

The impact replay supports `--combined-ref` to verify the saved-Mail regression
and exact two-path final delta against a committed merge. Its historical
planning status is distinct from the completed execution/independent acceptance
stored alongside it.

## Publication and captured history

The [final intake replay](intake-replay.json) accounts for all 341 later-captured
external heads at this final source: 317 ancestors, 24 verified historical
equivalents and zero uncovered entries. The earlier 338-head inventory is
already covered by an ancestor, and the later Word main is incorporated by
actual merge ancestry. Historical cutoff failures remain unmodified.

[PR #293](https://github.com/CrispStrobe/quds_office_suite/pull/293) publishes the
final evidence and reconciliation. PR #289 was automatically closed when
PR #291 incorporated the original Zotero implementation head. Final remote
main ancestry, tree identity and source/evidence verification are recorded in
the PR #293 publication receipt.

No GitHub Actions, workflow/check/status queue was queried or awaited.
Installed Word/LibreOffice/Zotero plugin acceptance, direct active ODT input,
cross-cell replacement and incoming nested-table content remain explicit
roadmap work; these local runs do not claim complete plugin parity.
