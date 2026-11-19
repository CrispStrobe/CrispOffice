# Office integration for remote main — 19 November 2026

The final integrated application, fixtures, execution harness and test-plan
source is **`4624218f9468eeeac07f1f100ac0e4bb6b050a17`**. Both fresh local
qualification receipts bind to that same commit: **611 passing test executions,
541 distinct test cases and 47 distinct suites**. Later publication changes are
documentation and evidence only.

This record accompanies the user-authorized integration into remote `main`
through PR #174. Code and evidence were saved incrementally on
`codex/office-main-integration-20261119`, with expected-head guards and exact
remote commit/tree readback. **No GitHub Actions run was queried, dispatched or
awaited.** Release acceptance remains separately tracked below.

## Reconciliation and preserved Office work

The bounded integration inventory accounts for **409 actual references**:
213 fork branches, 175 PR heads, 17 tags and four upstream branches. Of these,
381 are ancestors and 28 have 14 independently reverified historical source
equivalence proofs. No missing objects or unaccounted references remain.

| Captured incoming work | Integrated head |
| --- | --- |
| Main at the integration cutoff | `690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e` |
| Original PR #174, offline thesaurus | `df62b58975bab1f650879fc88f850550a3df5c13` |
| PR #175, Notes | `c320f28347f1cd292b848be2cf72998d41f8a6ac` |
| PR #172, latest captured Mail/TLS work | `71edec2de364805113d18e0f1d7edbb1f00467e5` |
| PR #173, latest captured Zotero/TLS work | `54c36e40daa7b17d73801dac1fd12f110b24017f` |

The [TLS ancestry audit](tls/tls_ancestry_review.json) identifies its input as a
frozen snapshot of already-fetched fork refs plus the saved upstream
advertisement. It records the five pointer updates from the preceding full
capture. This establishes the explicit qualification cutoff; it does not claim
that other writers cannot advance branches afterward.

The stable Notes Review layout, focus/selection/composition, tracked and
untracked IME/undo coverage, and revision-identity assertions remain intact.
Five reviewed Notes paths retain exact prior qualified bytes. Captured Zotero
Add Annotation work and all incoming Notes/Mail/Zotero evidence are retained.

## What the continuation adds and repairs

Mail now includes nullable durable standard flags and transactional schema-v3
migration from v1/v2, plus the initial native IMAP foundation: scoped account/
vault configuration, bounded UID synchronization, exact message retrieval,
guarded flag/move operations, cancellation and resource bounds. Omitted flag
snapshots preserve known state; explicit empty snapshots clear it. The browser
transport entry returns typed unsupported without using the vault or codec.

Parser repairs preserve the specialized resource-limit exception's
`FormatException` relationship, require one canonical FETCH root, reject
repeated lists and trailing fields, and enforce decimal UID wire syntax before
integer conversion. Invalid responses latch failure instead of accepting a
successful prefix or fabricating missing-message tombstones. The merged parser
retains unsolicited flag/status handling, missing-notified-literal checks,
EXPUNGE ambiguity protection and later flag confirmation semantics. Fourteen
raw-parser regressions retain both malformed and valid byte-exact controls.

Two concurrent TLS implementations were reconciled using the explicit
`ClientConnection` / `RawClientConnection` adapter. It retains the original TCP
owner through pending and established TLS, aborts stalled handshakes, preserves
ordered partial writes and final readiness, and cancels idle or active stream
producers. Disconnect also aborts pending TCP/TLS work. The competing Socket
facade remains preserved in its original Git commit; a second active connection
owner is not shipped. All three incoming TLS suites remain present; only the
Zotero capture fixture's adapter types/import were reconciled.

The manual `connect(Socket)` path retains ordinary and already-secure I/O. A
default TLS upgrade of an externally supplied socket is explicitly rejected
before handshake because its original TCP owner cannot be retained through the
SDK handoff; native upgrades use `connectToServer`. This boundary is documented
and tested. See [the merge decision](tls/merge-review.json),
[suite/fixture review](tls/tls-suite-review.json) and
[core/control merge review](tls/core-controls-merge-review.json).

The Mail equality fixture retains separately constructed equivalent objects and
adds the incoming hash equality assertion. Migration matcher disambiguation is
preserved. The timeout regression now handles process reaping between `/proc`
observations without weakening the child-termination requirement.

## Fresh qualification on the final source

| Focused cohort | Suites | Distinct passed cases |
| --- | ---: | ---: |
| Native transport/configuration/SQLite coordinator | 3 | 80 |
| TLS and connection ownership | 3 | 23 |
| Node unsupported transport boundary | 1 | 3 |
| IMAP and byte-reader regressions | 8 | 181 |
| Connection lifecycle, POP, SMTP and authentication | 10 | 63 |
| MIME consumers | 6 | 32 |
| Mail UI consumers | 4 | 30 |
| **Focused run** | **35** | **412** |

The fresh core/store gate on the same commit passed 31 core VM, 31 core Node,
95 native-store VM and 42 portable-store Node executions: **199 executions /
129 distinct cases**. Across both receipts there are **611 executions / 541
distinct cases / 47 distinct suites**, with 70 VM/Node repetitions excluded from
the distinct-case count. Identities use test file and case name. Earlier Office
and intermediate Mail/transport results are not added to these totals.

The TLS group combines real Linux TCP/TLS loopback tests with deterministic
raw-write and pre-handshake rejection controls. Coverage includes successful
implicit TLS and STARTTLS, default-trust rejection, hostname mismatch,
peer-observed closure after stalled-handshake cancellation/deadlines, fresh
connections, exact delayed 1 MiB encrypted payloads, ordered partial writes,
blocked-flush abort and idle-producer cancellation. Test certificates and keys
are explicitly public fixtures; trust is isolated to injected test contexts.
Production certificate and hostname checks remain enabled.

