# Web persistence follow-up

This directory records the narrow qualification of captured main
`dbfbbd28caa064f4850dc81860a68de14d48fb35` (PR #229), preserved in combined
source `a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1`. The three VM files pass
**19 application cases** with all guards. The fresh Chrome attempt is
**environment-blocked before any application case**: Chromium cannot create
its Unix process-singleton socket. Its failed receipt and complete loader
diagnostic remain preserved. No fresh browser success is claimed.

The preceding core source remains
`214c4ed80bef0cb871f74e90c506d508679d3d6e`. The nine-path incoming delta and
author-attributed results are retained in the
[incoming review](../host-main-followup/web-persistence-review.json).

## Exact selection and guards

| Runner | Selected files | Expected application cases |
| --- | --- | ---: |
| Original runner through `run_web_vm.py` | `studio_hunspell_web_host_test.dart`, `studio_hunspell_web_cancellation_test.dart`, `studio_downloads_manager_test.dart` | 19 |
| `run_web_chrome.py` | Browser-only `studio_web_persistence_test.dart` | 3 |

The VM adapter imports the unchanged original runner, SHA-256
`4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf`, and supplies
only the three-file catalog. Original process, event, input, no-skips,
completion, unique-name and diagnostics guards are retained. Additional guards
require the exact published SHA throughout, unchanged adapter code, and exactly
19 application passes. Unexpected results are failures; counts are not adjusted
to fit expectations.

The Chrome adapter uses the original input fingerprinting and JSON event auditor.
It requires the unchanged captured three-case browser test (SHA-256
`5b95ad0aacbff2d1d639aae002c94e797322379a720bc43c292808629f41e990`), exactly its
three expected case names, one selected suite, all starts completed once, one
successful final event, and no skips, errors, loader failures or parser errors.
Both adapters use the original shared SDK validation lock. Neither passes a test
timeout override; the 1,800-second default is only a whole-process watchdog.

The Chrome command uses both `--reporter json` and the SDK's official
`--file-reporter json:<path>`. The latter supplies the unfiltered machine event
stream to the auditor; complete stdout and stderr are preserved separately so
compiler/launcher messages cannot be mistaken for invented or filtered test
events. No runner success is inferred from a zero process exit alone.

## Runtime and cache attribution

The local pinned Flutter 3.47.8 / Dart 3.13.7 source was inspected, without
executing the CLI. It supports `--platform chrome`, JSON and file reporters,
and concurrency selection. The Chrome backend is marked deprecated in that SDK;
the exact supporting SDK files and their hashes are recorded in
[runner-support.json](runner-support.json).

The SDK's headless launcher itself supplies `--no-sandbox`. The executable
[Chromium wrapper](chromium_wrapper.py) records original and executed arguments,
verifies the pinned real Chromium ELF before launch, preserves the SDK flags,
and directs the profile and disk cache into a fresh evidence output directory.
It bypasses the distribution shell launcher, which otherwise sources additional
configuration and may clean old user crash reports. It does not add another
browser flag or access an existing browsing profile.

[chromium-baseline.json](chromium-baseline.json) pins the binary, its installed
support files and every `ldd`-resolved shared-library file. Execution compares
that full inventory before launch and hashes it again afterwards. The standard
source/dependency/configuration/runtime inventory is extended with the Flutter
web SDK, Dart compiler/runtime libraries, Flutter tool implementation, cache
stamps, qualification scripts and wrapper. Any changes in these immutable input
areas reject acceptance.

Generated compilation caches, the fresh browser profile and actual Cache Storage
are expected to change during execution. Their complete regular-file manifests
and manifest hashes are retained before and after, separately from immutable
input equality guards. Those outputs are not silently excluded or falsely
required to stay empty. The browser tests use synthetic verified byte fixtures;
they qualify persistence behavior, not live downloads, native models, or
successful activation of a real morphology model.

## Reproduction on the published source

Use the existing prepared `FLUTTER_ROOT` and `PUB_CACHE`. The runtime agent's
no-resolution proof must bind the existing package configuration and graph to
the later source before execution. The adapter never runs `pub get`, an SDK
download, a source checkout or a cache cleanup. Both commands below refuse a
source that does not contain the exact captured PR #229 merge and refuse an
existing output directory.

```bash
python3 docs/validation/zotero-research-materials-20261120/continuation/web-persistence-followup/run_web_vm.py \
  --repo . \
  --expected-head FULL_PUBLISHED_SOURCE_SHA \
  --output /absolute/path/to/new-web-vm-evidence

python3 docs/validation/zotero-research-materials-20261120/continuation/web-persistence-followup/run_web_chrome.py \
  --repo . \
  --expected-head FULL_PUBLISHED_SOURCE_SHA \
  --output /absolute/path/to/new-web-chrome-evidence
```

The current Chromium pin is environment-specific. To prepare a different
compatible machine, explicitly regenerate the pin by inspecting its installed
binary and local SDK, retain the changed pin and its provenance, and review it
before qualification. `prepare_web_environment.py` only reads local files and
`ldd` output; it never launches Flutter or Chrome. A failed pin comparison must
not be suppressed in the runner.

## Source binding and reuse of the `214c4ed8` receipts

The earlier broad input inventories intentionally include tracked workspace
source beyond each selected test's executed imports. The five changed/new
implementation libraries and example manifest will therefore change their
broad hashes. Preserve those earlier receipts unchanged. Do not relabel their
source SHA, claim whole-inventory equality, or add their counts again.

Before asserting applicability to the later frozen source:

1. Record the exact source commit/tree and prove that its executable delta from
   `214c4ed8` is the reviewed PR #229 delta plus any separately documented source
   changes. List every changed input; separately account for documentation.
2. Retain the runtime agent's no-resolution proof. `web 1.1.2` was already
   reachable transitively; the new direct Studio edge leaves all 152 package
   closures unchanged. The existing package configuration, graph and lock are
   explicitly reused with their older edge/dependency classification. They are
   not described as freshly regenerated metadata. Bind their exact bytes,
   resolved roots, versions and external dependency inventories, and separately
   record the new manifest edge and the unchanged effective closure. Reject
   reuse if that complete closure/byte proof fails; do not suppress a real
   resolution or input difference to manufacture equality.
3. Prove all earlier selected test files, imported executable libraries,
   fixtures, assets and direct file-read dependencies remain exact, except for
   explicitly replaced cohorts/files. A selected-test byte comparison by itself
   is insufficient. Evaluate conditional imports for the platform actually run.
4. Engine Zotero, engine Word/layout/rendering and editor Zotero/Word/rendering
   cohorts can retain their results only after their dependency/input closure
   excludes the new Studio web paths and their relevant runtime/dependency
   bytes match. This is a conditional applicability proof, not a fresh rerun.
5. Treat Studio and Mail host imports carefully. The host factories choose
   native implementations under `dart.library.io`, while direct imports of
   `studio_hunspell_host_web.dart` still execute the changed web-host class on
   the VM. Its store then selects the no-op implementation because
   `dart.library.js_interop` is false. The two direct web-host VM files receive
   a fresh run. The downloads-manager file imports the Studio application and
   workspace and is also rerun. Prove the remaining earlier Studio/Mail selected
   closures and any file reads separately; do not declare all five libraries
   irrelevant merely because their names contain “web”.
6. Bind the new VM and Chrome receipts, static checks and dependency proof to
   the later published source in a separate final applicability report. Deduplicate
   repeated application identities when combining results; downloads-manager
   cases overlap the earlier Studio cohort. Keep successful execution counts,
   distinct case counts and source-attributed historical evidence separate.

If the closure proof identifies another affected selected test, rerun that exact
test with the original guards. A source-preservation argument must never stand
in for exercising a genuinely changed reachable implementation.

## Execution status

| Evidence | Outcome on the combined source |
| --- | --- |
| [VM receipt](accepted-web-vm/receipt.json) | 19 passing application cases in three files; every guard passes |
| [Chrome launch receipt](accepted-web-chrome/receipt.json) | Failed launch, zero application cases; SDK aborts during Chromium startup |

The Chrome error is `process_singleton_posix.cc:297 socket() failed: Operation
not permitted`. Recorded source, dependencies, runtime, web SDK, browser and
qualification-tool inputs remain unchanged; loader and completion acceptance
guards correctly reject the attempt. The `accepted-web-chrome` directory name
does not override its `failed` receipt. Reproduction requires an environment
that permits the browser's required IPC, using a reviewed pin for that host.

PR #229's three author-reported Chrome passes remain separately attributed in
the incoming review. They are not counted as fresh execution here. No GitHub
Actions, workflow-run, check-run or commit-status endpoints were queried.
