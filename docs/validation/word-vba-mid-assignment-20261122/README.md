# VBA substring assignment continuation

## Implemented scope

The shared source compiler now accepts standalone `Mid` / `Mid$` assignment
for mutable local String and String-valued Variant bindings, including
allocated fixed/dynamic String/Variant array elements, ByVal helper parameters
and the current function's result variable. The operation replaces UTF-16 code
units without growing the target. This prepares fixed-width labels and
template data before the existing Word operations are emitted.

Target/index, start, optional length and replacement evaluate once in source
order. The compiler retains its strict String/exact-integer contracts,
inactive-source checks, copy-work and array budgets, native publication guards
and complete-plan failure boundary. Zero-length edits validate every supplied
argument while avoiding a copy charge. Ordinary expression `Mid$` is unchanged.

See the [exact contract](../../vba-macros-details.md#replacing-part-of-a-source-string),
[complete BAS](../../../packages/quds_office_engine/example/macros/word_fixed_width_labels.bas)
and [independent corpus](../../../packages/quds_office_engine/test/fixtures/vba_conformance/mid_assignment_v1.json).
Property lvalues, byte mode, broader coercions, live document reads, embedded
VBA execution and editor-host macro authoring remain separate work.

## Intake and remote preservation

The baseline was fork `main`
`3f3cb8508663dde917e913867908dbfd6c3efcf0`, after Word table-navigation PR #376
and Zotero research-note PR #377. [Initial intake](intake.json) checked all 37
fork branch heads, the latest 100 updated PR heads and all four upstream heads;
every head was already an ancestor. There were no open PRs and no intake merge
was necessary. Upstream `main` was
`15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`.

Incremental checkpoints remain on `codex/word-vba-string-search-20261122`:

| Checkpoint | Content |
| --- | --- |
| `82594a44daefc95acaada026dcc8e34b89723240` | Reconciled baseline and scope |
| `dcb769977857e5104570dad761e2b2b323459883` | Compiler, focused tests, independent corpus, example and contracts |
| `19a63d4455540bd797e546ab82ec14db128abea0` | Native Word, CLI and actual-example portable qualification |

Each remote tree was checked against the staged local tree, then saved with
an expected-head, non-forced branch update. GitHub Actions, workflow runs and
status checks were neither queried nor awaited.

[Final intake](final-intake.json) refreshes the original heads, upstream and
remote main. Two new concurrent branches appeared after initial intake:
`codex/zotero-note-formatting-20261122` and
`work/mail-connected-workspace-20261122`. Their records still identify work
in progress, with no ready PR or completed acceptance at the observed heads.
They are retained on their remote branches and recorded separately; this Word
continuation does not qualify or promote those incomplete workstreams.

## Local qualification

The source being qualified is saved in `19a63d44`; its exact changed inputs and
shared fixture dependencies are recorded in the
[source manifest](evidence/source-manifest.json). The broad run started at the
preceding implementation checkpoint with the three new document-test files
present; those unchanged bytes were then saved as `19a63d44`. Every recorded
compiler/test hash still matched at completion. Subsequent changes are the
validation records only.

| Check | Result |
| --- | --- |
| Full selected VBA/native macro regression, 152 files | **8,006 passed; zero failures and skips** |
| Focused Mid compiler suite | 80 passed |
| Independent conformance test suite | 316 passed |
| New Word native/CLI tests | 9 passed |
| Canonical 77-case corpus across all three adapters, VM and dart2js/Node | 231 cases per host; byte-identical receipts |
| Actual checked-in BAS on VM and dart2js/Node | Matching structured receipts for both DOCX and DOCM |
| Strict analysis of all seven changed/new Dart files | No issues |
| Formatting of those seven Dart files | No changes required |
| Independent code, test and documentation review | No actionable findings |

Targeted counts overlap the broad total and are not a compatibility percentage.
The [qualification receipt](qualification.json),
[full regression command and input hashes](evidence/macro-regression-command.json),
[regression results](evidence/macro-regression-result.json),
[final-source corpus commands](evidence/conformance-portable-commands.json),
[actual BAS commands](evidence/word-portable-commands.json),
[static checks](evidence/static-checks.json) and
[compressed-log manifest](evidence/log-manifest.json) retain the evidence.

The tests cover replacement truncation/no growth, self-overlap, ByVal isolation,
function-result and array ownership, evaluation order, allocation/boundary
refusals, exact array occupancy/release and work limits, surrogate splitting
and repair, and native Unicode rejection. Document checks verify the exact
eight-operation BAS, immutable validation, DOCX/DOCM save/reopen, untouched
geometry and opaque parts, native recording/replay, CLI/MCP, read-only policy,
late rollback and preservation of existing output/plan files after failure.

The [runtime record](evidence/runtime-provenance.json) identifies official
Dart 3.14.1 with its published archive checksum verified. The isolated
pure-engine workspace resolves 59 entries, uses repository-lock hosted
versions and maps to the actual checkout. Tracked manifests and lock files
were unchanged. The canonical pinned Flutter workspace, Flutter UI and an
installed Microsoft Word host were not executed. Corpus provenance separates
Microsoft specification-derived expectations from explicit Quds dialect rules.

## Reproduce

In a provisioned, dependency-resolved workspace:

```sh
cd packages/quds_office_engine
dart test test/office_vba_mid_assignment_test.dart \
  test/office_vba_mid_assignment_conformance_test.dart \
  test/office_vba_word_mid_assignment_integration_test.dart \
  test/office_vba_word_mid_assignment_cli_test.dart -r expanded

dart test test/office_vba_*_test.dart test/office_macro_*_test.dart \
  --concurrency=4 -r expanded
```

The portable runners accept the exact corpus or BAS bytes as Base64 compile
defines, `VBA_CONFORMANCE_BASE64` and `WORD_MID_ASSIGNMENT_BAS_BASE64`.
Recorded commands include the package configuration and the Node
`globalThis.self=globalThis` initialization used by the document runner.
No GitHub Actions result is part of this acceptance record.
