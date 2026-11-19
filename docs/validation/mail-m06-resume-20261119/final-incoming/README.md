# Final incoming cutoff

Origin branch and PR advertisements were captured once, finishing 2026-11-19 06:20:51 UTC. The separate upstream advertisement finished 06:20:52 UTC. The own continuation branch and PR 172 are excluded. There are 389 external refs; upstream is unchanged.

Two external branch/PR pairs advanced since the initial capture:

- Notes / PR 175: `8a5dd9baa1884beae3ae69cfe77946adab9d07a6` to `c320f28347f1cd292b848be2cf72998d41f8a6ac`.
- Thesaurus / PR 174: `39843ed4874c7b56572c7aa8195716e5892aeca2` to `df62b58975bab1f650879fc88f850550a3df5c13`.

These are exactly two new commits. Their 68 changed paths are all under `docs/validation/`: qualification reports, audit inputs, screenshots and evidence archives. Product source, tests, tools and manifests are unchanged. Independent `git merge-tree` checks against `8aa0e6cbe16414bc291f8b285c1d89e59bec5af3` found no conflicts for either head. The changes touch separate evidence directories.

Recommendation: merge both captured heads. No further product qualification is needed because of these documentation/evidence deltas; the independently changed Mail transport and runner still require their own planned gates. The incoming claims are preserved as historical evidence and do not stand in for the current source's local checks.

`before-final-integration.json` deliberately reports the four advanced branch/PR advertisements as not yet integrated. After merging, run the saved `audit_refs.py` with `--repo` and the merged `--head` to recheck all 389 refs and all 14 historical equivalence proofs. No further remote refresh is needed for this cutoff.

`baseline-published-readback.json` independently confirms the immutable remote commit `fdf4b1ed5fdd252ffd5519d7b8a52c19ebd0c68f` and tree `b07269953548a39fa8bb7bfad4c1901351b4c701`.

## Post-integration verification

The two captured heads were merged locally at `9e084d9495e16628ca7365a3e3fce56486d3ae69` and published canonically at `faab20b96e4a51fd6e3cf1a80b1439c4a1b01b9c`. Both have tree `d780ffff2bcdd9cb880d94e1105fac5079e3b8e5`, independently confirmed through the connected GitHub API. `published-readback.json` records that immutable remote verification. `post-integration-audit.json` accounts for all 389 external refs and both new commits. Historical equivalence proofs were reverified locally, with no additional advertisement refresh.

`post-integration-source-verification.json` confirms that the merge delta contains validation documentation only. All 4,537 package tree entries outside the intentionally changed Mail core/store packages are byte/mode/path identical to `479e1e038af0467b7f07b35d80bac9e4cc60a198`. The five specifically preserved Office/Notes files also match exactly; the third-party tree and root pubspec remain identical at this point. Intentional Mail flags and runner changes are enumerated separately in that receipt.

No GitHub Actions or CI state was queried or awaited. This audit establishes the captured frontier only and makes no claim about remote advances after the cutoff.
