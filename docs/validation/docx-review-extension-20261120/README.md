# Extended DOCX review — 2026-11-20

Adds native `rPrChange` and `pPrChange` review and paired text moves through
`moveFrom`/`moveTo` plus their named range endpoints. Current formatting is
parsed independently from its previous snapshot. Accept retains current direct
formatting; reject restores the prior sparse direct set and recalculates style
inheritance, including document/table/paragraph/character layers.

Moves resolve all source/destination fragments as one preflighted operation.
Malformed ranges and missing prior formatting fail explicitly. Locked content
controls are checked before either side changes; Undo restores both sides,
paragraph properties and original revision objects/metadata. Independent run
and paragraph formatting can overlap text revisions without false attribution
conflicts. Formatting over deleted text disappears or retains the surviving
range. Review labels/filters distinguish types in English and Arabic; formatting
is not displayed as deleted text. Text-only final/original previews exclude move
sources/destinations appropriately.

## Local and live validation

[Acceptance receipt](acceptance.json): **69 engine tests and 70 editor tests**,
139 unique passing cases, no skips. A final six-test editor replay covers the
completed history snapshots. Tests include three direct/isolate saves, inherited
properties, overlapping text/format revisions, empty runs/paragraphs, atomic
move preflight, protected content, multi-run/multi-paragraph move ranges,
comments, comparison projections and existing revision ownership/scaling.

Microsoft Word **16.111.1** opened the synthetic fixture without repair and
identified all four native types. It saved the DOCX; Quds imported that file,
preserved author/date and pending changes, then produced pending, accepted and
rejected copies. Word reopened those with **4, 0 and 0 revisions**, respectively,
and the expected text order. See [Word's native types](word-native-types.txt),
[Quds verification](quds-word-roundtrip.json) and
[Word reopening results](word-quds-reopen.json).

The first save attempt encountered Word's sandbox folder-access dialog. The
accepted run uses a dedicated fixture directory inside Word's own cache and
explicit native `open file name` automation. Only generated fixture documents
were saved; existing user documents were not changed. Fixture windows were
closed using accessibility actions restricted to their test-name prefixes.
The fixture's Word-saved document XML is checked into the engine tests, so this
import regression is reproducible without requiring Word on every machine.

Explicit live gate:

```sh
dart run tool/fidelity/check_extended_word_review.dart word-saved-fixture.docx output-directory
```

It requires the four-change synthetic fixture and fails on missing inputs.
It does not treat an empty/skipped run as interoperability evidence.

## Qualification boundary

This extends **run/paragraph formatting and paired text moves**. It is not
complete support for every Word revision class: paragraph-mark structural
changes, whole paragraph/row/cell insertion/deletion, table/section-property
revisions and moved floating objects remain outside this qualification.
The tested Word application round trip is on macOS, not every Word version.

Native semantics references:
[run-property history](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.runpropertieschange),
[paragraph-property history](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.paragraphpropertieschange),
and [move source runs and paired ranges](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.movefromrun).

## Integrated preview

Reconciled incoming main through `096ddbef`, including the bundled macOS runtime
qualification, mail and Zotero work. The only overlap with the tested Word source
was an unrelated Slide controller background update. The review implementation
is published as `a452efda`. Its separate **CrispOffice Review Preview** passed a
release arm64 build, deep signature verification and a 20-second startup. The
five native libraries and notices are bundled, with the spaCy digest sealed in
the app. The runtime was rebuilt with the incoming reproducible-prefix mapping.

The explicit native worker gate passed German/English linguistic analysis and
NER, plus the German grammar smoke `schläft => schlafen`, against that preview.
It used isolated test model data and did not download executable packages.
See [preview receipt](preview-acceptance.json), [native gate](preview-native-gate.txt)
and [analysis](analysis.txt). Existing app windows were not replaced.

## Empty-run attribution guard

A final regression adds a guard for multiple empty formatting runs at the same
text offset, or an empty run removed by an outside edit. Without a unique run
target, export/decision now fails explicitly rather than assigning one run's
history to another. A valid single empty run still saves and resolves normally.
The [23-case focused replay](empty-format-guard-tests.txt) passed; the additional
case raises the unique regression count from 139 to **140**.

Final preview code is `930074b8` (**CrispOffice Word Review Preview**), including
the empty-run guard. Its arm64 release build, deep signature validation and
20-second startup passed. All five signed native library hashes match the
previously qualified preview exactly. See [final preview receipt](final-preview-acceptance.json)
and [guard analysis](empty-format-guard-analysis.txt). This final preview is
opened separately; existing windows and documents are preserved.
