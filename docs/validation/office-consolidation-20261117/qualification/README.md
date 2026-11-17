# Frozen-source local qualification

Published source **`f5021f1c364baf010049fda2dd4bf7f414deda79`**, tree **`afd7a513dfa91472f58c27ead4d8be3f4b75c262`**,
passed the complete selected continuation scope on 17 November 2026,
**18:50:59–19:00:05 Berlin time**.
No qualified product source, HEAD, dependency, runtime, workspace, fixture or
harness input changed during the run. The temporary analyzer configuration was restored.

## Accepted results

| Primary cohort | Files | Substantive passes |
| --- | ---: | ---: |
| Engine Zotero — Dart VM | 19 | 390 |
| Editor Zotero — Flutter | 13 | 186 |
| Engine integration — Dart VM | 100 | 2,232 |
| Editor integration — Flutter | 37 | 398 |
| Harper contracts — Dart VM | 3 | 29 |
| GECToR, including native fixture — Dart VM | 11 | 194 |
| AOT contracts — Dart VM | 6 | 99 |
| Configured Studio — Flutter | 2 | 13 |
| **Total** | **191** | **3,541** |

All **180 previous primary files** and the original 174-file selection remain.
Eleven files were added: six AOT files, two Studio files, the incoming parallel
decoration suite, noun agreement, and the new table/tab fidelity suite.

The primary runner reported **3,543** successes.
Two inherited private-PDF cases returned before their assertions because their
fixture is unavailable; both are removed from the **3,541**
substantive total. No failure, error, unexpected skip or missing suite was
accepted. There were **zero primary skips**: the pinned native GECToR fixture
was available, hash-verified and executed successfully.

The Node lane repeats **486 cases across
23 files**: 387 engine cases in 17 files and all 99 AOT cases in six files.
Exact multisets of suite identity, case name and outcome match the VM runs.
These are repetitions, not extra unique cases. Seven unchanged `dart:io`
Office suites remain covered on VM and are excluded only from the Node lane.
The plan records their names and the reviewed import closures.

Separately, all **117 Python controls pass**, including the real tiny ONNX
converter control and all nine candidate-admission controls. There were no
Python skips, expected failures or missing selected controls.

All **six strict-analysis scopes** pass with fatal infos enabled. All **101
handwritten Dart formatting targets** pass at language version 3.12. Generated
data are checked against their exact committed manifests and excluded only
from handwritten formatting. All 18 planned commands pass.

## Exact exclusions

The absent optional fixture is `/home/mohammed/Desktop/al_tahreer_profile.pdf`.
The following two `pdf_file_test.dart` successes are excluded:

- `TrueType subsets without cmap get ToUnicode cmap for the host`
- `JPEG with DCT SMask attaches softMaskJpeg for the host`

No other case is excluded from the primary substantive count. The native
fixture and converter successes qualify those concrete controls; they do not
establish representative model accuracy, distribution readiness or all-device
performance. AOT contracts and configured Studio tests require no live daemon.

## Reproduction and evidence

The environment is Flutter **3.47.8**, Dart **3.13.7**, Node **24.22.1** and the
unchanged pinned workspace lock `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
The source-linked workspace resolved 110 packages offline. The incoming AOT
package is included without an unrelated Android URL-launcher dependency bump.

The exact runner, companion controls and both authenticated previous selection
plans are retained in [harness](harness/). Setup scripts, environment files and
receipts are retained in [setup](setup/). The indexed evidence archive includes
all raw compressed stdout/stderr, case summaries, rendered test artifacts,
before/after maps, the terminal receipt and the identical plan-only output.

The [archive](qualification-f5021f1c.tar.xz) has **124 members**, 975,320 compressed
bytes and 9,536,552 uncompressed bytes. Every member was read back and checked
against the [size/SHA-256 index](qualification-f5021f1c.tar.xz.index.json).
Archive SHA-256: `560eef7a14ebc90b011ff41a711fa5036487631461ecbecdfd41d51d251f3efc`.

| Before/after input map | Entries | Result |
| --- | ---: | --- |
| Tracked qualified source outside reports | 3,483 | Unchanged |
| External dependency files | 5,099 | Unchanged |
| Selected runtime inputs | 14 | Unchanged |
| Workspace files and links | 125 | Unchanged |
| System fixture entries | 6 | Unchanged |
| Pinned native model/library files | 2 | Unchanged |
| Harness inputs | 10 | Unchanged |

After restoring the recorded SDK, dependencies and pinned native development
fixture, check out the source above. Adapt environment locations only, then run:

```sh
source ENVIRONMENT_DIRECTORY/env.sh
source ENVIRONMENT_DIRECTORY/native-env.sh
PYTHON_WITH_NUMPY_ONNX_AND_ONNXRUNTIME \
  HARNESS_DIRECTORY/run_qualification.py \
  --repo CHECKOUT_DIRECTORY \
  --source-commit f5021f1c364baf010049fda2dd4bf7f414deda79 \
  --flutter-root FLUTTER_DIRECTORY \
  --workspace CANONICAL_WORKSPACE_DIRECTORY \
  --output NEW_OUTPUT_DIRECTORY
```

Use `--plan-only` to inspect selection without product tests. The runner refuses
to overwrite an existing attempt, compares every selected suite, checks test
completion identity, and rejects source/input mutation. SDKs, dependencies and
native model/library binaries are not redistributed in the evidence archive.

Development failures, corrected test titles and setup-attributed direct-analyzer
failures remain separately preserved in [development](../development/). They
are not included as qualification passes. The normalized package graph used
here resolved those analyzer-routing issues without altering product source.

No GitHub Actions, workflow, check-run or commit-status endpoint was queried,
awaited or used as an acceptance gate.
