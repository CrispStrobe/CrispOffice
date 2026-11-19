# Quds Office final branch synchronization — 19 November 2026

## Accepted integration qualification at `5c18db77`

**PASS:** the complete run and its independent audit qualify source
`5c18db77505f876bf70bf7e89c49e8c3b617e0d4` (tree `c29e6bae74ed0c1d0375fa230bf54762658c69cb`).
The frozen run completed **10:51:27 CET–11:00:37 CET
on 19 November 2026**. It records **1,026 application executions across 49
suite/platform runs and 38 distinct test files**, with **21 separate Python
controls**: seventeen bundle controls and four offline packaging controls.
All **89 strict analysis and 89 formatting targets**, whitespace checks,
offline locked resolution and browser compilation passed.

| Cohort | Platform | Suite runs | Passed cases |
| --- | --- | ---: | ---: |
| Native Hunspell, installation, disposal and cancellation | VM / Flutter VM | 4 | 28 |
| Mail cursor and store integration | VM / Flutter VM | 4 | 50 |
| Arabic writing and range rules | VM / Flutter VM | 3 | 294 |
| Word language inheritance and finding merges | VM / Flutter VM | 5 | 70 |
| Word editing and proofing integration | VM / Flutter VM | 4 | 73 |
| Studio, PDF, Notes, Zotero and dictionary setup | VM / Flutter VM | 18 | 119 |
| Portable Hunspell provider | Node | 1 | 11 |
| Portable Mail cursor and configuration | Node | 2 | 17 |
| Portable Arabic writing and ranges | Node | 3 | 294 |
| Portable Word language and finding merges | Node | 5 | 70 |
| **Total** | **Native + Node** | **49** | **1,026** |

The independent audit confirms zero failed/skipped cases, reporter errors,
duplicate completions, unfinished cases or suite discrepancies. It reverified
**5,125 immutable source inputs, 11,171 runtime inputs and thirteen fixture
files**, with unchanged source, runtime, source head and tracked checkout.
All eight rejected v3 plan files remain exact historical inputs. Original
`0669ac11` results, all four rejected attempts, and every development/preflight
execution contribute zero to these totals.

- [Final result and exact source](main-delta-v4/final/summary.json)
- [Independent raw-event and source/runtime audit](main-delta-v4/final/independent-summary.json)
- [Workspace/source continuity](main-delta-v4/final/continuity.json)
- [Fresh audit of the fixed 401-ref capture](main-delta-v4/final/reconciliation.json)
- [Two-archive publication manifest](main-delta-v4/publication-manifest.json)
- [Complete raw results](main-delta-v4/final/evidence.tar.xz) and [preserved reviews](main-delta-v4/reviews/evidence.tar.xz)

The two new archives preserve **336 exact members**: 103 qualification/audit
members and 233 review/development members. Archive membership is separate from
test counts. GitHub Actions were neither queried nor awaited.

A subsequent main observation returned `0114567f2e922dd0f0e31e6f846663462beeaac3`.
This packet preserves the accepted `5c18db77` source and results before that
further reconciliation; any new affected-source checks retain a separate
identity.

## Scope and checkpoint state

This continuation starts from remote main at
`55e262ef269634a0d618c0b5102dc9be5430a5f3`, after the Zotero, Notes and
thesaurus work merged through PRs #173–175. It preserves subsequent main and
branch history and publishes incremental checkpoints on
`codex/office-main-sync-20261119`. PR #178 tracked its initial checkpoint and
was later closed after an older head was integrated directly into main.

The fixed reconciliation scope is the direct remote advertisement at
**08:51:46.468061 CET on 19 November 2026** (07:51:46.468061 UTC): **401 refs**,
comprising 218 fork branches, 179 PR heads and four upstream branches. All are
accounted for at integration checkpoint `2122066f`: **373 ancestors and 28
verified historical equivalents**, with zero unaccounted refs. All 14
historical equivalence proofs were freshly recomputed. This is a fixed capture,
not a claim about later writes by concurrent contributors.

