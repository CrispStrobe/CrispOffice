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

The flags increment passed at `ebe0498a`: **261 test executions / 191 distinct
scenarios**, including 199 core/store executions and 62 MIME/UI cases. Strict
analysis, formatting, 42 Mail runner controls and browser-entry/worker compilation
passed. Raw logs, receipts and the independent audit are saved in [flags/](flags/)
and [review/fresh_mail_review.json](review/fresh_mail_review.json).

A later bounded refresh captured Mail `fa284f22` and Zotero `5107eff6`, including
new native IMAP transport and shared protocol lifecycle changes. Checkpoint
`3c66d76b` integrates these without changing the earlier qualified flags or Office
source. Additional transport qualification is **pending execution**. The new
[32-suite plan](transport-plan.json) covers transport VM/Node, IMAP/POP/SMTP
regressions, MIME and Mail UI. The full core/store gate will also run again.

Three narrow parser repairs preserve the FormatException subtype contract,
require one canonical FETCH root, and reject repeated field lists in strict mode.
The new regression suite preserves exact literal bytes and failure latching.
Legacy non-strict iteration is unchanged; failed reproductions are retained in
[diagnostics/](diagnostics/).
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
