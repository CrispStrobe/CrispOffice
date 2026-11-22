# Final local qualification plan

The first frozen run completed against
`d53f30f1874b38d36a791d1d3881583e4e42a2d6`. Its incoming engine gate passed 903
cases and shared Mail UI passed 294. Studio completed 2,221 cases with 2,203
passing and 18 failing; that run is **not accepted**. All captured inputs stayed
unchanged. The complete failure record, raw logs, source manifests and checksums
remain intact in [qualified-source](qualified-source/summary.json).

Focused development checks then passed the corrected cache/lifecycle fixtures
(79), provider navigation (64), and router/presets (15). These development counts
are not added to final qualification totals.

## Late main intake and revised scope

Remote main advanced to `4cc604810fb2f41ac7ba04cbed65cb76300bff59` through PR #382.
Its new code includes bounded VBA `Split` authoring, Zotero converter field and
revision preservation, ODT outline/shading guards, and atomic selected-account
refresh during Mail reconnect. The branch was merged normally as
`b843c81b15158ed0f4010b589f8ecdefd1a642fb`, preserving the local Mail recovery
fixes. The exact proposal, merge bases and source-driven rationale are recorded
in [main-382-intake.json](main-382-intake.json).

The prepared final scope runs **238 fresh behavioral suites**:

| Gate | Suites | Why it is included |
| --- | ---: | --- |
| Incoming engine | 92 | 66 affected Zotero/ODT/field/revision suites, 25 VBA array/string/Split/Word suites, and directional paragraph IO |
| Incoming editor | 30 | 29 affected Zotero/ODT controller suites and the directional ruler suite |
| Incoming Mail store | 2 | Existing local-account transactions and new expected-record atomic refresh |
| Studio Zotero | 4 | ODT open/export, transport and shortcut integration |
| Studio Mail | 110 | Complete selected Mail host, navigation, reader, compose, journal, outbox, cache and sign-in regressions |

Strict analysis and pinned formatting currently cover **109 live Dart paths**
changed since initial main `4621326a5a452da475f219353c298d0f9b12470e`. The full
source manifest currently contains **6,151 inputs**. Both counts and all suite
paths are recalculated and frozen at execution time. `--plan` executes no Dart
or Flutter gate.

The earlier 903 engine cases cannot be retained after these engine source
changes. `wml_properties.dart` also changed, so the earlier 10 ruler cases are
historical; that suite appears exactly once in the fresh editor gate. The earlier
802-case incoming checkpoint and the imported PR #382 evidence remain historical
and are never added to this run's fresh totals.

## Run only after the corrected source is frozen

Source the prepared runtime environment, then invoke:

```sh
python3 docs/validation/mail-connected-navigation-20261122/final/qualify_mail.py \
  --run --expected-head FROZEN_FULL_COMMIT_SHA --run-id merged-source-recovery \
  --gates analysis format incoming_engine incoming_editor incoming_store \
    studio_zotero studio_mail --retain-from qualified-source
```

The supplied exact commit must match current HEAD. The runner verifies the
repository-pinned Flutter version and explicitly sets `BOT=true`, `CI=true` and
analytics suppression before any Dart/Flutter command. Those supported settings
prevent Flutter's Azure metadata bot-detection fallback; SDK code and network
controls remain unchanged. Native store checks use the normal pinned `dart test`
runner from the Mail store package, and widget checks run from their own package
directories with `flutter test --no-pub`.

## Retain only independent shared Mail UI evidence

The 18 shared Mail UI suites previously passed **294 unique cases**. Before any
new gate, the runner verifies every original evidence checksum and the archived
original runner hash, then proves that this gate's exact inputs remain unchanged.
It compares every captured file in the repository-owned declared/actual package
closure, every actual local imported Dart file, root manifests/configuration,
generated package graph/configuration, runtime identity and selected test paths.

The current proof covers **393 package/root inputs** and **79 actual local Dart
imports**, across Mail core, MIME, shared UI and its example, and the vendored
`enough_mail` package. That dependency/import closure excludes Office engine,
Mail store and Studio. A read-only preflight passed; the proof is recalculated
against the final frozen source before execution. It does not rely on the now
invalid assumption that every package outside Studio stayed unchanged.

Any continuity failure prevents new qualification execution. Only the 294 shared
UI cases are retained; no original engine, ruler or failed Studio cases are
carried forward. Fresh and retained counts stay separate, and a combined accepted
count is produced only after every new selected gate passes with stable inputs.
The exact original runner remains archived in
[runner_versions](runner_versions/index.json).

## Evidence and limits

Gates run sequentially with test concurrency 2 and JSON reporting. No automatic
rerun, CI polling, golden update, source edit, SDK patch or Git mutation is
performed. Each run creates a new directory without replacing earlier attempts.
It captures all local package and third-party source/test/fixture/asset/example/
CLI files excluding screenshots, root manifests and SDK pin, and generated
package resolution. Full compressed manifests are captured before execution and
after every gate. Changed inputs stop later gates and prevent acceptance; all
initial inputs must match the supplied source commit.

Raw JSON reporters and stderr are compressed with raw/gzip checksums. Results
retain commands, times, source commit, test lifecycles, excluded loaders/hooks,
unique case identities, per-file counts, skips, errors and incomplete cases.
Interrupted and failed attempts remain explicit.

Acceptance covers the pinned Dart VM and Flutter widget scope. It does not
establish new JavaScript/browser `Split` behavior, live-provider operation,
installed-platform behavior, full Office visual goldens, installed converter
sessions, or complete desktop-mail parity.
