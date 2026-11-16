# Zotero continuation — 16 November 2026

The canonical code at **`72691877bd9bafab761e655c13d0c9a0936b55bb`** passed
all **875 selected tests**, strict analysis and formatting. The implementation
is shared with CrispCloud through its exact-source vendor manifest. Both
repositories save incremental checkpoints on `codex/zotero-support-20261116`.

## What changed

- Native catalog insertion is the primary action. On a fresh document, it opens
  native document preferences, carries the selected sources into the picker,
  and applies both stages as one transaction and undo step. Cancelled, failed
  or stale-target operations leave the document and source selection intact.
- The Document tab displays the saved CSL style, language and note placement.
  Malformed present preferences fail explicitly; genuinely unset preferences
  can enter the first-use flow. The preview/export style remains separate.
- Supported mixed character formatting stays within one protected Zotero field.
  Typing, partial deletion, copy/paste, Enter, native refresh and safe note
  conversion preserve complete field packets and linked metadata. Ordinary Word
  field behavior remains unchanged. Unsupported or ambiguous structures refuse.
- Automatic note labels follow body-anchor order, including ordinary notes,
  tables and supported content controls. Common numbering formats, starts and
  section restarts are respected without changing stored note IDs. Custom marks
  preserve authored text and do not consume automatic counters. Inexact cases
  identify their source ID in the Notes pane.

Independent bounded reviews of the staged preferences/seed flow and rich-field
mutation paths found no additional concrete defect after the recorded fixes.

## Executed qualification

| Local check | Passed |
| --- | ---: |
| Engine/client/Word field, revision and note selection | 579 |
| Shared editor/controller/dialog/note/paste selection | 195 |
| Actual Studio native transport | 16 |
| Incoming ODS metadata/conditional-affix integration | 85 |
| **Canonical total** | **875** |

Strict analysis passed for all **32 changed Dart targets**; formatter and Git
whitespace checks passed. All **1,568 recorded source/dependency-input hashes**,
HEAD and genuine harness inputs stayed unchanged. The recorded native-evidence
scripts are explicitly listed as archived execution evidence, separate from
production/test analyzer targets. No application or package paths are excluded.

[The final receipt](final/receipt.json) records commands, runtime identity,
source maps, dependency graphs, output hashes and timings. The measured runtime
is official **Flutter 3.47.8 / Dart 3.13.7**. Production manifests and dependency
constraints are unchanged. Actual source is compiled through resolved package
harnesses; no production implementation is replaced by a stub.

CrispCloud separately passed **37 actual host service, transport, credentials,
target and ribbon tests**, eight-target strict analysis, formatting and both
vendor guards against this same implementation. The managed inventory is
**542 Quds files plus 1,857 unchanged standalone parser files**. Its additional
incoming terminal checks are recorded in the
[companion evidence](https://github.com/CrispStrobe/CrispCloud/tree/codex/zotero-support-20261116/docs/validation/zotero-continuation-20261116).

`qualification-first-pass/` preserves the initial 875-pass run and five strict
analysis findings, fixed before the final run. `development/` and
`note-refinement/` preserve focused intermediate checks. Their overlapping test
counts are not added to the final total.

## Real native Zotero acceptance

[Live evidence and replay instructions](live-zotero/README.md) record two
successful scenarios against official **Zotero 10.0.8** in an isolated profile
with three synthetic sources: local catalog browse/search/collection membership,
and native document preferences plus full citation/bibliography refresh.

The actual Quds client, citing driver, Word adapter and Studio HTTP transport
communicated with the running application. After choosing the pinned Chicago
subsequent-ibid CSL style and German locale, the saved/reopened DOCX contains:

1. `Anna Beispiel, Synthetic Native Acceptance Alpha (Acceptance Test Publisher, 2024), 12.`
2. `Ebd.`
3. `Ebd., 34.`

The first title and bibliography title retain italics beside roman text. The
original document stayed unchanged until staged application. Bibliography
paragraph-layout simplification produced its expected review warning. The
actual before/after DOCX files, protocol transcript and source/runtime receipts
are preserved; archive/profile databases and application binaries are not.
These scenarios are counted separately from unit/widget totals. See the live
README for the exact measured source scope and the source-JIT fingerprint limit.

## Reproduce locally

Reconstruct the genuine locked harnesses with the scripts and receipts in
[`setup/`](setup/). The Flutter framework, engine and Dart pins are enforced by
the qualification runner. Set `FLUTTER_ROOT` and `PUB_CACHE` to that environment.
The default harness root is the checkout's sibling `zotero-toolchain/harness`.

```sh
python3 docs/validation/zotero-continuation-20261116/run-continuation-checks.py --plan
python3 docs/validation/zotero-continuation-20261116/run-continuation-checks.py --output /path/to/new-evidence
```

Explicit `--engine-harness`, `--editor-harness`, and `--studio-harness` paths are
also accepted. The runner restores temporary analyzer configurations on exit
and does not resolve dependencies or invoke GitHub Actions. Logs that contain
trailing whitespace are retained as lossless gzip files with original and
compressed hashes; decompress them to restore filenames recorded in receipts.

## Remaining boundaries

The native acceptance uses the actual integration path, not a full compiled
Quds/CrispCloud application. Private accounts, real OS-keychain behavior and
opening the exported file in Microsoft Word or LibreOffice remain unverified.
Small caps and bibliography paragraph layout still require reviewed
simplification; active ODT citation transfer is absent. Page-based note
restarts/unsupported formats use explicit source-ID fallback. Unsupported stories,
protected/ambiguous fields and unsafe note conversions refuse processing.

## Incoming-work reconciliation

The [final audit](final-integration.json) uses an explicit cutoff of
**2026-11-16 05:17:13 UTC**: **62 branch heads and 199 PR heads** across both
repositories. The two continuation branches are identified separately; all
**259 external refs** are actual ancestors after retaining both parents of the
CrispCloud terminal #160 merge at `49d63f78d0b854ba76289dba69fdb6584f8a1260`.
The durable CrispCloud merge is `d916a841c54ddcca8f6327e45939c4372ba1d3a9`.
No concurrent work beyond that recorded cutoff is implied.

### Initial audit before feature edits

Initial source cutoff: **2026-11-16 05:00:31 UTC**. All incoming work was accounted for before this continuation's feature edits.

- Repository: `CrispStrobe/quds_office_suite`.
- Starting commit: `dc5f93b673e6087cccc6d66b33dfbfd099668f77`.
- Prior Zotero checkpoint: `fc37658c907edf6687eccb9564d3046283b49a3a`; the new baseline is 18 commits ahead and contains that checkpoint as an ancestor.
- Continuation branch: `codex/zotero-support-20261116`.
- Audited **23 current branch heads** and **49 PR heads** (all states and pages); **72** actual ancestor references, **0** exact-tree-equivalent references, **0** unaccounted references.

The [machine-readable audit](incoming-integration.json) records each observed ref and SHA, its complete Git tree, and any integrated exact-tree equivalent. An equivalent means the entire tracked tree matches a real ancestor, including file contents and modes. It does not rewrite history or reapply older code over newer changes.

The companion repository was audited at the same cutoff: together the snapshots account for **60 branch heads and 198 PR heads**. Both earlier Zotero PRs (Quds #47 and CrispCloud #149) and terminal PR #140 have been merged. Both continuation branches start from current main.

No GitHub Actions or check/status endpoints were queried, polled, awaited or rerun. The audit itself records source reconciliation; the executed qualification and live evidence are described above.
