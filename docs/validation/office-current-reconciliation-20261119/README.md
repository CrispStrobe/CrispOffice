# Current Office reconciliation — 19 November 2026

> Completed historical reconciliation received at `a4b73fe4`. The 801-execution
> qualification below remains bound to `c268ce3b`, with publication at `3f0277c8`.
> The [UID discovery continuation](../mail-uid-pagination-20261119/README.md)
> records the later combined source and qualification, including implemented
> discovery, cursor freshness and incoming Arabic/Hunspell work.

## Result and source attribution

The complete bounded capture is reconciled at published checkpoint
**`3f0277c8c4d317c3607e3bd6a2bf0e9aaf73bd3d`**, tree
`40ff86aaa4700479768e45ca0aa9072ced429385`. [PR #177](https://github.com/CrispStrobe/quds_office_suite/pull/177)
is the merge vehicle into remote `main`. The user authorized incremental remote
checkpoints and the merge. **No GitHub Actions run was queried, dispatched or awaited.**

Fresh Dart qualification passed **801 application executions**, covering
**731 distinct test-file/case-name identities across 72 files and 78 suite/platform
executions**. The 70 repeated VM/Node executions are excluded from distinct-case
totals. **42 separate launcher controls** also passed.

The executed Dart source is **`c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e`**, tree
`aaa59b09bd369148e49495f1c480fc79d67c48d9`. Later reconciliation preserves every
application, test, configuration, dependency, fixture and plan input. Of 5,031
bound native inputs, **5,030 remain identical at publication**; the sole changed
input is `packages/quds_mail_store/README.md`. Its reviewed documentation update
distinguishes current and historical qualifications. Before/after blobs, hashes
and the full diff are in the [independent audit](review/final-publication-audit.json).
Arabic tooling has a separate source-hash-bound qualification at `3f0277c8`.
Later publication commits add reports and evidence only.

## All 415 captured references accounted for

The branch/PR capture completed at **08:47:50.599 CET** (07:47:50.599 UTC), and
tags/upstream were confirmed at **08:48:40.981 CET** (07:48:40.981 UTC). This is a
bounded sequential capture, not an atomic snapshot or a claim about future writes.

| Reference family | Count |
| --- | ---: |
| Fork branches | 217 |
| Pull-request heads | 177 |
| Tags | 17 |
| Upstream branches | 4 |
| **Total** | **415** |

The [reference audit](reconciliation/final-ref-audit.json) verifies **387 ancestors
and 28 historical equivalents**, with **zero unaccounted references**. All 14
historical proofs were freshly recomputed: three complete-tree identities and
eleven complete changed-path mode/type/blob identities at matching ancestor
commits. Earlier patch-equivalence results were not reused. A negative control
against preintegration main correctly identifies the then-outstanding work;
the archived union projection is distinct from the actual-commit audit.

| Incoming history preserved | Captured head |
| --- | --- |
| Main after PR #174 | `d41000336c84b6ebfe6b35f7f8335140b5d46038` |
| Main after PR #173 | `55e262ef269634a0d618c0b5102dc9be5430a5f3` |
| Main after Arabic PR #176 | `f059065fa622da8cee7824d66d29a2aff414d529` |
| Office/Mail cleanup integration | `ac1e4c8c788ea608402c2260488235c0189efcba` |
| Completed Mail evidence / PR #172 | `199690563b206948871ea0279f5e59f686265f8b` |
| Concurrent Office synchronization | `0b8f8f7f78fbf4e2e26671ecf9a0d858c38ca75c` |
| UID preparation reconciliation | `c1dc63f934f81e22a41bafd98df1abf22ee6a053` |
| Arabic preparation/publication metadata | `16cbbebdcf7781564658cc7636473c7d04846b38` |

The captured UID branch contains reconciliation only: **discovered-UID pagination
is not implemented by that checkpoint**. Its Dart source matches the newly
qualified source. README conflicts preserve complete incoming evidence with
explicit source attribution. No captured application change was discarded.

## Concrete fixes

### Rejected TLS upgrade cleanup

A direct rejected TLS upgrade could leave the client marked connected while its
original subscription was paused. The adopted repair aborts only if the connection
generation still matches and rethrows the original failure. A late failure cannot
abort a newer connection. Real TLS rejection tests check disconnected/logged-out
state **before** their `finally` cleanup. All three TLS suites remain present.

The [TLS review](review/tls-cleanup-review.json) verifies every member and source
binding of the saved controlled RED/GREEN reproduction. Those probes remain
separate development evidence; the fresh native gate supplies real loopback TLS
execution. External-provider and other-platform acceptance remain separate.

### Arabic resource-bundle publication

The original builder uploaded its entire output directory while verifying only
manifest files. The reproduction included unrelated hidden/private/nested files.
Publication now uses the exact manifest filenames plus `manifest.json`. The
combined suite preserves both incoming suites' meaningful controls without
duplicate test methods. Incoming Hugging Face licence metadata is retained.
The generated card accurately describes the Arabic adapter and in-app download
as planned. This continuation performed **no Hugging Face publication** and
enabled no Arabic runtime feature. The roadmap's earlier external publication
revision remains attributed to its incoming record.

## Fresh local validation

| Cohort | Suite/platform executions | Passed executions |
| --- | ---: | ---: |
| Native transport, TLS and coordinator | 6 | 112 |
| MIME consumers, VM | 6 | 32 |
| Mail UI consumers | 4 | 30 |
| Shared IMAP/POP/SMTP protocols and lifecycle | 44 | 428 |
| Mail core, VM | 4 | 31 |
| Mail core, Node | 4 | 31 |
| Native Store, VM | 7 | 95 |
| Portable Store, Node | 3 | 42 |
| **Total** | **78** | **801** |

Strict analysis with fatal infos/warnings and formatting passed on **35 Dart
paths**. Core/store analysis, format, enforced offline lock resolution, browser
entry/worker compilation and whitespace checks passed. The **42 launcher
controls** are separate from application executions.

The independent audit reconstructs suite/platform coverage, identities, complete
starts/completions and successful terminal events from raw logs. Original and
compressed log hashes agree. There are no failed/skipped/unfinished cases,
reporter errors, duplicate identities, layout overflows or missed-tap diagnostics.
One known Drift warning episode, with two warning-bearing messages, remains
visible in the passing separate-host-container test.

All **5,031 source inputs and 11,164 runtime records stayed unchanged during both
execution intervals**. The Store gate also retains its own 53 source inputs and
seven direct launcher/native mappings. The runtime was restored from the pinned
official Flutter 3.47.8 / Dart 3.13.7 stream, with 176 hash-verified hosted archives,
exact 131-package workspace resolution and the genuine SQLite/FTS5 hook asset.

### Arabic tooling qualification

The [final controls](arabic/tests.json) pass **five test methods with three
successful source-corruption subtests**, with no failures, errors or skips.
They cover deterministic builds, all resource names, independent hashes/sizes,
exact upload membership, preservation/exclusion of unrelated files, corruption
failure before remote mutation, and both content/manifest readback failures.
The security regression fails against original `dd953dcc` as expected. Root
integration reran the final suite and independently checked source hashes.

A fresh real-data local build passed without `--publish`: **nine output files**,
including **eight content files totaling 7,965,777 bytes**; complete output is
7,968,110 bytes. Manifest SHA-256:
`6db576c5eb30583f17b647a188f3ff821dd842ad673f845b60c0d25eb6e7214e`.
All upstream pins, MPL text, metadata and final source hashes were checked.
See [bundle review](arabic/real-bundle-review.json) and
[source continuity](arabic/publication-continuity.json).

## Historical qualification remains separate

The earlier Office **129-suite / 2,018-case** run and native/web evidence retain
their original source attribution. The inherited **836-execution / 78-control**
record remains at `5569c055`; the earlier **631-execution / 66-control** Mail
record remains at `71edec2d`. None is added to this continuation's fresh totals.

The separate historical **35 Node cases across seven suites were not rerun**.
Their tracked import/export/part closures, package manifests and root config/lock
remain identical through publication. Node selects the unsupported transport
branch, so the changed native TLS implementation is unreachable. The
[closure audit](review/historical-node-continuity.json) documents this narrow
continuity claim. Those 35 cases are excluded from the fresh 801.

## Checkpoints and retained evidence

| Remote checkpoint | Saved result |
| --- | --- |
| `9fe23d0b` | Latest main, Mail evidence and rejected-upgrade cleanup |
| `c94f833f` | Original Arabic preparation history |
| `c268ce3b` | Publication-isolation fix and frozen Dart qualification source |
| `5ea71d9f` | Independently audited 602-case native evidence |
| `3f0277c8` | Complete 415-reference reconciliation and final Arabic controls |

The [native archive](native/native-qualification.tar.xz) and its
[index](native/native-qualification.tar.index.json) retain raw events, receipts,
source/runtime snapshots and the native audit. The
[support archive](evidence/qualification-support.tar.xz) and its
[index](evidence/qualification-support.tar.index.json) retain complete Store
output, runtime provenance, initial/refreshed captures, independent audit scripts,
controlled failure evidence and Arabic test/build receipts. Each archive was
reopened and every member's size/hash checked. Language-resource bytes remain
separately reproducible with the pinned builder.

## Replay

Use separate clean repository, runtime and result directories. Set `QUDS_REPO`,
`QUDS_RUNTIME` and `QUDS_RESULTS` to their absolute paths. At the exact executed
source, run the committed restore helper and native plan:

```bash
git switch --detach c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e
python3 docs/validation/document-review-notes-20261118/runtime/restore_runtime.py \
  --repo "$QUDS_REPO" --runtime-root "$QUDS_RUNTIME" --node-tests
python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e \
  --base 55e262ef269634a0d618c0b5102dc9be5430a5f3 \
  --plan docs/validation/office-main-completion-20261119/native-plan.json \
  --runtime "$QUDS_RUNTIME" --output "$QUDS_RESULTS/native" --command-timeout 300
```

Extract the support archive outside the checkout. Invoke its saved
`qualification/replay/run_store_bound.py` with `--repo`, `--runtime`, `--native`,
`--output` and the same `--head`. It runs the existing `check_store.py --offline
--direct-tests` gate while recording full before/after inputs. Run native and
Store sequentially. The [audit script](replay/audit_fresh_reconciliation.py)
accepts these receipts, `--store-wrapper`, and `--publication-head`; its explicit
`--allow-store-readme-change` permits only the one reviewed documentation change.
The [reference auditor](reconciliation/audit_refs.py) accepts the two captured
ref files, `--expected-total 415`, and an actual final `--head`.

At the final tooling checkpoint, run:

```bash
python3 -B -m unittest discover -s tools/proofing/ayaspell -p 'test_*.py' -v
python3 tools/proofing/ayaspell/build_bundle.py --output "$QUDS_ARABIC_BUNDLE"
```

## Open acceptance boundaries

Actual offline-browser rendering/CSP/lifecycle/persistence/performance,
installed Studio and real OS/IME, live Zotero/external Word/LibreOffice
interoperability, and independent English/German linguistic judgments remain
open. This host still denies AF_UNIX creation. Compilation and Node execution
do not establish actual browser acceptance.

Mail external-provider/other-OS acceptance, OAuth/credential hosts,
discovered-UID pagination, SMTP/composition and the account-aware mailbox
workspace retain separate implementation or acceptance scope. Arabic runtime
integration and linguistic qualification remain planned. These limits are not
failed tests in this fresh local run, and the merge does not claim to complete them.
