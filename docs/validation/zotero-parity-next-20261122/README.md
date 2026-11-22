# Zotero parity continuation — 22 November 2026

## Delivered behavior

This increment closes two concrete gaps in the existing native Zotero workflow:

- **Unlink all citations** now accepts complete, exclusively owned citations and
  bibliography fields with damaged JSON or invalid metadata schemas. The
  confirmation identifies the damaged count. One undo transaction preserves
  visible text, character/paragraph formatting, notes, tables and document
  preferences; undo restores the exact original codes. Unsafe structures block
  the entire conversion, and a saved/reopened converted DOCX contains ordinary
  text.
- **Editable ODT note exchange** now preserves continuous decimal, lowercase
  Roman and uppercase Roman sequences with initial numbers from **1 to 32,768**.
  Footnotes/endnotes keep independent starts, including uncited notes in each
  sequence. Roman ordinals stay within **1–3,999** and decimal ordinals within
  **65,535**. Native settings persist through DOCX reopening; Zotero's numeric
  note indexes remain the physical note order.

This is a bounded parity increment. It builds on the existing native picker,
CSL processing, document preferences, bibliography, refresh, repair, research
note/annotation and document-transfer implementation. It does not establish
complete Word/LibreOffice plugin parity.

## Safe unlink behavior

The batch command reuses the existing individual-field recovery admission:
complete metadata-damaged packets may retain their native result, while locked,
nested, opaque, incomplete, shared or cross-owner structures remain protected.
Preflight runs before conversion. Cancellation, a changed document or selection,
protected content and unresolved tracking state preserve the original document.

Coverage includes atomic and complex fields, paragraph fields, invalid citation
schemas, multipart bibliography results, body/table/note ownership, supported
healthy header fields, rich formatting, source identity, one-step undo/redo and
DOCX saving. The confirmation is exercised in a narrow RTL layout as well as
ordinary document actions. The metadata extension does not infer missing field
boundaries or broaden the native repair operation.

## Numbering interoperability contract

ODF 1.3 §19.874.5 describes `text:start-value` as an initial number, defaulting to
one. LibreOffice imports and exports its zero-based `StartAt` offset instead.
Applying the wrong interpretation silently changes every note label.

Quds therefore keeps distinct, explicit conventions:

| Producer | Accepted interpretation |
| --- | --- |
| Generic ODF, including existing `CrispOffice` output | Literal initial number |
| Qualified stock LibreOffice/LibreOfficeDev declaration | Zero-based offset |
| Exact `CrispOffice Zotero ODT note-offsets/1` declaration | Versioned Quds offset convention, with explicit per-class format/start configuration |

Only editable exports needing a non-one active-note start use the new Quds
marker. It does not enable unrelated LibreOffice defaults, formatting or
separator handling. Offset declarations and non-one literal starts require a
nonempty exact cached label for every imported note. Duplicate, wrapped,
attributed, wrongly namespaced or unsupported recognizable offset-producer
metadata refuses instead of falling back to another numbering convention.
Unknown normative producers retain their existing literal behavior.

Independent review reproduced the ambiguous-LibreOffice fallback before the
final fix, including a retained active Zotero citation. The original failing
probe and a separate successful after-fix probe are preserved. Regressions cover
that case, all supported formats and note classes, boundaries, mixed starts,
uncited notes, section continuity, mismatched/empty caches and source immutability.
Custom marks, alphabetic formats, mixed settings within a class and page/section
restarts remain guarded. The reader retains its separate **10,000 notes per
class** limit; exporter limits do not imply that every emitted document is within
the bounded reader's content envelope.

## Initial intake and incremental remote saves

Baseline main was `b2bba1638924237435460e4238d4bd98c407fc3a`, after PRs #364–368.
The initial intake fetched all **30 fork branches**, all **368 PR heads** and
all **four upstream branches**. Every captured branch tip and every PR head
#153–368 was already an ancestor of baseline main. Fourteen older PR heads are
recorded as superseded in the existing reconciliation history. No fork PR was
open. The exact snapshot is in [intake.json](intake.json).

Forward-only remote checkpoints on `codex/zotero-parity-next-20261122`:

| Checkpoint | Commit |
| --- | --- |
| Captured intake and continuation plan | `29214ad0f362da2000d7ff20ae9287d33025c46b` |
| Atomic batch unlink recovery | `231926adfa3ed47c6753ab9ba41b41adaa4aebb9` |
| Note-start exchange and lifecycle coverage | `f06afa63a7e321482a60d3f3a4fc39c522fdb29d` |

The qualified product source is **`f06afa63a7e321482a60d3f3a4fc39c522fdb29d`**, tree
**`df98875d455fcd0a5fc648e5af1af4f4c302d54c`**. Remote trees were checked against
immutable local snapshots before advancing the branch. Later documentation and
evidence commits retain these exact production/test inputs.

Two parallel feature branches appeared after the initial intake. Their frozen
read-only review is in [late-intake.json](late-intake.json). Mail checkpoint
`5ecbd68b` references two missing snapshot interfaces and cannot compile as
captured; Word checkpoint `dbfd9329` has no completed qualification record.
Those in-progress tips remain preserved on their own remote branches. They
are not silently represented as accepted main work. Publication refreshes main
and preserves any subsequently published accepted history; no branch is force
updated or deleted.

