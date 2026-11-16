# Final local proofing integration

This directory describes the final integration verifier. The verifier writes a
dated, source-bound receipt when it is run; this README alone is not a passing
test result. No GitHub Actions are started or waited for.

## Run after the source checkpoint

Resolve the workspace dependencies and prepare the chosen Flutter SDK first.
Commit all source changes, including the verifier, before running it. Documentation
and evidence edits do not block verification. The intentionally ignored root
`pubspec.lock` is copied into the output and hashed as an additional input.

From the repository root:

```sh
python3 tools/proofing/verify_integration.py \
  --flutter /absolute/path/to/flutter/bin/flutter \
  --dart /absolute/path/to/flutter/bin/cache/dart-sdk/bin/dart \
  --output docs/validation/proofing-20261116/final/run \
  --build-web \
  --harper-build /absolute/path/to/prepared/harper-build
```

`--flutter`, `--dart` and `--output` are required. `--node` defaults to Node on
`PATH`. `--build-web` and `--harper-build` are independent: the latter verifies an
existing native and web Harper distribution, and additionally installs its web
assets if a host web build was requested. Prepare that distribution using
`packages/quds_proofing_harper/tool/build.py --native --web --output PATH` with
the pinned Rust toolchain before running the integration verifier.

The default German check downloads the generator's pinned word list and checks
its identity before checking exact regeneration. Supply `--german-wordlist PATH`
to use an existing copy of that pinned input. No correction model is downloaded
or evaluated. The verifier preserves the caller's `TMPDIR`, `PUB_CACHE`,
`XDG_CONFIG_HOME`, Rust environment and other settings; it does not change `HOME`
or resolve dependencies. The caller should provide writable temporary and cache
directories for this workspace.

Use a new output directory for each attempt. Existing receipts are preserved,
including failed attempts. Each command has a 15 minute deadline; the verifier
stops on the first failure and records the result and the final source hashes.

## Checks and scope

| Gate | Coverage |
| --- | --- |
| Strict analysis | All existing `lib`, `test` and `tool` directories in the engine, editor and editor example, with `--fatal-infos`. |
| Canonical hyphenation child | The existing `validate_hyphenation.py` generator, analyzer and selected engine layout/serialization/PDF regression set. |
| German proofing child | The complete `test/proofing` set, strict analyzer, exact pinned dictionary regeneration, and compiled Dart JavaScript smoke checks executed in Node. |
| Incoming engine regressions | ODS sheet reading; Zotero backoff, source identity, regular client and identity client tests. |
| Combined editor regressions | Proofing session, UI, context source mapping, hyphenation paint and resumed branch cases, platform spelling, find/replace history, content control, protection, operation history, note numbering, selection paint, content revision and incoming Zotero backoff/dialog/source identity tests. |
| IME lifecycle | The existing canvas test for reattaching IME after another client takes it. |
| Optional Harper | The package's `tool/verify.py` against a prepared source-bound native and web build, including its native, Wasm, transport, lifecycle and license checks. |
| Optional web distribution | Release editor example build using `--no-pub --no-wasm-dry-run`, optional installation of the audited Harper worker assets and license archive, then a complete file hash manifest. |

The exact test files are listed in the verifier. Actual case counts come from
the command logs and receipt summaries; counts are not hard-coded acceptance
criteria. The selected tests cover the integration and newly imported changes,
not the entire repository test suite.

If the same frozen Harper distribution was just validated separately, supply
`--harper-receipt /absolute/path/to/receipt.json` with `--harper-build` to retain
that evidence instead of running its checks twice. The verifier requires a
passing receipt with identical current source and artifact hashes, checks every
referenced log's digest and successful exit code, and copies the receipt and logs
into this run. The final receipt identifies this as retained evidence, rather
than presenting its commands as newly executed.

## Evidence and source binding

`receipt.json` records the starting Git commit, completion commit, command
arguments and working directories, exit codes, durations and log SHA-256 values.
Every child receipt and log is independently checked. It also records actual
test totals found in the expanded runner output.

The compressed `source-sha256.before.json.gz` and
`source-sha256.after.json.gz` manifests cover the tracked workspace libraries,
tests, tools, fixtures, manifests, native/platform code, assets and license
inputs. New untracked source files are detected too. Documentation, historical
evidence and generated build/cache directories are excluded. The root lockfile
is included even though it is ignored by Git. Source inputs must be committed
at startup; their hashes must remain identical throughout the run. A later
documentation-only commit may change the completion commit without invalidating
the measured source.

The actual Dart, Flutter, Node and Python executables, Flutter tool snapshot,
available host test runtime and resolved workspace package configuration are
also hashed before and after. A changed runtime or source prevents a passing
receipt. Large generated binaries remain in their build directories; evidence
stores their identities instead of duplicating them.

## Harper host handoff

A host web build receives these runtime files under `build/web/proofing/`:

- `harper_worker.mjs`
- `quds_proofing_harper.js`
- `quds_proofing_harper_bg.wasm`

The same directory receives `build-receipt.json`,
`licenses/manifest.json` and the complete
`licenses/notices-and-mpl-sources.tar.gz`. The archive preserves upstream notices
and the exact MPL source distributions. The existing build receipt must bind the
current sources, runtime files and both license artifacts before packaging.
The completed web bundle manifest records every delivered file's SHA-256, and
the receipt separately lists the installed Harper assets.

The provider's default worker location is
`Uri.base.resolve('proofing/harper_worker.mjs')`, matching that installation for a
host served at its entry URL. Hosts that use path-based deep routes should supply
an explicit worker URL rooted at their deployed application location. Serve the
whole build directory over HTTP with suitable JavaScript/Wasm MIME types; do not
open the application as a local file.

For a native desktop host, the existing Harper build tool can install the audited
library and accompanying notices with `--install-native PATH`. A Linux editor
example can use an explicit absolute library path via
`--dart-define=QUDS_HARPER_LIBRARY=PATH`; a packaged Linux application can place
the library in its bundle's `lib` directory, covered by the host's `$ORIGIN/lib`
runtime search path. Native binaries are specific to their target and must be
built and audited for each supported target.

## Acceptance limits

Node execution of compiled Dart and the shipped Wasm worker exercises the local
runtime contract; it does not establish browser Worker/CSP/HTTP deployment
acceptance. The web artifact build establishes compilation and packaging only.
This verifier does not launch an interactive browser, exercise a mobile device,
or claim native coverage for targets other than the locally tested host.
