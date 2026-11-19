# Quds Office final branch synchronization — 19 November 2026

This is the captured continuation-plan checkpoint from PR #177/#178. Its
pending statements remain historical observations. The
[current combined integration](../office-main-integration-20261119/README.md)
records completed qualification and subsequent reconciliation separately.

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

**Final expanded qualification is pending at this source checkpoint.** The
committed plans below are executed only after the review fixes are saved and
the source is frozen. GitHub Actions are neither queried nor awaited.

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
offsets. The Hunspell adapter and in-app dictionary download remain planned.

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

## Final local qualification plan

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
runtime restoration 16 and bundle publisher 12. Original raw reporter output,
source inventories and independent recounts will be published with the result.

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
QUDS_SOURCE=<qualified-source-sha>

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
