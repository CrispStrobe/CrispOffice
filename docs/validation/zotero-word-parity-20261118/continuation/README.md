# Zotero continuation — recovered runtime and native research lists

## Checkpoint status

The incoming integration is saved remotely at `8fa115e8358e305872fd14e757f9133fa9c1540d`, tree `2ad7d3b44e9039ab4c753bd9c16c6a3d281f6c91`. Native research-list support and stronger local qualification are being completed on the same branch. PR #173 remains a draft until the frozen selection passes. GitHub Actions are neither queried nor awaited; checkpoint messages include `[skip ci]`.

## Incoming work, before feature edits

The bounded snapshot captured 391 refs: 212 fork branches, 175 PR heads and four upstream branches. Mail `514c341d`, thesaurus `5535d2eb` and Notes review `c9f8cd8e` were integrated with the saved Zotero work. Both composition identity and exact header/footer variant identity survive in transaction guards.

The fresh full local audit of the published integration reports 363 ancestors, 28 historical equivalents, 14/14 equivalence proofs and zero unaccounted refs. The exact inventory and proof are in [reconciliation](reconciliation/published-local-audit.json). No historical branch was merged solely to create ancestry.

## Runtime recovery and previously blocked regressions

The official Flutter3.47.8 archive was verified against its recorded SHA256 and official release metadata. Actual Dart3.13.7 binaries are in use. All176 hosted package versions in the workspace/Flutter-tools lock union were verified by archive hash. Workspace and SDK-tool offline enforced locked resolution passed; workspace manifests and the original lock remained byte-identical. See [runtime](runtime/runtime-ready.json).

The focused IME recovery passed68 distinct visible cases: navigation32, direct-command22, Studio shortcuts14. Raw logs, exact source/runtime/config fingerprints and an independent recount are under [focused-ime](focused-ime/summary.json). This run used local merge commit `6e6e8a683bd998f5e91e8c946774a6f585539607`, whose tree exactly equals the published integration above. It does not qualify subsequent list-support edits.

The former executor's inaccessible staged tree is not available in this fresh workspace. The recovered remote regression files are preserved in history, formatted here, and executed anew; no comparison against inaccessible original staged wording is claimed.

## Research-list behavior

Supported flat bullet/decimal research-note lists become native Word lists. Each item supports inline formatting, safe links, soft breaks, active citation placeholders and one optional paragraph wrapper. Ordered starts1..999999 are retained. Lists remain separate from surrounding prose and existing list counters. Citations retain inline, footnote and endnote behavior and native reading order.

The Zotero undo snapshot now captures the small numbering part and its relevant metadata. Undo/redo restores numbering without copying the complete package or replacing unrelated relationships/media. A reused relationship ID receives a fresh safe numbering relationship on redo.

Nested lists, multiple paragraphs per item, custom/reversed markers, per-item value overrides and unsupported structures remain atomic refusals. See the [guide](../../../zotero-support.md).

## Qualification in progress

The saved plan retains all original77 files and expands to98 distinct Dart test files:36 engine,48 editor,7 Studio,1 Mail core,5 Mail store,1 Mail UI. It includes30 strict analysis/format targets and separate Python accounting tests.

The runner verifies starts/completions/terminal events, exact requested suite coverage, failures/skips/unfinished cases, source/runtime/dependency hashes and plan/runner identity. Python support cases are kept separate from Dart application totals. Final results have not yet been recorded at this checkpoint.

The first incoming Notes run exposed two nullable-caret test compilation errors (corrected) and three runtime assertion failures under investigation. Independent review also exposed normal lists continuing an imported research list after DOCX reopening; an isolation regression and correction are being completed before freezing qualification. Development runs are not added into final totals.

## Acceptance boundary

Model/controller and controlled-transport tests include Quds DOCX serialization/reopening. This continuation does not claim a new live Zotero/account session, installed application/OS shortcut acceptance, or actual Microsoft Word/LibreOffice reopening.
