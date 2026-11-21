# Native Zotero round trips through LibreOffice

## Combined-source completion

The [round-trip completion record](../zotero-roundtrip-complete-20261121/README.md)
reconciles this branch, the inline-image continuation, scheduled Mail and the
latest accepted main. It retains the earlier converter failure and separately
qualifies newly exported explicit note-marker styles, semantic uppercase text,
native reference metadata, repeated file saves and current editor workflows.
Its source, fresh local results, exact remote intake and installed-plugin
boundaries are recorded independently. This record retains its own executed scope and source identities.


## Latest integrated qualification

The final combined-source checkpoint is
bb2dfd5272ff8de27ed2ec7f68b71801a2e41886, with tree
5fadc8755a09f06cd1ba3c47a147e05c333258e0. It preserves the completed milestone
below and merges current main 2058a434b2bcc76e7fc7e8a449ff6ce31488eb25,
including native PNG/JPEG ODT support, Mail scheduled sending and the final
selection-cache invalidation fix. Production hunks merged automatically; the
changelog retains the updated Zotero entry once, without its older duplicate.

| Fresh combined-source gate | Suites | Passed | Failed / skipped |
| --- | ---: | ---: | --- |
| Engine | 84 | 2,015 | 0 / 0 |
| Editor | 11 | 147 | 0 / 0 |
| Studio | 16 | 169 | 0 / 0 |
| Total | 111 | 2,331 | 0 / 0 |

Formatting, fatal-info analysis and whitespace checks pass. All 874 tracked
workspace package-library Dart files are captured in the new source snapshots;
every gate's before/after hashes match. The editor cohort includes native image
loading and selection-cache pixels. Studio includes the affected Mail
scheduling, outbox and compose regressions alongside Zotero/ODT tests. These are
selected integration cohorts, not a claim that the entire repository was tested.

Fresh actual converter checks repeat all three core fixtures and 11 fields,
plus mixed-note export inventories. Separate PNG and JPEG fixtures each retain
two pictures and two citations through two actual LibreOffice saves, with three
native DOCX/ODT cycles after each save. All 23 converter commands exit zero;
captured source, original and intermediate input bytes remain unchanged.

Current results are in integration.json, integration-source-binding.json and
integration-intake.json/.md. The separate integration-execution.tar.gz and
integration-archive-contents.json retain the new raw evidence. The original
execution.tar.gz, archive-contents.json, source-binding.json and final.json
remain the completed first milestone below and are unchanged. Initial intake
coverage remains complete; Mail is now integrated, while five later ongoing
refs are explicitly recorded separately. No GitHub Actions were queried or
awaited for either milestone.

## First qualification milestone

This increment reopens supported LibreOffice-saved Zotero ODT files as editable
native Quds documents and preserves them through DOCX and further ODT saves.
Actual file-save acceptance covers body citations, a rich multi-paragraph
bibliography, fixed-width merged/unmerged tables and decimal endnotes. The
oracle compares the authored source model, complete metadata and ownership;
passing a read-only Zotero inventory alone is insufficient.

The first milestone's qualified production checkpoint is
d743c1b3e0791f7e73e5bd87638f8cd43a10fba2, with tree
c94e0fb95ca1897b845527a3cc8898f80c8796f8. Later validation-only commits retain
those production/test bytes. The independent source-binding.json connects
executed inputs to that immutable tree; final.json records exact results.

The converter is **LibreOfficeDev 26.8.0.0.alpha0**, build
2c87e51eeaa2b413ff4ae097b2705eea1995d8e5. These are file interoperability and
native editing checks, not installed Zotero-plugin, Microsoft Word application,
or supported stable LibreOffice release acceptance. GitHub Actions were neither
queried nor awaited, as requested.

## Intake and concurrent main integration

Work began at main 4970f71f983535d045ce263e86835b499db4fda9. The initial fetch
captured 39 fork branch tips, 332 PR heads and four upstream tips: **375 refs**.
All current branch/upstream tips were already ancestors of main; no PR was open
at that intake. Independent Git-object comparisons account for every captured
tip: **361 ancestors and 14 historical equivalents**. Thirteen equivalents have
identical complete trees. PR #140 has identical mode/type/blob entries across
all 37 paths it changed. No historical implementation needed replay.
See initial-intake.json and intake-equivalence.json/.md.

