# Local runtime and reproduction — Notes review continuation

The resumed **77-suite local gate passed** on source `a7512e94da8208123aa2df5f5c2c0354d079ddc7`: **1,244 Dart/Flutter cases, no failures or skips**, plus strict analysis, formatting and whitespace checks. See the [final resumed record](../resumed/README.md) and [exact receipt](../resumed/verification.json). The earlier disk-exhaustion observations below are retained as history.

## Earlier disk-exhaustion attempt (historical)

Before the host filesystem filled, the continuation restored and verified
Flutter **3.47.8** / Dart **3.13.7**, resolved the new Mail-inclusive workspace
with its exact dependency lock, and ran the existing editor
`office_units_test.dart` smoke suite. Both actual cases passed, with no
failures or skips. This establishes runtime readiness only; it is **not
acceptance of the new Notes/header/footer work**.

| Verified item | Value |
| --- | --- |
| Official SDK archive bytes | 1,581,444,364 |
| Official archive SHA-256 | `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2` |
| Flutter framework revision | `737ba8f885dc774b53b442759999a312c9461e4e` |
| Dart executable SHA-256 | `01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb` |
| Flutter tester SHA-256 | `800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f` |
| Workspace lock SHA-256 | `35d1ef372908f4ab278973355ec6a957cd3240bea115d615056c5b9e398df974` |
| Hash-verified hosted package archives | 176 |
| Resolved workspace packages | 130 |
| Flutter tool offline enforced resolution | Passed |
| Workspace offline enforced resolution | Passed |
| Actual smoke cases | 2 passed; 0 failed; 0 skipped |

The complete official SDK stream was hashed before any extracted executable
was invoked. Two earlier restoration attempts stopped at a disk-space guard;
neither ran an unverified executable.

The completed local runtime receipt had SHA-256
`b9bcda607be6822efb1af9d3be5c812dd3128f96d5ab85efd63b43d701722e62`.
A later local retained-input manifest covered **11,141** SDK/dependency files.
A 1,215,037-byte compressed evidence directory was successfully written before
the filesystem block.

## What this remote recovery package contains

- [Recovery summary](recovery-summary.json): observed runtime identities,
  command outcomes, case counts, and an explicit inventory of the exact local
  evidence bytes that could not be uploaded.
- [Recovery restorer](restore_runtime.py): a new portable implementation of the
  verified restoration approach, reconstructed after the disk block.
- [Gate runner](../run_checks.py): the complete authored runner source recovered
  from its recorded edit operation. It accepts an explicit committed test plan
  and binds source/runtime identities before and after sequential checks.

The recovery restorer is **not** the byte-identical collection of scripts
executed locally. Its VM-only path was subsequently executed in this
continuation. A separate verified SDK stream supplied the Node compiler (`compiler-supplement.json`);
the original extraction receipt remains distinct. The combined `--node-tests`
and native-smoke restore path below is new reproduction code, not a claim about
that original run. The gate runner had been written
locally but its syntax/self-tests and product gates had not run when disk
exhaustion blocked every filesystem tool launch. Its local file could not be
re-read for an independent byte comparison.

The original compressed logs, complete runtime receipt, Pub receipts,
retained-input and omission manifests, and machine-specific environment file
were copied locally but could not be read for publication. They are not
silently replaced by this summary. The GitHub recovery manifest identifies the
files that were actually uploaded.

## Restore on a machine with sufficient disk space

Use Python 3.12 or newer with PyYAML, access to the official SDK and Pub archive
hosts and the SQLite GitHub release asset host, an installed Node on `PATH`
for Node tests, and at least **2 GiB of free disk space** beyond the checkout.
Keep the runtime directory outside the repository.

Check out the source checkpoint to be tested. Its root `pubspec.lock` must
match the exact SHA-256 above. The recovery restorer refuses a different lock
and refuses a nonempty runtime destination.

```bash
python3 docs/validation/document-review-notes-20261118/runtime/restore_runtime.py \
  --repo /absolute/path/to/quds_office_suite \
  --runtime-root /absolute/path/to/toolchains --node-tests

source /absolute/path/to/toolchains/env.sh
```

