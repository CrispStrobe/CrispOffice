# Word VBA integer arithmetic — 22 November 2026

## Delivered scope

The shared source compiler now supports integer division (`\`) and signed
remainder (`Mod`) in the Word, Excel and PowerPoint adapters. The complete
`word_grouped_report.bas` fills an existing 2×2 table, appends group labels and
alternates emphasis in twelve native operations. The
[arithmetic contract](../../vba-macros-details.md#integer-division-and-remainder)
defines precedence, ties-to-even Long operands, strict conversion and Null
rules, zero/overflow errors and the signed-remainder specification discrepancy.

This is a bounded source-to-native-plan extension. It does not execute embedded
VBA, read live document values or claim installed Microsoft Office parity.

## Remote preservation and intake

Work is retained on `codex/word-vba-extended-20261122` and
[PR #370](https://github.com/CrispStrobe/quds_office_suite/pull/370).

- `fcabea23fec4d18597ed4293ebd65857bd958b30` preserves starting main,
  pending Word suffix and Mail identity histories in one ordinary merge.
- `ad27e97263eee11dbd7b76f846bfea0a8e250499` preserves the arithmetic
  implementation, tests, complete BAS and contracts, plus the incoming completed
  Word suffix validation.
- The captured intake accounts for 35 fork branch heads, four upstream heads
  and 100 recently updated PR heads: all 39 branch/upstream heads are ancestors;
  96 PR heads are ancestors and four historical heads have independently
  verified complete-tree equivalents. All 139 captured references are covered.
- Late Mail identity `06b4e747` and bulk organization `f25c62e3`
  were published after that capture. Their later work is not claimed as
  qualified by this continuation; the bulk branch contains new UI behavior.

Main at intake was `b38f2e38369855056eb9e23792f83fd1ab86ea24`. The incoming
Word suffix head `d4317dcc1ecc6c7b70a1773cc121f5639ad99428` and initial
Mail identity head `8da0e8385794e4ec0af10cd4fbd4d489f98acb01` are retained
as genuine ancestors. The Mail conflict resolution keeps both safety test
sets, timestamp rollback guards, display-name quota accounting and the
receipt-preserving nested savepoint.

## Completed local checks

| Gate | Result |
| --- | --- |
| New integer arithmetic | 94 passing tests |
| Existing numeric and Variant suites | 593 passing tests |
| Combined arithmetic/numeric/Variant execution | **687 passing tests across five suites**, zero failures/errors/skips, empty stderr |
| Integrated Mail core | 629 passing executions |
| Native SQLite store, migrations, identity and synchronization | 389 passing executions |
| IMAP/EWS transport | 218 passing executions |
| Vendored IMAP parser using the locked root runner | 22 passing executions |
| Combined Mail execution | **1,258 executions across 55 suites**, 1,257 unique suite/name keys, zero failures/errors/skips, empty stderr |
| Scoped Mail strict analysis | Four successful gates |

The arithmetic production file has SHA-256
`0847838044cb18fe844fc2660870a0141a9f8d16b3c9d98f183297afff94d60b`;
the new arithmetic unit test has SHA-256
`d43f1852854423aced48c6f9daeec3040aa61b4e2dd0195b5402cd60dd279eb9`.
No production arithmetic change followed the passing 687-test execution.

All 441 selected Mail inputs remained unchanged and were subsequently checked
against Git objects at `ad27e972`. The SQLite tests used real native build
hooks. The first hook attempt stopped before tests on ENOSPC and is excluded.
A supplemental vendor run using separately resolved newer test tooling is also
excluded; the accepted parser run used locked `package:test 1.31.1`.

The initial grouped Word gate successfully exercised actual BAS CLI compilation,
detached validation, DOCM execution, output protection, calculated native plans,
MCP arithmetic-failure refusal and mutation/tool/step policies. It was not a
complete passing gate: two static diagnostic expectations used the operator
column instead of the incompatible-operand column, and the document fixture
incorrectly expected `run` to record its own expansion. Those fixture mistakes
were corrected at `ad27e972`; the production compiler needed no change.

## Explicit verification limits

The complete 145-suite macro/VBA/native-command run encountered ENOSPC in
temporary directory creation and was interrupted with exit 130. Its partial
successes are **not** counted as a completed gate. The subsequent disk
exhaustion prevented even a new sandbox process from starting, so normal
cleanup, final engine analysis and further execution were unavailable.

These checks remain uncompleted:

- the complete corrected grouped-document and 54-case conformance suites;
- the complete 145-suite macro regression gate;
- VM versus compiled-JavaScript comparison of the new corpus and actual BAS;
- the affected Flutter Mail journal-dialog and move-identity suites;
- final engine static analysis.

The implementation is published with these bounded local results, not a claim
that the uncompleted gates passed. Raw local event streams and detailed input
manifests remain in the task workspace; the second ENOSPC prevented packaging
and uploading the full raw archive. The remotely preserved
[qualification summary](qualification.json) records the completed results,
source identity, exclusions and outstanding checks.

GitHub Actions, status and check queues were **neither queried nor awaited**.
No CI success is used as a substitute for local execution.

## Runtime and reproduction

The verified runtime is official Dart 3.13.7 / Flutter 3.47.8 with Node
24.22.3. Pure Dart qualification used a copied workspace containing 75 resolved
lock entries, all matching the repository's versions, sources and hashes.
The full Flutter workspace also resolved with `--enforce-lockfile`.
The tracked lockfile stayed byte-identical:
`2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.

From the repository root, with the pinned SDK available:

```sh
flutter pub get --enforce-lockfile
cd packages/quds_office_engine
dart test --concurrency=1 \
  test/office_vba_integer_arithmetic_test.dart \
  test/office_vba_numeric_intrinsics_test.dart \
  test/office_vba_numeric_conformance_test.dart \
  test/office_vba_variant_conformance_test.dart \
  test/office_vba_variant_conversions_test.dart
dart test --concurrency=1 \
  test/office_vba_word_integer_arithmetic_conformance_test.dart \
  test/office_vba_word_integer_arithmetic_integration_test.dart
dart analyze --fatal-infos lib test tool
```

Run the broad macro suites in batches of about five files to bound retained
compiler kernels. Serial concurrency within one large invocation was
insufficient for this workspace's available disk capacity.

The retained `run_portable.py` helper compares the exact 54-case arithmetic,
120-case Variant conversion and 38-case Variant composition corpora, plus the
actual grouped BAS, on VM and JavaScript. It records source and output hashes
and removes reproducible JavaScript build products after each comparison.
It was prepared but not executed in this environment:

```sh
python3 docs/validation/word-vba-integer-arithmetic-20261122/run_portable.py \
  --workspace "$PWD" --output /path/with/adequate/free/space
```

The affected Flutter checks are
`packages/quds_office_editor/example/test/studio_mail_journal_dialog_test.dart`
and `studio_mail_move_identity_test.dart`; run them with the pinned Flutter
runtime and existing locked dependencies. The ordinary macro workflow now
includes the new tests and portable checks for later CI execution.
