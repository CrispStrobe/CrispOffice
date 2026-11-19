# Quds Office final branch synchronization — 19 November 2026

## Scope and checkpoint state

This continuation starts from remote main at
`55e262ef269634a0d618c0b5102dc9be5430a5f3`, after the Zotero, Notes and
thesaurus work merged through PRs #173–175. It preserves subsequent main and
branch history and publishes incremental checkpoints on
`codex/office-main-sync-20261119` through PR #178.

The final reconciliation scope is the direct remote advertisement at
**08:51:46.468061 CET on 19 November 2026** (07:51:46.468061 UTC): **401 refs**,
comprising 218 fork branches, 179 PR heads and four upstream branches. All are
accounted for at integration checkpoint `2122066f`: **373 ancestors and 28
verified historical equivalents**, with zero unaccounted refs. All 14
historical equivalence proofs were freshly recomputed. This is a fixed capture,
not a claim about later writes by concurrent contributors.

**Expanded local qualification: PASS at
`0669ac119da05f5eb777c8cfdbce32e0261df647`.** The original execution ran
09:02:09–09:11:29 CET on 19 November. Its accepted independent audit verifies
**1,372 application executions across 111 suite/platform runs and 94 distinct
test files**, plus **90 separately counted Python controls**, with zero failures
or skips. GitHub Actions were neither queried nor awaited.

While this source was frozen, concurrent main advanced to `b655b8a3` with
optional Hunspell, macOS-runner and documentation additions. PR #178 had been
closed after an earlier checkpoint was integrated directly. This publication
preserves the exact qualified source and evidence first. Subsequent main
reconciliation and its checks retain separate identities; these 1,372 passes
are never relabeled as executions against a later source.

## Concurrent main continuation

The [main reconciliation record](main-reconciliation.md) describes preservation
of incoming `b655b8a3`, including optional Hunspell, the macOS runner, newer
Arabic guidance and all incoming evidence. The original cursor and Arabic
repairs remain byte-identical. Native Hunspell disposal, two stale publisher
assertions and macOS network/selected-file capabilities receive scoped repairs.
The separate merged-source qualification is recorded after its source checkpoint
is frozen; the 1,372 executions below retain their original `0669ac11` identity.

## Integrated behavior and review fixes

### Mail synchronization and connection safety

The captured UID-discovery implementation (`5fcdf726`) pages by existing UIDs
within a fixed sweep ceiling. Sparse numeric gaps do not consume the page limit
or generate synthetic tombstones. An authoritative closed UID range, actual
stored absences, pending-operation reconciliation and the next cursor commit
together in the SQLite transaction. Malformed, missing, duplicate, out-of-range
or over-budget SEARCH responses fail before they can authorize deletion.

Each remaining-range SEARCH must fit the configured UID count and protocol-byte
budgets. This supports sparse/high UID spaces; it does not provide unbounded
message-count pagination. ESEARCH/PARTIAL optimization remains separate.

Review reproduced a stale-write defect: completed sweeps reused the same cursor
value, allowing an older concurrent sweep to pass compare-and-set and restore
an expunged header. Version 3 cursors advance a monotonic revision on every
returned page, including completed/empty sweeps and UIDVALIDITY resets. Legacy
v1/v2 cursors remain readable. Exhaustion fails before vault/protocol I/O rather
than wrapping. A real provider/SQLite regression retains the failing-before
result and verifies the repaired stale-commit rejection.

The earlier direct TLS rejection cleanup is retained. A rejected upgrade aborts
only its current connection generation and clears connection/authentication
state before returning the original failure. Trust and hostname checks remain
enabled; rejection tests inspect state before teardown.

### Arabic proofing

The captured Arabic writing provider (`a4b9fc95`) supplies independently authored
orthographic, punctuation and style checks for Arabic-language text. It is
registered in default Word proofing and Studio and keeps original UTF-16
offsets. At this frozen source, the Hunspell adapter and in-app dictionary download
were still planned. Later main adds the optional package; host registration
and the download UI remain open.

