# Quds incoming-history audit, 2026-11-22

## Captured baseline

`b38f2e38369855056eb9e23792f83fd1ab86ea24` is the pinned initial `origin/main`.
The independently replayed inventory contains **414 local fetched references**:
388 exact ancestors, 24 verified equivalents, and two heads requiring integration.
The four upstream branch tips are also exact ancestors of the pinned baseline.
No GitHub Actions workflow, check, status or queue was queried or awaited.

`audit.json` records every ref/SHA/disposition and independently reproduced
historical equivalence proofs. A reference being old or having a similar patch
was not accepted as evidence. For full-tree cases the historical source and
included replacement tree SHAs are equal. For changed-path cases the source's
complete changed path set exactly equals the included replacement's blobs.
All replacement commits are ancestors of the pinned baseline. There are
15 unique historical heads represented by 24 historical refs. They must not
be replayed over newer source.

## New work to retain

- `codex/mail-identity-reconciliation-20261122`,
  `8da0e8385794e4ec0af10cd4fbd4d489f98acb01`: six commits ahead, typed
  authoritative move receipts, sync revision fences, durable cache reconciliation,
  guarded provider/host integration and focused regressions.
- `codex/word-vba-range-suffix-20261122`,
  `ab7fb01999efab093f2d5c81c9c328bb2c16a41c`: eleven commits ahead,
  partially shared Mail history, independent projection guards/regressions,
  and Word VBA table-cell suffix/InsertAfter authoring support.

The heads have two merge bases: the initial main and shared Mail implementation
`9b3b6378dc3f80040e1e2a0ab206600ac5a528bc`. Neither topic head supersedes
the other. Retain both histories through a normal merge, including both
families of tests.

## Reviewed integration

The parent merged identity first, then range-suffix. A read-only review of that
staged result found no lost behavior. The only executable Mail delta against
the identity head is the intended bounded destination-view metadata scan and
folder display-name quota accounting. The backwards journal-clock check,
quota/savepoint fallback, schema future-version fixtures `[16, 17]`, old-schema
table cleanup, and all identity tests survive. The incoming Word source and
tests survive. Conflict resolutions preserve the identity branch's clearer
contract wording while retaining range-suffix executable fixes.

`git diff --cached --check` passed and no unmerged index entries remained.
Exact reviewed blob SHAs are in `audit.json`. This review is source inspection,
not a passing-test claim. Both initial topic qualification README files still
say implementation/local qualification is in progress. Run the integrated
Mail/Word regression cohorts locally before final publication.

The root must refresh remote heads/main/PRs before final publication because
concurrent work is active. This audit is a captured inventory, not a claim that
remote state will remain fixed.
