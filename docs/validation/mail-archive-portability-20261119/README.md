# Local mail archive portability qualification — 19 November 2026

## Qualification status

**Passed: 1,750 tests, zero failed, zero skipped**, across **95 selected test
files and 10 cohorts**. All **20 required gates** passed. The accepted source is
[`9bdef4895922ae74f6275e421af5665552d18b4e`](https://github.com/CrispStrobe/quds_office_suite/commit/9bdef4895922ae74f6275e421af5665552d18b4e),
tree `b537d9f6f2c15657b0fc0b70ae825e347be681cd`.

| Fresh cohort | Passed |
| --- | ---: |
| Mail core — VM | 54 |
| Mail MIME — VM | 84 |
| Mail store — VM | 462 |
| Mail store — Node | 3 |
| Mail transport — VM | 373 |
| Mail transport — Node | 6 |
| Language-ID synthetic | 22 |
| Engine macros, VBA and operations | 341 |
| Shared mail UI | 33 |
| Studio mail | 372 |
| **Total** | **1,750** |

Strict analysis of **216 Dart targets**, formatting of **26 changed Dart
files**, the C++ language-ID fixture build, shell syntax validation, and all
three macro/VBA JavaScript compile-and-run pairs also passed. Command gates
are separate from the test count. The run used the unchanged packaged SQLite
native asset and performed no dependency resolution or manifest override.
GitHub Actions were not queried or awaited.

The before/after fingerprints match for **4,418 source inputs**, **9,298
dependency inputs**, and **608 runtime/native files**. Git HEAD, tree,
root production manifest and lockfile remained unchanged, and the checkout
was clean at both boundaries. The independent audit matched every raw log,
case list, planned file and gate; it found no non-JSON reporter lines.

- [Acceptance receipt](receipt.json)
- [Complete final run](final/receipt.json) and [compact receipt](final/compact-receipt.json)
- [Independent audit](independent-audit.json)
- [Publication identity check](publication-check.json)
- [Frozen remote frontier](remote-frontier.json) and [reconciliation](reconciliation-refresh.json)
- [Layout screenshots and provenance](screenshots/README.md)

The first frozen attempt stopped at strict analysis on one export-directive
ordering lint, before any test cohort ran. Its [failed receipt and raw logs](attempts/01-analysis/receipt.json)
are retained separately. The fix only reordered public exports; the complete
second run above supplies every accepted test count. Development runs and
historical receipts are not pooled into this result.

The executable contract is [run-local-validation.py](run-local-validation.py).
Missing, failed, interrupted, skipped or incomplete evidence never counts as
acceptance. The following publication adds documentation and evidence only;
implementation, test, dependency and executed-harness identities are preserved
by the publication check.

The workflows, resource limits and remaining MailStore gaps are in
[the archive guide](../../roadmaps/mail/archive-search.md). The preceding
[mail archive/search acceptance](../mail-archive-search-20261119/README.md)
and merged [VBA procedures acceptance](../office-vba-procedures-20261119/README.md)
remain separate historical evidence. Their previous totals do not qualify
this combined source tree.

## Incoming work and preservation

The task started from remote main
[`81ae98688860599f118748afca19bdb2ec45da37`](https://github.com/CrispStrobe/quds_office_suite/commit/81ae98688860599f118748afca19bdb2ec45da37),
the merge of [PR #203](https://github.com/CrispStrobe/quds_office_suite/pull/203).
Before new mail implementation, the initial reconciliation captured **228
advertised references**: **202 ancestors**, **23 historical equivalents** and
**3 incoming aliases**. The inventory covers fork branches, PR heads and upstream
branches. These are reference counts, not counts of unique new commits. The
captured `initial-reconciliation.json` records the individual references and
historical proofs for retention with the final evidence.

The incoming tip
[`f0ce86842452ee7397afcf21b93c73e126d7d07e`](https://github.com/CrispStrobe/quds_office_suite/commit/f0ce86842452ee7397afcf21b93c73e126d7d07e)
was integrated before mail changes. At that time it reconciled the language-ID
smoke-test correction at `ff71fa44c693ee2a30fb0372eac206af257c8477`; the later VBA
procedure implementation was still being developed independently.

A subsequent refresh found remote main advanced to
[`304d4bff45da24f22cee420ec464882d7c7ce516`](https://github.com/CrispStrobe/quds_office_suite/commit/304d4bff45da24f22cee420ec464882d7c7ce516),
merging [PR #204](https://github.com/CrispStrobe/quds_office_suite/pull/204) at
head `3db248be978b24d0693d1133505d9be200fd1256`. That completed implementation
adds reusable VBA procedures, scalar functions and early exits. It was merged
into this mail branch before final qualification; the fresh gate includes all
three new procedure suites and its additional JavaScript compile/execution
check.

The final pre-qualification refresh also integrated
[PR #206](https://github.com/CrispStrobe/quds_office_suite/pull/206) at head
`4c460621dda0fbff20f819adbf54c20e617f458d`. Its source change at
`d5abf0e09d9fef6a29821f412f791c1284d62be8` adds a macOS build/staging script,
a manual installed-bundle native gate and example documentation. The PR head
is an integration commit and adds no new GUI implementation. The Linux harness
checks shell syntax and formats/analyzes the manual gate; it does not execute
macOS packaging or native acceptance.

The frozen remote frontier, captured at **17:03:22 UTC**, contains **234
references**, reconciled as **211 ancestors** and **23 historical equivalents**.
`remote-frontier.json` preserves that cutoff for replay. The last incoming VBA
control-flow branch at `4df40458` was integration-only and changed no source
tree. The initial 228-reference inventory is retained as its earlier dated
frontier. Branch development after the frozen cutoff is outside this captured
set; remote main must still be checked again before the final merge.

Work is saved incrementally to
[`codex/mail-archive-portability-20261119`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/mail-archive-portability-20261119)
and tracked in [PR #205](https://github.com/CrispStrobe/quds_office_suite/pull/205).
The following checkpoints preserve integration, implementation and source freezes:

| Checkpoint | Commit |
| --- | --- |
| Initial incoming reconciliation | [`de8ab2e93cc5f2139e89ba72d117bf9b18ba4cae`](https://github.com/CrispStrobe/quds_office_suite/commit/de8ab2e93cc5f2139e89ba72d117bf9b18ba4cae) |
| Frozen export plans, resumable originals and bounded directory traversal | [`eb60e7da0a7bf4597c7e9b063f562de1bfb2f209`](https://github.com/CrispStrobe/quds_office_suite/commit/eb60e7da0a7bf4597c7e9b063f562de1bfb2f209) |
| Reconcile the completed VBA procedures merge | [`cbec3c775eefc1ebd8a0bcbe6ae7e84bc0f53158`](https://github.com/CrispStrobe/quds_office_suite/commit/cbec3c775eefc1ebd8a0bcbe6ae7e84bc0f53158) |
| Studio portability interface and core hardening | [`22601092c0c50a784a132c410984b0eeb18292f9`](https://github.com/CrispStrobe/quds_office_suite/commit/22601092c0c50a784a132c410984b0eeb18292f9) |
| Reconcile published macOS build integration | [`50fca8d3b6eda2fc1827960b0a74101f387e74f7`](https://github.com/CrispStrobe/quds_office_suite/commit/50fca8d3b6eda2fc1827960b0a74101f387e74f7) |
| Preserve the final integration-only frontier | [`cbeec827481e890340f4889014f1d507c00e08d1`](https://github.com/CrispStrobe/quds_office_suite/commit/cbeec827481e890340f4889014f1d507c00e08d1) |
| Freeze source, remote frontier and qualification harness | [`5611724b7b40cf0c86aa180f0d3f1316d5a77c9f`](https://github.com/CrispStrobe/quds_office_suite/commit/5611724b7b40cf0c86aa180f0d3f1316d5a77c9f) |
| Accepted source after export-order lint correction | [`9bdef4895922ae74f6275e421af5665552d18b4e`](https://github.com/CrispStrobe/quds_office_suite/commit/9bdef4895922ae74f6275e421af5665552d18b4e) |

Checkpoints do not replace qualification of the final combined source. The
acceptance receipt identifies its exact frozen commit and tree. Subsequent
evidence-only publication must preserve the tested implementation and test
inputs; remote-main consistency must be checked after the final merge.

## Implemented portability contract

The native archive's `planExport` selects every matching message using the
current query, structured filters and ordering, independently of the visible
page. One transaction freezes original IDs, byte sizes and provenance. It
preflights message/origin counts, original byte totals, persisted metadata
lengths and encoded manifest size before returning a bounded immutable plan.
The implementation is in
[archive_export_plan.dart](../../../packages/quds_mail_store/lib/src/archive_export_plan.dart)
and the bounded manifest types in
[archive_export_models.dart](../../../packages/quds_mail_store/lib/src/archive_export_models.dart).

Bulk export creates a dedicated directory containing exact `<SHA-256>.eml`
originals and a versioned `manifest.json`. The manifest stores its host/profile
binding and frozen selection, with an unsigned corruption-detection digest.
Original length and hash are checked before publication. Explicit resume
revalidates the manifest and every existing original, reports mismatches without
replacement, and writes only missing originals from the same archive profile.
Progress counts `planned`, `written`, verified `existing`, and `failed` for each
run. It does not infer completion from a saved progress counter.

Export defaults are 10,000 originals, 1 GiB of raw originals, 32 MiB per original,
16 MiB of encoded manifest data and 20,000 provenance records. Plans are refused
when over budget; they are not silently shortened. The manifest is published
before EML files, and `.export-owner.sqlite3` provides cooperating-process
ownership. `.manifest.pending` and `.pending-*/original.eml` are staging data,
not completed output. The native regression suite includes a real subprocess
`SIGKILL` after the first original is published, owner-conflict detection before
the kill, and two subsequent resumes that check exact output bytes and counts.
This scenario passed in the accepted native suite.
See the [native exporter](../../../packages/quds_mail_store/lib/src/archive_export_native.dart)
and its [regression suite](../../../packages/quds_mail_store/test/archive_export_native_test.dart).

Native Studio also exposes directory import with optional recursive traversal,
explicit `mboxrd`/`mboxo` selection and the existing opt-in attachment-text
indexing policy. Relative folders become provenance beneath the chosen base
folder; source-message IDs hash the full relative path plus a record ordinal.
The walker rejects links and non-regular files, bounds traversal and metadata,
and closes directory iterators on cancellation. The reader rechecks ancestors
and observed file sizes and bounds MBOX reads to the admitted size. Source
files are unchanged, and every imported original commits separately.
The [directory walker](../../../packages/quds_mail_store/lib/src/archive_directory_native.dart)
and [Studio import coordinator](../../../packages/quds_office_editor/example/lib/studio_mail_archive_directory_import.dart)
keep traversal outcomes separate from committed-message counts.

Directory defaults are 10,000 files, 100,000 inspected entries, 100,000 processed
message outcomes, 32 nested directory levels, 4 GiB of admitted source-file
sizes and 32 MiB per message. Reports distinguish completed, partial, limited,
cancelled and failed work, along with saved, duplicate, failed, skipped,
traversal-error and indexing-warning counts. Reimport starts from the beginning
and deduplicates; it does not resume a durable collection cursor.

Generic recursive import of an export directory ingests its published EML
files, not its manifest provenance, profile or search definitions. A directory
whose basename begins `.pending-` is skipped when its parent has a regular,
non-link `manifest.json` marker, including when that staging directory is
selected directly. The marker is not read or parsed. Unrelated hidden/pending
directories remain eligible for normal traversal. This exclusion prevents
leftover export staging from being interpreted as a complete mail source.

The existing English, German and Arabic archive interface is retained and the
new controls use the same localization scheme. The increment does not implement
PST/MSG ingestion, provider-mailbox restore, binary PDF/Office attachment-text
extraction, a background scheduler, durable mailbox-collection cursors, retention,
legal hold, ACL administration, managed backup, or encryption/key management.
The export digest is unsigned and does not establish legal authenticity.

## Fresh qualification scope

The runner discovers and sorts test files at execution time; new mail and Studio
mail tests present at the freeze are included automatically. A changed test
outside the plan causes an explicit error unless it has a recorded exclusion.
`--plan-only` prints the precise selection without compiling or testing.

| Cohort or gate | Fresh coverage |
| --- | --- |
| Mail core, MIME, store and transport | All package test files; normal/native suites on the Dart VM and declared JavaScript suites on Node |
| Mail archive portability | Frozen-selection/filter/limit checks, exact bulk originals, manifest/profile validation, conflicts, ownership, cancellation, repeat resume, actual process termination and bounded directory traversal |
| Mail UI | All `quds_mail_ui/test` tests |
| Studio mail | All `studio_mail*_test.dart` and `studio_saved_mail_test.dart`, including the new directory-import and portability UI tests |
| Language-ID synthetic | Unit tests plus the native transport/lifecycle suite with the locally compiled C++ counter fixture |
| Engine macros and operations | All `office_macro_*` and `office_vba_*` suites plus explicit operation, step atomicity, structure, table-grid and macro-preservation regressions |
| New VBA procedure suites | `office_vba_procedure_boundaries_test.dart`, `office_vba_procedures_integration_test.dart`, and `office_vba_procedures_test.dart`, discovered by the same dynamic pattern |
| Portable JavaScript checks | Compile and run `web_smoke.dart`, `web_vba_smoke.dart`, and `web_vba_procedures_smoke.dart`; verify each exact JSON result |
| Incoming macOS build script | `bash -n packages/quds_office_editor/example/tool/build_macos_app.sh`; parse shell syntax without executing build, staging or signing commands |
| Formatting and analysis | Changed product/test Dart files since the baseline; strict analysis of all changed targets, every selected test, mail package libraries/tests/tools and Studio mail libraries |

The new procedures smoke verifies isolated `ByVal` call scopes, exits, preserved
caller values, recalculated formulas, recursion refusal, shared work/numeric
bounds, validation/rollback byte preservation and MCP helper execution. The
runner compiles it again on this checkout; the incoming PR's prior test count is
not reused.

### Explicit exclusions and limits

`packages/quds_language_id/test/language_id_native_test.dart` requires the real
CLD3 native classifier and verified model. The incoming change corrects its
expected result length to follow configured `topK`; it is formatted and analyzed
here, but not executed with a counter fixture masquerading as a classifier.
Synthetic FFI checks do not establish language-model accuracy.

`packages/quds_office_editor/example/test/studio_macos_bundle_native_gate.dart`
is a manual gate whose filename deliberately lacks the automatic `_test.dart`
suffix. It is included in formatting and strict analysis, with execution
explicitly excluded. Execution requires macOS, a built Studio app containing
all four native libraries and the verified CLD3 model, and installed AyaSpell
and CamelMorph proofing data. The `QUDS_STUDIO_APP`, `QUDS_STUDIO_DATA` and Harper
library inputs must point to those real artifacts. Its current source is
preserved, but Linux shell-syntax validation does not qualify dylib loading,
signatures, entitlements or installed native proofreading behavior.

The exact archived script
`docs/validation/office-vba-procedures-20261119/stress/procedure_depth.dart`
belongs to the previous reduced-workspace evidence. Its original bytes and
formatting are retained and included in the source hashes. It is explicitly
excluded from this run's formatting and analysis: importing the engine from
that historical document path has a different dependency context than the
current root workspace. Current package procedure suites and the public
procedures JavaScript smoke execute afresh. Other newly changed test files or
unclassified historical Dart scripts cannot silently fall out of the plan.

All acceptance is local Linux qualification. Provider tests use fakes or local
loopback services; no real account credentials or live mailbox acceptance is
used. Node checks do not constitute browser interaction or an installed web
application test. Windows/macOS/mobile packaging, real external language models,
power-loss behavior, hostile concurrent filesystem replacement, performance and
enterprise/compliance qualification remain outside this gate.

## Prepared runtime

The setup uses the official repository-pinned **Flutter 3.47.8 / Dart 3.13.7**
SDK archive, verified against SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
The prepared cache contains 194 exact hosted dependency archives verified
against their recorded hashes, and workspace resolution used
`dart pub get --offline --enforce-lockfile` before qualification.

The unmodified **sqlite3 3.9.1** default native hook supplies **SQLite 3.54.1**
with FTS5. Its Linux x64 library SHA-256 is
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.
The generated native mapping, installed library and cached hook download are
checked before execution and hashed during the run. The root production
`pubspec.yaml` and `pubspec.lock` remain unchanged. No temporary system-SQLite
manifest override is used in this increment.

The harness itself performs no dependency resolution, model download, source
edit or manifest edit. It verifies the setup/readiness receipts and fingerprints
workspace and Flutter-tool dependencies, Flutter SDK source packages, Dart and
engine runtime inputs, native assets, selected fixture libraries and package
configuration before and after execution.

## Reproduce the final gate

Commit the entire checkout, including this guide and harness, before starting.
Keep the checkout unchanged until the run ends; final evidence is written to a
new directory outside the repository so that it cannot alter the tested tree.
The following commands use the current prepared workspace paths:

```bash
source /workspace/scratch/b1a98f2b2c3b/runtime/env.sh

python3 docs/validation/mail-archive-portability-20261119/run-local-validation.py \
  --plan-only

git rev-parse HEAD
```

Copy that full frozen commit SHA into `FULL_40_CHARACTER_COMMIT_SHA` below, and
choose an output directory that does not already exist:

```bash
python3 docs/validation/mail-archive-portability-20261119/run-local-validation.py \
  --expect-head FULL_40_CHARACTER_COMMIT_SHA \
  --output /workspace/scratch/b1a98f2b2c3b/portability-reproduction-01 \
  --runtime-receipt /workspace/scratch/b1a98f2b2c3b/runtime/runtime.json \
  --readiness-receipt /workspace/scratch/b1a98f2b2c3b/runtime/readiness-receipt.json
```

`--base-ref` defaults to the initial `81ae9868...` milestone. A real run refuses
a mismatched/incomplete SHA, dirty or untracked checkout, uncommitted selected
inputs, existing/in-repository output directory, changed SDK/native identities,
or a lockfile inconsistent with setup. Each gate writes `command.json` before
execution with its exact argument vector, working directory, runtime paths,
fixture environment and timeout. The default stops at the first failure;
`--keep-going` can preserve additional independent failures but never turns a
failed run into acceptance. Neither mode retries a cohort automatically.

## Evidence and acceptance rules

The output includes `selected-plan.json`, the executed harness and runtime
receipts; per-gate commands, stdout/stderr and result records; compressed
per-test case records; source/dependency/runtime manifests before and after;
and complete/compact receipts. Raw JSON reporter logs are retained. If logs
are compressed for publication, their recorded raw hashes apply to the
decompressed bytes.

Test parsing resolves each suite path against its actual cohort working
directory. Acceptance requires a successful terminal event, process exit zero,
all planned files observed, no unexpected test files, and zero failed, skipped,
duplicate, hidden-failure or incomplete cases. Native fixture builds, formatting,
analysis, shell syntax and JavaScript command gates are reported separately from
test counts.
Every planned gate must run; input hashes, Git HEAD/tree, root manifest and
lockfile must remain unchanged, and the checkout must still be clean.

Final publication must supply the frozen source SHA/tree, actual test/gate
counts, retained raw evidence, an independent receipt/input review, and a fresh
remote reconciliation. Until that evidence is added, the status at the top of
this document remains pending.
