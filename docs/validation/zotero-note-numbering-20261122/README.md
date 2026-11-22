# Zotero automatic note-numbering parity — 22 November 2026

## Delivered behavior

Editable Zotero ODT exchange now accepts Word's default lowercase Roman
endnotes and preserves continuous automatic **decimal, lowercase Roman and
uppercase Roman** numbering. Footnotes and endnotes have independent sequences
starting at one. The original document remains the source of ordinary saves;
exporting an editable ODT copy leaves its dirty state, undo history and DOCX
save destination intact.

The baseline reproduction at `b13a170c` refused a default Roman endnote while
accepting an explicit decimal control. The same reproduction succeeds with the
qualified implementation. The exporter validates effective native settings and
every ordinal in a cited note class, including preceding uncited notes. The
importer checks cached labels against those settings and retains explicit native
numbering through DOCX save/reopen. Zotero's numeric `noteIndex` remains an
integer independently of the displayed Roman label.

This is one bounded parity increment. It does not establish full Word or
LibreOffice plugin parity, installed Zotero acceptance, or visual equivalence.

## Supported and guarded numbering

| Setting or operation | Qualified behavior |
| --- | --- |
| Continuous decimal notes starting at one | Supported independently for footnotes/endnotes |
| Continuous lower/upper Roman notes | Supported for ordinals 1–3,999, including default Word endnotes |
| Uncited notes before/between cited notes | Counted in the actual sequence and validated |
| ODT import followed by DOCX save/reopen | Active fields, preferences, physical note owners and explicit formats preserved |
| Editor Refresh, original-source field context, undo/redo | Numeric note order and citation ownership preserved |
| Studio editable ODT copy | Source state and subsequent DOCX save route preserved; invalid settings refuse before destination selection |
| Custom marks, format changes within one note class, restarts, non-one starts | Remain guarded for active Zotero note exchange |
| Malformed, duplicate, incomplete or wrapped native settings | Refuse exact automatic-numbering qualification; labels and note IDs do not substitute for settings |
| Alphabetic numbering | Deferred pending an explicit producer-aware contract |

Default handling is explicit. A recognized LibreOffice file with no note
configuration uses decimal footnotes and lowercase Roman endnotes only when
its cached labels agree. A present LibreOffice configuration with omitted
`style:num-format` uses that producer's decimal behavior; an explicitly empty
format remains refused. A generic present configuration
with missing/empty format is not reinterpreted as a visible automatic number.
The existing generic absent-configuration decimal convention and qualified
LibreOffice zero-offset convention are retained. Ordinary ODT export keeps its
existing fixed-label behavior; the writer's exactness checks apply to explicit
editable Zotero export. Reader configuration and cached-label validation apply
to every imported note, including notes without Zotero fields.

A real 28-note LibreOffice alphabetic probe produced `z, aa, ab` when
`num-letter-sync` was absent/false and `z, aa, bb` when true. This conflicts
with the corresponding ODF prose, so broad alphabetic support would silently
change labels for some producers. Both probe attempts and original files are
retained; the canonical probe is the accepted investigation.

## Reconciled source and incremental remote saves

Initial main was `b13a170cdb5fd42b9a0f2c77d97c996caf5d0d7f`, including Zotero
PR #364, Mail PR #363 and Word PR #362. Initial intake fetched all 29 advertised
fork branches, all 364 PR heads and all four upstream branches, with no open
fork PRs. Recent PR heads #265–364 were already contained. Fourteen old,
superseded PR heads outside that range remain recorded rather than replayed
over newer accepted implementations.

The initial reconciliation preserved Mail's `13405f72` and Word's `ee3ba4f6`
histories in `be2908c7`. Subsequent forward-only checkpoints saved the scope,
implementation, editor/Studio tests, documentation, exactness fixes and local
qualification corrections. Incoming Word cell-prefix and Mail membership
observation work was preserved in `f16400dc`. The final bounded feature-branch
intake captured Mail `430bcf26` and Word `806525fd`, then reconciled them in
`89789360`. All 34 captured remote heads (30 fork, including this new branch,
and four upstream) are ancestors of that source.

The final tested source is **1896e11febd0d08159c85ddbbcd94743383f1e61**, tree **2f955065ec1ee94ea3db8e3cfbda7fcc94036fc1**. Its last
source adjustment removes four redundant null assertions from two incoming
Mail test-support files; it changes no production behavior. Relevant earlier
engine/editor/converter inputs remain byte-identical, and the final affected
Mail suites were rerun. Later evidence and publication commits change only
documentation/artifacts unless a separately recorded main reconciliation says
otherwise.

