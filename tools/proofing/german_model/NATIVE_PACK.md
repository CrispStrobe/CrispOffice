# Local German grammar development pack

`build_native_pack.py` assembles the exact mixed Q4_K model and native binary
from the [retained native qualification](../../../docs/validation/german-gector/2026-11-17-native/README.md).
It is an offline, explicit development tool. It does not download a model,
load the inference library, register a provider, or approve a release.

Only these qualified bytes are accepted:

| Artifact | SHA-256 | Bytes |
| --- | --- | ---: |
| Mixed Q4_K model | `549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b` | 82,756,896 |
| Linux x86_64 library | `9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604` | 2,064,104 |

The script authenticates the checked-in qualification, conversion manifest,
build receipt, license inventory and original `artifacts.json` against fixed
hashes. It copies all twelve exact metadata/source/license sidecars alongside
the GGUF, plus the installed native header, license and third-party notices.
The original 453 MB ONNX model and development executables are not copied.
Arbitrary self-declared model or native-library pins cannot replace this trust
root. A newly compiled binary requires its own reviewed qualification and pin
update, even if it was built from the same source revision.

## Build and verify

Use absolute local paths. The bundle is the previously authenticated Proofbird
directory; the native install is the standalone CMake installation containing
`lib/libcrispembed-gector.so`, `include/gector.h`, and `share/licenses/`.
The output's parent must exist and the output itself must not exist.

```sh
python3 tools/proofing/german_model/build_native_pack.py build \
  --model /path/to/gector-de-mixed-q4_k.gguf \
  --bundle /path/to/proofbird \
  --native-install /path/to/gector-install \
  --output /path/to/new-development-pack

python3 tools/proofing/german_model/build_native_pack.py verify \
  --pack /path/to/new-development-pack
```

The JSON result supplies `model_directory`, model filename/bytes/hash and
`library`/`library_sha256` for the existing Dart provider. Both artifacts use
directories named by their hashes; the native library is directly inside its
hash directory as required by `GectorNativeBackendFactory`. Sidecars reside in
`model_directory`, so `GectorVerifiedBundle.load` can use that directory and
construct `GectorModelArtifact` from the returned model fields. Set the native
experiment gate `CRISPEMBED_GECTOR=1` separately before starting the host, and
share its personal vocabulary when explicitly configuring the manual provider.

`pack.json` records every payload file's hash and size, the exact stored total
including the manifest, platform/ISA and prepared-input ABI, model recipe, and
the recorded system dependencies. Identical inputs produce identical manifest
bytes; local source paths and timestamps are excluded. Aggregate sizes are
file contents, not filesystem allocation or inference memory.

Build verifies sources before copying, copied files before publication, and
the final published tree. It rejects symlinks, traversal, duplicate destination
paths, conflicting input/output directories and existing outputs. A private
sibling staging directory is atomically published with Linux
`renameat2(RENAME_NOREPLACE)`, including protection against a racing empty
output directory. Files and directories are made read-only. Owners can still
change permissions: the application host must keep admitted paths immutable
throughout the process lifetime. Verification rejects modified, missing,
additional, writable or symlinked pack content and altered manifests.

## Platform and license boundary

This exact library targets Linux x86_64 with SSE4.2, AVX, AVX2, F16C, FMA and
BMI2 and a compatible system ABI. Turning off machine-native compiler selection
did not produce a baseline-ISA binary. Other platforms and older CPUs need a
separate build and qualification. Pack verification does not run inference or
prove that the current machine satisfies the runtime requirements.

The preserved native receipt identifies system GCC runtime libraries and
glibc/libm/loader licensing separately from the MIT source components and
Apache-2.0 model. Those system runtimes are not bundled here. Copying the receipt
and notices does not establish approval under the project's strict shipping
license policy. This remains a local development pack pending platform,
dependency-closure and application-quality qualification.

Run the model-free controls with the Python standard library:

```sh
python3 -m unittest discover -s tools/proofing/german_model -p test_native_pack.py -v
```

Synthetic fixtures inject tiny test-only trust objects into internal helpers;
the production CLI exposes no trust override. The real pack must separately
pass the existing full Dart/native provider runner before reporting an
inference smoke test or performance result.
