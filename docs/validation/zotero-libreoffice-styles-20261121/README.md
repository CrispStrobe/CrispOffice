# LibreOffice ODT styles and Zotero continuation — 21 November 2026

**Status: local qualification passed.** The completed receipts below bind accepted results to exact
source snapshots. Subsequent publication reconciliation retains the qualified implementation.

This increment opens the retained, untouched LibreOfficeDev prose fixture with its effective Latin
**11 pt** and Arabic **10 pt** formatting. A separately labeled synthetic extension exercises active
Zotero fields in the same style envelope. The imported document remains editable and saves as DOCX;
native editable ODT output and installed-host acceptance remain separate milestones.

Final runtime-qualified source: **`9a3e5021bd9dd6468f5e8f37334d5a02bd9c174e`**.
Git tree: **`d3735995e30c2325ea689a1e78829f6a99013932`**.
Broad engine source: `69bb63caa0e4a5423ed36f9118b0cfe562f9ea2f`; the final integrated source adds
completed Mail/German main history and receives the additional integration/editor/Studio gates.
Initial main: `01517de8886ef7bd24947894be5dc823d0328869` (PR #310).
Branch: `codex/zotero-libreoffice-styles-20261121`.

## Implemented behavior

Named, default and automatic styles resolve Latin, complex-script and Asian fonts, sizes, weight,
italic and language independently. Percentage sizes use the corresponding inherited script size.
Current text is materialized into native runs while retaining Unicode code points, combining-mark
context across spans, hyperlinks and the original UTF-16 citation endpoints. A shared 100,000-run
limit bounds alternating-script materialization across stories.

Existing imported script runs retain their editing behavior across DOCX saves. Font/language routing
covers non-RTL complex scripts as well as Arabic; scalar size, bold and italic edits update the
corresponding native complex slots. Initially equal script settings retain ownership before a later
edit makes them different. Private, ignorable provenance confines this synchronization to
importer-owned projections. Ordinary DOCX properties and foreign namespace lookalikes retain their
independent sparse-property ownership.

Automatic color, opacity and hyphenation are validated after inheritance. Supported inactive
paragraph/page defaults are accepted; unknown or foreign properties still refuse. Content-sensitive
guards reject active Asian typography, a nonstandard default tab interval used by actual tabs, an
active page grid, and a custom separator used by actual footnotes.

**Language is part of the typography guard.** The absence of Asian characters alone cannot establish
that hanging punctuation or strict line breaking is inactive: Chinese/Korean locale rules can affect
ASCII punctuation. Effective normal and complex-script break languages must be known and compatible
with the inert interpretation; unresolved ambient locales refuse conservatively. The fixture's
separate, unused Asian language slot does not activate that behavior. The [pinned LibreOffice source
review](lo-typography-research.md) explains this inference; it is not a new rendered LibreOffice
comparison.

## Original fixture and synthetic Zotero extension

The [fixture attribution](../../../packages/quds_office_engine/test/fixtures/zotero/odt/README.md)
and [original converter receipt](../zotero-rich-odt-20261121/converter-development.json) identify
LibreOfficeDev **26.8.0.0.alpha0**, build `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. Both retained
files are exact bytes from the preceding milestone's evidence archive; no source style was removed.

| Retained file | SHA-256 |
| --- | --- |
| `native-prose.odt` | `9fd4e0d23bf9cd2be0248bd5e9cfb496dfe512ec1226c456f324f2171705e1bd` |
| `native-prose.docx` | `2572f8964c08b4f9bf9087ed0a8e68c54d4b9899797c37d30bd42c7800c37d74` |

The original contains Quds-authored synthetic prose converted by the actual LibreOffice converter,
including bold, italic, Arabic and supplementary Unicode. **It contains no Zotero fields.** The
paired test injects canonical reference marks, a multi-paragraph bibliography and preference chunks
into a copy. Those fields are explicitly synthetic, not output from an installed Zotero plugin.
`styles.xml`, the `content.xml` prefix before `office:body`, and unrelated package members remain
byte-identical to the original fixture.

Regressions cover citation editing, staged HTTP refresh, unchanged state before transaction
publication, rich caches, unknown metadata, exact archived `meta.xml`, field ownership and repeated
DOCX reopening. The public asynchronous controller also opens the untouched fixture, preserves its
previous document until publication, and saves/reopens Latin/Arabic font and language projections.
Separate in-memory mutation controls activate typography, tabs, grids and a footnote separator;
neither retained source file is changed by those tests.

## Final local qualification

The [qualification receipt](qualification.json) is the authority for accepted results and source
binding. Every accepted gate completed with process exit 0, no failed or skipped tests, and unchanged
before/after source manifests. The final three runtime gates used the same integrated source.

| Gate | Selected scope | Final result |
| --- | --- | --- |
| Broad engine | 134 files: ODF/ODT, Word serialization, Zotero, fonts and the five incoming AllCaps suites | **2,865 passed; exit 0** |
| Integration engine | 28 files after Mail/German reconciliation: proofing, language, ODT, Zotero, font routing, isolate I/O and AllCaps | **641 passed; exit 0** |
| Editor | 55 files: loading, Zotero, language, AllCaps, German strings and live review | **989 passed; exit 0** |
| Studio | 4 files: About, ODT open, Zotero transport and shortcuts | **43 passed; exit 0** |
| Strict analysis | 12 changed Dart paths; `dart analyze --fatal-infos` | **Passed; exit 0** |
| Nonmutating formatting | The same 12 paths; `--output=none --set-exit-if-changed` | **Passed; exit 0** |

The [evidence archive](evidence.tar.xz) accompanies the receipt. Its gate receipts, raw JSONL
streams, stderr, exact argument vectors, suite selection, source manifests and runner retain the
evidence needed to reconstruct counts. Each requested file contributes once to its accepted gate.
The runs overlap; their counts are not summed as unique cases or a percentage of
Word/LibreOffice/Zotero parity. Development checks are excluded from acceptance. The engine completed in 319.580 seconds with all 1,629 selected
source/asset hashes unchanged. Its before/after manifest SHA-256 is
`c7c5baf40179e9ba06e1339f1ac1f445949d4b81fb1026b427a291d44b5a2b66`. The integration engine, editor
and Studio gates completed in 61.398, 391.397 and 102.958 seconds respectively. All three retained
exactly the same 1,638 source/asset inputs; their before/after manifest SHA-256 is
`567af486375e4ded9404e76d4e569b35aa7264f9871a8bfa73bd69ac71fc3b9d`.

The [publication reconciliation receipt](publication-reconciliation.json) separately accounts for later test-only main changes. All
production sources, dependency manifests, retained fixtures and every selected qualification test
remain identical to the runtime-qualified source (198 unique selected test files); two unrelated editor tests and macOS golden
assets/provenance are inherited from main. The completed runtime gates are not relabeled as runs
on that later commit.

The [runtime receipt](runtime-setup.json) records repository-pinned **Flutter 3.47.8 / Dart
3.13.7**, the official SDK archive and executable hashes, and verified locked packages. Offline `pub
get --enforce-lockfile` succeeded without changing tracked dependency manifests. Runtime smoke
checks establish setup only; they are not counted again as feature qualification.

### Development attempts retained separately

An early cohort produced 344 passing cases and one failed test: its citation cache contained a
hyperlink outside the existing editable-field contract. The corrected fixture checks hyperlink and
citation ownership independently; the production ownership guard was not weakened. Subsequent review
found complex font routing, cross-span script context and initially equal script ownership issues,
which received fixes and targeted regressions before the source freeze.

An interrupted review-era engine run (1,336 passing events) and the superseded pre-Mail editor
run (757 passing events) remain development evidence, with exit 130 and no acceptance claim. The
first environment-blocked editor smoke is also excluded. A scratch-owned temporary directory resolved that setup failure. Incomplete runs,
superseded source snapshots and preliminary success counts do not supply acceptance or add to final
totals.

## Remote intake and reconciliation

The [initial intake](initial-intake.json) covers 27 fork branches, 100 recent PR heads and four
upstream branches. The [expanded intake](expanded-intake.json) covers all 29 then-current fork
branches, all 310 fork PR heads, and all four upstream branches/PR heads. Every captured head was
already represented in starting main by ancestry or explicit equivalence proof; initial intake was
complete before implementation. Those historical records remain unchanged.

The [14:41 refresh](final-intake-20261121T144155Z.json) records later concurrent work. The [fixed
publication intake](publication-intake-20261121T145803Z.json) covers **353 refs**: 347 included,
this work branch excluded, and five unmerged refs representing four heads, with zero unclassified
refs. Its main cutoff was `3f6b9a2b9209693aa32bbad402bb7d093cf8b4db`, including PRs #312 and #313.

The [subsequent main observation](publication-main-20261121T150301Z.json) records completed AllCaps
PR #311 at main `49adcd6b693712b9e82f9fdefd2fdf09d0db4ee2`. Its shared production path is
`word_property_io.dart`. An ordinary parent-preserving merge reconciled that main; a following
compatibility fix retains incoming AllCaps through ODT/Zotero editing. The final gate includes its
affected engine/editor suites and Studio About.

Main then advanced through completed PR #314 to `3397ead3752f65bb3fa0e764c5da1bc2dd0af485`,
incorporating Mail saved searches/conversations, German review localization/proofing work, and our
earlier implementation checkpoint. An ordinary merge produced runtime-qualified source `9a3e5021…`.
All 37 previously changed Dart paths were byte-identical after reconciliation. The targeted
integration engine gate rechecked the incoming proofing interaction, and the full selected editor
and Studio gates ran on that integrated source. The archive retains the exact source comparison.

The [15:26 main observation](publication-main-20261121T152609Z.json) records PR #315 at
`089d11cd073520208f27a09b2914d57615cef7ff`: 32 test/assets paths, with no production source delta.
The final publication reconciliation retains this completed main history and verifies unchanged
production code and selected qualification tests. The independently advancing
`fix/studio-mail-tests-20261121` head `be539f3d…` was still explicitly WIP and unmerged at that
cutoff. It remains separately preserved. Historical intake snapshots retain their original dates
and classifications; the later reconciliations supplement them.

| Remote checkpoint | Saved scope |
| --- | --- |
| `2aa7833239ec4507a4a9db1c7f23c84bd01b4028` | Complete initial/expanded intake and retained-fixture contract. |
| `2e3280a175814dab7fccf14363f8dd1785acc78e` | Initial implementation, exact fixtures and regressions. |
| `2e464b14f586c33d608ff25007ef129b2a24d77c` | Complex font routing and cross-span script-context corrections. |
| `399d11886bd839da8945d7937524186ebba206cb` | Initially equal script settings retain later edit ownership. |
| `50115e2113756210f2160f5baf5811220622a7e0` | Ordinary merge of completed main `49adcd6b…`. |
| `69bb63caa0e4a5423ed36f9118b0cfe562f9ea2f` | AllCaps compatibility; broad engine qualification source. |
| `fb596c25d2b6ff86102c88e334f128d67377031d` | Clarified native citation ownership and preserved publication intake. |
| `9a3e5021bd9dd6468f5e8f37334d5a02bd9c174e` | Ordinary merge of main `3397ead3…`; final integration/editor/Studio qualification source. |
| `39dd5fb85901ead1dad9f6b82ed9590a35b26aa7` | Ordinary merge of main `089d11cd…`; production code and all 198 unique selected test files unchanged. |

Remote saves preserve parent history, verify Git-tree identity and use non-forced expected-head
updates. The [final publication reconciliation receipt](publication-reconciliation.json) identifies the later main merge and confirms
qualified-source preservation. This validation record describes local acceptance; the pull request
and Git history retain the final publication/main merge outcome. **GitHub Actions, queued workflows
and status checks were not queried or awaited.**

## Remaining parity work

This conversion preserves supported current content and edits to its existing script runs. It does
not retain dormant ODF typography as a live style engine for arbitrary future typing or Zotero
replacements. Active Asian typography, further rich-document structures and native editable ODT
output need additional ownership, layout and persistence work. Ordinary ODT export still writes
cached Zotero results; save this imported document as DOCX to retain active fields.

The [native ODT contract](../../roadmaps/zotero/native-odt-input.md) and [parity
roadmap](../../roadmaps/zotero/word-processor-parity.md) keep installed Word/LibreOffice/Zotero
plugin sessions and identified release versions as separate acceptance work. The earlier converter
list-continuation failure remains open. Historical Apache OpenOffice compatibility also needs its
own identified host/plugin fixtures; this milestone makes no such interoperability claim. Continue
from retained real files and concrete ownership regressions.
