# Host integration checkpoint — 19 November 2026

**1,285 passing executions / 979 distinct scenarios / 56 distinct suites**
are independently verified at frozen source
`9833831a013c98a8ce5c3f5e6f45de36593cb7df`, tree
`946667e34d796f5e0bf4e2904759b5e1d9e02d34`.
Captured main for this phase is
`be641457c8c7d1acc25091b31c87c73eaa3c9c2a`.
Source, runner, plans and runtime remained unchanged throughout both runs.
Later concurrent Studio changes have a separate source and qualification;
this checkpoint's results are not relabelled as their execution.

## Completed selection

| Cohort | Suites | Passed executions |
| --- | ---: | ---: |
| Office proofing engine / Arabic / merge / style / routing | 14 | 442 |
| English provider contracts | 3 | 29 |
| Office proofing editor / Notes | 19 | 321 |
| Studio functional integration / Mail / Zotero | 18 | 171 |
| Hunspell provider | 1 | 10 |
| Real instrumented native Hunspell lifecycle | 1 | 6 |
| Main selected run | 56 | 979 |
| Node repeats of five selected suites | 5 | 306 |
| Current execution total | 61 suite-platform executions | 1,285 |

All 306 Node identities exactly repeat main cases. The distinct total is
979, with 56 suite paths. There are zero failures, skips, errors, unfinished
cases, duplicate identities, warnings or layout/tap/disposal diagnostics.
Strict analysis with fatal infos/warnings and formatting passed for 51 Dart
paths; whitespace checks also passed.

The [independent audit](host_qualification_audit.json) reconstructs these
counts from raw events and verifies exact nonempty suite coverage, complete
starts/completions, terminal success, compressed/raw logs, case/error files,
source/runtime inventories and native build bindings. The
[case inventory](host_qualification_audit-cases.json) retains every identity;
the [replay auditor](audit_host_qualification.py) accepts explicit sources
and output directories rather than a predicted case count.

Both phases bind the same 5,092 source records. Main binds 11,166 runtime
records and Node binds 11,163; each before/after inventory is identical and
matches live readback. All 11,142 retained runtime files were reverified,
alongside the 176 verified hosted archive receipts from the original restore.
Flutter is 3.47.8 and Dart is 3.13.7. The dependency lock and resolved package
mapping are unchanged.

## Repairs included

- Native Hunspell disposal now closes and acknowledges the dictionary,
  rejects pending callers, handles repeat disposal and has a bounded shutdown.
  The fallback finalizer and controlled isolate termination retain native
  ownership until it can be closed. Six lifecycle cases use the actual
  compiled adapter with counters and a synthetic dictionary. The earlier
  [RED/GREEN archive](../latest-final/hunspell-disposal-evidence.tar.xz)
  preserves the original leak reproduction and build provenance.
- Arabic spelling and the new extended-rule matching retain semantic
  hamza/madda marks. Tests distinguish precomposed/decomposed spellings and
  preserve neighboring UTF-16 offsets. Existing incoming assertions and
  the earlier semantic-mark regression cases are both retained.
- Complex-script language routing requires a Unicode letter in the script
  ranges. Arabic punctuation/digits, BOMs and isolated combining marks no
  longer misclassify otherwise Latin text; Arabic/Hebrew and explicit
  complex-script formatting still route correctly.
- Studio Mail checks mounted state after both file picking and reading.
  Dismissal cannot cause a late state update, and a readable localized
  failure leaves the existing message available. The separate
  [Mail repair archive](studio-mail-evidence.tar.xz) preserves nine identical
  RED/GREEN cases (three passed/six failed before; nine passed after).
- Notes visibility participates in the cached workspace configuration key.
  A dedicated on/off widget regression exercises Settings without an
  unrelated configuration change. Existing Studio tests follow the current
  defaults, labels and public Settings controls. Controlled proofing setup
  precedes the Settings animations, preserving all prior providers and
  behavioral assertions.

The [review archive](review-evidence.tar.xz) retains the captured incoming
source review, exact repair reproductions, closure review and plan selection.
Its [index](review-evidence.index.json) preserves per-member source identities.

## Mail and history preservation

