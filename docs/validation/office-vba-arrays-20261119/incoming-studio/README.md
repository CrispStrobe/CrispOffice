# Incoming Studio mail restore — local qualification

19 November 2026. Qualified the three incoming Studio suites on the official
Flutter **3.47.8** SDK, using its bundled Dart and Linux Flutter tester. The
selected source checkpoint was
`ac9de9e000274718145659da0abc7c8cadb9e8c3`, which incorporates incoming mail
publication `358544a48466c942873a4718a87fa9d1c2be11f7`.
GitHub Actions were neither queried nor awaited.

## Results

| Suite or check | Result |
| --- | --- |
| `studio_mail_archive_restore_test.dart` | **12 tests passed** |
| `studio_mail_archive_restore_native_test.dart` | **1 test passed** |
| `studio_mail_archive_portability_visual_test.dart` | **5 tests passed** |
| Total distinct selected cases | **18 passed**, zero failures or skips |
| Recorded source/runtime input hashes | **All 2,197 unchanged** before and after execution |
| Copied full-workspace package manifests | **All 20** root/member manifests match their tracked repository counterparts |
| Flutter command and JSON reporter | Exit **0**, final `success: true` |

The widget cases cover explicit preview confirmation, cancellation and partial
results, dismissal, sanitized inspection errors, disposal during asynchronous
work, and localized behavior in English, German and Arabic. The native MIME
case verifies an export/restore round trip after removing the old database,
retaining exact original MIME, multiple provenance records, searchable body and
attachment text, binary attachments and rerun deduplication.

The visual suite always runs its layout assertions. It verifies localized
restore previews/results, desktop export controls and long paths, and narrow
Arabic controls with right-to-left layout and left-to-right filesystem paths.
Its optional PNG generator was not enabled; **none of these layout tests was
skipped**. There is no file named `studio_mail_archive_portability_test.dart`
in this checkout, so no such optional suite was selected.

## Source isolation and binding

The full Flutter workspace has 19 members and uses copied manifests with live
source/test/asset links. The runner used that workspace's complete package
configuration with `--no-pub --concurrency=1`; it did not alter the repository's
separate macro-validation package configuration.

Before running, all **345 engine library files** were copied into a separate
Studio-only directory and verified byte-for-byte against the original sources.
The Flutter workspace's engine `lib` link temporarily pointed at that snapshot.
This allowed a concurrent macro-parser compatibility correction to proceed
without changing the sources being compiled for the Studio tests. The original
engine link was restored after qualification; the isolated copy is retained in
the temporary workspace for inspection. No tracked production or test file was
modified for these checks.

The actual frozen engine inputs are recorded separately from the live
repository UI/mail inputs. [source-binding.json](source-binding.json) verifies
both groups against their tested Git checkpoint. The macro correction itself
is qualified by the separate macro acceptance record; this Studio result does
not claim to have tested the later compiler text. All other recorded repository
library/configuration inputs, relevant assets and fonts, selected test sources,
workspace manifests/locks/configuration, dependency manifests, and SDK runtime
binaries remained unchanged during this run.

The native fixture used the default `sqlite3` 3.9.1 hook with empty user defines.
It emits an existing Drift debug notice for multiple database instances, which
is retained in the reporter; the native test and the complete run succeeded.

## Evidence

- [receipt.json](receipt.json): exact command/environment, duration, exit code,
  output hashes, distinct counts and input stability.
- [studio-tests.stdout.log](studio-tests.stdout.log): original JSON reporter;
  stderr is retained separately.
- [test-summary.json](test-summary.json) and
  [suite-counts.json](suite-counts.json): visible completed test events and counts.
- [inputs-before.json](inputs-before.json),
  [inputs-after.json](inputs-after.json), and
  [input-stability.json](input-stability.json): actual execution input hashes.
- [source-frontier.json](source-frontier.json),
  [source-binding.json](source-binding.json), and
  [engine-snapshot.json](engine-snapshot.json): tested publication, copied
  manifest comparisons, and isolated engine content.
- [native-runtime.json](native-runtime.json): default SQLite hook and library
  hash captured after execution.
- [qualify.py](qualify.py): qualification runner for the retained workspace and
  engine snapshot. It restores the temporary engine link in `finally` and does
  not modify tracked sources, manifests, Git refs or CI state.