The latest integrated source is
`5c18db77505f876bf70bf7e89c49e8c3b617e0d4`. It includes directly captured main through
`9160eb0dba211225c85242114989631c0d14fb72`, together with the earlier
reconciliation and review repairs. The [fourth delta plan](main-delta-v4/README.md)
defines a fresh source-bound qualification after the rejected `26df7873`
attempt. Its complete result and independent audit passed as recorded above;
the historical qualification below remains bound to its original source.
Remote-main inclusion is verified separately from this source qualification.

**Historical expanded qualification: PASS at
`0669ac119da05f5eb777c8cfdbce32e0261df647`.** The original execution ran
09:02:09–09:11:29 CET on 19 November. Its accepted independent audit verifies
**1,372 application executions across 111 suite/platform runs and 94 distinct
test files**, plus **90 separately counted Python controls**, with zero failures
or skips. GitHub Actions were neither queried nor awaited.

While this source was frozen, concurrent main advanced to `b655b8a3` with
optional Hunspell, macOS-runner and documentation additions. PR #178 had been
closed after an earlier checkpoint was integrated directly. Publication checkpoint `26046f9894283f3ac1cc863d355896699693926c`
preserved that exact qualified source and evidence. Subsequent main
reconciliation and its checks retain separate identities; these 1,372 passes
are never relabeled as executions against a later source.

## Concurrent main continuation

The [main reconciliation record](main-reconciliation.md) traces the preserved
incoming heads from `b655b8a3` through `b559f6c7`, `be641457`, `00014577`,
`d8b7f1c4` and `9160eb0d`. They add optional Hunspell, the macOS runner,
Arabic T1 rules, CrispOffice Studio updates, complex-script language routing,
dictionary setup, the compact review footer and shared Settings test helpers. At the first main merge the original cursor and
Arabic repairs remained byte-identical; later Arabic changes retain those
safeguards while extending the provider and its regression coverage. Scoped
repairs cover native disposal, missing dictionaries, publication inventory,
macOS capabilities, language editing, finding merges, download cancellation
and truthful, bounded footer status. The 1,372 executions below retain their
original `0669ac11` identity.

The [first merged-source attempt](main-delta/attempt-aea5d91a/README.md)
remains FAIL: native diagnostic lines violated strict reporter admission. Its
159 observed assertion successes are excluded from accepted totals. Investigation
also reproduced a valid-affix/missing-dictionary false success. The following
repair checks both dictionary files before FFI and adds a regression; the result
parser is unchanged. The CrispOffice Studio update and Arabic T1 rules added
by `b559f6c7` are included in the current integrated source.

The [second merged-source attempt](main-delta-v2/attempt-c0c71a26/README.md)
at `c0c71a26` also remains FAIL: three stale Studio selectors and three strict
formatting discrepancies were rejected. Its 469 observed successful application
events and 17 Python controls contribute zero to accepted totals. All raw output,
source/runtime envelopes and the independent failed-attempt audit are preserved.
The [additional review packet](main-delta-v2/reviews/evidence.tar.xz) preserves
reviewed native binaries, pinned dictionaries and scoped development evidence.

The [pre-test v3 attempt](main-delta-v3/attempt-fce543de/README.md) at
`fce543de` remains rejected: its dependency-graph expectation omitted Studio's
explicit edge to the already-resolved `url_launcher` package. It executed
**zero application cases and zero Python controls**. Its successful independent
rejection audit preserves `accepted_qualification: false`.

The [following v3 attempt](main-delta-v3/attempt-26df7873/README.md) at
`26df7873` corrected that graph expectation but remains **rejected**. All
**634 native application cases and 21 separate Python controls** succeeded;
strict analysis reported one alphabetical export-order diagnostic in
`quds_office_engine.dart`. The driver stopped before Node tests and browser
compilation. The original logs, source/runtime envelopes and completed
independent rejection audit are preserved. None of these successes contributes
to an accepted total.

The latest integration retains main's `9160eb0d` changes and corrects the exact
export ordering. The fresh v4 qualification retains the prior regression
selection, includes the shared Settings helper in strict analysis, and uses
new output and source/runtime envelopes. Historical, rejected and development
executions contribute zero to its accepted totals.

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
offsets. Later main adds the T1 extension and the optional Hunspell package.
The current source implements native and web Studio hosts plus an explicit
Dictionaries setup dialog with progress, cancellation, removal and licence
information. Verified installed dictionaries are registered in Word proofing.
Native hosts retain verified files in the private application data directory;
the web host retains verified bytes for the current session. Dictionary data
is downloaded only after the user requests it. Actual platform acceptance
remains scoped as described below.

