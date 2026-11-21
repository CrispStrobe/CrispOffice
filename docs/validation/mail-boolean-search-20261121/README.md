# Boolean mail search — source and validation record

Date: **21 November 2026 (Europe/Berlin)**.

## Result and exact source

The feature and regression tests are implemented and saved remotely.
**Runtime qualification is pending. No Dart or Flutter test passed in this
session because none could be started.**

- Captured main: `1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0`.
- Reviewed incoming-work checkpoint: `4191be02ac9c7117e05ff4a052a5c92fbcfbf4b4`.
- Initial integrated search checkpoint: `580da80ca0f4e67a34490eb1817e5b105edc7a9c`.
- Final Mail feature source/test checkpoint: `c2b8138df334d1145003ef62bc8e395d901fd3ba`.
- Preserved final core branch head: `3e6374115c10a92fdb4b82734c1bc2b009210794`.
- Remote implementation branch: `work/mail-triage-20261121`.

The [machine-readable receipt](receipt.json) records source blob IDs, test
registration counts, environment failures and each unexecuted gate. Documentation
commits after the source checkpoint do not constitute a new test run.

## Incoming work

The [intake report](../../mail-intake-20261121.md) captures all 51 starting
branches, zero open pull requests and upstream ancestry. All recent mail branches
were already in main. Thirty-eight non-main heads were ancestors; ten divergent
heads were already integrated through squash commits or an exact replay.

The two genuinely missing branches were reconciled before feature integration.
The benchmark gained its two exact output fields. The remaining CLI tests now
use the bounded per-file launcher, with compilation awaited in setup and
appropriate setup timeouts. Generated test directories were omitted. The WIP
cross-test kernel cache was replaced by the reviewed per-file implementation
because its key, cleanup and lock behavior could reuse or remove another
test's kernel. Both incoming branch heads remain in commit ancestry.

A later publication check also captured the compile-only package-config path
fix at `41c363f40cdcdfbcc22a8932ea325ce87872f5a0` and documentation-only Zotero
PR #299 at `d9bfa44022781f0dd4493a923ca9f20316dc59f0`. The path fix is applied
to the safe helper; all four Zotero documentation files are preserved without
claiming native ODT implementation. Their original heads remain in ancestry.
The final-cutoff section of the intake report records this later snapshot.
Mail feature source and test blob IDs below remain unchanged.

## What changed

The loaded-folder header query accepts uppercase AND/OR/NOT, implicit AND,
leading minus and bounded groups, with NOT > AND > OR precedence. Matching is
three-valued for unknown flags/dates; only a known true result matches. The
complete input is parsed before evaluation. Bounds are 1,024 UTF-16 code units,
32 leaves, 32 explicit operators and eight nested groups.

The existing mailbox UI receives localized guidance/errors in English, German
and Arabic. Quick filters still combine with the entire query. Query edits keep
the existing checked-selection pruning and interaction-generation guards.
The independent UI review found that no-space `NOT(...)` help examples inherited
RTL direction; the final checkpoint fixes the recognizer and adds tight/nested
NOT fixtures.

No provider call, storage schema, credential flow, mailbox mutation, dependency
or sending behavior is added by search.

## Evidence collected

| Check | Observed result |
| --- | --- |
| Remote intake audit | Exact 51-head disposition recorded; no open PRs at capture |
| Independent core review | No blocking semantic finding after manual parser/evaluator and test-expectation inspection |
| Independent UI review | One RTL syntax-example defect found and fixed; remaining scope/selection expectations agreed with fixtures |
| Remote source readback | All eight changed Mail Dart paths retrieved at the final source SHA; expected contents or recorded blob IDs matched |
| RTL pattern reference | Eight examples checked with the identical pattern in JavaScript RegExp, eight matched expectations; this is not Dart/Flutter execution |
| New test registrations | 26 core, three mailbox widget, one bulk widget, three host-locale registrations; **zero executed** |
| Dart/Flutter analyzer, formatter and tests | **NOT RUN — local runtime unavailable** |
| Office CLI tests and typing benchmark | **NOT RUN — local runtime unavailable** |
| GitHub Actions | Not queried, awaited or rerun |
| Browser, installed app and live providers | Not qualified by this increment |

Core tests cover both operand orders of every nullable-flag truth-table pair,
missing dates, precedence, grouping, literal compatibility, exact error offsets,
complete-input rejection and each independent budget. UI tests cover Boolean
queries combined with chips, malformed-query recovery, stale row/bulk callbacks,
hidden-selection pruning, account reset, RTL syntax and translated diagnostics.

These are authored regression cases and static evidence, not a passing test
receipt. Historical Mail qualification remains attached to its original source.

## Environment failure

The public repository clone was requested with blob filtering, but checkout
materialized the repository's large validation artifacts and exhausted the
available disk. The observed filesystem then reported zero free bytes.
Subsequent ordinary commands and patching failed before execution with:

```text
bwrap: Can't create file /workspace/scratch/9e481f678650/.git: No space left on device
```

A narrowly scoped recovery command targeted only newly cloned docs/apps, whose
sources remained on GitHub. It could not start in the default sandbox; the
environment rejected escalation under its configured approval policy. Later
command startup failed with `exec-server ... No such file or directory`.
No Dart/Flutter runtime was installed, and no source tests could start.
All subsequent edits used sequential GitHub tree/commit/ref operations with
expected-head checks and without force updates. No GitHub CI queue was awaited.

## Reproduction on a working checkout

Use the repository's pinned Flutter **3.47.8** toolchain and committed dependency
lockfile. These commands are the remaining gates; they are not completed checks.

From the repository root:

```sh
flutter pub get
git diff --name-only 1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0...HEAD -- '*.dart' |
  xargs dart format --output=none --set-exit-if-changed
```

From `packages/quds_mail_core`:

```sh
dart analyze --fatal-infos
dart test test/header_search_test.dart test/header_search_boolean_test.dart
```

From `packages/quds_mail_ui`:

```sh
flutter analyze --no-pub --fatal-infos
flutter test --no-pub test/message_list_test.dart test/bulk_message_list_test.dart test/message_list_bulk_test.dart
```

From `packages/quds_office_editor/example`:

```sh
flutter analyze --no-pub --fatal-infos
flutter test --no-pub test/studio_mail_boolean_search_strings_test.dart test/studio_mail_workspace_test.dart
```

Also run the twelve changed CLI suites and the changed typing/proofing benchmark
listed in the intake report, following their existing fixtures and toolchain
requirements. Qualify browser and installed/live-provider behavior separately.
The search adds no new provider behavior but this session supplies no new
provider acceptance evidence.
