# Reproducible setup for the final Zotero qualification

This package preserves the setup completed before the current source
qualification began. It contains **no application-test results**. The
canonical, host, and Harper/Studio qualification receipts are published
separately. No GitHub Actions, workflow, or CI-status endpoint was used.

The relative record and script paths below refer to the extracted `setup/`
directory inside [setup-evidence.tar.gz](setup-evidence.tar.gz).

## Exact inputs

| Input | Identity |
| --- | --- |
| Canonical Quds source | `5b05664357eead5ddc86922bab248224dbd4da6d` |
| Actual CrispCloud host source | `342b744a3cb66e3ee9387733ebcf8613cdb23a33` |
| Flutter framework | `3.47.8`, `737ba8f885dc774b53b442759999a312c9461e4e` |
| Flutter engine | `cf636b1dfb818dd6a3ff16e390e93b1a036969c8` |
| Dart SDK | `3.13.7` |
| Dart executable SHA-256 | `01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb` |
| Linux Flutter tester SHA-256 | `800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f` |
| Official Dart ZIP SHA-256 | `b52a1d890575d6c286079bd51650dc77f90c2dddfdcb073a052ae06a5fdb276d` |
| Full Harper/Studio workspace lock SHA-256 | `344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130` |

The original official ZIP contains 238,851,283 bytes. Its URL is derived
from the exact framework's `bin/internal/update_dart_sdk.sh` and is retained
in the reproduction helper. Both executable hashes match the previously
qualified genuine binaries. The SDK's tracked files were unchanged.

## Completed setup

The focused setup receipt (`setup/records/current-setup-receipt.json` in the setup archive) records four
successful Flutter-managed `pub get --enforce-lockfile` resolutions. The
engine, editor, focused Studio, and actual host graphs contain **55, 79, 64,
and 96 packages**, respectively. All four original dependency lockfiles
remained byte-identical. Every graph already has genuine `flutterRoot` and
`flutterVersion` metadata before qualification fingerprints are taken.

The full workspace receipt (`setup/records/harper-workspace-resolution.json` in the setup archive)
records **108 packages**, including all nine local workspace package names.
Its lock is the unchanged committed
`docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock`.
Current production manifests and root analysis options are copied exactly;
implementation directories link to the canonical source. This graph supplies
Harper and the current Studio imports that the older focused Studio graph
does not contain. No dependency constraint was relaxed.

The host wrapper declares all six actual notice assets (`setup/records/host-six-notice-assets.json` in the setup archive),
including `ENGLISH_US_LICENSE` and `ENGLISH_GB_LICENSE`. The existing four-asset
helper remains unchanged; the two new declarations are an explicit wrapper
overlay. The engine wrapper exposes only the three PDF example files needed
by its selected tests, without exposing their workspace-only pubspec.
All four optional system-font fixtures (`setup/records/optional-font-inputs.json` in the setup archive)
were present and hashed; none was installed or replaced.

The full-workspace offline attempt exited **69** because `printing` was not
yet cached. The same enforced lock then resolved online successfully; its
bytes did not change. Both complete logs are retained. This was a setup-only
diagnostic and contributes no test cases to any qualification count.

## Reproduce in a fresh Linux x64 workspace

Place clean checkouts named `quds` and `crisp` at the exact source commits
above. Keep this published package outside the new `runtime` directory.
Python 3, Git, curl, and unzip are required. The following commands create
only a new runtime and wrappers; they do not edit either source repository:

```bash
task_setup=/absolute/path/to/this/setup
task_workspace="$PWD"

git -C quds checkout --detach 5b05664357eead5ddc86922bab248224dbd4da6d
git -C crisp checkout --detach 342b744a3cb66e3ee9387733ebcf8613cdb23a33

python3 "$task_setup/scripts/bootstrap-runtime.py" \
  --runtime "$task_workspace/runtime"
python3 "$task_setup/scripts/prepare-workspaces.py" \
  --workspace "$task_workspace" --runtime "$task_workspace/runtime"
python3 "$task_workspace/runtime/finish-setup.py"
python3 "$task_workspace/runtime/resolve-full-workspace.py"
source "$task_workspace/runtime/env.sh"
```

`bootstrap-runtime.py` and `prepare-workspaces.py` were assembled from the
recorded operations during publication and received static syntax and input
review only; they were **not executed while qualification was running**.
The published `finish-setup.py`, `resolve-full-workspace.py`,
`reconstruct-harnesses.py`, and `prepare-harness-assets.py` preserve the
actual used script bytes.

The bootstrap reproduction helper additionally restores the recorded
Flutter-tool lock and uses the exact framework's snapshot compilation
flags. This avoids choosing newer tool dependencies through the framework
launcher's normal initial `pub upgrade`. Its newly compiled snapshot receives
a fresh hash: relocation or recompilation is not claimed to reproduce an
identical JIT snapshot. Framework, engine, Dart/tester hashes, application
locks, source pins, and metadata assertions remain enforced.

Pass the new workspace/runtime paths to the helpers; do not delete or change
their assertions. The inherited reconstructor automatically rebases its old
paths. Recreate package graphs through the genuine locked resolver instead
of hand-editing recorded graph metadata. The full workspace's relative layout
preserves its exact manifest and lock bytes. Source symlinks, SDK/cache paths,
and `env.sh` are generated for the new location. A new runtime is required;
the helpers refuse to replace existing harnesses or evidence.

After setup, use `runtime/harness` for canonical tests,
`runtime/crisp-host-harness` for host tests, and
`runtime/harper-workspace` for Harper/Studio. Qualification launchers must
receive the new absolute source/harness paths while retaining the same
commit pins, test selections, timeouts, input fingerprints, and success
gates. Run the Harper/Studio analyzer after canonical analysis, as its
published runner enforces through the shared qualification lock. Do not
resolve dependencies or rebuild the SDK during any qualification run.

## Preserved evidence

- 43 frozen setup text inputs (`setup/records/harness-inputs-current.json.gz` in the setup archive):
  exact manifests, locks, analyzer options, and package graphs with hashes.
- SDK tool inputs (`setup/records/sdk-tool-inputs.json.gz` in the setup archive): the actual tool manifest,
  lock, graph, and version metadata.
- Setup-ready handoff (`setup/records/setup-ready.json` in the setup archive) and
  recorded environment (`setup/records/recorded-environment.sh` in the setup archive).
- Compressed setup logs and raw-byte hashes (`setup/records/log-index.json` in the setup archive),
  including the missing-package offline attempt and successful retry.
- Source/runtime identities (`setup/records/source-runtime-identities.json` in the setup archive) and
  publication inventory (`setup/artifact-index.json` in the setup archive).

Gzip members are lossless. For example,
`gzip -dc records/harness-inputs-current.json.gz` reads the input bundle.
Recorded absolute paths identify this actual run; they are provenance, not
paths that must be recreated. No SDK binaries, dependency-cache packages,
live qualification logs, or application-test results are included here.
