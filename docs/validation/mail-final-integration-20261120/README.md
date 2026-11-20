# Final Mail API integration — 2026-11-20

## Accepted checkpoint

This evidence accepts **1,161 distinct test case identities across 52 suites**, with **218 additional matching Node executions**, at source commit **`c62338c65571aa399da5592455b651fa5c6a9317`**, tree **`d8e43e6f43b0726e8fefded52c185e387291916d`**. All accepted product cases passed; none were skipped. The four strict analyzers and formatting check passed. GitHub Actions and live provider accounts were not used.

The qualification combines two executions on byte-identical source, dependencies, configuration and runtime. It does **not** mark the interrupted first aggregate as passed. Its first five Studio suites completed 323 cases; the next suite remained at a hidden loading event and was stopped with exit 130. The reason for that stalled load is undetermined. The continuation completed the cached Studio suite (32), Studio visual suite (8), UI visual suite (5), and all four analyzers. The original `progress.json` still says `running`, because force interruption did not rewrite it. The interruption record preserves this raw state and separately records the observed process exit.

The verifier accepts each of those five earlier Studio suites only after checking its root-group count, every started/completed test ID, absence of errors and failures, and exact visible case count. It excludes the unfinished loader entirely. All other accepted commands have one successful terminal reporter event and exit code zero. `qualification.json` is the combined receipt; it is not a replacement for either raw run.

| Scope | Canonical cases | Suites | Extra Node rechecks |
|---|---:|---:|---:|
| Mail core | 211 | 12 | 117 |
| Transport on VM | 415 | 19 | 101 |
| Browser-unsupported transport boundaries on Node | 6 | 3 | 0 |
| Mail UI | 161 | 10 | 0 |
| Studio Mail hosts, cache and visual scenarios | 363 | 7 | 0 |
| UI visual evidence tool | 5 | 1 | 0 |
| **Accepted** | **1,161** | **52** | **218** |

The Node rechecks repeat the same `(file, name, occurrence)` identities as their VM counterparts and are not additional features or logical cases. The previous 1,056-case qualification shares 1,055 identities with this run; there are 106 current-only identities and one replaced UI test name. Every current case was executed at c623. The old and new totals must not be added.

## Reconciled behavior

The merge retains the existing `MailBulkFlagRunner`, coordinator, optional provider inference, immutable full-order reports, `results` compatibility alias and original `stopProblem` evidence. The incoming provider-result factory is shared by both execution paths. Contradictory failed outcomes that also report possible mutation become uncertain; synchronous guard callbacks are followed by a lease recheck. Definite quota rejection stops the unattempted tail and retains retry guidance without automatically retrying writes.

Cloud mutation certainty uses an explicit status allowlist. Unknown client errors, timeouts and server failures remain uncertain. The native host retains captured loader/session/account, record-ID, UIDVALIDITY and mailbox guards, including the bulk-only adapter path. Native and EWS hosts reject duplicate or remapped identities and bind Stop to the original batch. Optional mutation evidence survives loader exceptions. Both public UI naming families remain usable, alongside the incoming cancellation control, localized reports and detail dialogs.

These are bounded, sequential best-effort flag actions on the selected loaded headers. They do not promise transactions, rollback, retries, whole-mailbox operations, multi-account atomicity or offline replay. A possible mutation requires refresh; stopping a batch cannot undo a dispatched operation. Node tests establish portable behavior and explicit unsupported boundaries, not live browser authentication or real provider service behavior.

## Source and visual evidence

Both runs sealed 5,833 tracked source files and 6,188 dependency files. All four source/dependency/runtime snapshots match. The verifier independently hashes all 5,833 source blobs from the immutable Git commit, so later evidence-only commits do not change the source binding. Package configuration resolves 21 local/path packages into the tested checkout; the 143 external SDK/hosted roots remain pinned. Source, lockfile, package configuration, compiler/test-runner artifacts, fonts and SQLite hashes are preserved in the archive.

The runtime was Flutter 3.47.8 with Dart 3.13.7, package:test 1.31.1 and Node 24.22.3. The SQLite FTS5 probe and actual Flutter build-hook library agree on SHA-256 `0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`. SDK binaries, caches, compiled JavaScript/kernel outputs and native binaries are excluded from this package; their provenance and hashes remain.

The 26 saved PNGs cover English, German and Arabic selection/action/working states, compact menus and receipt/details. `visual-review.json` records the specific reviewers, files and bounded findings. This is a review of generated headless screenshots, not an accessibility certification, native-device matrix or live account session. Existing historical packages under `mail-bulk-actions-20261120` and `mail-bulk-reconciliation-20261120` retain their original source bindings and diagnostics.

## Reproduction and recount

Run the following companion-script commands **from this evidence directory**, `docs/validation/mail-final-integration-20261120`. Use a clean checkout of the exact c623 source and fresh absolute directories. The runtime preparation needs Python with PyYAML, Git, Node, Linux Flutter runtime prerequisites and network access to the pinned official SDK and Pub archives. It verifies archive hashes and uses the repository lockfile; it does not query CI.

```sh
sha256sum -c SHA256SUMS
python3 reproduce_flutter_runtime.py --repo "$MAIL_REPO" --runtime "$MAIL_RUNTIME"
python3 qualify_mail_final_union.py \
  --repo "$MAIL_REPO" --runtime "$MAIL_RUNTIME" --out "$MAIL_NEW_RUN" \
  --expected-head c62338c65571aa399da5592455b651fa5c6a9317 \
  --format-base 80e240ec1f557c1ac7c170a8273de41dfaac0f20
```

The default runner performs all 13 gates. It writes exact commands, working directories, raw JSON reporter events, case identities and before/after seals. Output paths must be fresh. The archived continuation command demonstrates the documented `--only`, `--studio-test` and timeout controls; reproducing the initial stall is neither necessary nor an expected test outcome.

To recount the **recorded** acceptance without rerunning tests, extract the archive into a fresh directory and supply any Git checkout containing c623:

```sh
mkdir "$MAIL_EVIDENCE"
tar -xJf mail-final-qualification.tar.xz -C "$MAIL_EVIDENCE"
python3 verify_mail_final_union.py \
  --initial "$MAIL_EVIDENCE/initial" \
  --continuation "$MAIL_EVIDENCE/continuation" \
  --repo "$MAIL_REPO" \
  --historical-cases "$MAIL_EVIDENCE/historical/accepted-test-cases.json" \
  --out "$MAIL_RECOUNT"
```

`archive-manifest.json` lists every member hash and byte count. `package_evidence.py` deterministically rebuilds the archive from the original scratch receipts; no test execution occurs during packaging. The interrupted-run collector's initial expectation of a rewritten progress status is preserved as a diagnostic in `interruption-seal.json`; correcting that collector assumption changed no test result or source file.
