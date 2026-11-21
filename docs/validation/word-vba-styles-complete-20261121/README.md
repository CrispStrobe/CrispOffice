# Word VBA paragraph-style assignment — 21 November 2026

## Outcome

The previously compiler-only Word style increment now has a guarded native
implementation, preservation regressions, end-to-end execution and local
qualification. The qualified combined source is remote checkpoint
[`b11c8b1a9a2c0fa58a45f9893b4c86834ec276b2`](https://github.com/CrispStrobe/quds_office_suite/commit/b11c8b1a9a2c0fa58a45f9893b4c86834ec276b2),
with tree `d25991879e4e84b4364ea7756945806e94bc2b51`. This evidence-only
continuation does not change that qualified production source.

Development checkpoints are retained on
[`codex/word-vba-styles-complete-20261121`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/word-vba-styles-complete-20261121).
GitHub Actions were not queried, rerun or awaited. All acceptance below comes
from the genuine pinned local runtime, and repository protection was unchanged.

## Delivered compatibility slice

The `vba-word` compiler accepts writable `Paragraph.Style` and the `Style`
property of a range selecting one paragraph. Values may be an existing primary
paragraph-style name or one of 13 supported Word constants: Normal, Heading 1–9,
Caption, Title and Subtitle. Primary names compare case-insensitively while
retaining their spelling and spaces. Typed paragraph/range aliases, `With`,
and supported named/optional `ByVal` helpers use the same operation.

```vb
Sub Main()
    ActiveDocument.Paragraphs(1).Style = wdStyleHeading1
    ActiveDocument.Paragraphs(2).Range.Style = "Report Body"
End Sub
```

Both requested styles must already exist in the document. The complete
[runnable BAS example](../../../packages/quds_office_engine/example/macros/word_styles.bas)
also mixes inherited styles with explicit direct formatting.

Each assignment lowers to `docx.paragraphStyle` with the ordinary
paragraph/story selector and exactly one string `name` or integer `builtin`.
The native operation resolves the operative styles part, prepares a detached
target, preserves sparse direct formatting, edits the native `pStyle` reference,
and recomputes inherited values in the paragraph's actual story/table context.
It publishes only after all checks succeed. The selected inline-list and run
identities, style definitions, unselected paragraphs and foreign source metadata
remain intact. Same-value assignments still establish an explicit style
reference. DOCM fixtures retain opaque VBA/signature part bytes through repeated
save/reopen; this is a preservation check, not a signature-validation claim.

Validation and execution use existing transaction, policy, resource-budget,
recording/replay, CLI and MCP paths. Late failure rolls back the entire macro.
See the exact [VBA contract](../../VBA_WORD_MACROS.md#assigning-existing-paragraph-styles),
[native operation contract](../../MACROS.md), and
[compatibility roadmap](../../VBA_PARITY_ROADMAP.md).

## Intake and history preservation

Initial main was `3dbaa8429b14ac43721e165b4d50d3f6d2845309` (PR #323).
The initial open Word draft and unmerged Mail work were incorporated before
completion. Subsequent intake preserved main's PR #324 saved-Mail restore view,
PR #325 account signatures/Quick Text, and PR #326 editable Zotero ODT export.
The last captured main integrated here is
`c7380f53a55b47a5b7672eb3f7afee32d92def6e`.

The [captured ancestry audit](intake/captured-head-ancestry.json) checks 36 fork
heads and four upstream heads. Its original audit snapshot predates the last
main refresh; [source binding](source-binding.json) rechecks those captured
heads against the final qualified source. All are included. These are observed
snapshots, not a claim that independently active branches cannot advance later.

The independently advancing Word draft was integrated through `cf12544d`.
Its later captured reconciliation merge `8876bc0e` has no new production behavior
or missing test coverage beyond the combined source: its ODT changes match
exactly, its Mail difference is formatting, and its Word tests are retained.
The [bounded comparison](intake/bounded-pr322-summary.json) records that review.
`8876bc0e` is retained as another parent of the qualified checkpoint, alongside
latest main, without reverting the unified style implementation.

| Remote checkpoint | Saved increment |
| --- | --- |
| `db531880f9a1ef4d5060c6fffee5fac8af537b7a` | Combined initial Word and Mail intake |
| `cc39bd10b7b7bfe77d63e53d66f147964093bc11` | Native style implementation, integration fixtures and incoming qualification fixes |
| `ce90d6db8c28797a79b63ff1dfda8586faf74ff9` | Latest Mail/main and Zotero snapshot, native preservation guards |
| `ba510fef7b119bf4823447df387f0fa40ad0c9ad` | Concurrent Word native tests and Notes insertion ownership fix |
| `2fb916c70eb469c69e7d401c2bc553a8ad9225d7` | Unified live-identity, ownership, native-packet and numbering guards |
| `b11c8b1a9a2c0fa58a45f9893b4c86834ec276b2` | Latest main/ODT export and captured Word reconciliation ancestry |

Remote writes created immutable Git objects and advanced the branch using the
observed head and `force: false`. No branch was force-pushed or deleted. Local
temporary integration commits were aligned to the identical remote tree with
a soft reset; qualified source hashes bind the resulting remote source.

## Executed acceptance

Runtime: repository-pinned **Flutter 3.47.8 / Dart 3.13.7**. The official SDK
archive was checked against SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
All 204 hosted archives needed by the workspace and Flutter tools were checked;
offline dependency resolution enforced the unchanged lockfile. The
[runtime receipt](runtime.json) records commands, versions and executable hashes.

| Gate | Passing result | Evidence and scope |
| --- | ---: | --- |
| Complete reconciled Word cohort | **3,716 tests / 73 files** | [Summary](word/summary.json); 509 captured inputs unchanged; zero failures/skips |
| Post-main combined Word/ODT integration | **315 tests / 11 files** | [Summary](post-main/summary.json); 448 inputs unchanged; zero failures/skips |
| Final changed-Dart formatting and fatal-info analysis | **53 files** | [Receipt](static/receipt.json); zero formatting changes and no analyzer issues |
| Actual committed BAS on Dart VM and JavaScript | **Identical reports** | [Receipt](portable/receipt.json); stable source hashes, repeated DOCM reopen, recording, rollback and policy denials |
| Incoming complete Mail core package | **476 tests / 20 files** | [Incoming receipt](incoming/qualification.json) |
| Incoming complete Mail store package | **924 tests / 38 files** | Includes real SQLite SIGKILL crash recovery and schema migration |
| Incoming composer/settings/adapter | **37 tests / 3 files** | Shared native composer fixtures |
| Incoming editor insertion/ODT loading | **22 tests / 2 files** | Original 19 insertion plus three loading cases |
| Incoming ODT reader/Zotero merged tables | **85 tests / 2 files** | Reader and field preservation |
| Existing ODT/table/open regressions | **267 tests / 13 files** | Includes LibreOffice-derived fixture regressions |
| Late Mail/editor delta | **89 tests / 5 files** | [Receipt](incoming/late-mail-editor.json): 23 sync/migration, 21 insertion and 45 compose/draft-host cases |

These cohorts overlap. Do not add them into a claimed unique-test total. The
Word total includes 80 source-style tests, 74 focused native cases, all 60
incoming native cases and 20 end-to-end integration cases, alongside existing
Word/compiler/cascade regressions.

The 3,716-case run followed the final shared `rStyle` reader correction. The
subsequent main refresh changed only four engine library paths: the Zotero
model, ODT reader/writer and new ODT writer helper. The compiler, DOCX reader,
style helper and cascade remained byte-identical. The 315-case post-main run
therefore repeated both native style suites, both integration suites, cascade
and table-style suites plus all four affected ODT suites. The
[reconciliation receipt](post-main/reconciliation.json) records the exact
comparison. Final portable and static gates ran after that main refresh.

The incoming PR #326 retains its own separately attributed
[631-case qualification and converter evidence](../zotero-editable-odt-20261121/README.md).
It is preserved as incoming evidence; it is not added to this continuation's
execution totals or represented as a new installed-host test.

## Review findings and reconciliation

Independent review and executable fixtures identified and corrected native
namespace/lookalike projection, stale in-memory style definitions and table
spacing inheritance. The late independent implementation also supplied useful
ownership and preservation checks. The unified operation now:

- Checks cyclic/duplicate block ownership before generic field traversal.
- Counts generated TOC/result content as an owner and refuses generated targets.
- Retains live inline/run identity while atomically replacing prepared properties.
- Preserves metadata on an existing native `pStyle`, including pending model edits.
- Validates original native property packets and scalar/measurement values.
- Refuses active or style-linked numbering changes that cannot be preserved.
- Adopts the narrow native-namespace/direct-depth `rStyle` import correction.

Both independently authored integration fixtures are retained under distinct
names, with the [provenance comparison](reconciliation/checkpoint-preservation.json).
The incoming native suite's XML fixtures are retained: all 55 XML-bearing source
lines match the original `cf12544d` blob. Six registrations were reconciled to
the deliberately narrower documented contract. They continue to require atomic
refusal, identity/source preservation and true pre-edit style import assertions.
The [adoption record](reconciliation/adoption.md) explains each decision and
keeps the initial failures distinct from accepted final passes.

The earlier 3,654-test run predates the late native reconciliation and is
superseded by the full 3,716-test receipt. Interrupted setup, transient
in-progress source failures and the unchanged-intake failures are not counted
as passing evidence. The evidence archive retains the useful original intake
receipt and diagnostics so these distinctions remain reviewable.

Incoming Mail qualification corrected old-schema fixtures for the additive v10
tables. The late Notes guard refuses a body-caret insertion while a footnote or
endnote owns the active selection, preserving body/note content and
history. Four incoming Mail paths subsequently received only pinned-formatter
changes; their patch is included in the execution archive. Final strict analysis
covers those exact formatted files.

## Reproduction and evidence

The commands, selected file lists and source hashes are in the compressed
receipts and readable manifests under `word/` and `post-main/`. Ordinary
`dart test` implicitly waited during runner setup in this environment, so the
official `package:test` entry point was compiled once with the same workspace
package configuration and invoked directly:

```bash
# From the repository root, using the pinned SDK and enforced lockfile:
dart compile kernel --packages=.dart_tool/package_config.json \
  "$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart" -o /tmp/quds-test-runner.dill

# From packages/quds_office_engine; use the full file list in the receipt:
dart --packages=../../.dart_tool/package_config.json /tmp/quds-test-runner.dill \
  --concurrency=3 --timeout=180s --reporter=expanded \
  test/office_macro_word_paragraph_style_test.dart \
  test/word_paragraph_style_assignment_test.dart \
  test/office_vba_word_styles_test.dart \
  test/office_vba_word_styles_integration_test.dart \
  test/office_vba_word_styles_checkpoint_integration_test.dart
```

Flutter widget tests used `flutter test --no-pub --reporter expanded`.
Portable compilation injects the actual committed BAS through
`-DWORD_STYLES_BAS_BASE64`, compiles both kernel and optimized JavaScript, and
compares the complete JSON reports. Exact invocations, source digest and outputs
are retained in the portable receipt and execution archive.

[execution.tar.gz](execution.tar.gz) contains raw final event streams, stderr,
portable reports, static outputs, relevant incoming/late regression logs,
intake diagnostics and source-review probes. It excludes SDKs, caches, generated
kernels and generated JavaScript. [artifacts.json](artifacts.json) gives lengths
and SHA-256 hashes for the committed evidence. [source-binding.json](source-binding.json)
binds accepted final inputs and captured ancestry to the remote source checkpoint.

## Remaining boundaries

This is a tested write-only style-assignment increment, not full Microsoft Word
VBA parity. It does not implement style reads, `Style` objects, the `Styles`
collection, ordinal indices, automatic style creation, inferred localized
built-in names, arbitrary text subranges, whole-story style assignment or
generated TOC editing. Actively numbered paragraphs, shared mutable ownership,
unbalanced fields, stale style definitions and ambiguous native sources are
refused before publication. Namespace shapes whose effective values would
change on an ordinary native reopen remain unsupported.

Embedded VBA projects remain opaque and are not executed on open. No installed
Microsoft Word differential run, editor macro-authoring UI, live mailbox or
installed Zotero-plugin acceptance is claimed. Those remain separate milestones
in the existing roadmaps.
