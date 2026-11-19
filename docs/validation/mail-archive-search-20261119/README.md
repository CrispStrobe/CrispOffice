# Local mail archive/search qualification — 2026-11-19

This directory defines the final local gate for the mail archive/search work and
the recent changes reconciled into the same branch. The baseline is
`e00ca1495551ffaf61dd9b3ee7770f8bfde7e897`. The product scope and remaining
MailStore gaps are documented in
[archive-search.md](../../roadmaps/mail/archive-search.md).

`run-local-validation.py` creates fresh evidence for one explicit, frozen HEAD.
It does not query or wait for GitHub Actions, change source, resolve packages,
download dependencies/models, retry a failing cohort, or import historical test
counts. A final `receipt.json` copied here is acceptance evidence only when its
status is `passed`, inputs are stable, and every planned cohort completed.
Absence of such a receipt is not a passing result.

## Incoming work and remote checkpoints

The task began from remote main
`e00ca1495551ffaf61dd9b3ee7770f8bfde7e897`. Before archive development, the
incoming recovery head `623057111a9179552eb02b21a753a1728de9905d` was merged and
the advertised branch/PR frontier was reconciled. The
[initial reconciliation](initial-reconciliation.json) accounts for **220 refs**:
197 ancestor refs and 23 historical-equivalent refs. Historical equivalence is
supported by complete changed-path mode/type/blob identity or complete tree
identity; it is not inferred from commit messages or patch titles.

A fresh remote check found PR 201 / `codex/mcp-aligned-macros` at
`3c1764f5ff8bf9f89e090ef4e04e3142c4ccf90a`. That work was merged before the final
freeze. The [refreshed reconciliation](reconciliation-refresh.json) accounts for
**223 advertised refs**: 200 ancestor refs and 23 historical-equivalent refs,
with no gaps in that captured frontier. Fourteen distinct historical proof
records also verify the common base, complete original delta and ancestry of
the equivalent commit. Ref counts include branch/PR aliases and are not counts
of unique new commits.

Work was saved incrementally to the remote
`codex/mail-archive-search-20261119` branch:

| Checkpoint | Commit |
| --- | --- |
| Initial incoming reconciliation | `d7584360c187fa20167c6330f5476042983f524c` |
| Archive implementation checkpoint | `3ba7acd4b8d121a44228a2b41fd970ea7a268813` |
| Archive runner, native crash tests and bounds hardening | `8ef489f67e22280df79b4f214af4785104f708a3` |
| Incoming macro/operations reconciliation | `9f87eff5e9c3ade6a13f5a816b7b42313e5a9f74` |
| Connected message/folder UI and final profile bounds | `232171ca828a1f62e69d6c033f60c706c8979970` |

These checkpoints preserve progress; they are not substitutes for testing the
final combined tree. The executing receipt supplies the later frozen commit,
its tree and fresh qualification results. No GitHub Actions queue was used as
an acceptance dependency.

## Selected scope

The runner records a deterministic, sorted file list before execution. New
archive or Studio mail test files present at the freeze are included. The
`--plan-only` command prints the exact selection without compiling or testing.

| Cohort | Coverage |
| --- | --- |
| Mail core, MIME, store and transport | All package test files; VM suites use the real Dart kernel compiler, and declared JavaScript-only files run on Node |
| Mail store native tests | Separate file-backed archives, exact raw bytes, owner contention, future schema refusal, independent cache namespace, real subprocess SIGKILL before/after commit, FTS corruption and transactional recovery |
| Mail UI | Full `quds_mail_ui/test` widget/controller selection |
| Studio mail | All `studio_mail*_test.dart` and `studio_saved_mail_test.dart`, including selected-message/folder actions, readers, native loader, archive host, import/export and maintenance |
| Studio language/proofing | Language-ID widget/host tests; fake-host Arabic/Hunspell setup, web-host cancellation and comment-draft proofing |
| Editor regressions | Existing proofing, language, Arabic and thesaurus test files selected by name |
| Engine regressions | Explicit language-ID, Arabic synthetic grammar/writing, proofing merge/range/language and thesaurus tests |
| Language-ID/Hunspell lifecycle | Checked-in counter-only C++ fixtures compiled locally; real Dart FFI ownership, failure and cancellation paths with synthetic native implementations |
| Arabic morphology unit tests | Portable models, configuration and mocked behavior; no external morphology model |
| Incoming Office macros | Macro/operation tests plus the incoming receipt's fidelity step, word structure, table grid and VBA preservation regressions |
| Portable macro smoke | Compile `packages/quds_office_engine/tool/macros/web_smoke.dart` to JavaScript, execute it on Node and verify recalculation, failed-transaction byte preservation and MCP inspection |

