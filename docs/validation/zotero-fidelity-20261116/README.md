# Zotero saved searches, small capitals and bibliography layout

The Quds source at `ca4011de0e17783f12bcff07336e318adc1db99c` passed final
combined local qualification and the new live Zotero acceptance scenarios.
This overview covers that source increment. Previous continuation evidence
retains its original source identity and scope; its test totals are not added
to this run.

For user actions, see the [current Zotero guide](../../zotero-support.md).

## Implemented workflows and boundaries

| Area | Available behavior | Boundary |
| --- | --- | --- |
| Local saved searches | Choose **Saved searches**, select an existing personal/group-library search, page through names/results, filter within it, and insert selected sources | Desktop API only; Zotero evaluates conditions; create/edit searches in Zotero; notes/attachments are not citation sources; no minimum older desktop version is claimed |
| Small capitals | Preserve native DOCX formatting and explicit normal resets; display consistently in formatted previews, editor layout and PDF; keep authored text and original caret ranges | Synthetic scale 0.8; default Unicode casing without locale tailoring; no font-designed small-capital features; unsupported capital variants remain reviewed |
| Native bibliography | **Bibliography in Zotero…**, **Document style…** and **Refresh all with Zotero** operate on one linked field across real entry paragraphs, with supported indent, line/entry spacing and tab stops | Complete contiguous paragraph ownership in one block container; unsafe structural ranges remain refused; arbitrary CSS/multi-column layout remains reviewed |
| Earlier flattened bibliographies | A native content refresh can replace flattened entries with structural paragraphs and apply the native style | A style-only callback or unchanged plain text cannot infer entry boundaries; layout remains unapplied and is requested again |
| API bibliography preview | **Document → Zotero bibliography** retains supported character formatting, including small capitals, in its existing review | Still one bibliography paragraph with soft breaks; use native controls for paragraph layout |

### Source identity and catalog behavior

Saved-search metadata and results use the existing fixed localhost transport,
library identity checks, database pin when supplied, request bounds and strict
pagination validation. No online credential is sent locally. The additional
title/creator/year filter runs in Zotero with the saved search; conditions are
not interpreted in the editor. Refreshing the saved-search menu clears its
selected search and asks for a new choice. A deleted search clears stale
results while retaining the user's selected reference sources.

Relevant implementation and regressions:

- [Catalog client](../../../packages/quds_office_engine/lib/src/zotero/zotero_client.dart)
  and [saved-search model](../../../packages/quds_office_engine/lib/src/zotero/zotero_models.dart).
- [Catalog client tests](../../../packages/quds_office_engine/test/zotero_saved_search_test.dart)
  and [saved-search UI tests](../../../packages/quds_office_editor/test/word_zotero_saved_search_test.dart).

### Typography and source text

Small capitals are a run property. DOCX contains `w:smallCaps` and the original
letters, including explicit false/normal resets. The synthetic renderer uses
capital outlines at 0.8 scale for lowercase text and measures those outlines
before line breaking. Default uppercase conversion includes Unicode 17.0.0's
unconditional expansions, with combining accents kept on their source cluster.
A display expansion retains its complete original UTF-16 range, so it creates
no additional caret positions. A grapheme split across separate run-format
records keeps its original display instead of merging those records.

PDF export marks transformed glyph groups with their original `/ActualText`.
That representation also survives footnote/endnote line copying. Narrow-cell
wrapping keeps each source grapheme's expansion together. The fallback does
not apply Turkish/Azeri/Lithuanian locale tailoring or OpenType small-capital
features. Unsupported values such as `all-small-caps` and `petite-caps` remain
part of the explicit formatting review.

Relevant implementation and regressions:

- [Shared display helper](../../../packages/quds_office_engine/lib/src/word/model/word_small_caps.dart)
  and [licensed Unicode expansion data](../../../packages/quds_office_engine/lib/src/word/model/word_small_caps_case_data.dart).
