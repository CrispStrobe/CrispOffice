# Editable Zotero ODT output — 21 November 2026

**Status: implemented and locally qualified.** The final source passes 631
unique engine, editor and Studio tests with no failures or skips. Actual
LibreOffice file conversion preserves the seven native Zotero records in two
synthetic fixtures. Installed Zotero plugin and release-host acceptance remain
separate requirements.

Qualified remote source: `cb27581214e00b8cf58cafb65193ee85561c6eb4`.
Qualified Git tree: `baab4d22be5d462a86ddbe42a3c69c72ce9a1764`.
Starting main: `3dbaa8429b14ac43721e165b4d50d3f6d2845309`.
Integrated main: `1078372da9213c1ef4cdd362ca2285db9acb8d7b`.
Checkpoint branch: `codex/zotero-editable-odt-20261121`.

## Delivered behavior

Studio Word now provides **File → Export Zotero ODT…** and the corresponding
File ribbon action. The engine exposes
`OdtDocumentWriter.writeEditableZoteroBytes(document)`. This explicit copy path
retains native citation ReferenceMarks, complete bibliography TextSections and
ReferenceMark document preferences. It preserves exact field ownership and
metadata within the documented body, visible-table-cell and authored-decimal-note
envelope. Unsupported active data refuses before a file is offered for saving.

Studio serializes a detached snapshot before opening the save picker. The
source document, normal DOCX destination, dirty state and undo history remain
intact; edits made while the picker is open remain in the source. The export
adds an ODT extension when necessary. Ordinary cached-text ODT export retains
its existing contract. The [native-output contract](../../roadmaps/zotero/native-odt-output.md)
specifies storage, ownership, resource bounds, supported formatting and refusals.

Repeated-conversion tests exposed and fixed a native reader bug: admitted
decimal ODT endnotes reverted to Word's Roman default after DOCX saves. The
newly constructed section now records decimal endnote numbering explicitly.
Independent source review also resolved merged-cell output and bounded opaque
XML inspection before final qualification.

Strict Studio analysis exposed a conditional browser Mail constructor mismatch:
the shared workspace supplied `onClose`, while the browser dialog did not
accept it. The browser dialog and saved-message view now route that callback
consistently, with an embedded-close regression. This focused integration fix
does not qualify all recently integrated Mail features.

## Incoming-work reconciliation

All advertised fork branches and all 323 pull-request heads were fetched at
initial intake, along with all four upstream branch heads. At that snapshot,
31 fork topic heads and all four upstream heads were already ancestors of
starting main.

The [initial intake](initial-intake.json) accounts for all 361 fetched refs:
344 actual ancestors, ten reverified patch equivalents, two empty nonmerge
patch histories, two API-confirmed squash integrations and three refs for two
unfinished heads. No ref was unaccounted. The initial unfinished heads were
Word draft PR #322 at `870e0ff97c9c6290bfe14bb6a137d46c54f2e697` and Mail work
at `32a6dcd4e56584b5af34625b44a845eb15ba44bd`.

Mail PRs #324 and #325 landed during this continuation. Their source and
original ancestry are included through main
`1078372da9213c1ef4cdd362ca2285db9acb8d7b` and remote merge checkpoint
`2cf5055db72e229b10bf27735ba92e72e996ff84`. The Mail work record's own
outstanding qualification remains explicit; it does not borrow Zotero results.

The [publication intake](publication-intake.json) and
[final read-only refresh](merge-intake.json) record subsequent branch movement.
At the final ref observation, **21 November 2026, 18:32:48 CET / 17:32:48 UTC**,
main was unchanged, all four upstream heads were unchanged, and all 36 fork
branches were accounted for. No new completed main integration was required.
Two independent Word-style implementations remained unfinished:

| Work | Observed head | Reason preserved separately |
| --- | --- | --- |
| Draft PR #322, `codex/word-vba-extensions-20261121` | `cf12544df1a7965615f38eab8d22dae5cfa0d7c0` | Still open and draft; eight ahead and six behind main |
| `codex/word-vba-styles-complete-20261121` | `ce90d6db8c28797a79b63ff1dfda8586faf74ff9` | Contains current main and our earlier baseline checkpoint, but explicitly leaves final consistency review and exact-source qualification pending |

The Word heads diverged by twelve versus three commits. The original draft's
native operation had been added since initial intake, so its old missing-operation
assessment is historical. Neither branch was merged solely from its name or a
stale PR description. Both remote work histories remain preserved.

## Pending baseline completed

PR #323's merged-table implementation had not executed locally because its
executor exhausted disk space. This continuation installed and verified the
repository-pinned Flutter 3.47.8 / Dart 3.13.7 runtime and exact locked package
archives. The root lockfile remained unchanged. Runtime and dependency hashes
are retained in [runtime.json](runtime.json) and
[runtime-dependencies.json.gz](runtime-dependencies.json.gz).

The [baseline receipt](baseline/receipt.json) and [record](baseline/README.md)
report 219 passing engine cases and 93 passing editor cases, with no failures
or skips. All four pending files passed formatting and fatal-info analysis.
Only formatting and five automatic test-string interpolation fixes were needed;
that baseline checkpoint did not change reader behavior. Its original failures,
successful logs and source snapshots remain in
[the baseline archive](baseline/execution.tar.gz). Concurrent new export work
was identified there and was subsequently qualified against frozen source below.

## Final executed qualification