The final plan currently selects roughly 140 test files; the exact count and
per-cohort file list are captured in `selected-plan.json`, not inferred from an
older receipt. Cohorts run sequentially with per-runner concurrency one. Expect
approximately **6–12 minutes** on the prepared local runtime, depending on cache
warmth and host load; this is an estimate, not a performance qualification.

Deterministic synthetic widget captures were also inspected for layout and
readability. They are visual QA of fixture data, not live-account acceptance:
[archive desktop](screenshots/archive-desktop-en.png),
[Arabic mobile archive](screenshots/archive-mobile-ar.png), and
[selected-folder progress](screenshots/archive-folder-desktop-progress.png).

The incoming Office macro receipt's earlier 217 successes are historical. They
are not credited to this run. The same rule applies to development archive,
query, UI and inherited regression results. A failed development fixture that
attempted to violate SQLite's `length(raw)=raw_size` constraint remains a failed
attempt; the corrected corruption test explicitly enables and then restores
`ignore_check_constraints`. Neither development run is pooled into final totals.

## Explicit exclusions

- Real IMAP/SMTP/EWS/Gmail/Microsoft 365 accounts and credential-based service
  acceptance. Selected transport tests use fakes or local loopback HTTP/TLS
  servers. No external mail is sent or archived by the harness.
- Real language classifier, Arabic morphology analyzer/database, Hunspell native
  dictionary installation and live model/dictionary download tests. Counter
  fixtures demonstrate lifecycle behavior, not linguistic quality.
- Installed macOS/Windows/mobile apps, signing, native Keychain integration and
  real OAuth account callbacks.
- Browser interaction, full web application compilation and browser archival.
  Node executes declared JS transport boundaries and the portable macro smoke.
- Repository-wide tests, large-volume performance, remote point-in-time mailbox
  completeness, backup recovery qualification and compliance certification.

The script lists excluded files and reasons in the plan and final receipt. An
unexpected skip inside a selected cohort fails acceptance; it is not counted as
a pass.

## Runtime and dependency identity

The prepared runtime uses the complete, genuine **Flutter 3.47.8 / Dart 3.13.7**
SDK, with framework revision
`737ba8f885dc774b53b442759999a312c9461e4e`. The official archive is:

`https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz`

Its verified SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`
and size is 1,581,444,364 bytes. Setup verified 194 hosted Pub archives and
resolved the existing workspace offline. The root lockfile hash remained
`72a5a52654a1484f4df646c631b4d1ea47e96025a671beff045eecf2b9e78e82`,
including after the Studio direct dependency declarations were added. No
dependency version or checksum was changed for the archive feature.

The default sqlite3 native download was not retried after automatic approval
review rejected that route. Validation instead uses the package's documented
`hooks.user_defines.sqlite3` system-library option with the existing library:

- Path: `/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6`
- SQLite: `3.46.1`, with `ENABLE_FTS5`
- SHA-256: `14c4418a06c5c2e30f5fb57bc8add93762236ae17898c6708984cf15e680ca71`

This is a real SQLite library loaded by the unmodified sqlite3 dependency hook.
It is not a replacement parser, mock database, patched dependency, or fabricated
test runtime. It is also different from qualifying sqlite3's default downloaded
binary or every packaged platform library; those remain explicit limits of this
Linux validation.

A temporary **local-only** stanza is appended to the root `pubspec.yaml`:

```yaml
# Temporary local validation hook; restore production manifest before publication.
hooks:
  user_defines:
    sqlite3:
      source: system
      name: /lib/x86_64-linux-gnu/libsqlite3.so.0.8.6
```

The production root manifest is retained separately. The harness verifies that
it equals `HEAD:pubspec.yaml`, and that the tested manifest differs only by this
exact documented stanza. The hook must remain during native qualification and
must be removed before publication. It is not a shipped dependency or product
configuration change. The original production manifest hash is
`453a1f8ab62db1c5577c424b058b50033a8d3b49b99c83862ab58a7e1108f74f`;
the tested temporary manifest hash is recorded for each actual run.

Existing runtime recovery documentation is retained under
[mail-providers-20261119](../mail-providers-20261119/README.md). A fresh environment
must restore and verify the same SDK and locked dependency inputs before this
harness runs. The harness itself does not bootstrap or fetch them.

## Prepare and inspect the plan

From the repository root in the current workspace:

```bash
source /workspace/scratch/77e1c27b6c6f/toolchains/env.sh
python3 docs/validation/mail-archive-search-20261119/run-local-validation.py \
  --plan-only \
  --base-ref e00ca1495551ffaf61dd9b3ee7770f8bfde7e897
