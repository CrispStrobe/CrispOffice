# Frozen full-suite qualification: preserved original attempt

This directory records the complete local qualification of source commit
`e3212327954ac144847a7c06b5d2420f00debab3` (tree
`030e701c19f5a01b2e3ca54ddc67229871295527`), run on 2026-11-19 from
14:43:21 to 14:47:41 UTC. **The original attempt failed: 993 tests passed,
1 failed, and 0 were skipped.** Its raw evidence and failed receipt are retained.

The only failure was an incoming language-identification unit fixture that
implicitly assumed a three-candidate limit after the calibrated default had
changed to five. Every mail, Studio, proofing/thesaurus, Node boundary,
formatting, analysis, entitlement, and browser-compilation gate passed. The
one-line fixture correction and its separate qualification are recorded in the
[correction evidence](../correction/README.md); that follow-up replaces the
entire original synthetic-language cohort once, rather than adding its earlier
passes to the total.

## Test results on this exact source

Counts come from the raw JSON reporters in this directory. Hidden loader,
setup, and teardown events are excluded; error events, incomplete tests,
skips, and process failures fail acceptance. No development or historical test
results are included.

| Gate | Passed | Failed | Skipped | Evidence |
| --- | ---: | ---: | ---: | --- |
| Mail core, complete VM suite | 54 | 0 | 0 | [Cases](quds_mail_core-vm/test-cases.json) |
| Mail MIME, complete VM suite | 32 | 0 | 0 | [Cases](quds_mail_mime-vm/test-cases.json) |
| Mail storage, complete VM suite | 118 | 0 | 0 | [Cases](quds_mail_store-vm/test-cases.json) |
| Mail transport, complete VM suite | 373 | 0 | 0 | [Cases](quds_mail_transport-vm/test-cases.json) |
| Transport Node boundaries and EWS configuration | 13 | 0 | 0 | [Cases](transport-node-boundaries/test-cases.json) |
| Mail UI, complete widget suite | 33 | 0 | 0 | [Cases](mail-ui-widgets/test-cases.json) |
| Studio mail and saved mail, all 14 suites | 209 | 0 | 0 | [Cases](studio-mail-widgets/test-cases.json) |
| Language-ID unit and synthetic native transport | 21 | 1 | 0 | [Cases](language-id-synthetic/test-cases.json) |
| Engine language identification and calibration | 36 | 0 | 0 | [Cases](engine-language-id/test-cases.json) |
| Engine thesaurus | 25 | 0 | 0 | [Cases](engine-thesaurus/test-cases.json) |
| Editor proofing/session/thesaurus widgets | 75 | 0 | 0 | [Cases](editor-proofing-thesaurus-widgets/test-cases.json) |
| Studio language identification | 4 | 0 | 0 | [Cases](studio-language-id-widgets/test-cases.json) |
| **Original total** | **993** | **1** | **0** | [Receipt](receipt.json) |

The [selected Studio suite list](selected-suites.json) includes cloud accounts,
provider presets, credentials and ownership, Exchange EWS, discovery, message
loading, composition, reply, session/lifecycle/operation handling, browser
behavior, and saved mail.

The VM selector explicitly excludes four files that declare a JavaScript-only
platform; these are listed in [platform exclusions](platform-exclusions.json).
The three transport boundary files are exercised by the Node gate. The storage
`browser_problem_test.dart` is outside this VM/transport-Node matrix. These
explicit scope exclusions are not reported as skipped test executions.

## Non-test gates

All of the following commands exited successfully:

- Formatting checks for the cloud transport and probes, Studio mail and
  credentials, mail UI, and integrated proofing/thesaurus files.
- Strict analysis with fatal warnings and informational diagnostics for cloud
  transport, Studio, mail UI, integrated editor proofing/thesaurus, and engine
  thesaurus.
- Fresh compilation of the tracked synthetic language-ID C++ fixture with
  `-std=c++17 -shared -fPIC -O2 -pthread`.
- Parsing DebugProfile and Release macOS entitlements and verifying both
  network-client and network-server permissions (four assertions).
- Actual Flutter web frontend compilation, JavaScript generation, and
  `node --check` on the generated script.

The browser compiler emitted a dependency closure with 1,761 entries. It
selected the web Mail and saved-mail paths and excluded native Mail,
cloud/EWS native transports, the credential store, native message/file loaders,
and the checked `enough_mail` socket paths. See the
[closure assertions](mail-browser-import-closure.json),
[compiler dependency list](mail-web.dill.deps), and
[artifact fingerprints](web-artifacts.json). This is a compiler-boundary and
JavaScript-syntax check, not a browser runtime session.

## Diagnosed failure and correction boundary

