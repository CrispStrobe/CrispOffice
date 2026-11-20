# Main 698209aaa reconciliation

## Captured sources and preservation

The fixed incoming main is `698209aaa6e7f1350b6541df5eb192b7b233443d`
(PR #276). The first-parent integration baseline is the qualified Word/Mail
checkpoint `cf25a0a3d80ee18d2550161af182bacc4e49d18f`. Their merge bases are
`e975cec13b289fe067ef406cd3044701ecc44744` and
`835b8019cbb873c72424e63d4df292174edd3c3e`. No additional feature branches were
refreshed or swept into this reconciliation.

The only new production paths relative to that baseline are:

- `packages/quds_office_engine/lib/src/word/model/word_zotero.dart`
- `packages/quds_office_engine/lib/src/word/model/word_zotero_citing.dart`
- `packages/quds_office_engine/lib/src/word/model/word_zotero_note.dart`
- `packages/quds_office_engine/lib/src/zotero/zotero_citing.dart`

All fourteen changed Dart files (four production files, eight test files and
two acceptance entrypoints) match incoming main and its historically qualified
source `180399f99a3898501ab1959e3b845150d7da59fd` byte for byte before the final
gate. The [source review](main-698-source-review.json) records those hashes.

All other library code retains the baseline bytes, including the reconciled
Mail coordinator/providers/UI/hosts, the Word VBA compiler, the header-picture
and direct-formatting repairs, and the installed-font loader. Canonical
`word_measurements` (eight operations), `word_unit_conversions` (nine) and
`word_named_measurements` (thirteen) examples, tests and drivers remain unchanged.
The qualified contained-text fixture also remains unchanged. The shared
historical ancestry avoids reintroducing older Mail code or duplicate
measurement families under incoming alternate names.

## Documentation resolutions

The two VBA guides retain the qualified contract and example names from `cf25`.
Both engine and editor changelogs retain their existing Word/Mail entries and
add the incoming Zotero entries. All new Zotero usage/roadmap documentation,
tests and acceptance tools are preserved.

The incoming report and qualification receipt were renamed to
[incoming-main-698-checkpoint.md](incoming-main-698-checkpoint.md) and
[incoming-main-698-qualification.json](incoming-main-698-qualification.json).
The report carries an explicit historical heading and updated receipt links;
the receipt bytes and raw archive are unchanged. Existing intake links were
adjusted to point to that historical report. This prevents its earlier totals
from being mistaken for validation of the later combined checkpoint.

## Incoming evidence audit

The archive is 256,079 bytes with SHA-256
`16555ee79fd5d2699bc015a39cceac70f8d19f7cf700aa7a616b4bf24702917d`.
All 48 member sizes and hashes match the incoming manifest. An independent
recount of the archived JSON events confirms its historical populations:
495 engine passes, 378 editor passes with eight explicit skips, and 928
incoming Word/Mail passes. The separately recorded 405-case formatting rerun
is a subset of the incoming population, not an additional total. Terminal
events, complete test identities and empty error streams were checked.
These are historical-source checks, not execution of the combined tree.

## Focused combined-source qualification

The [machine-readable plan](main-698-gate-plan.json) selects fourteen engine
Zotero suites and nine editor Zotero suites. They cover all changed/new tests,
cell span/width/resource boundaries, note/table DOCX interoperation, structural
citation adjacency, protocol capability validation, stale results, editor
transactions and undo/redo. Their earlier populations were 470 and 257 cases;
those numbers are expectations for recounting, not claimed new passes.
Unrelated slide/proofing and already-qualified generic incremental suites are
not added merely to inflate this scope.

The changed adjacency helper is called by `WordZoteroCitingSession`; note HTML
parsing is likewise used by the Zotero transaction flow. Native editor commands
and the Zotero dialog drive the session/client. The retained automation sources
and `office_macro`/`office_vba` suites contain no calls to these changed helpers;
the Word serializer/layout and all macro test sources are unchanged. Their
previous executed counts keep their original source attribution rather than
being represented as fresh reruns.

The final gate must run only after publication of its exact remote source,
using a worktree-local package mapping. Its receipt must capture source/runtime
identities before and after, complete case identities, process exits and
terminal success. No final combined-source test result is asserted here.
