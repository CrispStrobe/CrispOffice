# Mail UID discovery continuation — 19 November 2026

## Qualification preparation

The local runtime and committed plans are prepared. **Final product gates have
not run yet.** This preparation record is not passing product evidence.

The continuation reconciles current incoming work before replacing the numeric
UID ceiling with bounded discovery and atomic range reconciliation. The
[incoming record](incoming/README.md) retains its exact captured references.
The [preflight refresh](preflight-incoming/README.md) preserves the subsequent
bounded capture, including concurrent Office reconciliation and AyaSpell work.

## Implemented behavior

The native provider discovers existing UIDs with strict simple SEARCH and pages
by discovered messages. Large numeric gaps do not consume page slots or create
synthetic tombstones. A typed `MailImapSyncRange` lets SQLite remove only actual
cached memberships absent from the confirmed range, in the same mailbox and
UIDVALIDITY. Pending local edits enter reconciliation with their cached evidence
retained. Upserts, removals, pending state and the cursor commit atomically under
the existing cursor comparison and account lease.

Version 2 cursors retain a frozen sweep ceiling and accept saved version 1
cursors. UIDVALIDITY changes reset membership; newly arriving higher UIDs enter
the next sweep. Discovery requires exactly one complete valid SEARCH response,
followed by successful tagged completion. Missing, malformed, duplicate,
extended or over-budget results cannot authorize a deletion or FETCH. A message
expunged between SEARCH and FETCH becomes absent; an unexpected fetched UID
rejects the page.

`maxDiscoveredUids` defaults to 10,000 existing UIDs per remaining-range SEARCH
and supports a maximum of 100,000. Protocol line/response budgets also apply;
the default 64 KiB line limit can bind first. This fallback repeats discovery
for each page and does not implement scalable ESEARCH/PARTIAL. An explicitly
supplied legacy `maxUidScan` retains its numeric meaning; it is unset by default.
The normal SELECT-derived sweep can reach UID `0xfffffffe` because UIDNEXT is
validated as a nonzero uint32. Raw discovery and stored identities admit
`0xffffffff`; exhausted-generation handling remains the server's responsibility.
Range reconciliation is bounded by stored account-message limits, independently
of the smaller fetched-page limit. No schema or dependency change is needed.

The incoming AyaSpell publication fix restricts uploads to verified bundle
filenames. Both independently authored offline suites are retained under
distinct filenames, including integrity/readback refusal, exclusion of unrelated
output files and deterministic local builds. No live publication is performed
by this continuation or its tests.

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
| Incoming AyaSpell controls | Two offline unittest suites | Verified-file publication selection and reproducible bundle/integrity behavior using local fixtures |

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
