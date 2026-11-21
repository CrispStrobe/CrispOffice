# Zotero document transfer — implementation and qualification

Quds implements Zotero's active-document transfer protocol: prepare a temporary
carrier in Quds, save it as DOCX or outbound ODT, and restore incoming DOCX
carriers through Zotero's native formatting callbacks. The editor keeps the
operation detached until it can apply the complete result as one undoable edit.
This is a delivered step toward Word/LibreOffice plugin parity. Installed-plugin
acceptance and direct native ODT field import remain separate milestones.

**Qualification is complete:** **7,225 distinct local VM/editor/Studio cases
passed**, with zero failures or runtime errors and eight identified preexisting
layout exclusions. **171 overlapping JavaScript cases** and three real
LibreOffice conversion routes pass separately. All 60 changed Dart files pass
strict analysis and formatting. Combined product source is
`24165f5ca6aff2d2a0c371ea473d82eba1e10f16`; subsequent changes retain evidence
and documentation. The [qualification receipt](qualification.json) and
[evidence index](evidence/index.json) contain exact source identities, counts,
hashes and acceptance limits.

## Delivered behavior

- **Prepare document for transfer…** invokes Zotero's `exportDocument` command
  and implements its matching document callback. The carrier retains the
  canonical marker, Zotero's instructions, complete raw citation/bibliography
  codes and serialized document preferences.
- **Import transferred references…** and Refresh recognize a pending DOCX
  carrier, reconstruct supported fields in a detached document and require
  Zotero to format every surviving imported field before publication. The
  transfer marker takes precedence over old stored document preferences.
- Ordinary body paragraphs, table cells and uniquely anchored authored
  footnotes/endnotes retain their owners and reading order. The supported
  envelope includes touching citations, formatted hyperlink fragments,
  multiparagraph rich bibliographies, ordinary links and inline pictures.
- Unknown metadata and preferences survive. Modern and legacy markers and
  narrowly verified Google Docs carrier URLs are recognized. Mixed active
  fields/carriers, missing links, duplicate preferences, protected or ambiguous
  owners and excessive payloads fail explicitly.
- Cancellation, stale source state, incomplete formatting and incompatible
  containers leave the original document intact. Successful preparation or
  import is one undo/redo transaction; existing paragraph and note identities
  are preserved.

