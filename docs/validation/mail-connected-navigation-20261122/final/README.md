# Final local qualification plan

The current plan follows PR #383 main
`b4f1150b18348f348489c93108158a397c922abe`, reconciled with the local Mail work.
It runs **236 fresh behavioral suites** and retains only **341 independent cases**
after exact source, dependency, runtime and evidence checks. The current planning
checkpoint is `893cca7a17b6bcda966f44248fa966084c5f1a74`; ongoing ownership fixes
must be frozen remotely before executing the next run.

## Evidence preserved from earlier source snapshots

The first frozen run, `d53f30f1874b38d36a791d1d3881583e4e42a2d6`, had 18 actual
Studio failures. Its original parser reported 2,203 passed and 18 failed Studio
cases; three additional passed Unicode-name cases were omitted by that parser.
The original run, raw output, summary and checksums remain unchanged in
[qualified-source](qualified-source/summary.json).

The expanded run against `9a371b616ae0fa0dbbecaed04708837125694d7c` completed every
command with exit code zero. Its original summary also rejected the same
Unicode-name decoding issue. An independent checksummed [reporter re-analysis](REPORTER_REANALYSIS.md) recovered all starts and completions: **6,893 fresh cases
across 238 suites**, plus **294 retained shared UI cases**, giving **7,187 accepted
cases on that exact source**. All 6,151 captured inputs and generated resolution
stayed unchanged. All 18 exact cases that failed in the first run passed in that
execution. No test was rerun to repair the evidence parser.

These records qualify their captured sources, not subsequent edits. Focused
development runs and imported upstream evidence are not added to final totals.

## Why the latest main requires fresh gates

The [PR #383 intake receipt](main-383-intake.json) records the actual package delta
from the qualified source. `word_zotero.dart` now excludes empty instruction-side
runs when selecting visible citation/bibliography result formatting, including
neighboring empty fields. Its fixture support and regression tests changed too.
Editor production sources are otherwise unchanged, but their engine dependency
changed. Mail hosts also receive the reconciled navigation work and pending
store-admission/Close ownership corrections.

| Fresh gate | Suites | Scope |
| --- | ---: | --- |
| Incoming engine | 92 | Affected Zotero/ODT/field/revision, VBA array/string/Split/Word, and directional paragraph regressions |
| Incoming editor | 30 | Zotero/ODT controller regressions and the directional ruler suite, once |
| Studio Zotero | 4 | ODT open/export, transport and shortcut integration |
| Studio Mail | 110 | Complete selected host, navigation, reader, compose, journal, outbox, cache and sign-in regressions |

Strict analysis and pinned formatting currently cover **111 live Dart paths**
changed since initial main `4621326a5a452da475f219353c298d0f9b12470e`. The manifest
currently contains **6,151 inputs**. Suite paths, changed Dart paths and input
counts are recalculated and frozen at execution time. `--plan` invokes no Dart
or Flutter gate.

## Command after the exact source freeze

Source the prepared runtime environment, then invoke:

```sh
python3 docs/validation/mail-connected-navigation-20261122/final/qualify_mail.py \
  --run --expected-head FROZEN_FULL_COMMIT_SHA --run-id reconciled-source-recovery \
  --gates analysis format incoming_engine incoming_editor studio_zotero studio_mail \
  --retain-gate shared_mail_ui=qualified-source \
  --retain-gate incoming_store=merged-source-recovery
```

The supplied exact commit must match current HEAD. The runner verifies the
repository-pinned Flutter version and sets `BOT=true`, `CI=true` and analytics
suppression before any runtime command. Those supported settings prevent
Flutter's Azure metadata bot-detection fallback; SDK code and network controls
remain unchanged. Normal pinned runners execute from their package directories.

## Retain only independent store and shared UI gates

| Retained gate | Original source | Suites/cases | Current exact comparison |
| --- | --- | ---: | --- |
| Shared Mail UI | `d53f30f1` | 18 / 294 | 393 package/root inputs and 79 actual local Dart imports |
| Mail store account transactions | `9a371b61` | 2 / 47 | 170 package/root inputs and 59 actual local Dart imports |

Each proof verifies original artifact checksums and the archived runner, decodes
its original raw reporter bytes with LF-only parsing, and checks all starts,
completions, skips, errors and duplicates. The store proof additionally verifies
the separate immutable `9a371b61` reporter re-analysis and its raw-output hashes.

Every captured file in each repository-owned declared/actual dependency package,
every actual imported Dart file, root manifests/configuration, generated package
graph/configuration, runtime identity and selected suite path must match exactly.
Store depends locally only on Mail store and Mail core; its closure excludes
Office engine and Studio. Shared UI depends locally on Mail core, MIME, shared UI
and its example, and vendored `enough_mail`. Read-only preflights passed, but both
proofs are recalculated against the final frozen source before any new command.

Any continuity failure prevents execution. The 341 retained cases remain separate
from fresh cases. No engine, editor, Studio or historical ruler counts are carried
forward. A combined accepted total is emitted only after all fresh selected gates
and their source-stability checks pass.

## Reporter correction and evidence policy

The runner now splits JSON Lines only on LF bytes, preserving valid Unicode
NEL/LINE SEPARATOR/PARAGRAPH SEPARATOR inside strings. Known native build-hook
progress preceding a reporter-start event is recorded explicitly. The decoder
requires a complete start/done protocol, exact suite selection and no missing,
orphaned or duplicate lifecycle records, failures, skips or unknown output.
The prior runners remain archived byte-for-byte in
[runner_versions](runner_versions/index.json).

Gates run sequentially with concurrency 2 and JSON reporting. No automatic rerun,
CI polling, golden update, source edit, SDK patch or Git mutation is performed.
Each run creates a new directory, preserving every earlier attempt. It captures
all local package and third-party source/test/fixture/asset/example/CLI inputs
excluding screenshots, root manifests and SDK pin, and generated resolution.
Compressed manifests are captured before execution and after every gate. Changed
inputs stop subsequent gates and prevent acceptance; initial inputs must match
the supplied source commit.

Raw JSON reporters and stderr retain raw/gzip hashes, exact commands and times.
Results distinguish unique cases from loaders/hooks and preserve per-file counts,
errors, skips, interruptions and incomplete cases. No large old evidence archive
is copied into a new run.

Acceptance covers the pinned Dart VM and Flutter widgets. It does not establish
new JavaScript/browser Split behavior, live-provider operation, installed-platform
behavior, full Office visual goldens, installed converter sessions, or complete
desktop-mail parity.
