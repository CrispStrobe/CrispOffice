# Word VBA language and complex-script font controls

This record qualifies source checkpoint
`05c14895c44054ca92a3f3c6671749ea2c7aa69c` for PR 308. Its tree is
`4cabffbf91b3850c04bdf65e5b76dd4ebfd963dd`. The final evidence commit adds
this record and receipts without changing runtime code, tests, examples or
dependencies. All qualification below ran locally; GitHub Actions, workflow,
check and status queues were neither queried nor awaited.

## Delivered behavior

- Bounded Word VBA accepts `Range.LanguageID` and `Range.LanguageIDOther`
  writes for 30 explicitly mapped language IDs, supplied as exact integers or
  supported `wd...` constants. Both write the normal proofing-language slot.
  `LanguageIDOther` means the Latin-language setting in right-to-left Word;
  it is not a bidi-language setter.
- `Font.NameBi` writes the complex-script font independently. Existing
  `Font.Name` owns the ASCII/high-ANSI pair. Each write retains unowned script
  slots, unrelated theme data, foreign attributes and opaque XML.
- Typed aliases, `With`, named `ByVal` object helpers, optional scalar arguments,
  body paragraphs and explicit independent header/footer paragraphs reuse the
  established compiler, transaction, policy, recording and replay boundaries.
- Same-value writes still become explicit direct overrides when inheritance
  requires one. Normal language writes retain bidi/East Asian language data and
  proofing flags. Namespace-aware parsing and property emission preserve foreign
  lookalikes, nested metadata and foreign section-property elements.
- Native `docx.runFormat` now accepts `language` and `csFont`. Canonical language
  tags use the documented bounded syntax; duplicate owned XML and ambiguous
  markup-compatibility alternatives refuse before mutation.