While qualification finished, main advanced through Word PR #365 to
`ffdf603c`. Checkpoint `dde9845f` reconciles that main history and its complete
Word evidence. Its ten-path delta from the tested source contains only
documentation/artifacts; the two incoming formatter changes were already
byte-identical. The [main reconciliation receipt](main-reconciliation.json)
records the unchanged production/test/dependency inputs and preserved ancestry.

The final publication check also retained main PR #366 (`8589e6f9`), which
updates only the earlier Word validation publication record. Its single-file
delta introduces no code/test/dependency changes. The outer
[final publication receipt](publication-final.json) supplements the unchanged
sealed evidence archive with this last main intake.

The [initial intake](intake.json), [final bounded intake](intake-final.json),
and [qualification summary](summary.json) record exact refs, parents, source
attribution and checkpoint history. The branch
`codex/zotero-native-parity-20261122` is retained remotely. GitHub Actions were
not awaited or used as an acceptance gate. Publication uses ordinary
forward-only updates with an observed expected head; repository protections
are unchanged.

## Local qualification

Runtime: verified **Flutter 3.47.8 / Dart 3.13.7**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`, with hash-verified dependency
archives and offline locked resolution. All 91 tracked manifests/lockfiles
remain unchanged. The receipts record the runtime, resolved package config,
commands, source tree, before/after inputs, reporter events and artifacts.

| Accepted cohort | Distinct passing cases | Source/evidence |
| --- | ---: | --- |
| Zotero engine, 11 suites | 372 | `52f53c99`, unchanged source-closure proof to final source |
| Zotero editor, 5 suites | 80 | `8e18fb2e`, unchanged source-closure proof to final source |
| Zotero Studio, 2 suites | 11 | Repeated on reconciled `89789360` shared host |
| Incoming Word, 10 suites | 583 | Latest complete result for each suite; final integration run on `89789360` |
| Incoming Mail core | 53 | Reconciled `89789360` |
| Incoming Mail transport | 258 | Reconciled `89789360`; 8 selected files, 5 visible test suites |
| Incoming Mail store, full VM cohort | 1,061 | Reconciled `89789360`; includes schema migration and crash recovery |
| Incoming Mail Studio, 7 suites | 305 | Reconciled run plus final replacements for 2 affected suites |
| **Effective total** | **2,723** | Unique package/suite/test identities, with superseded results replaced |

All accepted cases have zero failures, skips, unfinished cases or reporter
errors. The Zotero subtotal is **463**. This increment adds **70 Zotero cases**
(60 engine, seven editor and three Studio), already included in that subtotal.
Tests cover independent foot/endnote formats, uncited-note sequencing, Roman
range limits, actual native settings, default handling, conflicting cached
labels, malformed XML, active field ownership, note indexes during Refresh,
source preservation, stale operations, undo/redo and DOCX reopening.

The Word total is 423 unchanged original cases plus 146 cases from the first
supplement and 14 from the final integration run. The original two fixture
failures remain in the evidence: read-only recording is rejected before the
operation, and the unknown named argument is on source line four. Corrected
fixtures assert the real permission boundary and retained source state. No
production change was needed for these corrections. Original Mail core/transport
and earlier Studio results are likewise replaced, not added to the final total.

Strict formatting and fatal-info analysis pass for all **72 changed Dart
files**. The original formatting and four-warning analysis attempts remain
available alongside their clean replacements. The Mail store VM gate excludes
its explicitly Node-only `browser_problem_test.dart`; no Node/browser store
qualification is implied.

Separate Word portability checks run the same complete BAS and the 78-case
conformance corpus on the Dart VM and JavaScript. Outputs are byte-identical;
the smoke result records six operations, one revision, replay/reopen behavior,
opaque VBA preservation and rollback. Those 78 cases are not added to the unit
test total.

## Actual LibreOffice file round trips

The accepted converter source is `52f53c99059b1521dd08b9f8f4f65133e87e980b`.
The actual executable is **LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. This identifies a development
build, not a tested stable release or installed Zotero plugin session.

| Distinct fixture | Notes | Active citations | Formats |
| --- | ---: | ---: | --- |
| Default endnotes | 10 | 4 | Lowercase Roman |
| Mixed footnotes/endnotes | 20 | 4 | Uppercase Roman footnotes, lowercase Roman endnotes |
| **Unique coverage** | **30** | **8** | **2 fixtures** |

Each fixture undergoes **two actual LibreOffice save cycles**. At the original,
first-save and second-save stages, Quds imports the ODT and saves/reopens DOCX.
All six ODT packages and six reopened DOCX packages retain the expected labels,
content, citation IDs/metadata/order, note ownership, numeric `noteIndex` and
preferences, including the expected native ReferenceMark/Field adaptation.
Uncited preceding notes are included. Independent ZIP/XML inspection agrees
with the executable assertions. All nine commands exit successfully and all
34 recorded artifacts match their hashes.

LibreOffice adds an unused decimal footnote configuration to the endnote-only
fixture; its active endnote settings remain correct. Repeated stages do not
increase distinct fixture, note or citation counts. No screenshot-based layout
or Microsoft Word rendering result is claimed.

The independent evidence audit reparses reporters, verifies raw file/log and
input hashes against immutable Git objects, checks the source/dependency
closure proofs, and inspects the retained ODT/DOCX packages. Its report and
read-only scripts are retained with the evidence.

## Evidence and reproduction

- [Qualification summary](summary.json): final counts, exact source mapping,
  checkpoint links, limits and archive hash.
- [Readable receipts](receipts/): principal result and audit records.
- [Complete evidence archive](evidence.tar.xz): raw reporter events, case lists,
  immutable receipts, input manifests, scripts, baseline/control files,
  converter originals and both saved stages, alphabetic probes, portability
  outputs, runtime provenance and preserved failed/superseded attempts.
- [Archive file index](evidence-index.json): per-entry SHA-256 and size.
- [Local cohort runner](run_local_gate.py): executes the recorded suite list,
  records actual outcomes and refuses drift or incomplete results.

Extract the archive with `tar -xJf evidence.tar.xz`. The archived scripts preserve
the exact paths used for this session; use their recorded command arguments or
adjust only workspace/output/runtime paths on another machine. Obtain the
recorded runtime and run locked/offline dependency resolution before repeating
commands. For a focused current-source run, use:

```sh
python3 docs/validation/zotero-note-numbering-20261122/run_local_gate.py \
  --root "$PWD" \
  --package packages/quds_office_engine \
  --runner dart \
  --output /absolute/path/to/new-numbering-run \
  test/odt_zotero_note_numbering_test.dart
