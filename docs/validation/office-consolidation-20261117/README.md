# Office consolidation — 17 November 2026

This continuation starts from `93c832f53982a9f5956f19ae0cb9418f55fac8c0` and
is saved incrementally to `codex/office-consolidation-20261117`.

## Scope and current state

First integrate the fixed incoming branch/PR snapshot, including upstream,
then reconcile and locally validate the combined Office and proofing source.
The original source histories and source-bound evidence remain preserved.
GitHub Actions, workflow, check-run, and commit-status endpoints are not used.
Checkpoint messages include `[skip ci]`.

The [incoming snapshot](incoming-snapshot.json) records 268 external named
references and 179 distinct heads observed on 17 November 2026 at 18:36:23
Berlin time (17:36:23 UTC). The destination branch is excluded from that count.
New arrivals after this snapshot will be recorded separately from the source
qualified in this continuation.

Initial review identified required checks for custom-tab style identity,
minimum table row heights, numeric dimensions, and cell fill validation.
The recovered PAGE, paragraph-decoration and structured-frame repairs must
remain active while integrating the newer work.

This is an initial recovery checkpoint. No fresh product-test pass is claimed.