GitHub Actions were neither queried nor awaited. Local qualification is the
acceptance gate for this increment.

## Local qualification

Runtime: verified **Flutter 3.47.8 / Dart 3.13.7**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`. The complete official SDK archive and
204 locked dependency archives passed SHA-256 verification. Locked offline
resolution leaves every tracked manifest and lockfile unchanged.

| Accepted cohort | Suites | Passing cases |
| --- | ---: | ---: |
| Engine ODT, note numbering, native fields and citing | 21 | 717 |
| Editor unlink/recovery and ODT/note lifecycle | 10 | 154 |
| Studio editable ODT export and Zotero shortcuts | 2 | 27 |
| **Total** | **33** | **898** |

There are **zero failures, skips or unfinished cases** in the accepted runs.
Earlier overlapping runs are not added. All **13 changed Dart files** pass
formatting and strict fatal-info analysis; the entire serial library also
passes targeted analysis. The editor and Studio runs execute the qualified
commit and retain **4,456 unchanged inputs** each. The engine run retains
1,038 unchanged inputs, with all 1,037 Git-backed entries matched to that commit
and the resolved package configuration recorded separately.

The engine cohort uses the verified pinned `package:test` entrypoint directly,
from the engine package directory. This avoids an implicit dependency-resolution
wait and executes the same runner and suites. An earlier root-directory run's
fixture-path errors and an editor root-directory asset error remain diagnostic
records. Initial new unlink snapshot assertions were corrected to observe the
serializer's stable note-separator namespace form. No rejected attempt is
included in the accepted total.

## Actual LibreOffice conversion

Converter: **LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. This is the identified development
build available for file conversion; it is not a stable-release or installed
Zotero plugin session.

| Distinct fixture | Notes | Active citations | Visible labels |
| --- | ---: | ---: | --- |
| Interleaved footnotes/endnotes | 6 | 4 | Decimal 8, 9, 10; Roman ix, x, xi |
| Upper Roman boundary | 2 | 1 | 3998 and 3999 in uppercase Roman |
| Decimal start boundary | 2 | 1 | 32768, 32769 |
| **Unique coverage** | **10** | **6** | **3 fixtures** |

Each fixture passes **two actual LibreOffice ODT saves**. At the original and
both saved stages, Quds imports the ODT, saves/reopens DOCX and performs two
further native ODT/DOCX cycles. Assertions retain complete citation metadata,
source URIs, locators/affixes/omitted-author state, unknown metadata, preferences,
visible labels, physical note indexes and note ownership. Original input bytes
and source documents remain unchanged. Independent ZIP/XML inspection agrees.

All seven commands succeed and all 91 recorded artifact hashes verify. The
final converter run's 369 engine Dart inputs match the qualified commit exactly.
A preceding-source run and a fixture-authoring trailing-whitespace diagnostic
are preserved separately and do not increase distinct coverage. No screenshot,
Microsoft Word execution, installed Zotero workflow or visual-equivalence claim
is inferred.

## Evidence and reproduction

- [Summary](summary.json): exact source, checkpoint commits, counts and scope.
- [Receipts](receipts/): compact engine/editor/Studio/static/runtime/converter
  and independent-review records.
- [Evidence archive](evidence.tar.xz): raw logs, input manifests, original and
  converted ODT/DOCX fixtures, reproduction scripts, rejected attempts and
  read-only late-branch audits.
- [Archive index](evidence-index.json): member sizes and SHA-256 hashes.

Extract with `tar -xJf evidence.tar.xz`. Runtime and converter scripts preserve
original workspace paths; adjust workspace/output/runtime locations when
reproducing them. The archive omits SDK/Pub caches, temporary LibreOffice
profiles and duplicated source trees. Repository source is available at the
recorded commits.

For current editor checks, use the existing
[local gate runner](../zotero-note-numbering-20261122/run_local_gate.py), select
`--package packages/quds_office_editor --runner flutter`, and pass the suite list
from `receipts/editor.json`. Use the example package and Studio receipt for its
cohort. The exact direct engine runner and suite list are in
`receipts/engine.json`. Run from the recorded package directory after locked
resolution. The converter fixture tool and Python runner are under `converter/`
in the archive; their `--output` option creates a fresh result directory.

## Next parity milestone

Run the existing native end-to-end workflows against identified installed
Zotero, Microsoft Word and stable LibreOffice releases using a synthetic
library and these retained fixtures: insert/edit, change style, refresh, edit
bibliography, recover damaged metadata, unlink, save/reopen and transfer again.
Record host focus, note rendering and each plugin's actual responses. Then
extend the separately bounded alphabetic/restarting note, note-table editing
and richer ODF content cases from preserved originals. The
[parity roadmap](../../roadmaps/zotero/word-processor-parity.md) retains the
complete workflow matrix and next structural/image priorities.

## Primary references

- [Zotero Word plugin](https://www.zotero.org/support/word_processor_plugin_usage)
- [Zotero LibreOffice plugin](https://www.zotero.org/support/libreoffice_writer_plugin_usage)
- [HTTP Citing Protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [ODF 1.3 schema, §19.874.5](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html)
- [Pinned LibreOffice note configuration import](https://github.com/LibreOffice/core/blob/e2dc267756d88e979036b1a5715d8c585a9e85e6/xmloff/source/text/XMLFootnoteConfigurationImportContext.cxx)
