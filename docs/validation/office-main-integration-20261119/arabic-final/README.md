# Expanded Arabic and Mail qualification

The application, fixtures, harness and both plans are qualified at
**`e41679f85c511bc8cf42447d3d1af0931884dee2`**, tree
`9cdc66213dc329265057a8511357ce53f4583604`. Three fresh receipts on that exact
source pass **1,286 executions / 1,142 distinct cases / 80 distinct suites**.
This is a completed checkpoint. Subsequent main changes and their validation
are described separately in the [integration report](../README.md).

## Results

| Component | Suites | Passed executions | Distinct cases contributed |
| --- | ---: | ---: | ---: |
| Full core/store VM and Node gate | 12 distinct | 199 | 129 |
| Native transport/configuration/coordinator | 3 | 86 | 86 |
| Actual TLS and transport ownership | 3 | 26 | 26 |
| Node unsupported transport boundary | 1 | 3 | 3 |
| Vendored IMAP and byte-reader | 8 | 193 | 193 |
| Shared connection, POP, SMTP and authentication | 10 | 63 | 63 |
| MIME consumers | 6 | 32 | 32 |
| Mail UI | 4 | 30 | 30 |
| Engine proofing: Arabic, contracts and German | 9 | 213 | 213 |
| English proofing contracts | 3 | 29 | 29 |
| Editor proofing, including Notes and Arabic/German | 19 | 320 | 320 |
| Studio review and comment-draft proofing | 2 | 18 | 18 |
| Arabic rules repeated on Node | 1 repeated | 74 | 0 |
| **Combined** | **80 distinct** | **1,286** | **1,142** |

The main focused gate contains 1,013 cases across 68 distinct suites. There are
87 suite/platform executions overall. The 144 repeated case executions are
70 core/store VM–Node repetitions and the same 74 Arabic identities on VM and
Node. Historical counts and development reproductions are not added.

Strict analysis with fatal infos/warnings and formatting passed for all
**32 selected Dart paths**. The fresh core/store gate passed **42 separate
runner controls**, offline locked resolution, whitespace checks, and browser
entry/worker compilation. These compiler checks do not establish browser
runtime acceptance.

## Reproduced Arabic Unicode correction

The incoming rules discarded U+0653, U+0654 and U+0655 as optional marks when
matching closed lexical lists. Correct decomposed Arabic could consequently
receive an incorrect replacement containing doubled hamza. The narrow repair
preserves madda and hamza marks as letter identity, without normalizing source
text, changing the word lists, or introducing a dependency. Optional vowels,
tatweel handling and original UTF-16 offsets retain their existing behavior.

All 69 original Arabic cases remain. Five additional cases cover the three
semantic marks, adjacent corrected-word offsets/vowels, and punctuation.
The development reproduction produced 70 passes / four failures before the
fix and 74 passes afterward. The fresh integrated VM and Node runs each pass
all 74 cases with identical case identities. Exact source snapshots, failed
environment attempts, probes, logs and replay commands are in the
[Unicode evidence archive](arabic-unicode-evidence.tar.xz), with its
[member index](arabic-unicode-evidence.index.json).

## Independent audit and evidence

The [independent audit](arabic_final_review.json) reparses raw events, verifies
the exact suite inventory, complete starts/completions, terminal success,
case identities and recorded hashes. It finds zero failed/skipped/unfinished
cases, reporter errors, duplicate identities, layout overflows or missed-tap
diagnostics. The existing Drift debug-warning episode remains visible as two
warning-bearing messages in the separate-host-container test. Static analysis
has no diagnostics.

Both focused source inventories contain exactly **5,035 inputs**, with identical
selection, unchanged before/after records, and exact Git modes, blob identities
and live hashes. The main runtime snapshot contains **11,168 records**, and
Node contains **11,160**; each remained unchanged during its run. All **11,142
retained runtime files** match the restoration manifest. The separate store
gate binds 53 source inputs and seven direct launcher/native inputs.

The first Node attempt stopped during preflight because `git write-tree`
encountered an existing index lock. No test group started and no final runner
receipt was produced. The original partial snapshots, traceback and explicitly
operator-captured failure record remain in the archive. The later successful
receipt supplies the 74 Node cases; the failed attempt contributes none.

Primary records:

- [Main verification](verification.json), [Node verification](node-verification.json),
  and [fresh core/store receipt](store-receipt.json).
- [Case inventory](arabic_final_review-cases.json) and
  [independent audit replay](audit_arabic_qualification.py).
- [Raw qualification archive](qualification-evidence.tar.xz) and
  [complete member/hash index](qualification-evidence.index.json).
- [Main plan](plan.json), [Node plan](node-plan.json), and
  [coverage rationale](qualification-scope.json).

## Historical scope and reconciliation

The saved 409-reference inventory remains accounted for: 381 ancestors plus
28 historical equivalents through 14 freshly verified proofs. The separately
captured later heads `f059065f`, `c268ce3b`, `0b8f8f7f` and `f7117a49` are explicit
ancestors. They are an addendum, not a newly advertised 413-reference inventory.
See the [ancestry audit](arabic_ancestry_review.json) and
[known-head addendum](arabic_known_heads_review.json).

All 129 original suite files, five protected Notes files and original
fixture/helper files retain their bytes. However, the Arabic engine export
and default editor/Studio registration change tracked import closures:
119 of 129 original suite closures, all 14 native fixture closures and the
web fixture closure differ. Ten original suite closures remain identical.
The [historical continuity audit](arabic_historical_continuity.json) records
4,968 of 4,992 original records unchanged, 24 changed and 37 added product/tool
paths. The older 125-suite / 1,988-case closure finding remains scoped to the
prior `ac1e4c8c` phase.

The original 2,018-case run, separate overlapping 208-case native fixture and
web compilation stay attributed to `39843ed4`. They were not rerun here or
relabeled as current-source acceptance. Earlier 611-, 631-, 632- and
836-execution checkpoints retain their own source identities and archives.

## Replay

Restore the pinned runtime in a separate directory using the retained runtime
recovery instructions, including Node support, and source its `env.sh`. From a
clean checkout at `e41679f85c511bc8cf42447d3d1af0931884dee2`, run the gates
sequentially with separate empty output directories:

```bash
python3 tools/mail/check_store.py \
  --flutter-sdk "$QUDS_RUNTIME/flutter" --offline --direct-tests \
  --command-timeout 300 --output "$QUDS_RESULTS/store"

python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head e41679f85c511bc8cf42447d3d1af0931884dee2 \
  --base 5ec15bdd4c5016b320f0fe8edff36b1da69fa44f \
  --plan docs/validation/office-main-integration-20261119/arabic-final/plan.json \
  --runtime "$QUDS_RUNTIME" --output "$QUDS_RESULTS/main" --command-timeout 300

python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head e41679f85c511bc8cf42447d3d1af0931884dee2 \
  --base 5ec15bdd4c5016b320f0fe8edff36b1da69fa44f \
  --plan docs/validation/office-main-integration-20261119/arabic-final/node-plan.json \
  --runtime "$QUDS_RUNTIME" --output "$QUDS_RESULTS/node" --command-timeout 300
```

Set both variables to absolute paths. Sequential execution avoids overlapping
Git index snapshots. Preserve new receipts separately from these observations.
No GitHub Actions were queried, dispatched or awaited.

## Acceptance still separate

Actual offline-browser/CSP/lifecycle/persistence/performance acceptance, installed
Studio and real OS/IME, live Zotero/Word/LibreOffice interoperability, external
mail-provider/other-OS acceptance and independent linguistic review remain open.
Local Arabic regression success does not fill human reviewer judgments.
