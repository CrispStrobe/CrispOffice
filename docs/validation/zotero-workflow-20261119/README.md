# Zotero workflow extension — 19 November 2026

## Scope and preservation

Work starts from fork main `2170791c9250d72c9df31a065408365f9b50abaa`.
The recent `integrate/recent-pptx` commit
`5c3f9d7fd4531dfac7c0e49fba1827c39e17caf6` was brought in first by fast-forward.
The working branch is `codex/zotero-workflow-20261119`.

The initial audit covers current fork branches, all 216 PR heads and upstream
refs. Existing historical patch-equivalence proofs were recomputed; their old
heads do not need to be reapplied. See `initial-reconciliation.json` for exact
refs and proof results. A fresh remote check is required before final merge.

This increment adds:

- Searchable, paginated library/collection tag browsing with staged filters.
- Offline navigation from a cited source to its document citation occurrences.

Validation is in progress. No test success is claimed by this checkpoint.
Implementation, tests and qualification will be saved in incremental remote
commits. GitHub Actions will not be queried, polled or awaited; checkpoints use
`[skip ci]` as requested.

## Completed local checks at the current checkpoint

Source `780422316b4e37989e01ac871dd2956fbd2c8908` passes 602 Zotero engine,
584 Zotero editor, 23 PPTX engine and 10 PPTX editor cases. The independent
audit confirms all 75 selected files, all 2,048 input hashes and no failures,
skips, errors or unfinished cases. Incoming Mail passes 219 host and 6 transport
cases, with its own source bindings. The VBA qualification and final formatting
normalization are still in progress. Startup/compiler attempts are retained
separately and are not accepted results.
