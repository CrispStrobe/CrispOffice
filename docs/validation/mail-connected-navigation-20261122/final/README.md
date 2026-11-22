# Final local qualification plan

The original frozen run completed against
`d53f30f1874b38d36a791d1d3881583e4e42a2d6`. Its incoming engine gate passed 903
cases and shared Mail UI passed 294. Studio completed 2,221 cases with 2,203
passing and 18 failing; the original run is therefore **not accepted**. All
source/configuration inputs stayed unchanged. Its results and checksums remain
intact in [qualified-source](qualified-source/summary.json).

The full plan selects **110 Studio Mail suites**, **18 shared Mail UI suites**
and **14 incoming engine suites**. Strict analysis and pinned formatting cover
the live Dart paths changed since initial main
`4621326a5a452da475f219353c298d0f9b12470e`, including incoming Archive/Word/Zotero
changes and this navigation increment. The exact selection is recalculated and
frozen at execution time. `--plan` executes no Dart or Flutter gates.

## Scoped recovery after a new source freeze

Source the prepared runtime environment, then invoke:

```sh
python3 docs/validation/mail-connected-navigation-20261122/final/qualify_mail.py \
  --run --expected-head FROZEN_FULL_COMMIT_SHA --run-id studio-recovery \
  --gates analysis format studio_mail --retain-from qualified-source
```

The runner requires the supplied exact commit to match current HEAD. It verifies
the repository-pinned Flutter version and explicitly sets `BOT=true`, `CI=true`
and analytics suppression before any Dart/Flutter command. Those supported
environment settings prevent Flutter's Azure metadata bot-detection fallback;
SDK code and network controls remain unchanged.

This scoped recovery runs analysis, formatting and the complete Studio Mail
gate. It does not repeat the independent accepted engine and shared UI gates.
Before any recovery command, the runner verifies the original evidence checksums
and original runner hash, then compares every captured package/third-party input
outside Studio, root configuration, generated package configuration/graph, and
pinned runtime identity. The current comparison covers **5,561 source inputs**
outside Studio. Declared dependencies and actual local import/export/part
directives (including engine CLI entry points) must exclude Studio; the inspected
closures contain 481 engine and 79 shared UI Dart files.

Any continuity failure prevents recovery execution. The 903 engine and 294 UI
cases are reported as retained accepted evidence, separately from fresh recovery
cases. None of the failed original Studio gate's cases are carried forward. A
combined accepted count is produced only after the new selected gates pass with
unchanged inputs. The exact original runner is archived without modification in
[runner_versions](runner_versions/index.json).

## Scope and evidence

Gates run sequentially. Each test runner uses concurrency 2 and JSON reporting;
Flutter uses `--no-pub`. No automatic rerun, CI polling, golden update, source
edit, SDK patch or Git mutation is performed. The incoming engine gate reruns
the impacted VBA/directional scope after the late selector changes. The earlier
802-case checkpoint is historical and is never added to fresh totals. Exact
ruler/test/model/helper hashes are checked separately; the ruler test is rerun
only if one of those inputs changed.

Each run creates a new directory without replacing earlier attempts. It captures
all local package and third-party source/test/fixture/asset/example/CLI files
(excluding screenshots), root manifests and SDK pin, and generated package
configuration/graph. Full compressed manifests are captured before execution and
after each gate. A changed input stops subsequent gates and prevents acceptance.
All initial inputs must match the supplied source commit for final acceptance.

Raw JSON reporters and stderr are compressed with raw/gzip checksums. Result files
retain commands, times, source commit, all test lifecycles, excluded loaders/hooks,
unique case identities, per-file counts, skips, errors and incomplete cases.
Interrupted or failed attempts remain explicit. The final summary separates
fresh cases from retained historical evidence and records exact source stability.
No prior evidence archives are copied into this run.

This local regression scope does not establish live-provider, installed-platform,
full Office visual-golden, or complete desktop-mail parity acceptance.