```

Before execution, finish source changes and commit the product/test files.
The gate requires the exact expected HEAD and rejects uncommitted or untracked
product/test files. The documented temporary root-manifest change is permitted.
Documentation and evidence are recorded separately from that production change.
No source or runtime edits should occur while the gate runs.

## Execute after the source freeze

Replace `FROZEN_COMMIT_SHA` with the reviewed full commit and choose a new output
directory for every attempt:

```bash
source /workspace/scratch/77e1c27b6c6f/toolchains/env.sh
python3 docs/validation/mail-archive-search-20261119/run-local-validation.py \
  --base-ref e00ca1495551ffaf61dd9b3ee7770f8bfde7e897 \
  --expect-head FROZEN_COMMIT_SHA \
  --output /workspace/scratch/77e1c27b6c6f/archive-final-validation-01 \
  --runtime-receipt /workspace/scratch/77e1c27b6c6f/toolchains/runtime.json \
  --production-manifest /workspace/scratch/77e1c27b6c6f/toolchains/pubspec.production.yaml \
  --sqlite-library /lib/x86_64-linux-gnu/libsqlite3.so.0.8.6
```

The script checks the pinned runtime executable identities, lockfile identity,
SQLite version/hash/FTS5 capability and manifest exception before testing. It
uses the SDK's real Dart executable and resolved `package:test` CLI with
`--platform=vm --compiler=kernel --concurrency=1 --reporter=json`; this avoids the
default compiler launch stall observed during development. JS-only suites use
`--platform=node --compiler=dart2js`. Flutter cohorts use
`flutter test --no-pub --concurrency=1 --reporter=json`.

The format gate uses `dart format --output=none --set-exit-if-changed` for every
added or modified Dart file since the baseline. Strict analysis covers those
files plus the full mail package and mail UI source/test/tool surfaces with
`--fatal-infos --fatal-warnings`. Neither gate edits files.

Each command has a timeout and separate stdout/stderr logs. A timeout or operator
interrupt terminates its process group and cannot produce a passing receipt.
The default stops after a failed required step, preserving its result and
listing unexecuted cohorts. `--keep-going` may collect independent failures
without retries; it never converts the final status to passed.

## Evidence and acceptance rules

Each attempt creates:

- `selected-plan.json`: exact cohorts, sorted files, changed-Dart gates and
  explicit exclusions.
- `source-before.json.gz` and `source-after.json.gz`: SHA-256/size manifests for
  committed and relevant untracked product source/resources, root build inputs
  and this plan's documentation/harness.
- `dependencies-before.json.gz` and `dependencies-after.json.gz`: resolved
  hosted package `lib`, `bin`, `hook` and manifest input hashes.
- `runtime-before.json.gz` and `runtime-after.json.gz`: actual Dart/Flutter/test
  executables, compiler/Node, native assets, SQLite, fixture binaries and
  resolution/manifest hashes.
- Per-step `command.json`, `result.json`, `stdout.log`, `stderr.log` and, for
  tests, compressed case-level JSON including failures and skips.
- `receipt.json` and `compact-receipt.json`: actual HEAD/tree, baseline, runtime
  provenance, source stability, exact exit status per step and fresh counts.

A selected test cohort passes only when the process exits zero, exactly one
successful terminal JSON event appears, at least one visible test passes, every
started test finishes, and there are no failures, error events, unexpected skips,
hidden loader failures or duplicate case identities. Hidden loader successes
are not added to test totals. Macro compilation/runtime checks are command gates
and do not inflate unit-test counts.

Final acceptance also requires stable source, dependency, runtime and lock
hashes and an unchanged HEAD throughout the run. Compressed manifests retain
the exact input inventory without copying SDKs, dependency caches or repository
archives into evidence. The receipt records the whole commit/tree separately
from its worktree hashes so the temporary manifest exception remains visible.

Review the fresh compact receipt and preserve it as this directory's
`receipt.json` only after its status and omissions are understood. Preserve
failed attempts independently. Do not merge counts from different source trees,
development runs, platform replays or historical receipts.

After successful native qualification, restore the production root manifest
using the guarded workspace helper:

```bash
python3 /workspace/scratch/77e1c27b6c6f/restore_mail_test_manifest.py
```

The helper refuses to overwrite an independently edited manifest. Verify that
the restored file matches the committed production manifest and that the
lockfile remains unchanged before publishing the final source/evidence commit.
The validation evidence explicitly identifies the temporary runtime hook; it
does not imply that the production tree shipped that local setting.
