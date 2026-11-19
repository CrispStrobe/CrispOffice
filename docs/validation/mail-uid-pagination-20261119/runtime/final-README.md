# Final installed-backend and lifecycle preparation

The later [About workspace refresh](about-README.md) preserves this preparation
unchanged and records the final operational runtime receipt.

The later incoming source adds native/web/Android installation to the Hunspell
builder and additional lifecycle regressions. The earlier preparation receipts
and artifacts remain intact. The final setup rebuilds with the current
checked-in builder into `runtime/hunspell/build-final` and installs its verified
library and license/source materials into `runtime/hunspell/host-final`.

The new Linux build and installed library both have SHA-256
`648084ab2ea47b23da91c8e865cc8e2523322eb87d9fb921e4568dd3092e9338`.
All nine adapter/build/license inputs were unchanged during the build, all 28
upstream compilation members matched the pinned manifest, and all seven
installed files matched the build or checked-in license/source material. This
executes the new native installer and verifies its actual output. It does not
claim that a complete desktop application was built or launched.

Three separately compiled C ABI fixtures make the native ownership scenarios
observable. Their distinct environment names prevent one fixture from silently
standing in for another:

| Fixture | Environment | Scope |
| --- | --- | --- |
| Primary ownership counters | `QUDS_HUNSPELL_LIFECYCLE_LIBRARY` | The original eight cases, including rejected reopen and pending-work disposal |
| Incoming ownership counters | `QUDS_HUNSPELL_OWNERSHIP_LIBRARY` | Six cases, including delayed native open/check and eventual cleanup after bounded disposal |
| Incoming provider shim | `QUDS_HUNSPELL_PROVIDER_LIFECYCLE_LIBRARY` | Four provider/lifecycle regressions |

The final runtime receipt binds every fixture's source hash, compiler identity,
shared library, build log and receipt. The [refresh helper](refresh_final_runtime.py)
checks those inputs against the final source, retains all prior runtime inputs,
and selects the genuinely host-installed Hunspell library for the actual
dictionary and Studio integration tests. The dictionary remains the same eight
verified files at its immutable AyaSpell revision; live download qualification
remains explicitly enabled.

The [final runtime receipt](final-runtime.json) has SHA-256
`71d8cfd27118380f4dcf497786e6949ae2dd56ef60125b11cb3d1f79f7e2b5af`.
Offline lock enforcement on the reconciled source retained the exact dependency
lock and resolved all 132 expected package names. The binding retains the
11,142 verified SDK and hosted-package inputs and all 351 earlier additional
inputs, then adds 25 native installation, fixture and preparation records for
376 additional inputs in total. The previous operational receipt remains
preserved as `runtime-before-final-build.json` and inside the preparation
archive.

The [final preparation archive](final-preparation.tar.xz) is 454,360 bytes with
SHA-256 `201bf316c5ee0fe2794033d46683fc732c4523797dc83787161a2fb643d1b4b3`.
Its [member index](final-preparation.index.json) verifies all 33 retained
members against their original preparation files, including build and install
logs, source snapshots, both runtime receipts, the actual built and installed
backend, installed source/license materials, and the three separately compiled
lifecycle fixtures with their source, compiler and build records.

The copied Studio license notices are verified in
[host-notice-preservation.json](host-notice-preservation.json). The whitespace
gate permits exactly six fixed paths containing the same three upstream notice
blobs: the original package copies and the Studio asset copies. Product source
has no whitespace exception.

The desktop and cross-platform workflow received static command/path review.
The native installer was exercised locally on Linux. A full Linux desktop
build remains outside this execution because `gtk+-3.0` development metadata is
not installed. macOS, Windows, Android, browser Worker and Wasm builds/runs also
remain separate platform qualification. No GitHub Actions workflow, job or
status is queried, awaited or rerun for local acceptance.

The final current-source gate uses `run_tail_validation.py --replay-mail` to
execute the Mail cohorts afresh along with all selected Studio, proofing and
Hunspell suites. The separately audited 953-case subset at `162f53c0` remains
historical evidence and is not added to the current-source totals.

## Reproduction

After restoring the pinned SDK and tools described in the earlier runtime
instructions, build and install the native backend from the current source:

```bash
python3 packages/quds_proofing_hunspell/tool/build.py --native --jobs 2 \
  --output /absolute/path/to/runtime/hunspell/build-final \
  --install-native /absolute/path/to/runtime/hunspell/host-final \
  --install-licenses /absolute/path/to/runtime/hunspell/host-final/licenses/hunspell
```

Compile each fixture with the recorded g++ command and retain its distinct
receipt/environment mapping. The archive records the three exact source paths,
compiler executable hash and command lines. The refresh helper validates
prepared files; it does not download or compile them. In this session the
already prepared runtime was rebound using:

```bash
source /workspace/scratch/ab196f483cec/runtime/env.sh
dart pub get --offline --enforce-lockfile \
  > /workspace/scratch/ab196f483cec/hunspell-final-preparation/workspace-pub-get.log 2>&1
python3 docs/validation/mail-uid-pagination-20261119/runtime/refresh_final_runtime.py \
  --repo /workspace/scratch/ab196f483cec/quds_office_suite \
  --runtime /workspace/scratch/ab196f483cec/runtime \
  --preparation /workspace/scratch/ab196f483cec/hunspell-final-preparation
```

Run the final driver only after committing the source, plans and runtime receipt,
passing that exact commit as `--head`, the prepared runtime as `--runtime`, an
empty external evidence directory as `--output`, and `--replay-mail`.
