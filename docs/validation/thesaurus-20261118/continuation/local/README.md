# Offline thesaurus local acceptance — 18 November 2026

This evidence binds the recovered implementation to actual local execution.
The final provider uses a **64-shard** parsed-data cache. Production sources,
tests, pack assets and fixture inputs remained unchanged through the native
run and the release web build; see [receipt.json](receipt.json) and
[source-inputs.json.gz](source-inputs.json.gz).

## Completed checks

The sequential native Flutter run passed **126 substantive cases**
across eight suites, with zero failures, skips, unclosed cases, parse errors,
layout-overflow warnings or missed-tap diagnostics. Lifecycle events are
excluded from the case total. The complete machine events, audit and command
exit codes are retained; no GitHub Actions were queried or awaited.

| Cohort | Passed |
| --- | ---: |
| Thesaurus dialog and entry points | 18 |
| Guarded target, replacement and undo/redo | 51 |
| Existing proofing correction, capture and context | 42 |
| Existing review pane | 11 |
| Real installed-pack query/notice panel | 1 |
| Real-pack desktop/narrow render fixtures | 3 |
| **Total** | **126** |

The engine/provider's separate 24-case unit suite and non-result-cache
performance measurements are recorded in
[the data qualification directory](../../../../../packages/quds_office_engine/third_party/thesaurus/).
Those 24 cases are not part of the 126-case Flutter count here.

The pack panel exercises 15 actual queries: English bank, run, happy, ice cream,
children and dogs; German Bank, Häusern, Maße, Masse, sich freuen and Straße;
two invented negative controls; and unsupported French. It validates source
notices, polysemy, qualified word forms, German ß distinctions and bounded
caches. [native-pack-report.json](native-pack-report.json) retains the exact
source meaning IDs, terms, labels, relations and matched-form reasons. This
bounded automated panel is not a general linguistic quality assessment.

## Native reference measurements

Environment: official Flutter **3.47.8**, Dart **3.13.7**, Linux x86_64 native
Flutter tester, Intel Xeon Platinum 8573C, nine visible logical CPUs. The
reference is a shared development environment running JIT tests, rather than
an installed release desktop app. CPU identity, SDK hashes, the fresh official
release entry and verified dependency receipts are in [runtime/](runtime/).

| Measurement | Final run |
| --- | ---: |
| First English bank lookup, 18 meanings | 1343.170 ms |
| First German Bank lookup, 2 meanings | 61.987 ms |
| Warm result-cache p50, 75 lookups | 0.014 ms |
| Warm result-cache p95, 75 lookups | 0.053 ms |
| Native tester RSS before panel | 192,507,904 bytes |
| Native tester RSS after panel | 317,698,048 bytes |
| Native tester peak RSS | 363,880,448 bytes |

The warm samples above are explicitly result-cache hits over this panel. Use
the separate provider benchmark for normalized query variants that bypass
that cache. RSS includes the VM, Flutter, JIT code, assets and other process
state; it is not an isolated thesaurus allocation or browser memory result.
Cold timings vary substantially in this shared environment and include
verification, decompression and JSON parsing.

## Native visual evidence

- [English desktop](visuals/english-desktop.png), 1200 × 900.
- [German desktop](visuals/german-desktop.png), 1200 × 900.
- [German narrow layout](visuals/german-narrow-large-text.png), 390 × 844 at 1.5× text scaling.

These are real Flutter tester renders of the actual Quds editor and dialog
using the installed corpora. They are not browser captures or installed
Linux application captures. Source fonts and the SDK's actual Material icon
font are loaded in the fixture. The fixture waits for the button's
disabled-to-enabled color transition and asserts that Replace's rendered
foreground equals the theme's onPrimary color (0xffffffff).

## Browser and desktop limits

The final **release web compilation succeeded** with `--csp` and
`--no-web-resources-cdn`. All 1155 build files
(87,288,627 bytes, including host assets, fonts and
CanvasKit) are inventoried in
[browser-build-files.json.gz](browser-build-files.json.gz). The build retains
a warning about a CupertinoIcons font referenced by the wider editor library;
the thesaurus uses the bundled Material icons.

Actual browser execution remains **blocked by this environment**. Local
Chromium exits before application startup because the execution sandbox
rejects Unix socket creation (`process_singleton_posix.cc: socket() failed:
Operation not permitted`). The supported cloud browser could not reach the
local test origin (`ERR_CONNECTION_REFUSED`). No permissions or browser
routing were changed to bypass either restriction. The local launch error is
retained in [attempts/browser-launch-blocked.json](attempts/browser-launch-blocked.json).

Consequently, actual-browser rendering, browser CSP behavior, browser memory
and **network-disabled browser lookup are still pending release gates**.
A compiled JavaScript bundle is not evidence that those gates passed. The
native headless tests also do not establish installed desktop packaging;
this environment lacks the native Linux compiler/GTK development setup.

The browser fixture and test-only offline service worker are provided for
replay on a normal desktop: they install all built local assets, disable the
browser context's network, then exercise cold English/German dialog lookup,
explicit replacement and undo/redo, notices and the query panel. That script
has not reached application execution here and must be qualified on the
next browser-capable host.

## Replay

Restore the exact runtime using the documented
[SDK recovery](../../../zotero-citation-workflow-20261118/runtime/README.md), or
use an unmodified Flutter 3.47.8 installation and the saved lock. The runtime
scripts here retain this task's absolute paths; relocate them consistently
when replaying. Keep the checkout named `quds_office_suite` and the separate
resolved workspace named `zotero-validation` beneath the task root. Their
source paths are live links; no production manifests were relaxed.

With those paths prepared, run the saved native/build runner from the task
root, passing the current absolute root explicitly:

```bash
source zotero-toolchain/env.sh
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/run_final_validation.py --root "$PWD"
```

The runner captures sources before and after, runs all native suites
**sequentially**, audits complete machine events, and builds the real fixture.
To replay the pending browser gate on a host that permits Chromium startup:

```bash
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/install_offline.py thesaurus-browser-build-final
python quds_office_suite/docs/validation/thesaurus-20261118/continuation/local/fixtures/run_browser.py thesaurus-browser-build-final --output browser-replay
```

The browser script uses Python Playwright and `/usr/bin/chromium`; adjust the
explicit executable path for the qualified host as needed. It serves only the
local build, blocks other origins during installation and then sets the
browser context offline. The service worker is test infrastructure, not a
production deployment change.

## Earlier attempts retained

[attempts/](attempts/) keeps the missing FlutterError-import failure, the UI
fixture scrolling/clock failures, the lazy-finder failure, the concurrent
asset-bundle shader failure, the color-animation probe and the initial
32-shard receipt. The final run uses serialized suites and a stable source
snapshot, and passed without those diagnostics. The 32-shard performance
finding led to the separately tested 64-shard default; no corpus records were
removed to improve these results.