The [Mail continuity audit](host_mail_continuity.json) verifies all 394 Mail
package records unchanged from `29dd23a6`, including its original analyzer
configuration. It rechecks the prior inventory, Store inputs, resolved package
mapping and launcher/native inputs. The retained Mail evidence remains
**608 executions / 508 distinct scenarios / 33 suites at `29dd23a6`**; those
counts are not added to the current host run. The old draft claiming a final
analyzer exception was corrected by computing the actual final Git delta.

The [source preservation audit](host_source_preservation.json) retains the
409-reference accounting: 381 ancestor dispositions and 28 historical
reference dispositions through 14 immutable equivalence proofs. All saved
checkpoints and captured later heads remain ancestors; protected Notes files
retain their original bytes. It verifies 6,270 distinct non-README validation
artifacts/reports across its baselines. This is preservation of the saved
capture, not a claim that other writers have stopped advancing remote main.

## Failed attempt and supplemental controls

The [first frozen attempt](first-attempt.md) remains separately archived at
source `4681760c`: 920 passes/59 Studio teardown failures, plus 306 Node passes
and two analysis infos. It is not final acceptance. The current source fixes
that fixture order and both infos. No failed-attempt pass count is added here.

The current archive also preserves development preflights, including the
zero-selected-case invocation explicitly excluded from validation and the
corrected 62-case three-suite preflight. These are not added to final totals.

The 17 publisher controls were executed at `4681760c`; their five exact input
hashes still match this source, as recorded in
[publisher continuity](publisher-continuity.json). They performed no live
publication and changed no published AyaSpell revision or catalog hash.
Four offline package-install helper controls remain in the review archive
with their own pinned inputs. Earlier runner controls retain their original
receipts and are not represented as newly executed here.

## Reproducible evidence and replay

The [qualification archive](qualification-evidence.tar.xz) contains raw logs,
receipts, before/after inventories and supplemental/development context.
The [index](qualification-evidence.index.json) verifies every archived member.
This archive has no separately excluded generated outputs.

Archive: 848,808 bytes; 72 members; SHA-256
`fcf4a44cf7f3a971d5e59f9dc287a0bc5578ab560ff904c877a10f97187887a4`.

Restore the pinned runtime using the retained
[runtime instructions](../../document-review-notes-20261118/runtime/README.md)
and rebuild the instrumented library using its original archive. Use a clean
detached checkout of the frozen source, matching runtime bindings, and new
empty output directories. Complete locked dependency resolution first.

```bash
source /absolute/path/to/runtime/env.sh
QUDS_HUNSPELL_LIFECYCLE_LIBRARY=/absolute/path/to/instrumented-library.so \
python3 -B docs/validation/document-review-notes-20261118/run_checks.py \
  --head 9833831a013c98a8ce5c3f5e6f45de36593cb7df \
  --base be641457c8c7d1acc25091b31c87c73eaa3c9c2a \
  --plan docs/validation/office-main-integration-20261119/host-final/plan.json \
  --runtime /absolute/path/to/runtime --output /absolute/path/to/new-main-output \
  --command-timeout 600
python3 -B docs/validation/document-review-notes-20261118/run_checks.py \
  --head 9833831a013c98a8ce5c3f5e6f45de36593cb7df \
  --base be641457c8c7d1acc25091b31c87c73eaa3c9c2a \
  --plan docs/validation/office-main-integration-20261119/host-final/node-plan.json \
  --runtime /absolute/path/to/runtime --output /absolute/path/to/new-node-output \
  --command-timeout 600
```

Original receipts bind the exact recorded paths. Replays at other paths need
fresh truthful bindings. Avoid simultaneous Git preflight operations. Never
overwrite original evidence directories.

## Acceptance boundaries

Node tests establish portable Dart behavior; they do not execute a browser.
The retained Flutter web SDK lacks compiler artifacts, so no fresh complete
Studio web build was launched in this phase. Actual browser rendering,
worker/Wasm initialization, CSP, storage/offline lifecycle and performance
remain unverified here. Installed Studio/macOS/mobile behavior, real OS/IME,
live Zotero and external Word/LibreOffice interoperability are not established
by controlled widgets. Real AyaSpell installer/download acceptance was not
selected. The Linux native lifecycle fixture uses a small synthetic dictionary.
Independent English/German linguistic judgments remain incomplete.

The earlier 2,018-case run, 208-case native fixture and release web build keep
their original `39843ed4` attribution. They are not current execution or build
results. No GitHub Actions run was queried, dispatched or awaited.