- [Engine typography/DOCX/PDF regressions](../../../packages/quds_office_engine/test/word_small_caps_test.dart)
  and [editor typography/caret/undo regressions](../../../packages/quds_office_editor/test/word_small_caps_test.dart).

### Native bibliography ownership and layout

Structural XHTML boundaries become entry paragraphs; explicit `<br>` breaks
remain within an entry. A native bibliography retains one field code spanning
its complete range. Safe refresh can grow or shrink that range, preserve
neighboring content, retain layout when no callback is repeated, and participate
in one controller undo transaction. The range must own every paragraph and
inline in one real block list. Interleaved blocks, ranges crossing cells or
sections, surrounding prose and unrelated structural markers do not qualify.
This contract does not enable multi-paragraph citation replacement.

`Document.setBibliographyStyle` supplies the native layout. Body/relative
first-line indents, entry spacing and tabs convert from twips to points;
line spacing converts from the callback's 240-based value to an automatic
line multiplier. Negative first-line values become hanging indents. A
style-only callback can reset old indent, spacing and tabs without replacing
text. Layout is stored in paragraph properties and persists through DOCX.

For legacy flattened text without reliable entry boundaries, the adapter
requests the layout again through `bibliographyStyleHasBeenSet` while retaining
the chosen style and unrelated XML/JSON preferences. A callback that cannot be
applied does not falsely certify completion. A fresh native formatted result
provides the structure needed for migration.

Relevant implementation and regressions:

- [Formatted-text parser](../../../packages/quds_office_engine/lib/src/zotero/zotero_formatted_text.dart)
  and [paragraph-boundary tests](../../../packages/quds_office_engine/test/zotero_paragraph_runs_test.dart).
- [Native field ownership/replacement](../../../packages/quds_office_engine/lib/src/word/model/word_zotero.dart)
  and [native citing/layout adapter](../../../packages/quds_office_engine/lib/src/word/model/word_zotero_citing.dart).
- [Bibliography layout tests](../../../packages/quds_office_engine/test/word_zotero_bibliography_layout_test.dart)
  and [controller staging/rollback/undo tests](../../../packages/quds_office_editor/test/word_zotero_bibliography_controller_test.dart).

## Qualification status

| Check | Status in this overview |
| --- | --- |
| Canonical engine/catalog/fields/notes regressions | 617 passed |
| Shared editor/controller/dialog regressions | 223 passed |
| Actual Quds Studio native transport tests | 18 passed |
| Additional typography/layout/PDF integration tests | 70 passed |
| Total selected tests in the final combined run | **928 passed** |
| Strict canonical analysis and formatting | 33 changed Dart targets passed |
| Canonical source consistency | 1,577 recorded source hashes unchanged during qualification |
| Running Zotero saved-search acceptance | Passed local execution and additional-query scoping |
| Running Zotero small-capital/bibliography-layout acceptance | Passed two style scenarios and four native refresh transactions, including reopen |
| CrispCloud host qualification and vendor guard | Recorded separately in the companion repository |
| Complete Quds Studio Dart/assets compilation | Passed Linux debug bundle; 90 output files, source unchanged |
| Complete CrispCloud application Dart kernel | Passed from the merged actual application; required Cargo hook blocked the overall bundle |
| Full compiled Quds/CrispCloud application acceptance | Not claimed |
| Microsoft Word/LibreOffice interoperability and external PDF-reader extraction | Not claimed |

The [final qualification receipt](final/receipt.json) records the exact
commands, completion summaries, source/harness hashes and restored analysis
configuration. It uses official Flutter 3.47.8 / Dart 3.13.7 and genuine locked
dependencies. The [local runner](run-checks.py) is retained for reproduction.

The [Studio bundle receipt](studio-bundle/receipt.json) separately records a
successful compilation of the complete actual Studio Dart application and its
assets with the genuine resolved graph. Its source inventory stayed unchanged.
The [bundle runner](run-studio-bundle.py) retains the command and output hashes.
This establishes Dart/assets compilation; it does not build the native desktop
executable or exercise the full application GUI.

