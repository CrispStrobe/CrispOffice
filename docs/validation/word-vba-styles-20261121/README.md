# Word VBA paragraph styles — completed local qualification, 21 November 2026

## Outcome

The bounded Word VBA compiler and native executor now support writable
`Paragraph.Style` and a selected paragraph's `Range.Style`. The compiler,
native operation, transaction behavior, portable examples and documentation
are implemented and locally qualified. GitHub Actions were not awaited or
used as a gate.

This record supersedes the original compiler-only checkpoint and its workspace
disk failure. The historical intake remains in [intake.json](intake.json);
the current reconciliation is in [reconciliation.json](reconciliation.json).
The original checkpoint remains available in Git history.

This is a source-to-plan compatibility increment, not an embedded VBA runtime
or a claim of complete Microsoft Word compatibility.

## Supported contract

- Select an existing paragraph style by nonempty XML-safe primary name, matched
  case-insensitively while retaining significant spaces.
- Select one of 13 built-in constants: Normal (-1), Heading 1–9 (-2 through -10),
  Caption (-35), Title (-63) and Subtitle (-75). Numeric selection requires a
  noncustom native definition with the corresponding English primary name.
  Native IDs may differ from those names.
- Use existing typed Paragraph/Range aliases, nested With blocks, required
  ByVal helpers and named arguments. A String such as "-2" remains a name.
- Select ordinary body or independently owned header/footer paragraphs using
  the existing paragraph/story/section selectors.
- Emit one `docx.paragraphStyle` step with exactly one `name` or `builtin`.
  The existing `docx.applyStyle` operation retains its separate behavior.
- Refresh the selected paragraph's inherited paragraph and run formatting
  without erasing direct formatting, explicit overrides, character styles,
  table context, previous plan edits or unrelated native/foreign metadata.
- Preserve native prefix aliases, foreign namespace bindings, existing
  pStyle marker metadata and opaque DOCM parts through repeated saves/reopens.
- Create an explicit native style reference even for a same-value assignment.
  Unselected paragraph and run identities remain unchanged.

The executor resolves the operative native document/styles relationships and
validates unique style identities/names, compatible acyclic inheritance,
supported native property values and exact target ownership. It refuses
unsynchronized modeled style replacements/removals, cyclic/shared content
owners, ambiguous markup alternatives and effective numbering changes.
Unchanged numbering is supported and tested, including actual labels and
original operative definitions. Style-linked numbering changes refuse even
when the model has no effective numId.

Shared property objects on otherwise independent runs are detached safely.
Shared content/run objects, including aliases retained in a TOC source cache,
are refused before mutation. Generated TOC/result paragraphs are not targets.

Mutation policy, allowlists, step budgets, validation-only execution,
recording/replay and late transaction rollback retain their existing contracts.
Style reads, Styles collections, Style objects, arbitrary numeric collection
indices, automatic style creation, multi-paragraph/whole-story Range.Style and
embedded VBA execution remain outside this increment. Direct-format semantics
have not been differentially qualified against an installed Microsoft Word host.