The source contract, all 30 mappings and exclusions are in
[VBA_WORD_MACROS.md](../../VBA_WORD_MACROS.md#proofing-language-and-complex-script-font-controls).
The executable example is
[word_language_controls.bas](../../../packages/quds_office_engine/example/macros/word_language_controls.bas).
It requires two nonempty body paragraphs and one independent primary-header
paragraph. It produces seven native operations, including normal-language,
proofing and independent font writes.

This is an extension of the bounded source adapter. It does not execute embedded
VBA projects, implement general Word COM automation or add live property reads.
Arabic, Hebrew, East Asian, undefined, no-language and no-proofing language IDs
are explicitly refused by these setters. Use the existing `NoProofing` control
for that separate operation. DOCM VBA payloads remain opaque and inert.

## Final local qualification

| Check | Result and exact scope |
| --- | --- |
| Combined engine regression | **5,322 passed, zero failures/skips**, across **110 test files** on `05c14895…` |
| Combined input integrity | All **602** captured source, test, manifest and external-fixture hashes unchanged during the final gate |
| Static analysis | Clean across all **24 changed engine Dart files** |
| Formatting | All 24 changed engine Dart files pass the formatter check |
| JavaScript compiler cases | **110/110 passed** under Node; all 19 compiler/test inputs still identical |
| Actual BAS portability | Dart VM and compiled JavaScript produce byte-identical complete receipts, including plan, state and native-part hashes |
| Portable input integrity | All **428** captured inputs unchanged during the accepted run and identical at the final source checkpoint |
| Incoming Mail core slice | **110/110 passed** at captured commit `0dd22723…`; separate from engine totals and later Mail UI work |

The combined gate contains all 90 selected `office_*` macro/VBA suites, six
adjacent Word style/proofing suites, the 13-file ODT/ODF/isolate-open cohort,
and the incoming two-case ODT/VBA language round-trip suite. Counts are unique
within that final gate. Earlier 110-case compiler, 11-case transaction,
187-case native/adjacent and 432-case import cohorts overlap it and are not
added to its total. The Node compiler run checks the same 110 compiler cases on
a second backend; it is not another 110 distinct feature scenarios.

The new Word suites cover source acceptance/refusal, inherited and direct
formatting, slot ownership, alias namespaces, split ranges, headers/footers,
package preflight, validation-only nonmutation, rollback, CLI/MCP behavior,
existing-output preservation, record/replay, repeated save/reopen and inert
macro payloads. The added ODT/VBA cross-feature cases preserve Zotero citation
ownership, cached text, metadata and independent script formatting through
three DOCX cycles after either language or complex-font edits.

The accepted portable runner is
[web_vba_word_language_controls_smoke.dart](../../../packages/quds_office_engine/tool/macros/web_vba_word_language_controls_smoke.dart).
Its exact BAS source SHA-256 is
`8bf6a6a382ce7bf602064e9b1a47286a5ee781625e6bf02797fe134faa3b421b`.
Both canonical receipt hashes are
`f2d904a881ed42bd206dee3f4a57e4765cda0f638306e8558bbbfd0fbb349319`.
The receipt includes seven operations and seven recorded steps.

## Runtime and evidence

Qualification used official Dart **3.13.7**, with the downloaded SDK checked
against its official SHA-256, and Node **24.22.3**. The engine and legacy-parser
manifests were copied byte-for-byte into an isolated pure-Dart workspace.
Genuine enforced offline Pub resolution used all **56 hosted dependencies** at
the exact versions and content hashes from the repository lock. The separate
Mail core workspace used its exact 50 locked dependencies. No dependency or
package-version changes were introduced by this work.

The Node harness uses the unchanged locked `node_preamble 2.0.2` bytes used by
the installed `package:test` Node backend. No application logic was replaced
for the portable run. The exact source define, commands, working directories,
stdout, stderr, exit codes and source hashes are retained.

The first broad run completed 5,316 cases and failed four line-spacing layout
cases solely because the isolated workspace lacked the repository's
`LiberationSans-Regular.ttf`. The exact committed font and license were then
materialized; the font SHA-256 is
`075e71be4c58beda172ecb574a799308f04c3d054c6a5b7434954d3b0f1b28d8`.
The complete final 110-file gate was rerun with those fixtures included in the
before/after fingerprints. No code change was needed for that failure.

[local-evidence.tar.gz](local-evidence.tar.gz) contains the raw local receipts,
commands, runtime/dependency provenance, executable JavaScript artifacts and
source manifests. [evidence-manifest.json](evidence-manifest.json) records the
archive hash and every member hash; archive extraction was checked against the
manifest. [summary.json](summary.json) provides the final results without
unpacking the archive.

Earlier failing or invalidated attempts remain separately named in the archive.
They include initial test/fixture corrections, namespace-preservation probes,
the missing-font run, bare-Node/bootstrap failures and portability runs rejected
because incoming ODT source changed during execution. The accepted evidence is
under `final-word-gate`, `final-word-static` and
`word-language-portability-accepted`; earlier records do not claim final success.

## Incoming work and merge preservation

The initial remote main was `2f90a0c8f21499d5a1113943971cb7379183885c`.
[intake.json](intake.json) accounts for all **305** existing fork PRs, **26**
captured fork branch heads, four upstream branches and four upstream PR heads.
Of those PRs, 291 heads were already ancestors, 13 had exactly equal integrated
trees, and PR 140 had equal entries for all 37 changed paths in its integrated
squash. This avoids replaying superseded historical snapshots.

The initial Mail continuation through `0dd22723…` was brought in before Word
implementation. Normal merges subsequently preserved main
`fcb2128884768553141f41c02bf804e2267f9dbb` and completed PRs **306, 307 and
309**. Refreshed ODT heads `3b1625e5…`, `5647e457…` and `ec656412…` were also
preserved with their original histories. The final ODT checkpoint adds only
documentation/evidence/changelog updates and the independent VBA round-trip
test; runtime source remains identical to Word checkpoint `e254d17f…`.

[intake-frontier.json](intake-frontier.json) and
[intake-final.json](intake-final.json) preserve the refreshed remote snapshots.
[intake-acceptance.json](intake-acceptance.json) verifies that all **27** captured
fork branch heads, all four newer PR heads and all upstream heads are ancestors
of the final source checkpoint. Only our PR 308 was open at that capture.

Independent review of the incoming ODT reader found silent table-width loss,
sparse table/row inheritance resets, lost transparent-cell overrides and
unsupported used style content being dropped. The resolution preserves the
latest incoming width allocation, fixed-column consistency rule, loader guards
and source-path protection, and retains stricter duplicate-property and
used-metadata refusal. The added table suite has 23 cases. Its final 432-case
ODT/ODF/open cohort is included in the combined gate above.

Remote checkpoints were saved throughout, using normal parent-preserving
commits and expected-head ref updates:

| Checkpoint | Preserved work |
| --- | --- |
| `521fb2c2…` | Initial Word compiler/native extension, tests and intake |
| `8b236255…` | Completed Word preservation and latest completed main |
| `9d4b3b9e…` | Captured initial ODT reader history for qualification |
| `5899282f…` | Reproduced ODT table-preservation corrections |
| `e254d17f…` | Reconciled latest ODT import and Word source freeze |
| `05c14895…` | ODT documentation and independent cross-feature regression |

## Acceptance boundaries

The final gate is headless engine validation. This work did not execute Flutter
widget/Studio tests, macOS keychain acceptance or installed Microsoft Word,
LibreOffice or Zotero workflows. Imported ODT editor evidence explicitly binds
its own older checkpoint `5647e457…`; it is retained with that scope and is not
presented as a new run on this source. The native ODT reader continues to refuse
unsupported active formatting or structure instead of publishing a lossy
document. The mapped VBA language and font capability is the accepted extension;
complete VBA or installed-host parity is not claimed.