The [companion application compilation evidence](https://github.com/CrispStrobe/CrispCloud/tree/codex/zotero-support-20261116/docs/validation/zotero-fidelity-20261116/full-app-build)
records its genuine locked graph, successful complete Dart kernel, compiler
inputs and the separate Cargo/native-assets failure. No native hook was disabled.

The read-only [delivery verifier](verify-delivery.py) compares current bytes
with all independently qualified source maps and retained compilation outputs.
After the final Quds documentation commit, its authoritative
[cross-repository receipt](https://github.com/CrispStrobe/CrispCloud/blob/codex/zotero-support-20261116/docs/validation/zotero-fidelity-20261116/delivery-source-proof.json)
is saved in CrispCloud, so the exact Quds pin can be checked without making a
receipt depend on its own commit hash. The local interim receipt is explicitly
named and retains the expected pre-delivery pin mismatch; it is not the final
delivery result.

### Running desktop Zotero

The [live result](live-zotero/logs/result.json) and
[acceptance receipt](live-zotero/logs/acceptance-receipt.json) record execution
against Zotero **10.0.8** in an isolated native profile with synthetic sources.
The compiled harness used the actual Quds catalog client, Studio transport and
Word adapter. The [catalog result](live-zotero/logs/catalog-result.json) shows
that the selected saved search returned only its matching source and that an
additional query stayed scoped to that search.

German Chicago and the retained
[synthetic small-capital style](live-zotero/quds-synthetic-smallcaps.csl) each
completed an initial refresh and a second refresh after DOCX reopen. Four note
citation fields retained their source/locator links; repeated citations yielded
`Ebd.` and `Ebd., 34.`. Both styles produced one bibliography field with two
entry paragraphs, 720-twip body/hanging indents and 240-twip spacing after
entries. Chicago used 240-based single line spacing; the synthetic style used
480-based double line spacing and native small-capital runs beside italic
titles. The [independent DOCX inspection](live-zotero/logs/independent-docx-verification.json)
confirms the field counts, separate paragraphs and native properties in all
four saved outputs.

The [delivery source proof](live-zotero/delivery-source-proof.json) confirms
the live source inputs and executed kernel remained unchanged. Protocol traces,
scripts, before/after DOCX files, and unsuccessful preparation attempts remain
under [live-zotero](live-zotero/). These checks exercise the integration
components against the running application. They do not claim a full compiled
Quds/CrispCloud UI, private-account/keychain acceptance, a new picker/locator
popup exercise, or Microsoft Word/LibreOffice interoperability.

The [earlier continuation](../zotero-continuation-20261116/README.md) and its
[live acceptance index](../zotero-continuation-20261116/live-zotero/INDEX.md)
remain historical evidence for the specific sources and scenarios recorded
there. They are not substituted for acceptance of this increment. No GitHub
Actions are queried, polled, awaited or rerun for this work.

## Primary protocol and formatting references

- [Zotero local API, including saved-search execution](https://www.zotero.org/support/dev/web_api/v3/local_api).
- [Zotero local API implementation](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/server/server_localAPI.js).
- [HTTP Citing Protocol and bibliography layout callback](https://www.zotero.org/support/dev/client_coding/http_integration_protocol).
- [Zotero wire protocol: relative first-line/body indent](https://www.zotero.org/support/dev/client_coding/libreoffice_plugin_wire_protocol).
- [Zotero bibliography format-parameter generator](https://github.com/zotero/zotero/blob/main/chrome/content/zotero/xpcom/cite.js).
- [CSL character-formatting values](https://docs.citationstyles.org/en/stable/specification.html#formatting).
- [Unicode 17.0.0 SpecialCasing.txt](https://www.unicode.org/Public/17.0.0/ucd/SpecialCasing.txt)
  and [Unicode licence](https://www.unicode.org/license.txt).