Review reproduced and repaired decomposed-hamza corruption, matches inside
mixed-script tokens, detached-waw matches across token boundaries and an
ambiguous bare `لان` correction. Nine new negative controls supplement the
incoming cases. Combining madda/hamza remain significant, ordinary vowel marks
retain their supported behavior, and Unicode token boundaries protect adjacent
letters, marks, numbers, connectors and joiners.

The AyaSpell publisher selects only manifest members and `manifest.json`,
excluding unrelated files from a reused output directory. The five local and
seven incoming controls formed the twelve publisher controls accepted at
`0669ac11`; later main adds another five. The current v4 plan selects all
seventeen controls across the three retained files. Their scenarios overlap,
so these counts describe controls rather than distinct product features.
The later published bundle metadata is preserved. This continuation performs
no Hugging Face upload.

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

For `0669ac11`, all **83 strict analysis and 83 formatting targets** passed,
covering all 27 changed Dart paths, alongside full core/store analysis,
formatting, offline locked resolution and browser entry/worker compilation.
Its independent audit recounts raw events and checks case inventories,
missing/duplicate completions, suite coverage, source Git blobs, and actual
runtime files. That run's outer envelope bound 5,051 source inputs and 11,157
runtime inputs; both remained unchanged. These are the historical envelope
counts, not inventories for the later integrated source.

That accepted run used pinned Flutter **3.47.8** / Dart **3.13.7**, restored from the
verified official SDK stream and 176 hash-pinned hosted archives. All 131
resolved package names matched the then-current workspace and lockfile.

See the [compact result](final/summary.json), [original execution](final/execution.json)
and [accepted independent audit](final/independent-summary.json).

## Preserved evidence and remote checkpoints

The [original publication manifest](publication-manifest.json) lists the six
indexed archives for the `0669ac11` publication. Each member is byte-matched
against its original file. Later attempts and review packets retain their own
manifests, linked in the continuation sections above. Archive/member counts
are separate from application test counts.

| Packet | Scope |
| --- | --- |
| [Qualification](final/evidence.tar.xz) | Original raw events, generated browser outputs, manifests, accepted audit, failed initial accounting audit and verbose-control supplement |
| [Reconciliation](reconciliation/evidence.tar.xz) | Exact 401-ref snapshot, advertisements, proof candidates and freshly recomputed dispositions |
| [Runtime restoration](runtime/evidence.tar.xz) | Original pinned runtime receipts and wrappers; SDK/package binaries are not bundled |
| [Reviews and development](reviews/evidence.tar.xz) | Arabic/publisher failing-before evidence, repaired development runs, source reviews and 12 inherited archive integrity checks |
| [Cursor regression](reviews/cursor-aba.tar.xz) | Original stale-write failure and repaired provider/SQLite development evidence |
| [Preliminary qualification](preliminary/evidence.tar.xz) | Earlier 237-application/90-Python checkpoint, excluded from the new totals |

The initial remote checkpoints were fetched and tree-verified after publication:

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

## Replay the accepted `0669ac11` baseline

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

For the latest integrated source, use the [v4 driver and replay instructions](main-delta-v4/README.md),
including its baseline, pre-resolution and native-fixture receipts. Its exact
source and results retain their own identity. The earlier v3 plans and rejected
attempts remain historical evidence and are not relabeled as v4 executions.

## Acceptance boundaries

Mail acceptance uses Linux loopback TLS and controlled protocol fixtures;
external providers, other operating systems, native OAuth/vault hosts, SMTP
composition and the account-aware mailbox workspace remain separate. Browser
compilation and Node tests do not establish actual browser rendering, storage
or cross-tab recovery. The current source includes dictionary host/UI code;
Linux native and controlled host/widget checks do not establish an installed
macOS/Windows/mobile launch, actual browser WebAssembly-worker execution,
persistent web downloads, or manual installed-platform setup acceptance.
Arabic tests establish the specified rule behavior and integration, not
independent linguistic acceptance. Live Zotero, installed shortcuts and actual
Word/LibreOffice reopening retain their earlier unperformed scope.
