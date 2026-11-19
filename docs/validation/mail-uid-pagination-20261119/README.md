# Mail UID discovery continuation — 19 November 2026

> Captured source record retained with its original qualification state. The
> [later synchronization report](../office-main-sync-20261119/README.md)
> records the combined source, review fixes and final local acceptance.

## Qualification preparation

The local runtime and committed plans are prepared. **Final product gates have
not run yet.** This preparation record is not passing product evidence.

The continuation reconciles current incoming work before replacing the numeric
UID ceiling with bounded discovery and atomic range reconciliation. The
[incoming record](incoming/README.md) retains its exact captured references.

## Planned local gates

All gates execute sequentially on one committed source. GitHub Actions are not
queried, awaited, dispatched or used as an acceptance condition.

| Gate | Selection | Purpose |
| --- | --- | --- |
| Core and durable store | `tools/mail/check_store.py` discovers the current core and store suites | VM and Node contracts, atomic SQLite range application, migrations, recovery, enforced offline dependencies and browser entry/worker compilation |
| Native transport and TLS | 7 suites | Sparse/high UID discovery, page/cursor behavior, actual SQLite coordination, current implicit TLS/STARTTLS and connection lifecycle controls |
| Fork protocol regressions | 46 suites | New bounded UID SEARCH parser and client framing, existing FETCH/SEARCH and mailbox parsers, shared IMAP/POP/SMTP behavior |
| MIME and reader consumers | 6 MIME + 4 UI suites | MIME and saved-message reader regression coverage across changed shared dependencies |
| Portable Node | 9 suites | Transport configuration and browser unsupported boundary, MIME, portable fork import |
| Python controls | Existing Mail/shared-runner/restorer controls | Fail-closed event accounting, process cleanup and runtime verification |

The [native plan](native-plan.json) contains 63 suites and explicitly lists strict
analysis and formatting inputs. The [Node plan](node-plan.json) contains nine
suites. The shared runner binds every tracked package, app and vendored entry,
selected fixtures, manifests, launcher and native inputs before and after each
gate. The wrapper also binds source and runtime across the separate core/store
gate and refuses changed Mail Dart files missing from the strict check list.

Suite counts are planned selections. Final case counts must be derived from
successful raw reporter events, with failures, skips, unfinished cases and
missing suites rejected. VM/Node repetitions are not additional distinct
scenarios. Earlier qualifications retain their original source identity.

## Reproduce

Restore the pinned runtime using the checked-in
[restorer](../document-review-notes-20261118/runtime/README.md). The current
[runtime record](runtime/README.md) preserves this session's fresh restoration.

Commit all product changes, tests, plans and the driver before qualification.
Use the reconciled baseline as `BASE_COMMIT`, and the committed implementation
and plan as `SOURCE_COMMIT`. Both arguments must be full known Git commit IDs.
Keep runtime and output directories outside the source checkout.

```bash
source /absolute/path/to/runtime/env.sh
python3 docs/validation/mail-uid-pagination-20261119/run_validation.py \
  --head SOURCE_COMMIT --base BASE_COMMIT \
  --runtime /absolute/path/to/runtime \
  --output /absolute/path/to/empty-validation-output
```

The wrapper runs shared-runner and restorer controls, the complete core/store
gate, the native plan and then the Node plan. It preserves each child receipt,
raw output and command log, records the final source/runtime snapshots, and
stops after a failed gate. Use a different empty output directory after repairs;
do not overwrite an earlier failed attempt.

## Acceptance boundaries

Controlled protocol and Linux loopback execution do not qualify real provider
accounts, OAuth/PKCE or refresh, host credential vaults, other operating systems,
SMTP/composition or the account-aware mailbox workspace. Browser compilation
and Node execution do not exercise actual browser persistence, quota/reload,
Web Locks or rendered browser UI. Final reporting must keep those boundaries
explicit.
