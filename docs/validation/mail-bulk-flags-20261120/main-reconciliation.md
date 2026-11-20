# Intermediate main reconciliation: Word and Zotero

The later [final peer-main reconciliation](peer-reconciliation.md) supersedes this
intermediate source for publication. All results below retain their original
source attribution, including the one recorded Zotero analyzer style info.

**The combined source passed local acceptance at
[`00d44a69`](https://github.com/CrispStrobe/quds_office_suite/commit/00d44a69d19de20cdb7754b754c4d32d86d078cc),
tree `83a5034ac7020c1cd7a2d1143144357fc26bf80c`.** This source contains the completed foreground mail milestone,
both publication-time main advances, and the bounded Word corrections below.
[PR #275](https://github.com/CrispStrobe/quds_office_suite/pull/275) records the
final remote merge, tree equality and ancestry verification.

The original mail baseline remains `3645e8a4db535fc0ab5ab0923ee7385e5c4e5195`. Its raw archive, manifest,
source-applicability proof and verifier are unchanged. All **298** mail library, test
and tool Dart files in the mail packages and Studio mail hosts are identical
between that baseline and the accepted combined source. The source-inheritance
proof in the late archive enumerates the sets and exact Git modes/blobs.

## Main advances and saved checkpoints

The full branch/PR source inventory stays frozen at 20:58:00.677 UTC on
20 November 2026. Publication-time main checks are separate from that cutoff.

| Saved remote checkpoint | Preserved change |
| --- | --- |
| [`9265604a`](https://github.com/CrispStrobe/quds_office_suite/commit/9265604a3d2ed91fc382e4be77cc1041572ea86c) | Complete immutable baseline evidence and original incoming main `e975cec1` |
| [`53f7d42c`](https://github.com/CrispStrobe/quds_office_suite/commit/53f7d42c665ca6970f7da5bd19330a18c3567bfc) | First focused Word picture/table repairs and their new regressions |
| [`58dca948`](https://github.com/CrispStrobe/quds_office_suite/commit/58dca948144976a8b25faf13df426c76ed05cac8) | Incoming Zotero main `698209aa`, preserving PR #276 history, source, tests and original evidence |
| [`00d44a69`](https://github.com/CrispStrobe/quds_office_suite/commit/00d44a69d19de20cdb7754b754c4d32d86d078cc) | Continuous-section correction and final accepted production/test source |

Main first advanced from `b6657785` to
`e975cec13b289fe067ef406cd3044701ecc44744`, changing three Office files:
font filename aliases, Word header/footer picture layout and Word table/border
deserialization. It then advanced through Zotero PR #276 to
`698209aaa6e7f1350b6541df5eb192b7b233443d`. Both complete incoming main histories are ancestors of the accepted
source. The retained branch is `work/mail-bulk-flags-20261120`.

### Word picture and continuous-section corrections

The first incoming renderer could discard distinct pictures merely because
they shared dimensions or byte counts, and its final global deduplication could
remove legitimate body frames after the body-frame count had been recorded.
The corrected implementation compares picture content and rendering properties
at the same placement, with deduplication restricted to the relevant header or
footer. Inline and separately listed references to one visual still render once;
distinct pictures, vertical placements and body pictures remain intact.

A separate scratch probe then exposed three continuous-section failures: a
shared header was duplicated; a replacement header retained the previous one;
and a footer was treated as body content, forcing an unnecessary page break.
Both section carry and content-bottom calculation now use the recorded body
frame prefix. Header/footer chrome is recreated for the current section. The
same probe now passes, and the regression suite also preserves body pictures
and compares incremental with full layout after an edit.

The incoming 4.25-point cell padding remains. One contained-text fixture now
expresses its intended 31.2-point usable width as that width plus two cell pads.
All original cluster, ownership and save/reopen assertions remain unchanged.

### Table-style and import provenance corrections

The existing style cascade already applies conditional table run formatting
with direct, character and paragraph precedence. The incoming second pass
reapplied first-row color/bold after that cascade, overriding explicit settings
and reaching into nested tables. Removing that redundant pass preserves both
conditional formatting and authored overrides.

The incoming border-color fallback and table-spacing defaults remain. Resolving
an automatic border color no longer replaces an explicitly authored border
width. Inferred spacing defaults are recorded in the imported baseline, so a
save does not turn inherited defaults into new direct paragraph edits. Existing
explicit/style-derived spacing remains protected. Fourteen import regressions
cover precedence, nested-table isolation, borders and save/reopen provenance.

The eight system-font filename aliases are retained unchanged under the existing
family, face and deduplication checks. Their source analyzes cleanly; discovery
on an installed macOS system was not exercised.

### Zotero and historical overlap

The four incoming Zotero implementation files and their new/updated test files
are retained exactly from `698209aa`. The new behavior supports horizontally
merged research-note/annotation table cells and Refresh merging of physically
adjacent native citation packets, with existing staging, stale-result and
undo/redo boundaries. The incoming
[Zotero qualification](../zotero-merged-cells-20261120/README.md) remains a
historical source-specific record; this supplement adds current-source checks.

Older mail coordinator and Word measurement work on that main history was
already reconciled into the accepted baseline. Its original coordinator test
blob is retained in `bulk_flags_coordinator_test.dart`, alongside the combined
API and provider-result suites. Four alternate positional Word filenames map
to canonical retained files: three exact blobs and one exact result after two
filename substitutions plus an import wrap. Our named suites retain all
incoming text and the additional 43/105 lines already accepted. The replayable
proof and all 50 incoming path classifications are preserved under `intake/`
in the late archive. No duplicate historical suite is counted as a new feature.

The Word documentation retains the tested eight-, nine- and thirteen-operation
examples and current execution attribution. Both mail and Zotero changelog
entries remain. No compiler implementation, dependency version or package
lockfile changed during this publication reconciliation.

## Accepted checks on the combined source

These cohorts overlap; do not add them into one unique-test total. Unlike the
historical baseline compositions, the current Studio and Word VM/Node totals
below come from complete successful invocations.

| Cohort | Result | Late archive evidence |
| --- | --- | --- |
| Seven connected/cached Studio mail suites | **374 passed** | `final-mail/receipt.json`, `hosts.log` |
| Full shared mail UI | **161 passed** | Same receipt, `ui.log` |
| Localized mail visual probes | **10 passed**, 20 captures byte-identical to the baseline | Same receipt, `visual-comparison.json` |
| Combined Word measurements, line spacing and new import/layout regressions, VM | **893 passed** | `final-word/word-vm.json` and log |
| Portable Word cohort, JavaScript/Node | **751 passed** | `final-word/word-node.json` and log |
| Actual eight- and thirteen-operation BAS drivers | Both pass VM and compiled JavaScript with equal JSON | `final-word/*-vm-js-comparison.json` |
| Focused layout cohort | **148 passed**; original continuous probe now passes all three expectations | `layout/continuous-final/receipt.json` |
| Earlier focused table import repair | **75 passed** on its recorded pre-Zotero source; its 14 new cases also pass Node | `deserializer/qualification.json`; current 14 cases are also in the complete Word runs |
| Incoming Zotero engine, six changed/new suites | **282 passed** on VM | `zotero/zotero-vm.json` |
| Four portable Zotero suites | **175 passed** on Node | `zotero/zotero-node.json` |
| Zotero/editor/layout/proofing coverage, 14 suites | **378 passed, 8 existing skips** across a 362-pass editor run and a 16-pass Studio run | `final-mail/receipt.json`, `zotero-editor.log`, `zotero-studio.log` |
| Static checks | Word/mail/font analysis clean; Zotero recorded one incoming test-only style info; **20 later changed Dart files, zero formatter changes**; whitespace clean | Per-domain receipts and `final-checks/receipt.json` |

The eight editor skips are the existing image-only fixtures with no editable
paragraphs; all Zotero editor cases ran. Their paths remain listed in the
incoming qualification and the current raw log. They are not counted as passes.
The preserved baseline mail-core **205 VM**, bulk **111 Node** and provider
boundary **195** results remain applicable through exact unchanged source
proof; they are not claimed as new executions after the main advances.

Every accepted run records its exact command, raw log and before/after source
hashes. The final-mail receipts additionally capture the package libraries and
editor inputs used by the combined host/editor run. The late source verifier
compares accepted bindings with Git source `00d44a69d19de20cdb7754b754c4d32d86d078cc`. Earlier successful runs
on different sources stay historical. Diagnostic failures remain failed.

## Diagnostic and evidence preservation

The late archive preserves the original picture-loss failures, the stale
geometry fixture failure, the seven failing import regressions, and all three
failing continuous-section probe observations. It also keeps the successful
890/748 Word and 374/161 mail runs before the last source reconciliation, without
relabeling those runs as the final source. Fresh combined-source runs above
replace them for publication acceptance.

The baseline archive remains SHA256
`63e9efefcf3eb36ef3ae06483cd1d8da622560265494a3c8de9e0f8713d65074`.
The separate [late evidence archive](late-evidence.tar.gz) is
**4,736,442 bytes**, SHA256 `1ab839ebdeb86599af507d623f98d224620fdd533ff870118a58a8134e8711b8`.
Its [member manifest](late-evidence-members.json) has SHA256 `3f2a4c552ebadc1c1c286fae254caecd9a6c002ea048ce4607598b4750dc0e3c`.
The [source applicability index](late-source-applicability.json) records final
and historical bindings. Equal screenshots are referenced by exact baseline
member/hash rather than stored repeatedly.

```sh
python3 docs/validation/mail-bulk-flags-20261120/verify_evidence.py
python3 docs/validation/mail-bulk-flags-20261120/verify_intake.py
python3 docs/validation/mail-bulk-flags-20261120/verify_late_evidence.py
```

These verifiers use recorded files and local Git objects; they do not query
GitHub Actions. The branch updates used observed expected-head leases without
force. The final publication check verifies equal remote main/branch trees,
ancestry of the saved source and both main advances, and a clean synchronized
local main checkout. Its observed commit identifiers are recorded on PR #275.

Live mail accounts and real sends, installed Zotero/Word/LibreOffice acceptance,
native release packages, macOS font discovery, browser rendering and WASM remain
outside these gates. Node acceptance is compiled JavaScript execution. The mail
feature remains foreground-only, with durable sessions and a remote-command
journal as the next milestone. **GitHub Actions, workflow runs and status
endpoints were neither queried nor awaited.**
