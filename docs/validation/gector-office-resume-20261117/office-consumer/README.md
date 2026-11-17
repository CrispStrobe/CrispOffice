# Frame bookmark repair and current Office consumers

The reconciled writer now preserves a floating text frame's bookmark when
LibreOffice converts its ODT output to DOCX. The repair moves the existing
`SectionFrame` graphic style from automatic styles in `content.xml` to the common
styles in `styles.xml`. Its properties, paragraph anchor, and authored geometry
are unchanged. The common style is emitted once, only when a body or master-page
story uses it.

## Fresh before and after evidence

The baseline product source is commit
`38abbbb744d1d5dab1eb9162d584370d661fef24`, whose writer SHA-256 is
`a3de7e33cd53b2ad220b55427c51bc261e1103b59e0dba375d4f8b4cadd029b0`.
The execution HEAD was its documentation-only successor
`faffbc419e07e73cbf24169b75844c2354413e5f`. The tested repaired writer SHA-256 is
`7c0019e03e767e42b2ad223f2333bb0256e4469ca55ceab0ae316a414729764a`.
Exact source snapshots, commands, runtime identities and input hashes are in the
evidence archive.

| Check | Before | After |
| --- | --- | --- |
| Five strict document-consumer fixtures | 4 pass; frame bookmark fails | 5 pass |
| Official ODF 1.3 schema checks in Jing | 20/20 pass | 20/20 pass |
| New common-style structural cases | 1 expected failure, 1 pass | Both pass within the focused suite |
| Focused engine cases across six files | Not a complete baseline cohort | 102 pass; 0 failures; 0 skips |
| Sealed consumer inputs | 5,152 unchanged | 5,152 unchanged |

The baseline's sole consumer failure is the missing `FrameMark` range in the
converted DOCX. After the repair, both DrawingML and VML representations retain
the exact `FrameBookmark` selection. Both carry page-relative x=36 pt, y=190 pt,
width=210 pt and height=35 pt. Every surrounding body/header word has unchanged
PDF coordinates; maximum measured drift is 0.0 pt.

The internal frame text moves by +0.10 pt horizontally and −1.85 pt vertically
when LibreOffice imports it as a Writer text frame instead of a generic shape.
This difference is explicitly retained in `frame-comparison.json`; it is not
described as identical glyph placement. The authored frame box remains exact,
and the rendered text remains inside it.

`verify_frame_repair.py` independently compares the two generated ODT packages.
It confirms that moving the identical graphic-style definition is their only
XML change, checks the strict before/after fixture outcomes, reconstructs the
DOCX bookmark selection and placement, and compares PDF word coordinates.
All other package members are unchanged.

## Current field contract

The copied harness preserves the current bounded PAGE/NUMPAGES conversion:
plain supported instructions require one authored cached run. An explicitly
empty run can produce a live field before an inline column break; a missing
cache remains covered by the engine's fallback tests. DATE, TIME and TITLE
remain visible cached text, with their styling and hyperlinks retained.

The five consumer fixtures cover native page fields and unsupported-field
fallbacks, malformed packets, three-page first/even/default header/footer
selection, bookmarks across body/table/header/frame/TOC stories, and an empty
cached PAGE before a column boundary. The historical recovery harness is
unchanged. Its old DATE/TIME/TITLE native expectations and absent-cache fixture
are not used to redefine the current contract.

Six significant-whitespace cache cases reside in the portable
`odt_inline_field_fidelity_test.dart` suite. The shared-empty-run regression
remains in `odt_complex_field_fidelity_test.dart`, including both leading and
nonleading section positions. These cases are included in applicable suite
totals, never added again as separate executions.

## Runtime, archive and limits

The run uses pinned Dart 3.13.7, the resolved frozen package graph, and the
restored LibreOfficeDev 26.8 consumer runtime. Jing checks the unchanged official
ODF 1.3 schemas. Lxml accepts 19 of 20 XML parts; its known nested page-count
disagreement is retained diagnostically and does not replace Jing's result.

The first Dartdev test launch failed during automatic package resolution because
its temporary-directory environment was incomplete. It produced no substantive
test result. That failure is preserved separately. The direct pinned test
runner with the explicit package configuration and runtime environment produced
the expected before failure and the passing after suite.

`office-consumer-evidence.tar.xz` contains 129 verified members and has SHA-256
`2fad85acb843840f54f70727575796458daaf4a95bf3da35a6602dd8d3a1137a`.
Its adjacent index records every member's byte count and SHA-256. Archive
readback matched every source member. It includes raw generated ODT/PDF/DOCX
files, XML, PDF coordinates, schema outputs, command receipts, structural tests,
the historical-input style-only diagnostic, exact writer/test snapshots and
the harness revision used for both runs. Disposable LibreOffice profiles and
Python bytecode are excluded.

These are bounded current-writer results in one pinned LibreOffice build. They
do not establish arbitrary imported-document fidelity or complete DOCX field
result-formatting preservation. The native page values may refresh in a
consumer; the harness checks their actual PDF styling and keeps authored
source-cache assertions separate.

No GitHub Actions or CI-status endpoint was queried or awaited.
