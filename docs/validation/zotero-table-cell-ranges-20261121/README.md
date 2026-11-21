# Zotero research-content replacement within a table cell

## Result and publication

Add Note and Add Annotation can replace a consecutive range of ordinary
paragraphs within one table cell. The existing cell, its properties, surrounding
content, active citation fields and supported rich formatting are retained.
The controller publishes one undo/redo action.

The implementation passed **2,551 distinct local cases in 119 original suites**,
with zero failures, skips, runtime error events or stderr bytes. A separate
Node execution passed **121 overlapping cases**. Independent review also
accepted 21 supplemental ownership probes. These counts are separate.
Strict analysis found no issues, and all four changed Dart files were already
formatted. This is local implementation qualification; installed Word,
LibreOffice and Zotero plugin acceptance remains separate.

The remote branch is `codex/zotero-parity-20261121-next`. Incremental checkpoints:

| Checkpoint | Commit |
| --- | --- |
| Incoming-history reconciliation and increment plan | `674ce9701e185971388fc2e517d305689ccba471` |
| Complete implementation, tests and user-facing documentation; frozen qualification source | `a6095c304ad2d6935f2ae6f8b74412038d19f142` |
| Qualification evidence and final intake dispositions | `149a8ae46d6dad02d21040c3587389f3c954a577` |
| Incorporation of the later main update | The subsequent merge checkpoint containing the applicability record below |