Incoming main was merged twice, preserving new Word shading/text-construction
work and PR #335's proofing/selection repaint cache. The only textual conflict
was the engine changelog; both independent entries were retained. Main
3440c90bc63f9d43edb7e64172bfec3d82036fee is an ancestor of the qualified
checkpoint. The final captured inventory has **385 refs**, with no incoming main
commits left outside that checkpoint. Seven refs represent later concurrent
typography, image and Mail work. final-intake.json/.md and final-refs.txt
identify them explicitly without claiming integration. All original 375 tip
identities were independently rechecked.

Remote checkpoints were saved incrementally without force-pushing:

| Checkpoint | Purpose |
| --- | --- |
| 98a4d0cb69a0d1c70388339c9c76a0b11de6d116 | Intake and execution plan |
| bf54a8e7d976670af87dd3d36f3afc26c1821d3b | Bibliography reopening, note offsets and fixed tables |
| 3eac83d12180f189430e8c81bfef4bf438087c5d | DOCX margins, soft-page hints and converter tool |
| e48b1b617f76823ec4fefd7ce17c0bb4c848aa65 | Note styles, compatible masters and guards |
| 9b4323500d476558a13af8194a65cec165d45da6 | Incoming main Word changes |
| b111ef82508a8418040bfee11bd14180712aa55b | Missing-style regression classification |
| d743c1b3e0791f7e73e5bd87638f8cd43a10fba2 | Incoming main repaint changes |

Every connector-created tree was compared with the exact local Git tree before
advancing its ref. Local/remote merge metadata can differ while trees remain
identical; source-binding.json retains that correspondence.

## Corrected behavior

### Bibliographies

LibreOffice bibliography TextSections now resolve inherited/default section
properties. Only the inert subset is admitted: transparent background, zero
section margins, one column and no active protection. Used unknown formatting,
authored structural content, multiple columns and protection still refuse.
Unused sequence declarations are validated without enabling active sequence
fields. Rich and empty bibliography paragraphs retain ownership, formatting and
unknown metadata through controlled native refresh/edit/unlink regressions.

The retained unmodified bibliography fixture has SHA-256
f2e940184bfe599a646ee9ff7931643f487767af6f0a6690dbcc8a4ad3c0d05f.

### Decimal notes and endnote pages

A narrowly qualified stock LibreOffice generator identifies its zero-based
note-start convention. Each cached decimal label must independently match the
native ordinal. Unknown producers retain the existing ODF interpretation.
Custom labels, alternate formats and restarts remain guarded.

The editable writer declares distinct 65-percent superscript styles for each
footnote/endnote symbol and anchor role. Reusing a character style lets
LibreOffice overwrite a role's internal pool identity and recreate a baseline
symbol or 58-percent anchor. This was reproduced with unchanged host files and
traced to the exact converter build's
[character-style setters](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/core/doc/docftn.cxx).

The reader checks the complete effective marker style and admits no extra
formatting it would discard. Endnotes select the final section's regular master.
On reopening, that master must have compatible supported geometry with all
used body masters. Different note-page margins, stories, alternation, missing
references and authored structural text remain errors.

### Tables and DOCX margins

The previous ODF margins alignment expanded an explicitly sized table to page
width in LibreOffice. Editable export now pairs absolute widths with physical
left/center/right alignment. Border-model defaults are admitted only inside the
existing borderless, zero-padding ODT subset; active geometry is not dropped.

The actual ODT-to-DOCX cycle also exposed zero cell margin becoming the native
constructor's four-point default. New tables now serialize all four equal
physical margins. Complete uniform direct/inherited native dxa margins project
into the scalar model. Partial, asymmetric, logical-edge, malformed or extension
source remains opaque and sparse; an unsupported direct declaration blocks a
guessed inherited fallback. Physical widths are bounded to 0–32767 twips.

### Pagination hints

Optional text:use-soft-page-breaks and empty cached soft-page markers are
validated and recomputed. Reexport does not copy stale hints. Authored hard
page breaks retain their separate native properties.

## Actual converter acceptance

The oracle is the authored model, not a model normalized by a prior DOCX save.

| Fixture | Active fields | Preserved content |
| --- | ---: | --- |
| Body and bibliography | 3 | Two citations, rich/empty entries, 36-point hanging indent, six-point spacing |
| Tables | 6 | Left/center/right, 72 + 108 point grids, merged/ordinary cells, zero margins |
| Endnotes | 2 | Labels 1/2 from source IDs 7/19, marker/anchor styles, page geometry |