The [usage guide](../../zotero-support.md#move-an-active-document-between-word-processors)
explains the controls and supported content. The
[parity roadmap](../../roadmaps/zotero/word-processor-parity.md) distinguishes
implemented workflows, structural limits and remaining acceptance.
`upstream-sources.json` and `transfer-carrier-sources.json` retain pinned Zotero
core/plugin contracts and the exact source locations used for implementation.

An initial Add Note callback hypothesis was rejected after tracing its actual
caller: stale wrapper parameter names did not change the positional arguments.
The speculative change in `fb692a7f` was removed in `3da241d5`; it is absent from
the delivered behavior. The original callback contract and tests remain.

## Source intake and preservation

Work started from remote main
`84046975f286407e3c62e5e5352bc16bc89c0d26`. The initial frozen audit covered
**334 fork/upstream branch and pull-request heads**: 309 ancestors, 24
independently verified exact historical equivalents and one uncovered branch.
The three commits ending at `2cd11ced` on `perf/keystroke-trace-20261121` were
integrated first, preserving their ancestry. The resulting audit accounts for
310 ancestors and 24 equivalents, with zero uncovered refs. `intake/` retains
the full inventory, equivalence proofs and portable replay script.

A second capture at **2026-11-21 06:06:59 UTC** covered **338 heads**. It added
Word section controls (`81b76200`), repository-backed Mail sessions (`4d435f81`),
proofing scheduling (`ef30d540`) and keystroke harness improvements (`1460876e`).
All were merged with their ancestry intact. The bounded inventory has
**314 ancestors, 24 verified historical equivalents and zero uncovered refs**.
`publication-intake/` retains immutable-SHA fetch receipts, reviews and replay.

Before final publication, remote main had advanced to
`290dfa43e3bcf410d9bf1bd8194c997c4ee613ae`, containing the completed Word/Mail
PRs and later proofing work. Merge checkpoint `24165f5c` preserves that main as
its second parent. Source changes were limited to proofing scheduling and
notification suppression plus native-I/O/benchmark test corrections; Zotero
transfer production files were unchanged. The combined-source editor and
Studio gates replace the affected earlier runs. Documentation conflicts retain
both the complete incoming API/research contract and the transfer findings.

### Incremental remote checkpoints

| Checkpoint | Preserved work |
| --- | --- |
| `48411168` | Initial recent-work integration before implementation |
| `fb692a7f` | Protocol research/checkpoint, including the later rejected Add Note hypothesis |
| `3da241d5` | Staged model/session/controller/UI transfer; removed that hypothesis |
| `c21b6d51` | Carrier fidelity, appearance guards and transfer documentation |
| `d480d31e`, `43fb2e1a` | Word and Mail ancestry |
| `d24240ee`, `f4c493d9` | Proofing and performance ancestry |
| `d58b8769`, `9228cb58` | Atomic publication, bibliography style and final transfer source freeze |
| `9e78bd86` | Real converter evidence and native test-I/O wait correction |
| `1cad8c01` | Host-owned test fixture shutdown and four disposal regressions |
| `24165f5c` | Current-main reconciliation before the final combined-source gates |
| `338bdd4c`, `5bcb90f9` | Studio raw evidence, reproducible archives and exact current-main applicability proofs |

The branch is `codex/zotero-transfer-20261121`. Existing histories are preserved;
no branch is force-updated. GitHub Actions, check/status endpoints and queues
were neither queried nor awaited. All acceptance described here is local.

## Qualification and counting

| Accepted population | Passed | Skipped | Source applicability |
| --- | ---: | ---: | --- |
| Zotero/ODT/style/proofing-service engine VM, 55 suites | 1,378 | 0 | Frozen transfer/engine source and unchanged engine dependencies |
| Incoming Word/VBA/layout engine VM, 90 disjoint suites | 4,287 | 0 | Same unchanged engine dependencies |
| Final combined editor, 77 suites | 1,371 | 8 | Six disjoint version-5 cohorts; all 1,723 inputs match combined source `24165f5c` |
| Final combined Studio, 8 suites | 189 | 0 | Directly qualified on combined source `24165f5c`, including all three optional benchmark cases |
| Targeted engine JavaScript, 6 suites | 171 | 0 | Additional platform execution; overlaps engine VM and is not added to the distinct total |

The four nonoverlapping VM/editor/Studio populations total **7,225 passes** in
230 suites, with zero failures and eight exclusions. Editor coverage consists
of all 892 Zotero cases, 409 proofing/spelling/language cases and 70 layout cases.
The 171 additional Node executions overlap the engine VM population; the
verifier reports 7,396 executions when that platform repeat is included.

Each accepted test process requires normal exit, a successful terminal event,
zero failed cases and runtime errors, identified expected skips and unchanged
captured inputs during execution. The raw-output audit also rejects unhandled
Flutter/runtime errors outside the JSON test stream. Aggregate rows do not add
another copy of their member cases, and rejected or superseded runs add none.

The eight preexisting editor exclusions are image-only layout fixtures with
`no paragraphs to edit`; their exact names and reasons are retained. All Zotero
editor suites execute. The incoming Word and Zotero engine suites have disjoint
file sets. Portable Word sections/page-setup BAS results are byte-identical
between VM and JavaScript; these assertions are supplemental, not more test
cases. Historical incoming Mail evidence retains its source attribution and
is not counted as fresh execution.

The engine runner captured a deliberately broad 1,967-file snapshot. After the
current-main merge, 1,966 of those files remain exact; the one changed file is
Flutter editor proofing, outside the pure engine's dependency graph. Its exact
old/new hashes and dependency-scope review are retained rather than describing
the entire broad snapshot as unchanged. The portable 1,580-file and converter
357-file snapshots remain exact. Final editor and Studio receipts capture the
combined source directly.

The runtime is authentic **Flutter 3.47.8 / Dart 3.13.7**, framework revision
`737ba8f885dc774b53b442759999a312c9461e4e`. Validation uses an isolated dependency
workspace; repository manifests and its root lockfile were not rewritten.
Formatting uses the declared Dart **3.12** language version. All **60 changed
Dart files** pass fatal-info analysis, format checking and scoped whitespace
checking on `24165f5c`.

The original version-3 harness bytes were not snapshotted. Its commands, raw
results, case identities, environment and input hashes are retained, and the
verifier independently checks them. Later harness/scanner versions are retained
as identified versions; they are not represented as original version-3 bytes.

## Real file-converter qualification

The transfer implementation at `9228cb58` passed three routes using
**LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`:

| Route | Result after native restoration and another DOCX reopen |
| --- | --- |
| Quds transfer DOCX directly | Five active citations and one bibliography |
| Quds transfer DOCX → LibreOffice ODT → LibreOffice DOCX | Five active citations and one bibliography |
| Quds transfer ODT → LibreOffice DOCX | Five active citations and one bibliography |

These are actual file conversions followed by Quds import with controlled Zotero
formatting callbacks. The fixture checks German/Arabic/emoji metadata, item URIs,
locators, unknown members, directly touching citations, a table, footnote,
endnote, ordinary hyperlink, inline image, authored prose and rich bibliography
formatting. Generated, converted and reopened files, exact commands, versions,
hashes and the reproduction script are in
[converter-qualification/](converter-qualification/README.md).

No running Zotero client or Word/LibreOffice Zotero plugin participated in these
converter runs. They establish the tested converter routes and controlled
callback behavior, not installed-plugin compatibility or all LibreOffice
releases.

### Defects found and fixed

Adjacent ODT links with the same target lost part of a citation's linked Unicode
metadata in the tested converter. The writer now emits one continuous link
containing independently styled spans, without crossing structural boundaries.
An undefined generated Bibliography style made that converter append an extra
character; the referenced built-in style is now defined through the existing
selective style export, preserving sparse documents and custom definitions.
Imported carrier appearance is stripped narrowly so active fields do not retain
recognized temporary hyperlink styles/colors.

A covariant programmatic block list exposed a publication atomicity defect:
clearing it could succeed before a bulk insertion rejected its widened element
type. Every owner is now preflighted before any source mutation, elements are
published individually, and editor snapshots verify restorability before the
apply/rollback sequence. Tests cover compatible covariant lists, incompatible
owners, fixed/unmodifiable collections and complete undo/redo.

## Rejected attempts and harness corrections

An initial concurrent editor run stalled while loading two suites after 641
passes and eight skips. It was interrupted and excluded; all 77 suites were
replayed in smaller serial cohorts. Two broad analyzer attempts through
symlinked directory identities also produced duplicate-library diagnostics and
are retained as rejected attempts. The accepted gate analyzes exact changed
source paths and the actual test compiler executes the suites.

The first Studio attempt exhausted 1,000 fake-clock pump turns before a native
SQLite fixture had completed real I/O (approximately 238 ms of wall time), then
stalled on benchmark loading. The helper now has a bounded 15-second wall-clock
wait while retaining fake-timer pumping and real-event-loop yields. Result/error
propagation and assertions are unchanged. Incoming main separately moves two
real-I/O fixture operations into `runAsync`; both changes are retained.

A later 185-case Studio run had green JSON cases but four raw unhandled SQLite
shutdown errors. It is **rejected**, including its historical JSON-only
`accepted_process` flag. The fixture had called the store's close while the
application's asynchronous subscription cancellation was still draining a
repository read transaction. The corrected fixture waits for the actual
host-owned close. Four provider tests hold cancellation, verify the owner stays
open, release it and verify ordered shutdown. A minimal before/after
reproduction and the full 189-case clean retry establish the correction.
Production shutdown code did not change. The stricter version-5 gate and
retrospective raw-log audit prevent green JSON totals from masking these errors.

[Studio evidence](studio-qualification/README.md) and the indexed archives keep
the original attempts, diagnoses, corrections and replacements. They are not
silently overwritten or included in final totals.

## Reproduce and inspect

The **32 immutable archives** total 4,609,614 bytes. Every superseded scope has
an identified replacement, and independent final verification passes with no
unresolved accepted-source mismatch. The evidence index records SHA-256 hashes
for archives, member files, source
snapshots, environment information and exact command vectors. The verifier uses
only Python's standard library, reads archives without extracting them, derives
case totals independently and compares applicable inputs against this checkout:

```sh
python3 docs/validation/zotero-transfer-20261121/verify_qualification.py --repack-check
python3 docs/validation/zotero-transfer-20261121/intake/audit_intake.py \
  --snapshot docs/validation/zotero-transfer-20261121/publication-intake/snapshot.json \
  --head HEAD --output /path/to/intake-replay.json
```

Use `--integrity-only` to inspect historical evidence without requiring a matching
checkout. Real test reruns need the identified runtime/dependencies; exact suite
lists, arguments and environment are retained. The converter has its own portable
[replay instructions](converter-qualification/README.md#reproduce). Raw logs keep
their original bytes even where their whitespace is not source formatting.

## Remaining parity work

The next gate is the versioned
[installed-application acceptance matrix](installed-application-acceptance.md):
Quds ↔ Word and Quds ↔ LibreOffice with live Zotero plugins, including repeated
transfers, rich bibliographies, notes/tables, cancellation and undo. Each route
needs its own application/plugin versions and retained input/output evidence.

Incoming Quds transfer currently uses **DOCX**. Direct native ODT `ReferenceMark`
and preference ingestion requires additional ODF reader/model work. The ODT
carrier exporter does not implement that reader. Legacy Apache OpenOffice needs
explicitly identified compatible versions and its own acceptance; LibreOffice
results cannot establish it. The broader roadmap also retains bounded research
content and table-layout limits. Complete Word/LibreOffice/OpenOffice parity is
not claimed by this increment.

The Word branch's earlier 798 native and 97 Flutter checks of `3da241d5`, and
its subsequent 30-case helper cleanup, retain their original attribution in
[that branch's report](../word-vba-sections-20261121/README.md). They are not
added to the current totals or treated as qualification of later Zotero changes.