[PR #289](https://github.com/CrispStrobe/quds_office_suite/pull/289) records final
publication and main readback. The starting main was
`e2abbcda6d19f932bfbacc85e0dafd41a3c478f8`. The initial observation was
`fcb3ff13537eb31c2cabead033a50723124682c5`; the newer main includes PR #285's
final two performance documentation files. Its runtime implementation was
already incorporated. Publication uses an ordinary merge with an expected PR
head; no forced ref update is needed. GitHub Actions and status/check queues
were neither queried nor awaited.

## Incoming-history reconciliation and cutoff

All **338 initially captured external heads** are accounted for: 46 fork
branches, 288 PR heads and four upstream branches. There are 314 actual
ancestors and 24 independently verified historical equivalents, with zero
uncovered references. The checkpoint branch is recorded separately.

The audit recomputes 13 complete tree identities and two exact changed-path
comparisons (37 ODT-continuation paths and three PPTX-integration paths),
including Git modes and object identities. Every accepted replacement is an
ancestor of the target. The full inventory, candidate mappings, proofs and
replay script are retained in [intake/](intake/).

The later refresh captured 341 external heads and found **three post-intake
branch advances** outside that completed inventory: Word VBA, Mail sync and a
Mail Close-control fix. Their exact heads and review dispositions are retained
in [final-intake/](final-intake/README.md). They are preserved separately for
their own acceptance and are not included in this Zotero publication. The raw
final audit still reports three uncovered heads and exit code 1; it is not
relabeled as a fully integrated final inventory. This report distinguishes
completion of the bounded initial intake from concurrent work arriving later.

To replay the completed initial inventory against the current merge:

```bash
python3 docs/validation/zotero-table-cell-ranges-20261121/intake/audit_refs.py \
  --repo . --head HEAD \
  --snapshot docs/validation/zotero-table-cell-ranges-20261121/intake/snapshot.json \
  --candidates docs/validation/zotero-table-cell-ranges-20261121/intake/historical-candidates.json \
  --output /tmp/zotero-table-cell-intake.json
```

## Implemented behavior

The session resolves an exclusively owned, consecutive range within one real
cell block list. Existing nested-table ancestry and merged originating cells
are supported. It captures the exact section/note and table/row/cell/container
identities and the initially eligible endpoints when the transaction starts,
then rechecks before staging and applying the result. A replacement owner
containing the same paragraph objects cannot silently receive a stale result.
This pins ownership; it does not promise detection of every geometry mutation
that bypasses the host's revision tracking.

Ordinary text, headings, lists, supported pictures and active citations stay
inside the existing cell. Surrounding paragraphs, unselected native citation
packets, cell properties and neighboring cells survive. Undo restores the
original selection direction; redo reapplies the single published operation.
Tests cover DOCX save/reopen and subsequent editing, direct Add Note and Add
Annotation dialog completion/cancellation, forward/reverse ranges, both
simple and complex citation fields and before/after-picker ownership changes.

Cross-cell/row/story ranges, vertical-merge continuation cells, aliased
ownership, control/drawing ancestors and selected protected or structural
content are refused. Incoming table payloads still require a main-flow
destination. Existing nested tables can own the selected cell; this does not
add nested tables from incoming Zotero content.

Raw engine sessions support body cells and cells in authored footnotes or
endnotes. The standard Notes pane still exposes authored-note main-flow text;
engine coverage does not create a Notes-pane table editor.

Independent development probes found a covariant `List<WmlParagraph>` insertion
failure for rich headings/lists. Inserting each actual block into the existing
owner fixes that valid-model case. Regression tests cover the retained owner,
history and serialization. The original probe failures and the accepted
frozen-source rerun are retained in the evidence archive.

## Qualification scope and evidence

| Disjoint execution scope | Original suites | Passed cases |
| --- | ---: | ---: |
| Zotero engine | 41 | 1,157 |
| Word/ODT ownership, fields, notes, tables and persistence | 27 | 432 |
| Zotero editor, controllers and UI | 49 | 929 |
| Studio transport and shortcuts | 2 | 33 |
| **Total distinct local cases** | **119** | **2,551** |

All original test files were executed through standard `package:test` or
`flutter test`; no merged synthetic test module or name filter was used.
The total excludes 119 loading events and 12 setup/teardown events. The
independent audit reconstructs every case from the raw streams, confirms
successful process exits and a unique successful terminal event, and rejects
failed lifecycle events, hidden real cases, duplicate identities and runtime
diagnostics. See [qualification.json](qualification.json),
[selection.json](selection.json) and the
[independent audit](review/qualification-review.md).

The two focused engine suites also passed all 121 cases on Node v24.22.3:
62 table-cell cases and 59 existing paragraph-range cases. Their exact
suite/name population is a subset of the VM population. They add platform
coverage, not another 121 distinct cases. The separate accepted 21 ownership
probes and earlier development smokes are not added to the regression total.

Every VM/Flutter cohort binds the same **2,978 recorded source, fixture,
manifest and lock inputs** to the implementation commit above, including SHA-256, Git blob
identity and executable mode. The canonical source-map SHA-256 is
`b02b5b7f62c34bf37698d53e0cb614df93ac30d955ce0ad8b1cb1707f6f18916`.
All before/after maps match. One hidden fixture `.gitattributes` file was not
captured by `rg --files`; independent review separately verified its unchanged
Git identity. Actual XML fixtures are bound. This is the recorded source scope,
not a claim that every repository metadata file was captured.

The runtime was verified Flutter 3.47.8 / Dart 3.13.7 with the existing lockfile,
an isolated validation workspace, 135 verified hosted root-lock packages and a
164-package resolved graph. Dependencies were resolved offline with lockfile
enforcement. No manifest or lockfile changed. The 33 recorded runtime files
remain identical across execution; this is not an exhaustive hash of every
extracted dependency file. SDK verification, setup logs, environment scripts
and exact per-cohort commands are retained.

### Preserved audit correction

The first engine process passed all 1,157 cases and exited successfully, but
the first Python audit rejected its suite-path comparison: relative test paths
were resolved against the wrapper's directory instead of the recorded process
working directory. The correction changes exactly that expression. The v1
runner, raw streams, exit receipt, source maps and rejected summary remain
unchanged. A separate audit accepts those same execution bytes; the tests were
not rerun for the correction. The remaining 78 suites ran once under v2.
Independent review verified the exact one-expression difference.

### Retained archive and verification

[evidence.tar.xz](evidence.tar.xz) contains original streams and process exits,
compressed source maps, accepted and rejected audit records, runner scripts,
independent probes, Node receipts and runtime setup evidence.
[evidence-index.json](evidence-index.json) records the archive hash and every
member's size and SHA-256. SDK/cache binaries are not embedded.

From the repository root, verify every archive member and the original source
bytes on the qualified implementation/evidence checkpoint without rerunning tests:

```bash
python3 docs/validation/zotero-table-cell-ranges-20261121/verify_evidence.py --repo .
```

Use `--archive-only` to check the preserved evidence after future source
changes. Original runner/auditor scripts preserve the actual absolute execution
paths; rerunning those scripts requires their recorded workspace/runtime layout
or deliberate path relocation. The archive verifier itself is portable and
does not require the original SDK.

## Later main update: App Store screenshots

After qualification and the captured final intake, remote main advanced to
`eb286fb7254d6850c9f33b46e8aa65e2ea32f7f0` through PR #290. It adds six App Store
screenshots and changes the standalone `app_store_screenshots_gate.dart`.
This main update is incorporated before publication, preserving its seven
files exactly. It does not include the three historical deferred branch heads.

The screenshot gate is one of the broadly recorded 2,978 inputs, so the current
combined tree is **not** described as having an identical complete source map.
Exactly **2,977 inputs remain unchanged**; that one unselected gate is the
explicit exception. All 119 executed suite files, Zotero product files,
fixtures, manifests and locks remain unchanged. The gate's imports are
unchanged, no other recorded Dart/YAML source refers to it, and it is absent
from every executed test command. Independent review found its changes confined
to screenshot fixture layout, local native-host settling and capture helpers.

The original 2,551-case and overlapping 121-case Node qualification therefore
retains applicability to the unchanged Zotero implementation. No fresh run of
the macOS screenshot gate or of the full populations is claimed. The exact
seven incoming file identities and the single recorded-source exception are
retained in [main-applicability.json](main-applicability.json).

On the combined main tree, verify the archive plus this precisely bounded
source reconciliation using:

```bash
python3 docs/validation/zotero-table-cell-ranges-20261121/verify_main_applicability.py --repo .
```

The original strict verifier intentionally rejects the combined tree's changed
screenshot gate unless `--archive-only` is selected. Neither verifier silently
accepts further source drift. Ancestry, merge tree and remote main readback are
recorded separately in PR #289's publication receipt.

## Remaining parity work

The native citation, bibliography, preferences, refresh, unlink and transfer
workflows already exist. This increment closes a bounded editing gap.
Direct active ODT input still requires a structured ODT reader, reference-mark
ownership and preference restoration; the existing ODF text extractor does not
provide that model. Installed Word/LibreOffice round trips with their actual
Zotero plugins remain a separate acceptance gate. Cross-cell replacement and
incoming nested tables also remain outside this increment.

See the [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) and
[usage guide](../../zotero-support.md) for workflow details and the ordered next
implementation and acceptance steps.