Review reproduced and repaired decomposed-hamza corruption, matches inside
mixed-script tokens, detached-waw matches across token boundaries and an
ambiguous bare `لان` correction. Nine new negative controls supplement the
incoming cases. Combining madda/hamza remain significant, ordinary vowel marks
retain their supported behavior, and Unicode token boundaries protect adjacent
letters, marks, numbers, connectors and joiners.

The AyaSpell publisher selects only manifest members and `manifest.json`,
excluding unrelated files from a reused output directory. All five local and
seven incoming offline controls are retained. Their scenarios overlap; twelve
executions do not mean twelve distinct product features. The later published
bundle metadata is preserved. This continuation performs no Hugging Face upload.

### Existing Office workflows and historical evidence

The earlier Zotero annotation/note workflows, Notes review and thesaurus work
remain included. The 631-, 632- and 836-execution Mail records keep their
original source identities and archives. They are not added to the new totals.
The preliminary 237-application/90-Python synchronization gate also remains a
separate checkpoint; the expanded capture adds application changes and receives
new qualification.

## Accepted local qualification at `0669ac11`

The [final native plan](final-native-plan.json) covers transport discovery and
TLS, shared protocol parsing/lifecycle, MIME and reader consumers, Arabic engine
rules and adjacent proofing behavior, and Word integration. The
[final Node plan](final-node-plan.json) covers portable transport/MIME, cursor
freshness and Arabic Unicode/offset behavior. The full core/store gate discovers
all core/store suites and includes actual SQLite migration, rollback, crash and
range-reconciliation checks plus browser entry/worker compilation.

The [committed driver](final-run-validation.py) executes the gates sequentially,
binds the complete selected source and runtime inventories before and after,
and enforces strict analysis/format coverage for every changed Dart path.
Python controls are counted once: Store launcher 42, qualification runner 20,
runtime restoration 16 and bundle publisher 12. The original shared-runner log
contained 20 dots and an `OK` summary rather than named case records. The first
independent audit therefore rejected its exact-case accounting. That failed
audit and the original log remain unchanged. A source/runtime-bound verbose
rerun recorded all 20 case names; they are counted once, with no application
rerun and no extra 20 added to the total.

| Fresh cohort | Platform | Passed executions |
| --- | --- | ---: |
| Native Mail transport and cursor discovery | VM | 119 |
| Real TLS and connection ownership | VM | 26 |
| Shared protocol and parser regressions | VM | 496 |
| MIME consumers | VM | 32 |
| Mail reader UI | Flutter VM | 30 |
| Arabic and adjacent engine proofing | VM | 137 |
| Word proofing integration | Flutter VM | 137 |
| Portable transport, MIME, fork and Arabic Unicode | Node | 145 |
| Core contracts | VM + Node | 98 |
| Native store, migration and recovery | VM | 110 |
| Portable store policy and codec | Node | 42 |
| **Total application executions** | **VM + Node** | **1,372** |

All **83 strict analysis and 83 formatting targets** pass, covering all 27
changed Dart paths, alongside full core/store analysis, formatting, offline
locked resolution and browser entry/worker compilation. The independent audit
recounts raw events and checks case inventories, missing/duplicate completions,
suite coverage, source Git blobs, and actual runtime files. The outer envelope
binds 5,051 source inputs and 11,157 runtime inputs; both are unchanged.

The pinned runtime is Flutter **3.47.8** / Dart **3.13.7**, restored from the
verified official SDK stream and 176 hash-pinned hosted archives. All 131
resolved package names matched the then-current workspace and lockfile.

See the [compact result](final/summary.json), [original execution](final/execution.json)
and [accepted independent audit](final/independent-summary.json).

## Preserved evidence and remote checkpoints

The [publication manifest](publication-manifest.json) lists six indexed archives.
Each member is byte-matched against its original file. Archive/member counts
are separate from application test counts.

