# Mail M06 continuation — 19 November 2026

## Recovered source and incoming reconciliation

The continuation restored `eafcd80fdfbd7ff678a7a04fb9a9a98b5330ad00` from
`codex/mail-reader-20261118`. The previously isolated M06 source had not been
published. The continuation now includes durable flags and a bounded native
IMAP foundation, with integrated qualification pending as described below.

Three subsequently captured commits from the thesaurus and Zotero branches
were integrated into published source
`479e1e038af0467b7f07b35d80bac9e4cc60a198`, tree
`03b895b74affd80c54fa1c35dfa87a6eb1d645c6`. All 389 captured external references
are accounted for by ancestry or 14 freshly reverified historical equivalents.
The five existing Notes source/test/changelog files were preserved exactly;
the incoming integration changes only documentation and evidence. See
[incoming verification](incoming/post-integration-source-verification.json),
[ref audit](incoming/post-integration-audit.json), and
[remote readback](incoming/published-readback.json).

A final bounded capture at 06:20 UTC added the Notes and thesaurus evidence
heads `c320f283` and `df62b589`. Their 68 changed paths are documentation and
validation evidence only. Published merge `faab20b96e4a51fd6e3cf1a80b1439c4a1b01b9c`
preserves both parents and accounts for all 389 captured external refs. The
existing Office source remains byte-identical to its qualified baseline. See
the [final capture and audit](final-incoming/).

## Fresh baseline Mail qualification: PASS

The [receipt](baseline/mail-receipt.json) binds source commit `479e1e03` and
records 186 passing test executions, zero failures and zero skips:

| Cohort | Passing cases |
| --- | ---: |
| Core VM | 30 |
| Core Node | 30 |
| Native store VM | 87 |
| Portable store policy/codec Node | 39 |

The 42 Python launcher regressions, enforced offline lock resolution, strict
core/store analysis, formatting, browser entry/worker compilation and whitespace
checks also pass. Source hashes and all direct launcher/native asset inputs
are unchanged before and after execution. VM and Node repetitions are reported
as separate executions, not distinct test scenarios.

[Original logs and case lists](baseline/mail-results.tar.xz) are retained with
an [archive index](baseline/mail-results.tar.index.json). Actual browser
persistence, locking, reload and quota behavior are not covered by these Node
and compilation checks.

## Runtime and Office qualification

The official Flutter 3.47.8 / Dart 3.13.7 archive, 176 hosted package archives,
SQLite hook asset and workspace native mapping were independently restored
and verified. The root dependency lock was unchanged. The [runtime receipt](runtime/runtime.json)
and [original restoration evidence](runtime/restore-evidence.tar.xz) retain the
new run's identities, command logs, retained input manifest and omissions.

The 72-suite Office/reader plan passed against the same frozen source with
**1,230 cases, zero failures and zero skips**: 233 engine, 887 editor, 99 Studio
and 11 Mail-reader cases. Strict analysis, formatting and whitespace checks
passed. All 5,002 materialized source inputs and 11,163 runtime inputs remained
unchanged. See the [complete receipt](baseline/office-verification.json),
[original evidence](baseline/office-results.tar.xz), and
[archive/case-list audit](baseline/office-archive-audit.json). Historical counts
from earlier work are not included in these fresh results.

## Integrated M06 qualification: pending

Checkpoint `c2db80d4caacb4818c06d596566e50f25811d28a` preserves nullable
durable standard flags and schema v3 migration source. Checkpoint
`fa284f22a7e3ad236bc991a4a796ad83565f11ce` adds the bounded native IMAP adapter,
exact raw-message fetching, guarded mutations and coordinator/SQLite fixtures.
The following source also preserves inherited `FormatException` compatibility
for deterministic resource limits and removes unrelated notices from the new
MIT package license. Existing MPL fork notices remain intact.

The fresh integrated qualification will use `tools/mail/check_store.py`, the
[native plan](native-test-plan.json) and the [Node plan](node-test-plan.json)
against one frozen published source. The native plan covers all new transport
tests, real coordinator/SQLite integration, affected IMAP/SMTP/POP client and
framing paths, all MIME suites and all saved-message reader suites. The Node
plan exercises the conditional unsupported transport and portable MIME paths.
Development checks and static review do not substitute for this final gate;
the baseline test results above apply only to source `479e1e03`.

The [exact-SDK review](review/tls-sdk-review.md) identified T12 before freezing
acceptance source: during a real stalled TLS handshake, the SDK has transferred
socket ownership, and aborting the previous `Socket` cannot close the pending
secure connection. The repair retains the actual TCP owner throughout TLS and
races negotiation against abort. It also preserves queued-write, flush and
write-close behavior. The original finding remains in the review history.

Development checks pass 39 native provider cases plus 14 TLS/manual/write
controls. Ten of the added controls use real local TLS in both modes, including
stalled-handshake cancellation/deadlines, successful authenticated exchanges,
default-trust rejection and hostname rejection. Two cover manual sockets; two
use a deterministic RawSocket fixture for partial-write/close/abort contracts.
The strengthened TLS rerun requires actual client certificate-validation
errors, a secure LOGIN and a bounded deadline result. These development
results do not replace the pending frozen-source qualification.

## Continuation boundaries

The transport remains a bounded M06 foundation. `maxUidScan` bounds the highest
numeric UID, default 10,000 and maximum 100,000; it is not a message-count cap.
Larger or sparse UID spaces require discovered-UID pagination. Real loopback
TLS controls complement the controlled protocol fixtures; live mailbox
interoperability and other operating-system implementations remain separate
gates. Deterministic partial-write controls do not establish actual Windows
execution or operating-system backpressure. Mutation uncertainty is surfaced
for reconciliation, and delete marks `\Deleted` without expunging.
System-browser OAuth, actual browser storage, live disposable-account
interoperability, SMTP composition/submission and the account-aware UI retain
their independent implementation and acceptance gates.

No GitHub Actions workflow, job or status was queried, awaited or rerun.
Remote checkpoints use `[skip ci]` and non-forced expected-head updates.
