# Incoming Word work: final local qualification

Status: **PASS**. This is the new qualification of the combined Word implementation imported while developing Mail bulk actions. It covers main's official named measurement arguments and ratio evaluator, the eight physical conversion functions, the large-scalar regression preserved from the continuation branch, and the existing line-spacing contract.

## Accepted gates

| Gate | Result |
| --- | --- |
| VM, nine compiler and integration suites | **757 passed**, zero failures or skips |
| JavaScript/Node, five portable compiler suites | **712 passed**, zero failures or skips |
| Formatting and strict static analysis | **13 files clean**, including the production parser, nine suites and three portable drivers |
| Exact committed line-spacing BAS | VM and compiled JavaScript/Node pass; semantic JSON identical |
| Exact committed measurements BAS | VM and compiled JavaScript/Node pass; semantic JSON identical |
| Exact committed named-measurements BAS | VM and compiled JavaScript/Node pass; semantic JSON identical |

The Node cohort is a subset of the VM cohort; do not add them into a unique-test total. The unit-conversions BAS is exercised by its integration suite and does not have a separate JavaScript driver in this increment.

The accepted receipt is [intake-local-word-final-validation.json](intake-local-word-final-validation.json). It records every command and working directory, stdout/stderr log and hash, process exit result, terminal test-runner result, portable output equality, runtime versions, and before/after hashes for **369 scoped source and dependency inputs**. All inputs were unchanged during this run. Initial and final Git heads may differ when Mail-only work is committed concurrently; the Word source binding is explicit.

- Started: `2026-11-20T21:08:22.132580+00:00`.
- Completed: `2026-11-20T21:11:13.423971+00:00`.
- Initial checkout: `0d2fb8d1baceba6340e0d8cd6fdf3e81aa53d5cd`.
- Final checkout: `0d2fb8d1baceba6340e0d8cd6fdf3e81aa53d5cd`.
- Runtime: `Dart SDK version: 3.13.7 (stable) (Thu Oct 22 14:28:57 2026 -0700) on "linux_x64"`; Node `v24.22.3`.
- Word parser SHA-256: `41de865411b884d18c1097e9a80d68cd6bf1fb245e1844a46f72af05636f5ecd`.
- Locked dependencies SHA-256: `0d64a732cd7f6c7cc4e1e01255276f081b59e6f43039636c3d36f6785a958ce2`.

## Preserved diagnostics and exact correction

The first strict formatting check rejected five incoming test/probe files. The formatter changed only those files; the production parser was already formatted. The failure and unchanged-source binding remain in [the formatting diagnostic](intake-local-word-final-diagnostic-validation.json).

The first expanded VM run recorded **749 passes and eight failures**. All eight were instances of the same incoming fixture: it declared `Dim result` after the executable assignment `value = "1"`. The compiler correctly rejected that declaration order before reaching the intended nonnumeric-Variant check. Moving the declaration above the assignment preserves both the invalid numeric-string input and the original `vba_type_error` assertion. No production implementation was changed. The original failed run remains in [the fixture diagnostic](intake-local-word-final-diagnostic-fixture-validation.json).

A tool-context refresh then interrupted the next VM run. Its process handle was lost and its output had no terminal result. It is explicitly nonaccepted in [the interruption receipt](intake-local-word-final-interrupted-validation.json); partial output was preserved, and the final run above started afresh.

The earlier [185 VM / 63 Node receipt](intake-local-word-validation.json) remains historical evidence for the pre-reconciliation parser. It is not used as acceptance for the final named/ratio implementation.

## Portable evidence

Each portable driver receives the Base64 encoding of the actual committed BAS bytes. It is run on the VM, compiled with `dart compile js -O1`, then run on Node with `globalThis.self = globalThis` as required by the asynchronous dart2js bootstrap. Successful exit status alone is insufficient: the harness parses both JSON results and checks equality.

| Driver | Equal output sections |
| --- | --- |
| line spacing | `example`, `exampleReplay`, `ordinaryDecimals`, `presetGuards`, `policies`, `rollback`, `recording`, `refusedSources` |
| measurements | `example`, `lateFailureRollback`, `readOnlyPolicy`, `mcpCompileAndRun` |
| named measurements | `example`, `guards` |

These gates cover the local compiler, macro execution, integration and portable driver contracts. They do not claim a real Office application, installed platform release, browser or WASM run. Mail provider and UI acceptance is recorded separately. GitHub Actions, workflow runs and status endpoints were not queried or awaited.

## Frozen cutoff supplement

A later reconciliation of a branch already present in the frozen intake retained thirteen additional named compiler cases and one integration case. The [targeted qualification](intake-local-word-cutoff.md) records the 171 VM / 160 Node reruns, the unchanged production/BAS binding and the assembled final 771 VM / 725 Node cohorts. This original receipt remains unchanged evidence for its own source.
