# Word VBA continuation: captured remote intake

Repository: `CrispStrobe/quds_office_suite`.
Initial main: `aa861c28e336b17bcd4c259351164380cd6b1438`.
The inventory records 44 fork branches, all 339 PR heads, and all four
`MohammedAsaadAsaad/quds_office_suite` upstream branches. A follow-up fetch
added `codex/zotero-note-layout-20261121` at the initial main commit, for **388
captured refs**. No GitHub Actions/check/status queue was queried or awaited.

## Work requiring integration

1. Open PR #333, `codex/zotero-odt-roundtrip-20261121`, head
   `c0ae75c226b13ae1ec4ab31238004d558ad01531`: five commits ahead of initial
   main. Its delta is validation/evidence plus
   `packages/quds_office_editor/test/word_page_text_cache_test.dart`.
2. `codex/zotero-roundtrip-complete-20261121`, head
   `a7f69313ed2e610f82242c31be8ad5387ae5cea0`: five different commits ahead
   of initial main. Its delta is documentation/evidence, the engine changelog,
   and `packages/quds_office_editor/test/word_page_text_picture_cache_test.dart`.

Neither tip changes production implementation files relative to initial main.
The latter branch's earlier renderer correction is already preserved in the
completed Word Font.Position/main history. `git merge-tree --write-tree` finds
one conflict when combining these tips: the introduction of
`docs/validation/zotero-odt-roundtrip-20261121/README.md`. Preserve both the
"Latest integrated qualification" and "Combined-source completion" sections,
which describe distinct source-qualified execution cohorts. Both editor cache
test files should be retained and executed with the current renderer tests.

All other captured current fork branch heads and all four upstream branch
heads are ancestors of PR #333. All but 14 historical PR heads are ancestors.

## Historical PR replacements

`historical-proofs.json` independently rechecks the 14 old PR heads that were
replaced in prior history. Thirteen have identical complete Git trees to
replacement commits already in main. One (PR #140) has exact equality of every
path changed from its recorded base against the replacement. These equality
checks were rerun using local Git objects; they are not assumptions based on
old prose. Re-merging the replaced commits would reintroduce obsolete history.

Once both outstanding tips above are included, the captured inventory should
be covered by **374 ancestor refs and 14 verified historical equivalents**.
This is a captured frontier in an active repository; later remote advances
need their own follow-up record.

## Replay

`remote-inventory.json` records the exact remote heads and PR metadata.
`replay_intake.py` recalculates ancestry and all equivalence proofs against a
specified final head:

```bash
python3 replay_intake.py --repo /path/to/quds_office_suite \
  --inventory remote-inventory.json --proofs historical-proofs.json \
  --head HEAD --output final-intake.json
```

It exits unsuccessfully if any captured head is uncovered. The initial
ancestry snapshots are diagnostic artifacts of the pre-integration state;
the final replay is authoritative for the integrated result.
