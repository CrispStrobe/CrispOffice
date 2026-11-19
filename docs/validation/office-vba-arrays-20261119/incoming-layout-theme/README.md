# Incoming layout/theme — retained initial failure and fixture diagnosis

This directory preserves the first local qualification of incoming GUI head
`4fd010fcae209b6ea033828d76908508b7327b9f`, integrated at
`ae4c8223d1814df4a500518c8b223831cbb0b51f`. It is **historical failure
evidence**, not the final acceptance. The later corrected and expanded run is
recorded separately in `../incoming-layout-theme-final/`.

## Initial result

| Check | Observed result |
| --- | --- |
| Nine selected editor suites | 207 cases: **199 passed, 8 failed**, no skips |
| Three new GUI suites within that editor cohort | **17 passed** |
| Three repeated Studio mail suites | **18 passed**, no failures or skips |
| Strict analysis of eight changed editor library files and three new suites | Exit **0** |
| Source/runtime input snapshots | **2,207 unchanged** |
| Copied workspace manifests | All **20** match their repository counterparts |

The failed `receipt.json`, original JSON reporters, command/exit records, and
before/after hashes remain at their original paths. GitHub Actions were neither
queried nor awaited.

## Baseline reproduction

All eight failures were existing `embed_test.dart` widget fixtures that mounted
the default Word surface under only `Directionality` and `SizedBox`. Its default
review status includes a Material `Tooltip`, which requires an application
`Overlay`. The primary `No Overlay widget found` exception also disrupted
layout and produced subsequent geometry or keyboard assertion errors.

The two representative Tab-insertion and custom-chrome host cases were then
run against an isolated copy of the **pre-GUI editor library** from
`c3eaf57c85d363b1453f2a3407ba62768b0e2c08`. Both reproduced the same Overlay
failure. The test fixture was byte-identical to that baseline, and all **2,206
recorded baseline inputs** stayed unchanged. See `baseline/receipt.json`,
`baseline/source-frontier.json`, and the raw baseline reporter. The normal
workspace editor source link was restored after that diagnostic run.

The documented default review/proofing features are retained. The correction
provides a standard `MaterialApp` host to the eight fixtures and explicitly
unmounts and disposes the seven externally owned Word controllers after their
assertions. The custom-chrome `QudsOfficeHost` owns its controller. Production
editor behavior was not changed.

## Intermediate fixture probes

| Preserved log prefix | Result and purpose |
| --- | --- |
| `fixture-check` | Overlay host supplied: 1 passed; 7 exposed pending proofing timers from externally owned controllers |
| `fixture-teardown-late` | Registered teardown ran too late for Flutter's pending-timer invariant: the same 1 passed and 7 failed |
| `fixture-runner-error` | Incorrect package working directory caused dependency resolution errors before test execution; no accepted cases |
| `fixture-check-final` | Explicit unmount/disposal before completion: **8 passed, 0 failed, 0 skipped**, final reporter success |

The focused probe logs were diagnostic invocations. Their JSON reporter
outcomes are retained, but their shell exit statuses were not captured in a
separate command receipt. The final full qualification records both the actual
process exit status and the reporter outcome.

`fixture-change-proof.json` compares the corrected fixture against the pre-GUI
version: all **510 `expect`/`expectLater` expressions** are byte-identical and in
the same order. Eight application hosts and seven explicit controller cleanups
were added. Default review/proofing were not disabled, and no assertion was
removed or relaxed. The proof records both fixture SHA256 values and the
successful focused reporter hash.

## Evidence scope

`qualify.py` is the exact initial runner. It uses the full Flutter workspace,
official Flutter 3.47.8 and its bundled Dart, `--no-pub`, serial test execution,
and JSON reporters. The snapshot covers repository library sources and shared
configuration, selected test inputs, relevant editor/Studio assets, workspace
manifests/lock/package configuration, dependency manifests, and SDK binaries.
It does not replace the repository's separate macro validation configuration.

The original 18 Studio cases are repeats of the previously qualified mail UI
cohort and must be counted once in any distinct final total. Newer incoming GUI
commits broaden the final cohort; they are not covered by this historical run.
