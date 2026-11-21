# Word VBA paragraph styles — work in progress, 21 November 2026

## Completion notice

This historical compiler-only checkpoint has been completed and qualified in
the [Word style completion record](../word-vba-styles-complete-20261121/README.md).
The native operation, preservation guards, independent incoming fixtures and
local runtime checks are now implemented. The original status and workspace
failure below are retained as evidence of what was true at this checkpoint.

## Original status (superseded)

**Not qualified and not ready to merge.** The source-compiler draft lowers
paragraph `Style` assignments to `docx.paragraphStyle`. The native operation
and its integration coverage still need implementation. The new source tests
and BAS example are authored but unexecuted. No analysis or tests ran in this
session, and no complete VBA compatibility claim is made.

This checkpoint exists to preserve work remotely after the execution workspace
ran out of disk. It must not be merged to main in this state.

## Completed intake

The captured remote main is
`115f1c20131bf0157d047dfe2e9d704ddffb22a2`. All 30 non-main fork heads and all
four upstream heads are ancestors of that commit. There were no open PRs; the
25 most recently updated closed PRs were merged. The exact heads, comparison
results, source URLs and observation timestamp are in [intake.json](intake.json).
This is a recent-window PR audit, not a claim about every historical PR head.

Remote baseline checkpoint:
`40dfc476a1fd23ca503514c3a6e8c239dc32a405` on
`codex/word-vba-extensions-20261121`.

## Intended bounded contract

- Writable `Paragraph.Style` and a selected paragraph's `Range.Style`.
- A nonempty XML-safe primary style name, compared case-insensitively without
  changing spelling or spaces, or one of 13 supported built-in constants:
  Normal (-1), Heading 1–9 (-2 through -10), Caption (-35), Title (-63), and
  Subtitle (-75).
- Typed existing Paragraph/Range aliases, With, and required ByVal helpers.
- Static rejection of Boolean/object/array values, including unused helpers;
  runtime checks for scalar Variant values.
- No style reads, Styles collection, Style objects, positive ordinal indices,
  guessed localized built-in translations, or automatic style creation.

Microsoft documents the broader Style setter and the constant identities:
[Paragraph.Style](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.style),
[Range.Style](https://learn.microsoft.com/en-us/office/vba/api/word.range.style),
[WdBuiltinStyle](https://learn.microsoft.com/en-us/office/vba/api/word.wdbuiltinstyle).
The proposed direct-format preservation rule is an explicit bounded dialect
contract; it has not been compared with an installed Word host.

## Native work still required

Implement `docx.paragraphStyle` with the ordinary paragraph/story/section
selector and exactly one `name: String` or `builtin: int` argument. Do not
reuse `docx.applyStyle`: its WordStyles.apply implementation overwrites direct
paragraph and run formatting and falls back to catalog/global styles.

Resolve an existing, unique paragraph style from the operative native styles
part. Require unambiguous internal document/styles relationships, unique style
IDs and primary names, valid native properties, and a resolved acyclic basedOn
chain. Built-in selection must reject custom styles. Preserve the independent
header/footer ownership guard and table style context.

Add a targeted style-cascade method following the exact-owner traversal used by
editParagraphTabStops. Prepare a detached paragraph, serialize pending direct
edits, change only native pStyle/@val while preserving foreign metadata, refresh
its inherited properties, and publish only after preparation succeeds. Do not
call broad refreshStyles or mutate unselected paragraphs.

Review boundaries identified before implementation:

- Foreign/nested pStyle must not become effective through local-name parsing.
- WordPropertyIo currently replaces a changed pStyle node; prepare sparse XML
  and its baseline explicitly or implement attribute-granular preservation.
- A same-value write must still create an explicit style reference.
- Effective numbering changes require native label recomputation or explicit
  refusal; the current cascade retains old listLabel/listRestart.
- Reject ambiguous MC alternatives and mutable target aliases.
- Preserve pending plan writes, DOCM opaque bytes, direct character style
  overrides, and complete transaction rollback.

## Runtime blocker and recovery

The official Flutter 3.47.8 archive (Dart 3.13.7) was downloaded and checked
against the official manifest SHA-256:
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
All 137 hosted archives in the workspace lockfile were also SHA-256 verified.
Tracked manifests and lockfiles were not changed.

Selective extraction failed with ENOSPC. The partial SDK is unusable.
Subsequent sandbox command/patch processes could not launch because their
temporary mount placeholders could not be created. Automatic approval rejected
an unsandboxed exact-file cleanup because sandbox escalation is disabled.
The native desktop interface was unavailable too. No cleanup executed.

The reproducible download to remove after workspace access is restored is:

`/workspace/scratch/22b8f7cbd7d4/flutter-3.47.8.tar.xz`
(1,581,444,364 bytes).

Prefer the smaller official standalone Dart 3.13.7 SDK for the engine checks.
Finish locked dependency resolution and then run fresh formatter, strict
analysis, source/native/integration regressions, and the committed BAS on the
VM and compiled JavaScript. Include validation-only behavior, recorder/replay,
policy/budgets, late rollback, save/reopen and DOCM preservation.

GitHub Actions were not awaited or used as a gate. Before eventual publication,
refresh remote main/branches/PRs, reconcile any newer work, and verify the
complete combined source before merging.
