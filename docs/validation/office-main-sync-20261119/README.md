# Quds Office final branch synchronization — 19 November 2026

This is the captured continuation-plan checkpoint from PR #177/#178. Its
pending statements remain historical observations. The
[current combined integration](../office-main-integration-20261119/README.md)
records completed qualification and subsequent reconciliation separately.

## Scope and checkpoint state

This continuation starts from remote `main` at
`55e262ef269634a0d618c0b5102dc9be5430a5f3`, after PRs #173, #174 and #175
merged. It preserves the remaining Mail qualification history, the
Socket-compatible TLS rejection cleanup, and the Arabic proofing roadmap and
bundle builder. The branch is saved incrementally before local qualification.
GitHub Actions are neither queried nor awaited.

The incoming integration head is
`c1dc63f934f81e22a41bafd98df1abf22ee6a053`. The subsequent Arabic head
`df98958045f8a63e26d827a819958ddaab13352b` records the upstream bundle publication
and corrected Hub metadata; both histories are retained.

## Changes under qualification

- A rejected direct TLS upgrade aborts its own current connection and clears
  connected/authenticated state before returning the original failure. The
  generation guard prevents an obsolete upgrade from aborting a new connection.
  Trust and hostname checks remain enabled.
- Real TLS rejection tests inspect client state before teardown can hide a
  failed cleanup. The core flag-value test explicitly exercises `Set.add`.
- The optional AyaSpell publisher selects only manifest members and the
  manifest itself. Unrelated files in an existing output directory are excluded.
  The Arabic adapter and in-app download workflow remain planned.
- Historical Mail evidence is retained with its original source identity.
  Current documentation distinguishes that record from newer qualifications.

## Frozen local qualification plan

The committed [VM plan](vm-plan.json) covers changed core-model tests, native
TLS/provider behavior, and shared IMAP, POP and SMTP connection regressions.
The [Node plan](node-plan.json) separately executes the changed portable model
test. Strict analysis and formatting cover the three changed Dart files.
The existing fail-closed runner binds the complete product input inventory,
runtime and dependency fingerprints before and after execution.

The separate Python controls exercise the runner, runtime restoration, process
launcher and new bundle publisher. Publication tests use local fixtures; they
do not upload a bundle. A controlled failing-before bundle regression is
retained separately from final passing results.

**At this source checkpoint, final local qualification is pending.** The result
and final remote-main receipt will be added in a later evidence-only commit.
Previously published 836- and 631-execution reports remain historical evidence
for their respective sources, not new runs on this continuation.

## Replay

From a clean checkout of the source commit recorded by the final verification
receipt, restore the pinned runtime outside the checkout:

```bash
python3 docs/validation/document-review-notes-20261118/runtime/restore_runtime.py \
  --repo "$QUDS_REPO" --runtime-root "$QUDS_RUNTIME" --node-tests
python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head "$QUDS_SOURCE" --base 55e262ef269634a0d618c0b5102dc9be5430a5f3 \
  --plan docs/validation/office-main-sync-20261119/vm-plan.json \
  --runtime "$QUDS_RUNTIME" --output "$QUDS_RESULTS/vm" --command-timeout 300
python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head "$QUDS_SOURCE" --base 55e262ef269634a0d618c0b5102dc9be5430a5f3 \
  --plan docs/validation/office-main-sync-20261119/node-plan.json \
  --runtime "$QUDS_RUNTIME" --output "$QUDS_RESULTS/node" --command-timeout 300
python3 -B -m unittest discover -s tools/proofing/ayaspell -p test_build_bundle.py -v
python3 -B -m unittest discover -s tools/mail -p test_check_store.py -v
python3 -B -m unittest discover \
  -s docs/validation/document-review-notes-20261118 -p test_run_checks.py -v
python3 -B -m unittest discover \
  -s docs/validation/document-review-notes-20261118/runtime \
  -p test_restore_runtime.py -v
```

Set the four `QUDS_*` variables to absolute paths/source before running. Use
separate empty output directories and run the gates sequentially.

## Acceptance boundaries

The incoming Office, Notes, Zotero and thesaurus application code remains
unchanged from the merged main source. Historical tests are not counted again.
Fresh Mail acceptance uses Linux loopback TLS with the pinned runtime; external
providers, other operating systems and installed-app interoperability remain
separate. Browser persistence, live Zotero, installed shortcuts and actual
Word/LibreOffice reopening retain their earlier unperformed scope.

This synchronization does not implement discovered-UID pagination, OAuth hosts,
SMTP composition, the account-aware mailbox workspace or the planned Arabic
Hunspell adapter. The branch named `mail-uid-pagination` supplied an integration
checkpoint, not a completed pagination feature.
