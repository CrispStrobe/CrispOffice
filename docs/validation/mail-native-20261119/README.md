# Mail native continuation — 19 November 2026

Restored remote checkpoint `db7501ee42c97e8da42b776a4213802cac41a9b0` into a new workspace. Earlier unsaved source and raw logs were not present. The previous status is preserved as historical evidence.

## Incoming integration

All ten new captured commits from Notes review, Zotero native annotations and thesaurus qualification are integrated at `ed7af02411c8210f8553cdb76276e4d7c1b71dd1`. The GitHub tree equals the local integrated tree `62dad09eafa631a29f647ff04fdc0bc92278837b`. The complete capture includes 211 external origin branches, 174 external PR heads and four original-upstream branches. All 389 refs are accounted for by ancestry or 14 reverified historical equivalents. See [audit](incoming/audit.json) and [conflict review](incoming/merge-review.md).

## Qualification preparation

The official Flutter 3.47.8 / Dart 3.13.7 SDK and 176 locked hosted packages are verified. The root lock is unchanged. SQLite 3.54.1 with FTS5 and the generated workspace native-assets mapping are bound by the [runtime evidence](runtime/evidence-index.json). This is preparation evidence, not a product-test result.

The store qualifier supports direct invocation of the resolved package:test entry when command precompilation stalls, records launcher and native-library inputs before/after, and rejects newly shadowing package mappings. Every command has a finite timeout, and POSIX timeout/interruption cleanup stops the complete process group. Forty-two local runner regressions pass. A fresh complete Mail run and the 72-suite Office plan are next; no previous totals count as new results.

Run from the root after restoring the verified environment:

```bash
python3 tools/mail/check_store.py --flutter-sdk /path/to/flutter --offline --direct-tests --command-timeout 300 --output /path/to/fresh-mail-receipt
```

## Implementation in progress

M06 work is isolated from qualification: nullable durable standard flags and schema migration; native IMAP configuration, host credential access, bounded UID synchronization and exact on-demand literal retrieval. OAuth host integration, SMTP submission, actual browser persistence and live disposable-account interoperability remain distinct acceptance gates. No completed M06 claim is made at this preparation checkpoint.

No GitHub Actions workflow, job or check status is queried, awaited or rerun. Checkpoints use `[skip ci]` and expected-head non-forced updates.
