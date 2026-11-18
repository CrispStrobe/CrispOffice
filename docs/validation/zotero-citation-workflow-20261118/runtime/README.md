# Local Flutter runtime recovery

[runtime-ready.json](runtime-ready.json) records the fresh recovery for this
increment. Genuine Flutter **3.47.8** / Dart **3.13.7** was downloaded from the
official release archive and verified against its recorded SHA-256; a fresh
official release manifest independently confirmed that digest. All **162**
hosted package archives were downloaded and hash-verified. Both workspace and
Flutter-tools dependency resolutions passed `dart pub get --offline
--enforce-lockfile`, preserving their locks. The resolved workspace contains
**110 packages**, all **11** copied manifests match the checkout, and the SDK's
tracked files are unchanged.

Setup ran **no product tests** and used no GitHub Actions endpoints. Product
qualification is recorded separately by the editor runner.

## Saved recovery evidence

[setup.tar.gz](setup.tar.gz) contains the five setup scripts, environment file,
exact workspace lock, expected and freshly verified package inventories,
official SDK metadata, recovery receipts, and fresh execution logs. Its **20
members** are listed with sizes and SHA-256 hashes in [index.json](index.json).
It contains no SDK binaries, dependency cache, or inherited execution logs.

The original task root was `/workspace/scratch/ba0874ba8ec5`, containing:

| Directory | Purpose |
| --- | --- |
| `quds_office_suite` | Source checkout |
| `zotero-toolchain` | SDK, hosted cache, setup scripts and receipts |
| `zotero-validation` | Locked workspace with live links to checkout source |

The checkout's generated `.dart_tool` link points to the validation workspace
and is excluded locally from staging. Product source, dependency manifests and
tracked lockfiles were not changed by recovery.

## Reproduce

Start with a fresh writable task root containing the checkout. Extract the
archive into a new sibling `zotero-toolchain` directory. Retain a copy of the
archive before rerunning its scripts, because the current receipt and log paths
will receive the new execution's evidence. Replace the original task-root
literal in `env.sh` and `restore_flutter.py` with the new absolute root. The
other scripts derive that root from their own location. Keep the three sibling
directory names shown above.

From the new task root:

```bash
mkdir -p zotero-toolchain/tmp zotero-toolchain/config zotero-toolchain/cache
mkdir -p zotero-toolchain/data zotero-toolchain/logs zotero-toolchain/pub-cache
python zotero-toolchain/restore_flutter.py
python zotero-toolchain/prefetch_recorded_packages.py
python zotero-toolchain/prepare_workspace.py
python zotero-toolchain/finish_runtime.py
source zotero-toolchain/env.sh
```

The scripts require Python's standard library and enough disk space for the
1,581,444,364-byte archive plus its extracted SDK. Finalization expects no
conflicting `.dart_tool` directory in the checkout. It resolves only from the
verified cache and compares the locks, manifests and SDK tracked state.

After saving and freezing the intended product/test source, the editor runner
requires PyYAML and a fresh output directory:

```bash
python quds_office_suite/docs/validation/zotero-citation-workflow-20261118/editor/run_editor_zotero.py \
  --output zotero-editor-validation
```

The runner defaults to these sibling paths; `--repo`, `--workspace` and
`--toolchain` can override them. It selects every `word_zotero*_test.dart`,
requires all four new citation-workflow suites, checks the eight changed Dart
targets, and retains raw machine events and before/after source, dependency,
workspace and runtime bindings. A setup receipt alone is not a passing test
result.