All **11 fields** pass authored model → editable ODT → actual LibreOffice save
→ native reopen → DOCX save/reopen → editable ODT reexport → second actual
LibreOffice save → native reopen. Checks compare complete citation, bibliography
and preference JSON, unknown members, locators, Unicode text, editability,
offsets, story/paragraph ownership, rich run/paragraph formatting, table topology,
note roles/labels and page geometry. Geometry is compared in native Word twips.
Captured source and original/reexported input bytes remain unchanged during runs.

The separate mixed-post-merge check preserves all seven inventories/labels in
the existing body/bibliography and table/footnote/endnote fixtures after one
actual host save, including all four distinct 65-percent note styles. This is
**export/inventory acceptance only** for the mixed-note fixture; it does not
claim native footnote reopening.

## Local qualification and evidence

The runtime is Flutter **3.47.8** and Dart **3.13.7**. The SDK archive and all
**204 locked hosted dependency archives** were verified against expected SHA-256
hashes. Resolution was offline with the unchanged tracked lockfile. Formatting
uses the package's Dart 3.12 language version.

The completed milestone passes **2,078 tests in 93 suites**, with zero failures,
skips or errors:

| Scope | Passed tests | Suites |
| --- | ---: | ---: |
| Engine | 1,913 | 81 |
| Editor | 139 | 9 |
| Studio | 26 | 3 |
| Total | 2,078 | 93 |

Final editor coverage adds selection painting, proofing geometry and live review
to the six Zotero/ODT suites. Studio covers ODT opening, export and Zotero
transport. Exact exits and static-check results appear in final.json and raw
receipts. Development reruns and independent probes are excluded from these
totals; converter fixtures are reported separately.

The later main repaint change affects only editor source. Engine and converter
compiled inputs retain their final Git-blob identities. The engine runner also
observed unrelated editor/Studio libraries; source-binding.json explicitly
records the one changed incidental observer, rather than claiming all 810
observed inputs stayed unchanged after that merge. Editor and Studio are rerun
against the new canvas source. Independent bibliography/margin/note probes are
retained separately and are not added to the unique engine total.

execution.tar.gz includes raw commands, test events/cases, original/saved/
reexported ODT and DOCX, expected/actual oracles, source snapshots before/after,
runtime/cache receipts, baseline reproduction, independent review and failed
development attempts. archive-contents.json lists every member's size and
SHA-256. Packaging verifies deterministic rebuilding and unchanged inputs.
SDKs, package contents, profiles, caches and kernels are excluded. The first
three tool sources were recovered exactly from compiler-embedded text and
matched against their original hashes.

The frozen baseline verifies all 436 source files against initial main. Its
actual host saves passed inventories but failed native reopening. Failed
padding, soft-page and default/shared note-style cases remain available.
No converter fixture was edited to turn a refusal into a pass.

## Reproduction

Use the pinned runtime and unchanged workspace lockfile. The repository tool
packages/quds_office_engine/tool/zotero/odt_roundtrip_acceptance.dart accepts
create ORIGINAL, verify SAVED ORIGINAL, and reexport SAVED ORIGINAL REEXPORTED.
An explicit --fixture=NAME selects one fixture. Save the generated ODTs through
the identified LibreOffice binary between stages, then repeat for reexported
files. Archived runners preserve exact commands, isolated profile setup and
environment paths; substitute SDK locations for an equivalent installation.

## Remaining parity boundaries

1. Model, import, export and render active footnote separators before claiming
   native reopening of the mixed footnote fixture. Its width, color, thickness
   and spacing differ from Quds's fixed layout.
2. Make Quds rendering consume preserved table cell margins. It still uses
   fixed 4.25-point padding; file preservation does not establish identical
   screen layout. Arbitrary positive/asymmetric ODT padding remains unsupported.
3. Qualify complete command flows with installed Zotero and identified supported
   Word/LibreOffice releases, including real refresh/edit/preferences/unlink and
   restart/session recovery. Controlled native tests and a development converter
   are separate evidence.
4. Treat legacy Apache OpenOffice as a separately versioned host/plugin target;
   no result here establishes that combination.

Continuing contracts: [native ODT input](../../roadmaps/zotero/native-odt-input.md),
[native ODT output](../../roadmaps/zotero/native-odt-output.md), and the
[word-processor parity roadmap](../../roadmaps/zotero/word-processor-parity.md).
