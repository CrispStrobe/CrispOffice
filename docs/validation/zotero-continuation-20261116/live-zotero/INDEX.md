# Live native Zotero acceptance overview

**Three scenarios passed** against official Zotero **10.0.8** with an isolated
profile containing three synthetic sources. They use the actual Quds client,
Word adapter and Quds Studio native transport.

| Scenario | Observed outcome | Evidence |
| --- | --- | --- |
| Local catalog | Probe, browse, search, collection membership and persistent local source identities | [Original catalog/refresh receipt](README.md) |
| Native document processing | Native German Chicago style selection, complete citation/bibliography refresh, `Ebd.` and `Ebd., 34.`, mixed italics and DOCX roundtrip | [Original catalog/refresh receipt](README.md) |
| First-use catalog insertion | Fresh document with no style → native preferences → same-session seeded picker with page 12 → one staged apply → linked footnote at the original caret after DOCX roundtrip | [First-insertion receipt](first-insertion/README.md) |

The original two-scenario README and its artifact hashes remain unchanged. Its
scope statements describe those two runs. The later first-insertion scenario
has its own source/runtime/kernel receipt, artifacts and integrity manifest.
Together these are **three acceptance scenarios**, separate from unit/widget
counts. The actual full Flutter applications and editor undo UI were not built
or driven by these harnesses; controller/widget regressions cover staging,
cancellation, undo and target guards separately.

The first-use run captured **455 production/manifest hashes** before compilation
and executed one recorded Dart kernel, whose hash was verified afterward.
All captured inputs match qualified source
`72691877bd9bafab761e655c13d0c9a0936b55bb` and remained unchanged. The earlier
catalog/refresh runs used source JIT and recorded eight relevant integration
source hashes; no full compiled-kernel fingerprint was captured for those runs.
Each detailed receipt states its exact evidence scope.

A bounded initial picker attempt could not edit the locator utility popup with
this environment's routed input and timed out without applying the document.
It is retained and excluded from pass counts. The successful retry accepted
the displayed page 12. **Native popup locator editing remains unverified**;
the earlier refresh run independently verified changed-page rendering as
`Ebd., 34.`. Bibliography paragraph-layout simplification produced the expected
review warning during refresh; first insertion needed no formatting warning.

All source data is synthetic; no account was connected. Zotero was closed after
the scenarios. Private accounts, OS-keychain behavior, full application builds,
and Microsoft Word/LibreOffice interoperability remain separate acceptance
steps. No GitHub Actions were queried, polled, awaited or rerun.