| Gate | Actual final result | Evidence |
| --- | --- | --- |
| Engine, 18 unique suites | 513 passed; zero failed or skipped | [Regression receipt](final/regression-receipt.json) |
| Editor, four suites | 93 passed; zero failed or skipped | [Regression receipt](final/regression-receipt.json) |
| Studio, four suites | 25 passed; zero failed or skipped | [Studio receipt](final/studio-receipt.json) |
| Engine/editor and Studio fatal-info analysis | No issues; both final checks exited zero | The two receipts and archived analyzer logs |
| Formatting, all 16 changed Dart files | Zero changes required | [Format receipt](final/format-receipt.json) |
| Independent source review | No remaining blocking finding | [Review receipt](final/review.json) |
| Actual LibreOffice save and inventory comparison | Two fixtures; all seven records matched | [Converter receipt](final/converter-receipt.json) |

**631 is the unique final test total.** Earlier baseline and iterative runs
(78 writer/preferences cases, 63 lifecycle/reader cases, and 23 Studio cases)
overlap these suites and are excluded from that total. The engine gate includes
the eight original baseline suites, new writer and lifecycle suites, ordinary
ODT export, document preferences, note and section fidelity, Word note numbering,
and the existing transfer model/session/protocol suites. The Studio gate covers
export, native ODT opening, shortcuts and the browser Mail close callback.

The engine runner used the exact locked test-package entry point because the
ordinary `dart test` startup stalled in this executor. Flutter tests used
`--no-pub`. Receipts contain exact commands, working directories, timestamps,
exit codes, actual JSON completion events and output hashes. No passing result
is inferred from test source or a process merely starting.

Before/after manifests verified 534 engine/editor inputs and 916 Studio/workspace
inputs with zero byte changes. Direct Git-blob comparisons additionally matched
all 533 and 915 corresponding tracked inputs to published source `cb275812`:
[regression binding](final/regression-source-binding.json) and
[Studio binding](final/studio-source-binding.json). The only captured generated
input outside Git was `.dart_tool/package_config.json`. The manifests include
libraries, selected tests, tooling, manifests and locks.

The engine receipt's pre-commit HEAD was `462331f`; its working-tree hashes bind
the tested changes to the published source. The Studio run spanned publication
from local commit `887207af` to remote commit `cb275812`; both commits have the
same qualified tree. Git Data API publication verified every blob SHA and the
complete tree before advancing the remote branch with an expected-head lease.
Subsequent evidence/documentation changes do not alter the qualified product
source.

## Actual LibreOffice file conversion

The committed `packages/quds_office_engine/tool/zotero/odt_export_acceptance.dart`
created fresh fixtures, the installed LibreOffice opened and saved them through
`--headless --convert-to odt:writer8`, and the same tool checked their inventories.
All three commands exited zero with empty stderr. The exact runtime was
**LibreOfficeDev 26.8.0.0.alpha0**,
build `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.

| Fixture | Native records | Verified locations |
| --- | --- | --- |
| `body-bibliography.odt` | Two citations and one bibliography | Body paragraphs |
| `table-notes.odt` | Four citations | Body, merged table cell, footnote and endnote |

The verifier matched field order, complete names, kinds, storage, metadata,
cached text, paragraph-text lists, document preferences, starting stories and
table-cell ancestor counts. The saved inventories had no reported issues, and
all fields remained native import candidates. Source fixtures were unchanged.
The generator SHA-256 is
`cf61f5ff91d534aaab93cb7547abf09b18787536b09cf4fff747d9a57ffe2be8`.
The receipt records both executable hashes and every fixture hash.

This is actual file-converter evidence. It does not exercise an installed
Zotero plugin, compare rendered layout, establish stable-release compatibility,
or import LibreOffice's rewritten output through `OdtDocumentReader`. The
separate automated lifecycle tests qualify their own native import/export and
DOCX cycles. General Word/ODT formatting limits remain independent of active
metadata preservation.

## Retained evidence and remote checkpoints

[summary.json](final/summary.json) provides the machine-readable final totals.
The [final execution archive](final/execution.tar.gz) contains all final logs,
source manifests, exact commands, harnesses, both original and LibreOffice-saved
fixtures, independent review evidence and retained iterative failures.
[archive-contents.json](final/archive-contents.json) hashes every archived file;
[artifacts.json](final/artifacts.json) hashes the published receipts and archive.
The isolated LibreOffice profile and runtime/package caches are not archived.

| Remote checkpoint | Preserved work |
| --- | --- |
| `0a5db51c8483e7ad0b6de088ae1e75b566942a7d` | Initial scope and incoming-work record |
| `2cf5055db72e229b10bf27735ba92e72e996ff84` | Completed Mail/main integration with original ancestry |
| `462331f66e1ba3f97cbd74818ee9beaf1861d9e0` | Executed pending ODT baseline and runtime evidence |
| `cb27581214e00b8cf58cafb65193ee85561c6eb4` | Editable ODT implementation, regressions, Studio flow and converter tool |

This evidence commit completes the record on the same remote topic branch.
The user authorized final main integration without waiting for the starved
GitHub Actions queue. Actions were not queried, rerun or awaited. Checkpoint
and merge messages use `[skip ci]`; branch protection is unchanged.

## Remaining parity work

The next acceptance step is a supported release-host matrix with actual Zotero
plugins: citation editing, Refresh, style changes, bibliography editing and
repeated saves across Quds, LibreOffice and Word. The retained fixtures and
committed acceptance tool provide a reproducible starting point.

Further implementation remains for richer note numbering and note tables,
additional ODT formatting/images, unsupported stories and structural selections,
and compact merged-row rendering. Current explicit refusals remain in place.
Legacy Apache OpenOffice needs identified application/plugin versions and its
own evidence. This increment closes the bounded native metadata export gap;
it does not claim complete Word/LibreOffice/OpenOffice plugin parity.