The test `invalid probabilities, labels, order and candidate counts fail
closed` in `packages/quds_language_id/test/language_id_unit_test.dart` expected
four well-formed, descending-probability candidates to be rejected while
constructing the identifier with its default settings. Incoming commit
`ddcbb009a0ce7be932cec4de33de439f4e33b2d0` intentionally changed the default
`topK` from 3 to 5; merge `8b35ee35394a59b27881ecf75ace47ad61dff908`
preserved that calibrated default. Four candidates are valid under that
contract. The production guard remains `answer.length > topK`.

The follow-up sets `topK: 3` explicitly in that existing invalid-result fixture.
It preserves the malformed-result and overflow assertions, the production
five-candidate default, and the production limit check. The correction runner
requires that this test file be the only changed source/test input, verifies
unchanged runtime hashes, reruns the entire 22-case unit/synthetic cohort,
checks strict language-ID analysis and formatting, and proves the replacement
cohort has the same case identities as this original run.

## Source and runtime integrity

All 4,334 tracked product/test/configuration/asset inputs in the source manifest
remained byte-for-byte unchanged during the original run. HEAD, the dependency
lockfile, and the recorded runtime inputs also remained unchanged. The source
manifest covers tracked `packages`, `third_party`, `apps`, `tool`, and `tools`
inputs except documentation, plus the root manifests and repository rules.
It is a source-input manifest, not a hash of future validation documentation.

| Recorded value | SHA-256 or commit |
| --- | --- |
| Source commit before and after | `e3212327954ac144847a7c06b5d2420f00debab3` |
| Canonical source manifest before and after | `7c9dce69595316ab3ede21caadde46f56eff6ad764a393cb3bb27058f6e6d0ea` |
| Canonical runtime manifest before and after | `89a4c7bd995379bdeffda84184393345b1081ccfac4f9109aabb609e90ba6549` |
| Root `pubspec.lock` before and after | `72a5a52654a1484f4df646c631b4d1ea47e96025a671beff045eecf2b9e78e82` |
| Executed runner | `fe9d32731299a8e97353bc191b880fdc0af3fda7a2858f6ed6ab553150520cc5` |

The canonical manifest digests hash sorted compact JSON; the manifests also
record SHA-256 and byte size for each individual input. Compare
[source before](source-before.json) with [source after](source-after.json), and
[runtime before](runtime-before.json) with [runtime after](runtime-after.json).
The runtime records Dart 3.13.7, Flutter SDK commit
`737ba8f885dc774b53b442759999a312c9461e4e`, Node 24.22.3,
Python 3.12.14, GCC 14.2.0, package resolution, native SQLite bindings/library,
synthetic native fixture, and the relevant compiler/test executables and
snapshots.

Each gate directory preserves `command.json`, `stdout.log`, `stderr.log`, and
`result.json`, including exact argv, working directory, environment overrides,
exit status, timestamps, elapsed time, and output hashes. Test gates additionally
contain parsed `test-cases.json`. The complete original orchestration is in
[run_final.py](run_final.py). No GitHub Actions were queried or awaited.

## Replay

Prepare the pinned Flutter/Dart SDK, resolve the repository's dependency lock,
and provision the native SQLite binding used by the store tests. Set
`FLUTTER_ROOT` and `PUB_CACHE`; the original environment additionally set local
`TMPDIR` and `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, and `XDG_DATA_HOME` for Flutter.
A C++17 compiler and Node are required. The runner invokes the actual Dart SDK
binary rather than the Flutter Dart wrapper and performs no package resolution.

The frozen source commits predate these evidence files. Keep an evidence
checkout at a later commit containing this directory and a separate clean
source worktree at the desired frozen commit. Resolve dependencies in that
source worktree, then invoke the runner by its path in the evidence checkout.
Use a new empty output directory for every attempt:

```bash
python3 /path/to/evidence-checkout/docs/validation/mail-providers-20261119/final/run_final.py \
  --repo /path/to/frozen-source \
  --scratch /path/to/scratch-build \
  --output /path/to/new-empty-evidence \
  --freeze FULL_SOURCE_COMMIT_SHA
```

Using the original `e3212327954ac144847a7c06b5d2420f00debab3` source reproduces
the stale-fixture expectation. To replay the corrected qualification in full
on another machine, use the corrected source commit recorded by the follow-up
receipt. The follow-up's narrow reuse audit requires the original local runtime
and is not a substitute for a full replay when source or runtime inputs differ.

## Acceptance limits

No credentials or tenant endpoints were supplied, so this evidence does not
establish live Gmail, Microsoft 365, EWS, or IMAP/SMTP acceptance. The
language-ID native test uses the tracked synthetic allocation/lifecycle fixture;
`language_id_native_test.dart`, which requires the real external language-ID
library, is explicitly excluded. Installed OS credential stores, an actual
system-browser OAuth callback, and a signed macOS application build were not
exercised. macOS entitlements were parsed, and credential/browser behavior was
unit/widget tested. Browser checks establish compilation and native-import
isolation only.
