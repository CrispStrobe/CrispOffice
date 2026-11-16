# Final pinned incoming snapshot

The last incoming inventory for this continuation is fixed at **2026-11-16
20:10:54.959 UTC**. It contains **185 branch and pull-request references**:
92 branches and 85 PR heads in `CrispStrobe/quds_office_suite`, plus four
branches and four PR heads in `MohammedAsaadAsaad/quds_office_suite`.
References can point to the same commit; 185 is a reference count, not a count
of independent changes or unique commits. Later arrivals are outside this
cutoff.

The authoritative pins are the `refs[].sha` values in
`final-remote-snapshot.json`. Its top-level `branch_head` is inherited metadata
from an earlier observation; it is not the rendering branch at this cutoff.
The refs array correctly records the rendering branch and PR #72 at
`f23675a4e6443c2958d0eef274bc3e301e6ff201`. The original snapshot is retained
without rewriting historical metadata.

## Source integration

Pinned main `63194d8e482892f284eaccb95ce48a8a8132376d` supplies worksheet
page-setup modeling/serialization and ODS header/footer round-trips from
PRs #80–84. It changes eight code, test, and documentation paths. The seven
feature/documentation/vendor aliases are matched to canonical main commits
by stable Git patch ID **and** exact full diff bytes after removal of Git
index lines only. The two vendor trees include inherited unrelated history;
their whole trees are not asserted identical to main.

The remaining pinned ancestry reduces to four independent tips:

| Incoming work | Pinned commit |
|---|---|
| English hyphenation | `377e312a2fd4a0d5e87b7abbe8f464aaedf9b15b` |
| German quality | `3ebe347f8d3c9577d44ac51b1f1fc92a544f1bf4` |
| Zotero recovery | `b87f9d6c3a2532c9695024adf48ca9fbd3c0927a` |
| English/German and Harper integration | `bdd752e01b4c97cf0cd1248af8a4e544f18ea863` |

Main and these four tips were merged with real Git merges, all without
conflicts, producing local commit
`765438f6de643b7162ec6c4d2aab9a54703515e8` before final formatting and
qualification. `final-integration-provenance-review.json` checks every
snapshot pin against that local commit and also against the saved rendering
checkpoint `bc195165` plus the four incoming parents. The separately published
checkpoint uses those parents and the reviewed final tree. Its final ancestry
receipt must check the published commit itself. Ancestry alone does not
establish correct merged contents; the source-bound local gates qualify them.

`format-normalization.patch` preserves the exact Dart formatter changes to
nine incoming code/test files, separately from incoming semantic changes.

Zotero recovery introduces no different rendering implementation. Its eight
ODS/documentation blobs are exactly those of pinned main. The only unique
additions beyond the already saved rendering work and pinned main are its
recovery README and incoming-ref inventory. Its older rendering CHECKPOINT
is inherited historical text and must not replace current qualification.

## Recovered evidence and runner changes

The rendering continuation at `5ed98a033b8d2efe24778649f190d559df3d5f74`
adds 55 evidence/runtime files and modifies the CHECKPOINT and validation
runner relative to its proper common base `3a8306e`. It changes no production
or test source. Comparing it to an older base would also show already
integrated ODS and test-fixture changes and would misclassify those as new.

Its historical editor receipt records 66 passing tests plus strict analysis
and formatting, with 462 unchanged input hashes, at source heads `59b69ac`
through `6bf486e`. The review independently verifies all six compressed
stdout/stderr log hashes against that receipt. This evidence is preserved
with its original source attribution. Its overlapping test count is not
added to a newer cohort's count or represented as validation of later source.

The runner adds the ODS reader and legacy-reader tests, progress every
60 seconds, 900-second test/analyzer and 120-second formatting deadlines,
process-group cleanup on timeout, and explicit timeout metadata. Final
cohorts retain these changes while adding the focused regressions required
by the incoming proofing and worksheet changes. The recorded
`validate-used.py` in each evidence directory remains the exact runner used
for that particular run.

The proofing-recovery tip `738f0b6a3f1f46f83585579291d0847613d780c5`
contributes five evidence files and no production or test changes.

## Evidence map

- `final-remote-snapshot.json`: original cutoff, counts, ref pins, and changes
  since the earlier 166-reference snapshot.
- `final-ancestry-before-integration.json`: initial missing ancestry and four
  independent incoming tips; its failing pre-integration status is expected.
- `final-ods-equivalence-local.json`: complete local patch/blob equivalence
  review. `ready_for_ancestry_only_merge: false` describes the pre-main source
  and is not a license to omit real incoming changes.
- `final-overlap-review.json`: initial Zotero, rendering-continuation, and
  proofing-recovery overlap classification.
- `final-integration-provenance-review.json`: independent candidate-parent
  coverage, Zotero/main exact blobs, and historical editor-log verification.
- Final source-bound receipts and final ancestry evidence state the actual
  integrated commit, test outcomes, and current source bindings.

GitHub Actions were not queried, awaited, polled, or rerun. Local gates and
explicit evidence supply qualification; remote checkpoints use `[skip ci]`.