See the [public contract](../../VBA_WORD_MACROS.md#existing-paragraph-styles)
and [complete BAS example](../../../packages/quds_office_engine/example/macros/word_styles.bas).
The example performs five operations on three existing body paragraphs.

## Reconciliation

The working branch is `codex/word-vba-extensions-20261121`, with PR #322.
The initial task intake started from remote main
`3dbaa8429b14ac43721e165b4d50d3f6d2845309`, the existing draft style branch,
and the outstanding Mail compose branch. Remote progress was preserved in
incremental checkpoints.

Subsequent intake incorporated:

- Mail compose and saved-account restoration work through main
  `1078372da9213c1ef4cdd362ca2285db9acb8d7b`.
- The concurrent Word style implementation through
  `2fb916c70eb469c69e7d401c2bc553a8ad9225d7`, with its final independent
  qualification preserved at `0cf5b2c4295b303d15d11a92faeee2063f6b33c7`
  and its last input-bridge regression at
  `f086214c9e99bca547957d8ba9f6ee3ab15321dc`.
- Editable Zotero ODT export and its qualification through
  `b699f88501a10818e0f71bfd9c53cde53866cdf6`, merged in main
  `c7380f53a55b47a5b7672eb3f7afee32d92def6e`.
- The subsequent autocorrect and IME-aware proofing PRs through main
  `0172df91adeb4a1abb2f43346621e10999937572`, followed by the final concurrent
  Word PR #329 merge at `4760902b654e3af5e4d3f0a83d28ac65a387c8f8`.

The two Word implementations were reconciled into one native implementation.
Distinct incoming native and integration fixtures were retained; duplicate
implementation files were removed. Additional pending-style synchronization,
namespace-binding and retained-TOC ownership guards were incorporated.
Incoming tests that had asserted broader refusal were retained as explicit
preservation/isolation tests for the combined supported behavior.

All 36 fork branch heads and all four upstream heads observed at the recorded
intake are accounted for by ancestry. The record states its observation scope;
it is not a claim about every historical pull-request head.

## Executed local checks

The pinned runtime was Flutter 3.47.8 / Dart 3.13.7 with locked offline
dependency resolution. The Flutter archive matched the official SHA-256:

`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`

Tracked dependency manifests and lockfiles were not changed.

| Check | Executed result and scope |
| --- | --- |
| Broad Word/VBA/style/transaction regressions | 3,301 passed in 71 suites at checkpoint cf12544d, before the last concurrent reconciliation |
| Reconciled style compiler and two integration fixtures | 100 passed: 80 compiler, 9 original integration and 11 alternate integration cases |
| Final native style suites | 138 passed in one run: 64 original native and 74 alternate native cases |
| Portable committed BAS | Both independent fixtures passed on the VM and compiled JavaScript, with matching JSON for each fixture |
| Final engine analysis | Full engine `dart analyze --fatal-infos` passed after both latest remote heads were incorporated |
| Changed Dart formatting | 57 changed Dart files passed the formatter check after five whitespace-only corrections |
| Mail qualification | 476 core, 37 compose/settings/adapter, 56 earlier host regressions and 21 editor insertion tests passed; final reconciled hosts passed 63 plus 14 automatic-connection tests |
| Mail store | Initial full run: 922 passed and two obsolete fixture failures; the corrected sync file subsequently passed all 23 cases |
| Incoming ODT/Zotero | 132 combined engine tests passed; after the decimal-note correction, the focused writer/lifecycle/ordinary-writer gate passed 48 |
| Incoming editor/Studio ODT | Three merged-table loading and five export widget tests passed |
| Real Writer save | Two editable Zotero acceptance fixtures retained seven field records, preferences and decimal note labels after the correction |
| Latest-main editor interactions | 48 passed: five autocorrect, 22 typing/proofing and 21 insertion tests, plus strict analysis of the affected paths |
| Final concurrent-main regression | Six autocorrect tests passed, including one additional independent empty-paragraph/next-keystroke regression; test analysis and formatting passed |

Counts overlap across gates; they must not be added into a unique-test total.
The broad 3,301-case run was not repeated after the final narrow guards.
Those guards are covered by the final 138-case native run. The final formatter
changed layout only. Flutter export checks preceded the engine-only numbering
correction; its affected writer paths and actual consumer save were rechecked.

The portable fixtures exercise five BAS operations, validation without
publication, two additional reopen cycles, repeated execution, opaque DOCM
preservation, late rollback, two-step recording/replay and six atomic policy
denials. The second fixture additionally checks aliased native pStyle metadata.

Raw root-run logs, commands and portable results are preserved in
[execution.tar.gz](execution.tar.gz). The [validation summary](validation.json)
records counts, scope, archive hashes and the final source inventory. Native
test/analyzer output was emitted directly to the execution tool; its exact
commands, output identifiers and source hashes are in
[native-validation.json](native-validation.json), rather than an invented raw
log file.

## Reconciled adjacent fixes

Mail integration corrected the saved-account restoration screen so ordinary
manual catalog edits remain available, forwarded embedded native close
callbacks and retained the footnote/endnote insertion ownership guard.
The [Mail record](../mail-compose-tools-20261121/README.md) distinguishes the
initial store failures from the corrected focused rerun.

A real LibreOfficeDev save exposed two numbering defects in the incoming
editable Zotero export: automatic decimal endnotes reverted to Roman, and a
fixed Roman note incorrectly advanced the exporter's automatic counter.
The exporter now emits explicit decimal note configuration and refuses cited
mixed numbering that it cannot preserve. Ordinary cached ODT export remains
unchanged. The [supplemental note](../zotero-decimal-endnotes-20261121/README.md)
preserves the failing examples, correction, exact consumer version and
after-check evidence. This is not installed Zotero-plugin acceptance.

The final main intake also introduced autocorrect and IME-aware proofing.
Reconciliation fixed two demonstrated interactions: corrected text now reaches
the input bridge/system IME, and active composition suspends already pending
automatic proofing work until commit. The original 46-case affected gate passed;
two added regressions then failed before correction, and the final gate passed
all 48 cases. Exact commands, logs and source bindings are in
[editor-proofing-validation.json](editor-proofing-validation.json).
The last concurrent main merge independently fixed the same input-bridge issue.
Its additional boundary regression was retained alongside ours and the resulting
six-case autocorrect file passed. Production editor source remained identical to
the source qualified by the 48-case gate. Those two gates overlap by five cases.

## Reproduction

Resolve the repository's pinned workspace dependencies, then run these checks
from `packages/quds_office_engine`:

```sh
dart analyze --fatal-infos
dart test --concurrency=1 --timeout=4x \
  test/office_vba_word_styles_test.dart \
  test/office_vba_word_styles_integration_test.dart \
  test/office_vba_word_styles_alternate_integration_test.dart \
  test/word_paragraph_style_assignment_test.dart \
  test/office_macro_word_paragraph_style_test.dart
```

The recorded environment invoked the locked package:test runner directly with
the root package configuration; exact commands and working directories are
retained in the receipts. No replacement dependencies were introduced.

To run the exact committed BAS on either host:

```sh
WORD_STYLES_BAS_BASE64=$(base64 -w0 example/macros/word_styles.bas)
dart -DWORD_STYLES_BAS_BASE64="$WORD_STYLES_BAS_BASE64" \
  tool/macros/web_vba_word_styles_smoke.dart
dart compile js -O1 \
  -DWORD_STYLES_BAS_BASE64="$WORD_STYLES_BAS_BASE64" \
  tool/macros/web_vba_word_styles_smoke.dart -o word_styles.js
node -e 'globalThis.self = globalThis; require(process.argv[1])' ./word_styles.js
```

Repeat with `web_vba_word_styles_alternate_smoke.dart` for the independent
fixture. Compare each fixture's VM and JavaScript JSON results.

Primary API references:
[Paragraph.Style](https://learn.microsoft.com/en-us/office/vba/api/word.paragraph.style),
[Range.Style](https://learn.microsoft.com/en-us/office/vba/api/word.range.style)
and [WdBuiltinStyle](https://learn.microsoft.com/en-us/office/vba/api/word.wdbuiltinstyle).