The restorer streams the complete official archive, validates its full hash and
the Dart/Flutter tester hashes, verifies 176 package archives against the two
locked dependency sets, and runs offline lock enforcement for Flutter tools and
the workspace. It regenerates package configuration, wrappers, a runtime
receipt, and retained-input/omission manifests for the new location. It runs the
exact `native_asset_smoke.dart` bytes through a temporary entrypoint under
`packages/quds_mail_store/.dart_tool/`, invokes `dart run` from that member,
and removes only the temporary probe directory afterward. Dart discovers hooks
from the entrypoint's owning package: running the original root-level docs file
skips SQLite's hook because the workspace root declares no dependencies, even
when the working directory is the Mail member. No tracked manifest is changed.
The genuine hook prepares the workspace's native mapping, and the probe
verifies an in-memory SQLite/FTS5 round trip. The receipt records both probe
hashes and binds that
mapping, each absolute library, the original cached hook library used by child
`dart run` fixtures, and (with `--node-tests`) Node's resolved path,
version and hash. SQLite must match the pinned Linux x64 hook asset SHA-256.

`bind_test_inputs(repo, root, receipt, node_tests=True)` can also be imported
and called after that smoke against an existing runtime; save the updated
receipt separately from historical receipts. It neither downloads an
SDK nor reruns hooks, and leaves original restore commands/archive data intact.

The selected SDK contains **530,414,490 bytes**. It supports VM Flutter tests
and AOT analysis. `--node-tests` retains another **20,827,888 bytes** for the
verified Dart-to-JavaScript compiler. It omits Flutter Git history, the Flutter
web SDK and other web compilers, DevTools,
sanitizer runtimes, the duplicate JIT analyzer, the DDS AOT snapshot, and the
native GTK build library. The genuine Flutter version cache supplies the
framework identity; no fabricated Git metadata is needed.

The package cache omits author tests, examples, documentation, benchmarks, and
Drift's IDE extension: 312 directories and 197,605,450 bytes of file content in
the observed restoration. Runtime libraries, native hooks, executables, and
package-root notices remain unchanged from hash-verified archives. The
restorer records per-file omissions and verifies the observed selection totals.
This is not a full native/web application build environment.

## Run the selected final cohort

The committed [test-plan.json](../test-plan.json) selects **77 suites**: 9 engine,
49 editor, 9 Studio, 1 Mail core, 7 Mail native store, 1 Mail Node, and 1 Mail UI.
It also requests strict analysis and formatting checks for the integrated
changed Dart files. The first resumed combined run completed with 1,243 passing
cases, one failing off-screen-tap fixture, and no skips. Analysis and formatting
passed. The fixture and exact preserved-evidence whitespace handling were
corrected before the passing frozen-source run. See the [resumed validation record](../resumed/README.md)
for its exact source identity and preserved raw evidence; the historical two-case
smoke result above is not feature acceptance.

Verify the recovered runner's syntax and reporter parsing before using it as
acceptance evidence. Format the source and commit any formatting
changes before recording the full source commit.

The entrypoint placement and cleanup controls run without Dart or network:

```bash
python3 docs/validation/document-review-notes-20261118/runtime/test_restore_runtime.py
```

Commit the final source, runner, and committed plan; keep the tracked worktree and
index clean. Run one Dart/Flutter verification process at a time:

```bash
python3 docs/validation/document-review-notes-20261118/run_checks.py \
  --head FULL_SOURCE_COMMIT \
  --base 690e6ac8a1f7d8f5c8d4bea69d989a6728f3b27e \
  --plan docs/validation/document-review-notes-20261118/test-plan.json \
  --runtime /absolute/path/to/toolchains \
  --output /absolute/path/to/empty-check-output
```

Each test group runs sequentially at concurrency one. The runner records
commands, exit status, logs, completed user cases by full suite path, source
manifests, and runtime/dependency manifests. Hidden/loading/setup/teardown
events do not inflate the case count. Failures, skips, reporter errors, protocol
anomalies, missing/empty suites, unfinished events, and source/runtime changes
prevent acceptance. Optional `analysis` and `format` values may be exact
repository-relative file lists or `"changed"`. A whitespace check always runs.

Sparse historical fixture/evidence files are recorded as omitted with their
Git blob identities. Materialized source files receive SHA-256 identities.
Executable Dart and YAML/lock configuration files cannot be omitted. A sparse
Git identity is never presented as a hash of a file read from disk.

No GitHub Actions status was queried or awaited during this setup, and neither
the restorer nor the gate runner contacts GitHub Actions.