```

Use `--runner flutter` with the appropriate editor/example package for widget
cohorts. Exact full suite lists and arguments are in the receipts. The archive
omits installed SDK/Pub caches, temporary LibreOffice profiles and duplicated
frozen source trees; their identities and source manifests are retained so the
Git-backed source and runtime can be reconstructed. Original receipts are not
rewritten to hide absolute paths, failed attempts or earlier source identities.

## Remaining parity work

The next acceptance priority is the installed Zotero workflow on identified
Word and stable LibreOffice releases: edit citations, Refresh, change style,
edit bibliography, save/reopen and repeat transfers using these retained Roman
fixtures. Qualify actual host rendering and retain any failing original files.

Alphabetic numbering, custom marks/restarts and richer native note configurations
need explicit ownership/producer contracts and separate fixtures. Broader ODT
table/image/structure limits and custom DOCX separator behavior remain tracked
in the [parity roadmap](../../roadmaps/zotero/word-processor-parity.md). Existing
source-preservation, stale-operation and undo guarantees remain required for
each continuation.

## Primary references

- [Zotero LibreOffice plugin usage](https://www.zotero.org/support/libreoffice_writer_plugin_usage): the word processor controls note numbering; Zotero controls citation style and placement preferences.
- [Moving Zotero documents between word processors](https://www.zotero.org/support/kb/moving_documents_between_word_processors): native editable ODT and temporary transfer carriers have separate contracts.
- [ODF 1.3 Part 3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html): note configuration and number-format/default semantics (§16.31.3, §19.504–505, §19.832, §19.874.5, §19.875).
- [Pinned LibreOffice numbering conversion](https://github.com/LibreOffice/core/blob/e2dc267756d88e979036b1a5715d8c585a9e85e6/xmloff/source/core/xmluconv.cxx).
- [Pinned LibreOffice note configuration import](https://github.com/LibreOffice/core/blob/e2dc267756d88e979036b1a5715d8c585a9e85e6/xmloff/source/text/XMLFootnoteConfigurationImportContext.cxx).
