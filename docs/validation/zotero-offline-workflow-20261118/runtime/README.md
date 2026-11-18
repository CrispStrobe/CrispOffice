# Recovered local validation runtime

The [runtime receipt](runtime-ready.json) records the setup used for this
increment: genuine Flutter **3.47.8** / Dart **3.13.7**, 162 hash-verified hosted
package archives, and a 110-package workspace graph. The official SDK archive
hash also matches the current official Flutter release manifest. Both workspace
and Flutter-tools dependency resolutions succeeded with
`dart pub get --offline --enforce-lockfile`; neither lock changed, and all eleven
mirrored workspace manifests matched the checkout. Runtime setup executes no
product tests; the separate editor cohort contains the acceptance result.

## Saved contents

[setup.tar.gz](setup.tar.gz) contains the five setup scripts, the actual resolved
workspace lock, the expected package manifest, current verified download
receipts, official SDK metadata, setup receipts, and nine logs from this
execution. [index.json](index.json) records every member's size and SHA-256.
The bundle contains no SDK or dependency binaries, downloaded archive caches,
or inherited historical logs.

The prefetch manifest `setup/prefetch-162.json` was recovered from the previous
qualified runtime and supplies the expected package versions and hashes.
`setup/prefetch-current.json` and `logs/prefetch-current.log` record their new,
genuine downloads in this execution. The 1,581,444,364-byte SDK archive was
verified and extracted, then removed to recover disk space; its URL and SHA-256
remain in `flutter-recovery.json`.

## Original paths and reproduction

The original task root was `/workspace/scratch/7f793b53d474`. Its sibling
directories were:

| Directory | Purpose |
| --- | --- |
| `quds_office_suite` | Git checkout containing product source |
| `zotero-toolchain` | SDK, genuine package cache, setup scripts and logs |
| `zotero-validation` | Separate resolved workspace with live source links |

For a fresh setup, place the checkout and a new `zotero-toolchain` directory
under one writable task root. Extract this bundle into `zotero-toolchain`.
Preserve the archived `logs/`, `runtime-ready.json`, `flutter-recovery.json`,
`setup/workspace-prepared.json`, and `setup/prefetch-current.json` elsewhere if
you want to retain the original receipts alongside newly generated ones.

Update the literal `/workspace/scratch/7f793b53d474` in `env.sh` and the hardcoded
`ROOT` in `restore_flutter.py` to the new task root. `prepare_workspace.py` and
`finish_runtime.py` derive that root from their own location and expect the
three directory names above. Adjust those names in the scripts if necessary.
Use a Python environment with PyYAML when subsequently running the editor
validation runner; these five setup scripts use the Python standard library.

From the new task root, run:

```bash
mkdir -p zotero-toolchain/tmp zotero-toolchain/config zotero-toolchain/cache
mkdir -p zotero-toolchain/data zotero-toolchain/logs zotero-toolchain/pub-cache
python zotero-toolchain/restore_flutter.py
python zotero-toolchain/prefetch_recorded_packages.py
python zotero-toolchain/prepare_workspace.py
python zotero-toolchain/finish_runtime.py
source zotero-toolchain/env.sh
```

The restore script requires a fresh SDK destination and verifies the complete
official archive before extraction. Allow enough disk for both the archive and
its extracted contents. The current prefetch script verifies every package
archive against the saved digest before extracting it. Workspace preparation
copies the eleven manifests and saved lock and links package source to the
checkout. Runtime finalization resolves both locked graphs offline, compares
the locks and manifests, checks the SDK's tracked state, records executable
hashes, and links the checkout's `.dart_tool` to the separate workspace graph.
It expects no preexisting conflicting `.dart_tool` directory in the checkout.

The SDK version command reports the original framework and engine revisions.
Analytics suppression is provided through the environment; no telemetry
consent setting was changed. No GitHub Actions or workflow endpoints were used.

## Preserved setup correction

The first prefetch execution wrote a trailing newline in each pub cache digest
file. Although all 162 archive hashes were verified, the first offline
resolution rejected that serialization. The inline correction checked each
digest against the expected manifest and rewrote it without the newline.
Both offline enforced-lockfile resolutions then succeeded. Package source,
archive digests, lockfiles and product source were unchanged by the correction.

The original failure logs and successful retry logs are retained. The top-level
`prefetch_recorded_packages.py` is the corrected reusable script. To document
what actually ran, `attempts/prefetch_recorded_packages_executed.py` reconstructs
the earlier executed version by reversing that single recorded one-line edit;
`attempts/normalize_cached_hashes.py` transcribes the actual inline correction.
These provenance details are recorded explicitly in
`setup/hash-cache-serialization-correction.json`. The two attempt scripts are
historical evidence and are unnecessary for fresh setup with the corrected
prefetch script.
