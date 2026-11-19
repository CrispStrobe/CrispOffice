# Office integration for remote main — 19 November 2026

This continuation integrates the latest captured branches and pull requests,
saves remote checkpoints, and qualifies the new Mail flags/schema increment
before merging into `main`. GitHub Actions are not queried, dispatched or awaited.

## Preserved work

The starting head is PR #174 at `df62b589`. Remote checkpoint `a9e417d3` merges
Mail `fdf4b1ed` and its Zotero `17ec8cc8` ancestry. Checkpoint `f38959f0` also
merges the final Notes `c320f283` evidence. All four open PR heads are ancestors.

The five reviewed Notes source/test/changelog paths retain the exact qualified
`df62b589` bytes: stable Review layout, focus/selection/composition, tracked and
untracked IME/undo behavior, and the stronger tracked-revision assertions. The
incoming alternate Notes changes add a redundant pane key or change equivalent
test fixtures, comments and ordering. All newer Notes and Zotero evidence is
retained. No Office/Notes/Zotero application or test source changes from the
previously qualified `39843ed4` source.

The new application increment is `c2db80d4` from Mail: nullable durable standard
flags and transactional schema-v3 migration from v1 or v2. An omitted snapshot
preserves observed flags; an explicit empty snapshot clears them. The incoming
four test files are formatted without changing their behavior.

## Qualification scope at this checkpoint

New Mail behavior is **pending execution**. The complete `check_store.py` gate
will run core/store VM and Node tests, strict analysis, formatting, launcher
controls and browser-entry/worker compilation. The committed consumer plan
adds all six MIME suites and four Mail UI suites on the final integrated source.
Runtime recovery uses the verified Flutter 3.47.8 / Dart 3.13.7 release, locked
dependencies and a genuine SQLite native-assets smoke run.

The prior [2,018-case / 129-suite qualification](../thesaurus-20261118/resumed-20261119/README.md)
remains attributed to source `39843ed4`. Historical Notes, Zotero and Mail
results retain their original identities and are not added to any new total.
Final results and independent audits will be saved in this directory.

## Remaining release acceptance

Actual offline-browser lifecycle/CSP/performance, installed Studio and real
OS/IME/live Zotero interoperability, and independent English/German linguistic
judgments remain open. This user-authorized integration into main does not
claim those release checks passed. The linguistic packet remains `not_reviewed`.
