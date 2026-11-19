# Quds Office reconciliation and local qualification — 19 November 2026

## Qualified source and publication scope

The completed local qualification is bound to application commit
**`5569c055a021c893e941fc54d40499ad9d96a5db`**, tree
`9d2c815eda61378fbc4b234124e8e7c9cfeacb5b`.
All final Store, native, Node and supplemental Python executions use this exact
source. The Mail/Office publication commits add reports and evidence; the later
main merge of PR #176 separately adds Arabic proofing documentation and an
AyaSpell bundle-building helper, outside this application qualification.
The [initial publication audit](release/publication-continuity.json) verifies
unchanged bound inputs at that checkpoint. The final Mail evidence reconciliation
also updates `packages/quds_mail_store/README.md`; its
[review](release/mail-tail-review.json) records this one documentation-only
input change explicitly. Application code, tests, plans and runtime inputs
remain unchanged.

PR [#173](https://github.com/CrispStrobe/quds_office_suite/pull/173) merged the
qualified application and evidence into remote `main` at `55e262ef`. PR
[#172](https://github.com/CrispStrobe/quds_office_suite/pull/172) completes the
remaining Mail evidence reconciliation while retaining newer main history.
The user authorized the merge and incremental remote checkpoints.
**GitHub Actions were not queried, dispatched or awaited.**
Remote updates use non-forced expected-head writes followed by fetched-object
verification; branch history and incoming evidence are retained.

## What is included

The integration carries the existing Zotero annotation and research-note work,
Notes/document-review updates, offline thesaurus work, and native Mail foundation
together. The Zotero 9 annotation picker, active citation identity and locators,
note placement, atomic undo/redo, cancellation safeguards and Quds DOCX persistence
retain their prior implementation. This continuation adds no separate claim of a
new live Zotero or Microsoft Word acceptance run.

Fresh work concentrates on the newly integrated Mail code and concrete defects
found while reconciling it:

- **Durable flags and schema v3.** Unknown observations remain distinct from an
  explicitly empty flag set. Migrations, reopen behavior, repository updates,
  equality/hash contracts and the native coordinator are covered together.
- **Native IMAP foundation.** Manual account configuration, current scoped vault
  lookup, bounded numeric-UID sweeps, exact message literals and guarded flag,
  delete and move operations are included. The browser provider explicitly
  returns unsupported without touching the vault or codec.
- **Raw FETCH correctness.** Valid unsolicited flag notifications do not consume
  literal quotas. Safely identified later flags supersede earlier snapshots;
  missing literals and ambiguous sequence changes after EXPUNGE cannot produce
  false deletion records or falsely confirm a write. Strict grammar rejects
  duplicate/trailing lists, malformed structural delimiters and noncanonical
  UIDs. Human-readable status text and unrelated atoms remain separate.
- **TLS lifetime and cancellation.** The default connector retains the original
  TCP owner during and after TLS. Cancellation and deadlines close stalled
  handshakes; abort also settles direct pending APIs and blocked/idle producers.
  Late completions cannot revive an abandoned connection. Hostname and trust
  checks remain enabled, and existing Socket-returning integration seams remain
  compatible.
- **Runtime and control repairs.** Resource-budget errors retain their existing
  FormatException relationship. Runtime replay validates exact locked/workspace
  package names rather than a historical package count. A launcher test now
  handles the operating system reaping a child during observation.

The [merge review](merge-review.md) records how the two TLS implementations were
reconciled, which safeguards were ported, and how incoming tests were retained
against the chosen implementation. The TLS/FETCH [review archive](review/tls-review.tar.xz)
contains failing-before reproductions and their replay tools. Its development
results are excluded from the final qualification totals.

## All captured branches and PR heads accounted for

The fixed release cutoff is **08:15:06 CET on 19 November 2026**
(07:15:06 UTC). It contains **392 refs**: 213 fork branches, 175 pull-request
heads and four upstream branches. Against the qualified source, independent
accounting verifies **364 ancestors and 28 historical equivalents**, with
**zero unaccounted refs**. All **14 historical-equivalence proofs** were freshly
recomputed.

| Incoming work | Captured head included in the source |
| --- | --- |
| Main at the cutoff | `690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e` |
| Zotero annotation handoff | `17ec8cc8d241c76a753efb69893682c76683db04` |
| Notes/document review | `c320f28347f1cd292b848be2cf72998d41f8a6ac` |
| Thesaurus | `df62b58975bab1f650879fc88f850550a3df5c13` |
| Mail / PR #172 | `71edec2de364805113d18e0f1d7edbb1f00467e5` |
| Office integration, including Mail | `4624218f9468eeeac07f1f100ac0e4bb6b050a17` |

This is a bounded release capture, not a claim about future writes to other
branches. The [reconciliation summary](release/reconciliation-summary.json) and
complete archived advertisement/proof records preserve its exact scope.

During final publication, PR #174 advanced main to `d4100033` through its
`59e0a7c2` evidence checkpoint. Its application state exactly matches the already
integrated `4624218f`; all 20 additional paths are documentation/evidence.
That main merge and its 611-execution historical receipt are also preserved.
The [post-cutoff main review](release/post-cutoff-main-review.json) records this
additional reconciliation; the final qualified application inputs remain
exactly those of `5569c055`.

The final PR-state check also found Mail evidence commit `700e5a35`, a child of
the already included `71edec2d`. Its 40 paths are reports, evidence and README
updates, with no executable/test/configuration changes. These records are now
retained, including the separately attributed 631-case / 66-Python Mail result.
The Store README is the sole changed documentation file within the recorded
qualification inventories: 5,032 of the combined 5,033 bound inputs remain
byte-identical, and every executable, test, plan and dependency input is exact.
This reviewed documentation update requires no product test rerun and does not
change the 836-case / 78-Python execution identity.

While PR #172 was being made ready, main advanced to
`f059065fa622da8cee7824d66d29a2aff414d529` through PR
[#176](https://github.com/CrispStrobe/quds_office_suite/pull/176). Its three paths
are `docs/PROOFING.md`, `docs/roadmaps/arabic-proofing.md` and
`tools/proofing/ayaspell/build_bundle.py`. Both documentation files are retained
byte-for-byte. The helper receives one reviewed safeguard: its output directory
must be new, preventing an explicit upload from including unrelated files that
were already in a reused directory. This is separate dictionary packaging
tooling and a roadmap; it does not enable an Arabic spelling provider in the
application.
The [additional main review](release/proofing-tail-review.json) verifies that
none of these paths intersects the frozen application inputs and that the
complete 5,033-input union is unchanged from the reviewed Mail publication
`19969056` (5,032 exact to `5569c055`, plus the documented Store README change).
The helper was inspected and syntax-checked, and its output-path guard was
checked with downloads stubbed and publication prevented. The
[guard receipt](release/proofing-output-guard.json) and
[replay script](release/check_proofing_output_guard.py) preserve that separate
scope. No resources were downloaded or published, no fresh external-bundle,
licensing, or application acceptance claim is made for PR #176, and these helper
checks are not added to the 836/78 totals.

## Final local results

All **836 application case executions** passed, across **85 suite/platform
executions and 73 distinct test files**. VM and Node executions of the same file
are reported by platform and are not claimed as different source files.

| Cohort | Suite/platform executions | Passed cases |
| --- | ---: | ---: |
| Native transport, TLS and coordinator | 6 | 112 |
| MIME consumers, VM | 6 | 32 |
| Mail UI consumers | 4 | 30 |
| Shared IMAP/POP/SMTP parsing and lifecycle | 44 | 428 |
| Browser-unsupported transport, Node | 1 | 3 |
| MIME consumers, Node | 6 | 32 |
| Mail core, VM | 4 | 31 |
| Mail core, Node | 4 | 31 |
| Mail Store, VM | 7 | 95 |
| Portable store, Node | 3 | 42 |
| **Total** | **85** | **836** |

The separately reported **78 Python controls** also passed: 42 Store-launcher
controls, 20 qualification-runner controls and 16 runtime-replay controls.
All **35 changed Dart files** are selected for strict analysis and formatting;
both passed. Store-specific analysis/formatting, enforced offline lock resolution,
browser entry/worker compilation and whitespace checks also passed.

The final results contain **zero failures, skips, reporter errors, incomplete
cases, duplicate completions or suite discrepancies**. These are fresh final
executions. Earlier 778-case and 795-case checkpoints and development attempts
are preserved separately and contribute zero to these totals.

An independent read-only audit recounts the original reporter events, verifies
the exact suite/platform inventory, matches source inputs against Git, and
checks source/runtime/configuration stability. Native and Node each bind
5,031 source inputs. Native binds 11,164 runtime inputs and Node binds 11,161;
the Store audit independently verifies its 53 source inputs and 20 driver/runtime
bindings. See the
[independent summary](release/independent-summary.json),
[coverage summary](release/coverage-summary.json), and the complete
[qualification archive](release/local-qualification.tar.xz) with its
[member index](release/local-qualification.index.json).

## Runtime and unchanged Office source

The runtime is pinned to **Flutter 3.47.8 / Dart 3.13.7**. Recovery verifies the
complete official SDK stream, 176 locked hosted archives, the exact 131-name
workspace resolution, Node/compiler inputs and the genuine native SQLite/FTS5
hook. Dependency manifests and the lockfile remain unchanged by qualification.
The [runtime evidence](evidence/runtime-evidence.tar.xz) preserves recovery
receipts and original diagnostics; the replay-helper repair is already committed
in the qualified source.

All **2,622 tracked entries** in Office engine, editor and Studio are byte- and
mode-identical to qualified source `39843ed4874c7b56572c7aa8195716e5892aeca2`.
Its historical 2,018-case report retains its own identity; those tests were not
rerun or added to the fresh Mail totals. This source-continuity check preserves
the Notes, Zotero and thesaurus behavior while the changed Mail scope receives
new execution.

## Remote checkpoints

| Checkpoint | Saved work |
| --- | --- |
| `17aa63ab` | Initial current Office/Mail reconciliation |
| `5107eff6` | Concurrent flag/schema test repairs |
| `6be76779` | Unsolicited flags/EXPUNGE fixes and frozen qualification plans |
| `edf2fe7f` | Generic status text versus FETCH data |
| `57c24597` | Exception compatibility and exact workspace replay validation |
| `30e9efce` | Runtime and Store evidence |
| `f9932d40` | Concurrent strict FETCH grammar and Mail cleanup |
| `c634f494` | Independently audited 778-case baseline and diagnostics |
| `54c36e40` | Real TLS lifecycle repair and nine real TLS regressions |
| `f7fba99b` | Canonical UID grammar and latest integration evidence |
| `292f9b97` | Independently audited 795-case checkpoint |
| `5569c055` | Final reconciled source, safeguards, regressions and plans |
| `022a974a` | Source-bound TLS/FETCH review and replay archive |
| `bbf1032d` | Final 836-case evidence archive, audits and completion report |
| `55e262ef` | PR #173 merged into remote main |
| `19969056` | Remaining Mail evidence and reviewed Store README update |
| `f059065f` | Concurrent main PR #176, preserved without application changes |

Later publication commits are discoverable in Git history and PRs #172–#176.
Archives were reopened and each member compared with its
original bytes before publication. Final fetched-object checks bind the remote
publication to the exact qualified inputs.

## Replay

Use a clean checkout at the exact qualified source. Keep new output/runtime
directories outside that checkout. These commands target Linux x86-64. Runtime
recovery needs Python 3.12 or later with PyYAML, an available Node executable,
at least 2 GiB free as required by the helper, and access to the pinned
SDK/package/SQLite release downloads. The following commands perform local work;
they do not query GitHub Actions.

```bash
QUDS_REPO=/absolute/path/to/clean-replay-checkout
QUDS_RUNTIME=/absolute/path/to/new-empty-runtime
QUDS_RESULTS=/absolute/path/to/new-results
QUDS_SOURCE=5569c055a021c893e941fc54d40499ad9d96a5db

git -C "$QUDS_REPO" switch --detach "$QUDS_SOURCE"
cd "$QUDS_REPO"
python3 docs/validation/document-review-notes-20261118/runtime/restore_runtime.py \
  --repo "$QUDS_REPO" --runtime-root "$QUDS_RUNTIME" --node-tests
source "$QUDS_RUNTIME/env.sh"

python3 tools/mail/check_store.py --flutter-sdk "$QUDS_RUNTIME/flutter" \
  --offline --direct-tests --command-timeout 300 --output "$QUDS_RESULTS/store"

python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head "$QUDS_SOURCE" --base 5107eff6bf45fe0dca4ecbf511c2e1a98958caaf \
  --plan docs/validation/office-main-completion-20261119/native-plan.json \
  --runtime "$QUDS_RUNTIME" --output "$QUDS_RESULTS/native" --command-timeout 300

python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head "$QUDS_SOURCE" --base 5107eff6bf45fe0dca4ecbf511c2e1a98958caaf \
  --plan docs/validation/office-main-completion-20261119/node-plan.json \
  --runtime "$QUDS_RUNTIME" --output "$QUDS_RESULTS/node" --command-timeout 300

python3 -B -m unittest discover \
  -s docs/validation/document-review-notes-20261118 -p test_run_checks.py -v
python3 -B -m unittest discover \
  -s docs/validation/document-review-notes-20261118/runtime \
  -p test_restore_runtime.py -v
```

Run these gates sequentially. The archived Store driver and supplemental Python
driver additionally bind before/after source/runtime identities for reproducing
the published receipt format. Independent audit helpers and their exact source
hashes are included in the qualification archive. The review archive's separate
README explains the deliberately failing baseline reproductions; those runs
must remain outside acceptance totals.

## Acceptance boundaries

Real TLS coverage is Linux loopback with the pinned Dart runtime, including
ClientHello observation, peer-observed closure before teardown, trusted encrypted
payloads, trust/hostname refusal and fresh connections. It does not establish
external mail-provider, other-OS or installed-application interoperability.
Arbitrary injected socket implementations retain responsibility for their own
physical transport ownership.

M06 remains partial: discovered-UID pagination for large/sparse mailboxes,
OAuth authorization/refresh hosts, platform vault integration, SMTP/composition
and the account-aware mailbox workspace remain future work. The numeric scan
ceiling still defaults to 10,000 and is configurable up to 100,000. Browser
compilation and Node tests do not establish actual browser persistence or
cross-tab recovery. Live Zotero, installed shortcuts, Word/LibreOffice reopening
and independent linguistic acceptance retain their earlier unperformed scope.
