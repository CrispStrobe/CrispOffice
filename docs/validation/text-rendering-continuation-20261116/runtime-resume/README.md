# Local runtime restored for the interrupted continuation

The workspace resolves offline with the original enforced lockfile and **108
packages**. The actual runtime reports Flutter **3.47.8**, framework commit
`737ba8f885dc774b53b442759999a312c9461e4e`, engine
`cf636b1dfb818dd6a3ff16e390e93b1a036969c8`, and Dart **3.13.7**.
The source checkout is detached at the official tag, so its reported channel is
`[user-branch]`. Tracked Flutter source files are unchanged.

This directory qualifies runtime preparation. Engine/editor test results belong
to their separate source-bound receipts and are not counted here. No GitHub
Actions jobs, checks or statuses were accessed for this restoration.

## What was installed and verified

- An authentic, shallow, sparse checkout of the official Flutter tag. Its `bin`
  and `packages` source is retained; framework tests/examples and unrelated
  platform source were omitted.
- **529 unmodified Dart SDK members** from the official engine's Linux x64 ZIP.
  The complete SDK libraries and the native VM, command runner, analysis,
  compilation and test snapshots are retained. DevTools UI, web compilers,
  sanitizer runtimes and the redundant JIT analysis snapshot were omitted.
  Every selected member passed its ZIP size and CRC check; per-file SHA-256
  values are recorded in `receipts/dart-selected-install.json`.
- All five original Flutter SDK engine archives: `sky_engine.zip`,
  `flutter_gpu.zip`, both patched SDK archives, and Linux x64 `artifacts.zip`.
  The native test engine executable matches the earlier whole-SDK qualification.
- The official `engine_stamp.json`, downloaded from the pinned engine URL and
  preserved verbatim. Flutter generated its framework version JSON from real
  source and engine metadata. The artifact cache marker was written after the
  corresponding official engine artifacts had been installed.
- **162 exact hosted package archives** for the Flutter tool and Office
  workspace. Their SHA-256 values match the previously qualified pinned
  package closure. Offline tool resolution and workspace resolution succeeded.

The two executable identities also match the earlier SHA-verified full SDK:

| Executable | SHA-256 |
| --- | --- |
| Dart | `01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb` |
| Flutter tester | `800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f` |

The entire 1.58 GB Flutter archive was not downloaded or rehashed in this run.
Its earlier qualification remains attributed to the earlier receipt. The
selected installation has the narrower verification described above.

## Project inputs and commands

The exact bytes of
`docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock`
were copied to the untracked workspace lock before resolution. Its final digest
remains `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
A preliminary text transfer had added one trailing LF; the byte-for-byte copy
corrected that preparation error before the successful workspace resolution.

The final workspace command was:

```sh
source /workspace/scratch/0caf1983021b/toolchain/env.sh
dart pub --suppress-analytics --directory quds_office_suite get --offline --enforce-lockfile
```

It exited zero and generated the actual 108-package configuration. The Dart
source smoke check and the Flutter `--version --machine` retry also exited zero.
`runtime-ready.json` binds these outcomes to the exact logs and installed files.

The task-local `flutter` launcher invokes the real Dart executable and the
unchanged official `packages/flutter_tools/bin/flutter_tools.dart`, with the
tool's actual offline package configuration. `dart` points to the real SDK
executable through a shell shim that uses its exact SDK path. No SDK binary
changed. No production package or bundled font was added by this setup.

## Reproduction and retained failures

The existing repository helper
`docs/validation/proofing-20261116/integration-followup/flutter-setup/bootstrap_flutter.py`
can reproduce the full pinned official SDK when bandwidth permits. This run
used the smaller selected-artifact route because the full download was slow.
The supplemental scripts here preserve selected ZIP extraction with ordinary
HTTP ranges, resumable pinned Pub archive downloads, common engine installation,
and the initial finalization attempt. Their paths expect copies under a fresh
`toolchain/setup` directory. The original SDK package pin receipt is included.
The Dart ZIP's central directory is obtained from the last 262,144 bytes of
the exact URL in the extraction script; an existing partial ZIP is optional.
The Linux engine archive URL, full archive SHA-256, and executable SHA-256 are
in its receipt. All retrieval used the configured ordinary network route.

Actual failed preparation attempts are retained:

1. The first direct-source Flutter version invocation timed out at 300 seconds
   with an empty log. The official engine metadata was installed during
   recovery; a bounded verbose retry then succeeded. Flutter's source uses a
   Git fallback when this metadata is absent; the first process's live stack
   was not captured, so that fallback is a suspected cause.
2. Direct workspace Pub initially failed before Flutter had generated its
   version metadata. After the successful Flutter startup, the same offline,
   enforced-lockfile resolution succeeded with the unchanged lock.
3. An optional app-jit tool snapshot build timed out at 180 seconds. It produced
   no completed snapshot. The working source launcher is retained, and the
   timed-out optimization is not reported as successful.

A bounded `dart test --help` probe timed out while the engine cohort was
performing its first cold compilation. Later probes through the exact SDK
executable, direct VM, and a shell shim all returned full help with exit zero.
The original engine cohort also completed successfully. These sequential
timings do **not** establish a symlink defect. The shell shim is retained as
an explicit-path launcher; `receipts/dart-launcher-checks.json` records the
comparison and unchanged native binary digest. The successful cohort is
qualified separately; no additional test suite was run for this comparison.

Download retries also encountered incomplete HTTP bodies. Resumable downloads,
ZIP checks, and pinned archive SHA-256 checks completed the installation; the
final success receipt is separate from the failed setup receipt.
