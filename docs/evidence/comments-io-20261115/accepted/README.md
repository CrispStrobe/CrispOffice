# Accepted comments IO correction

Exact saved source: [`25c373626368c4a800dbaff2024c7972ba8a6e50`](https://github.com/CrispStrobe/quds_office_suite/commit/25c373626368c4a800dbaff2024c7972ba8a6e50).

## Behavior

Comments now serialize in the SpreadsheetML namespace with plain content inside `text/t` and `xml:space="preserve"`. Import follows the worksheet's actual internal comments relationship, and saving updates that reachable part. New relationships are relative to the actual worksheet path. Clearing comments removes the owned link and part so notes do not reappear after reopening. Old fixed-name packages without relationships remain readable.

External, missing, wrong-type and wrong-root comments targets are rejected before package mutation. A conventional filename occupied by unrelated data is preserved. Shared comments parts are retained when another owner still references them, and edits allocate a separate part when required to keep the other owner's content intact.

## Observed results

- **139 tests passed across all eight requested suites**, with no failures, errors, skips, missing or unexpected suites. This includes 22 comments tests, 67 ODS tests, and schema/import, builder, formula and native spreadsheet controls.
- **Strict analysis of three files found no issues**, with fatal infos and warnings enabled.
- Three fresh XLSX save/reopen cycles retained all six authored comment cases. **339 independent ZIP/XML checks passed**, and openpyxl 3.1.5 recovered the exact text and author of every comment. Cases cover leading/trailing whitespace, multiline text and tabs, an empty comment, escaped XML characters and Unicode, with repeated authors.
- All four commands ran on the same saved source with unchanged before/after source, HEAD/tree, resolved package inputs and recorded tool hashes. The external oracle also confirmed unchanged output workbook bytes.

The baseline in `../baseline/` retains the 11 reproduced behavioral failures and independently observed empty comment texts. `../initial-correction-compilation/` preserves the initial nullable-URI compile failure before its correction.

`artifacts.tar.xz` retains exact commands, machine events, per-suite results, before/after snapshots, tool hashes, actual XLSX outputs, the independent checker, and primary-source references. `artifacts-manifest.json` records every member's size and SHA-256; every member and the complete inventory were verified after archiving. The original locked dependency setup is retained in the baseline archive.

These gates qualify the recorded plain-comment profile and related unit scope. They do not certify rich-comment formatting, VML geometry, native Excel execution or the complete Open XML schema. No GitHub Actions run was awaited or restarted.