| Packet | Scope |
| --- | --- |
| [Qualification](final/evidence.tar.xz) | Original raw events, generated browser outputs, manifests, accepted audit, failed initial accounting audit and verbose-control supplement |
| [Reconciliation](reconciliation/evidence.tar.xz) | Exact 401-ref snapshot, advertisements, proof candidates and freshly recomputed dispositions |
| [Runtime restoration](runtime/evidence.tar.xz) | Original pinned runtime receipts and wrappers; SDK/package binaries are not bundled |
| [Reviews and development](reviews/evidence.tar.xz) | Arabic/publisher failing-before evidence, repaired development runs, source reviews and 12 inherited archive integrity checks |
| [Cursor regression](reviews/cursor-aba.tar.xz) | Original stale-write failure and repaired provider/SQLite development evidence |
| [Preliminary qualification](preliminary/evidence.tar.xz) | Earlier 237-application/90-Python checkpoint, excluded from the new totals |

Remote checkpoints were fetched and tree-verified after publication:

| Commit | Saved scope |
| --- | --- |
| `c1dc63f934f81e22a41bafd98df1abf22ee6a053` | Initial incoming integration |
| `0b8f8f7f78fbf4e2e26671ecf9a0d858c38ca75c` | Arabic publication reconciliation and publisher upload restriction |
| `b8063b8abf9d8de8e55b0bd451b2e52215bbb846` | Concurrent main, Mail evidence and both publisher test suites |
| `2122066f0eccf06a6f2c3c523c5715a7233bb95d` | All heads in the fixed 401-ref capture |
| `0669ac119da05f5eb777c8cfdbce32e0261df647` | Cursor freshness, Arabic token fixes and frozen full qualification plans |

## Reconciliation decisions

The [merge review](merge-review.md) records the earlier documentation/test
overlaps. Later captured heads add:

| Incoming work | Preserved head |
| --- | --- |
| Sparse UID discovery and atomic range reconciliation | `5fcdf726694b5356d8fb85fb8e01a715e0fadc0c` |
| Separate completed Socket qualification / PR #179 | `cd430b2229ff81e3d486c9ed95c80e92a41fe8af` |
| Arabic writing rules | `a4b9fc958753c937bc9a2020779d9c1f7f43d039` |

The later integration retains all three parents. Current Mail status describes
the new discovery behavior; earlier reports remain explicitly historical.

## Replay

Use Linux x86-64, Python 3.12 or later with PyYAML, and Node. Set the paths below
to a clean checkout, an empty runtime directory and an empty results directory.
Set `QUDS_SOURCE` to the exact source recorded by the final execution receipt.
Runtime recovery requires access to the pinned SDK/package/SQLite downloads.

```bash
QUDS_REPO=/absolute/path/to/checkout
QUDS_RUNTIME=/absolute/path/to/runtime
QUDS_RESULTS=/absolute/path/to/results
QUDS_SOURCE=0669ac119da05f5eb777c8cfdbce32e0261df647

git -C "$QUDS_REPO" switch --detach "$QUDS_SOURCE"
cd "$QUDS_REPO"
python3 docs/validation/document-review-notes-20261118/runtime/restore_runtime.py \
  --repo "$QUDS_REPO" --runtime-root "$QUDS_RUNTIME" --node-tests
python3 docs/validation/office-main-sync-20261119/final-run-validation.py \
  --head "$QUDS_SOURCE" --base 55e262ef269634a0d618c0b5102dc9be5430a5f3 \
  --runtime "$QUDS_RUNTIME" --output "$QUDS_RESULTS" --command-timeout 300
```

The original `vm-plan.json` and `node-plan.json` belong to the preliminary
237-execution checkpoint; use the `final-*` plans for this expanded source.
Development/failing-before probes must remain outside acceptance totals.

## Acceptance boundaries

Mail acceptance uses Linux loopback TLS and controlled protocol fixtures;
external providers, other operating systems, native OAuth/vault hosts, SMTP
composition and the account-aware mailbox workspace remain separate. Browser
compilation and Node tests do not establish actual browser rendering, storage
or cross-tab recovery. Arabic tests establish the specified rule behavior and
integration, not independent linguistic acceptance. Live Zotero, installed
shortcuts and actual Word/LibreOffice reopening retain their earlier unperformed
scope.