Strict analysis with fatal infos/warnings and formatting passed on **26
transport/vendor Dart paths**. The core/store gate also passed package analysis,
formatting, offline lock enforcement, **42 runner controls**, whitespace checks
and browser entry/worker compilation. Supplemental adapter stream probes are
retained separately and are not counted as Dart cases.

The [independent raw-event audit](tls/tls_final_review.json) reconstructs exact
suite coverage, unique identities, complete starts/completions and successful
termination. It verifies zero failures, skipped cases, reporter errors,
unfinished cases, duplicate case identities, layout overflows or missed-tap
diagnostics. The sole existing Drift debug-warning episode belongs to the
separate-host-container test; its two warning-bearing messages remain visible
and the case passed. Strict analysis was clean.

All **5,031 focused source inputs and 11,164 runtime records** remained unchanged.
The store gate independently binds 53 source inputs and seven direct launcher/
config/native inputs. Live readback verified all recorded hashes and 11,142
retained runtime files. The runtime is the hash-verified Flutter 3.47.8 /
Dart 3.13.7 release, with 176 verified hosted archives and a genuine SQLite/FTS5
smoke check. Its 131 resolved packages match 114 locked and 17 workspace names.
Earlier runtime-helper and cleanup-control results retain their own receipts.

Primary evidence: [focused verification](tls/verification.json),
[store receipt](tls/store-receipt.json),
[distinct case inventory](tls/tls_final_review-cases.json),
[35-suite plan](tls/plan.json), and
[raw archive index](tls/qualification-evidence.index.json).

## Earlier qualifications remain separately attributed

The [preserved report before TLS](pre-tls-report.md) records the preceding
389-case focused pass at `7d279e08`, retained 199-execution gate at `1655db9f`,
the 359-case first transport pass and earlier flags qualification. Their raw
evidence and failed reproductions remain under their original directories.

The original **129-suite / 2,018-case** Office qualification, separate
**14-suite / 208-case** native fixture and successful web compilation remain
attributed to `39843ed4` in the
[original continuation report](../thesaurus-20261118/resumed-20261119/README.md).
They are not reruns or a fresh web build of the current source.

The [historical continuity audit](tls/tls_historical_continuity.json) verifies
all 129 original suite files, 4,971 of 4,992 ordinary source records, the tracked
Dart closures of 125 Office suites / 1,988 historical cases, all 14 native
fixture closures, the web fixture closure and 12 bound fixture/helper sources.
Twenty-one records changed and 32 product paths were added. Four original Mail
UI suites reach changed core inputs and are covered by the fresh run. No
original suite closure reaches the changed vendor TLS/parser source.

The historical web inventory remains 1,155 compiled files / 87,446,576 bytes and
1,156 installed-cache files / 87,447,167 bytes, with its original warnings and
screenshots. The linguistic packet remains `not_reviewed`; human judgments
have not been filled in.

## Incremental remote preservation and replay

The checkpoint history retains initial reconciliation (`a9e417d3`, `f38959f0`),
flags fixes/evidence (`ebe0498a`, `86560baf`), initial transport repairs/evidence
(`1655db9f`, `f9104833`), latest notification/runtime reconciliation
(`d1dda005`, `2890a0f2`), decimal UID qualification/publication
(`7d279e08`, `99dd7307`, `7a5c6874`), incoming native TLS capture (`f9346ed1`),
and the final combined TLS source (`4624218f`). Later commits publish only
documentation and evidence. The remote checkpoint branch is retained.

The [qualification archive](tls/qualification-evidence.tar.xz) contains raw
events, receipts, source/runtime snapshots and case inventories. The
[development archive](tls/development-evidence.tar.xz) retains adapter probe,
merge and certificate-review inputs. Earlier flags, transport, parser-failure
and runtime archives remain intact. Generated JavaScript is recorded by compile
logs and hashes rather than duplicating reproducible application bytes.

For a new replay, use a clean checkout at `4624218f` and a separate empty runtime
directory. Follow the
[runtime recovery instructions](../document-review-notes-20261118/runtime/README.md)
with `--node-tests`, then source the generated `env.sh`. From the repository:

```bash
python3 tools/mail/check_store.py \
  --flutter-sdk /absolute/path/to/toolchains/flutter \
  --offline --direct-tests --command-timeout 300 \
  --output /absolute/path/to/fresh-store-results

python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head 4624218f9468eeeac07f1f100ac0e4bb6b050a17 \
  --base 7d279e084bae438d383630726ad7b0514da77d35 \
  --plan docs/validation/office-main-integration-20261119/tls/plan.json \
  --runtime /absolute/path/to/toolchains \
  --output /absolute/path/to/fresh-focused-results --command-timeout 300
```

Preserve new replay receipts separately; do not overwrite these observations.

## Acceptance still open

| Gate | Current status |
| --- | --- |
| Actual offline browser | Browser rendering, CSP, offline lifecycle, persistence and performance remain unverified. Node and compilation do not establish these behaviors. |
| Installed Studio and real OS/IME | Installed-app acceptance, live Zotero sessions and external Word/LibreOffice interoperability remain unperformed. |
| Independent English/German linguistic review | Review packet is prepared; human identity, judgments and recommendations remain incomplete. |
| Mail interoperability and remaining product work | Local Linux TLS controls passed. External providers/disposable accounts, other operating systems, OAuth redirect/refresh, platform credential hosts and power-loss durability remain unqualified. Large/sparse UID pagination, SMTP/composition and the account-aware mailbox workspace remain subsequent implementation. |

Integration into main does not close these release and product gates.
