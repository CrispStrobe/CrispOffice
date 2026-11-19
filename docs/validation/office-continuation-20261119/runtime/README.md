# Fresh Linux qualification runtime

This directory preserves preparation evidence, not product-test acceptance.
The operational runtime for this continuation is outside the source checkout:
`/workspace/scratch/688e1d3b1ee4/runtime/test`.
Its committed [receipt](runtime.json) has SHA-256
`d7c66838d6af65c5aaefb4e33430e04cc819a3c06925bd87c3e683f731a86b58`.
All 11,142 retained runtime records and 400 additional bindings were verified
before the product gate. The dependency lock was unchanged and offline enforced
resolution identified all 133 workspace/dependency package names.

## Immutable inputs

| Input | Pin or preparation result |
| --- | --- |
| Flutter / Dart | 3.47.8 / 3.13.7; framework `737ba8f885dc774b53b442759999a312c9461e4e` |
| Official Linux SDK archive | 1,581,444,364 bytes; SHA-256 `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2` |
| Hosted packages | 176 archives, each verified against its dependency-lock SHA-256 |
| CMake | 3.31.10; Linux wheel SHA-256 `2f766bb46367e5e0559fa33184653754bce044583a06014dcaebf8e6dff8a1f1`, matched official PyPI metadata |
| Hunspell | 1.7.2; release archive SHA-256 `11ddfa39afe28c28539fe65fc4f1592d410c1e9b6dd7d8a91ca25d85e9ec65b8`; all 28 compilation members verified |
| AyaSpell | `cstr/ayaspell-ar-hunspell` revision `e9ace7cca3844bef906d8d9fc5431c4e15bd2740`; all eight catalog files verified |
| Morphology native source | CrispEmbed `8e40ad88945ca2e0b5e22f311835664c67501fee`; all 26 pinned files verified |
| Camel Morph noprob data | `cstr/camel-morph-msa-v1.0` revision `b31cf4a83f8ad63bb1989cf2879e72f23fadbfb0`; four files, 78,086,645 bytes, verified against the compiled catalog |
| Node and Poppler | Installed executables, versions, Poppler assets and shared libraries recorded and hash-bound in the receipt |

Both native libraries were freshly built using their checked-in builders and
installed into separate host directories. The three Hunspell ownership fixtures
were independently compiled; they do not replace either real backend. The
native SQLite hook and FTS5 smoke also completed successfully.

## Reproduction

Restore the pinned SDK and hosted dependency cache into a new empty directory,
using the checked-in generic restorer from the repository root:

```bash
python docs/validation/document-review-notes-20261118/runtime/restore_runtime.py \
  --repo /absolute/path/to/quds_office_suite \
  --runtime-root /absolute/path/to/runtime/test \
  --node-tests
```

The restorer downloads and verifies the complete official SDK stream before
running its selected executables, verifies all hosted archives, performs offline
enforced resolution and prepares SQLite. Its retained SDK supports VM tests,
analysis and Dart-to-JavaScript compilation; it is not a full desktop or Flutter
web build installation. Keep the runtime outside the repository.

The [preparation archive](preparation-evidence.tar.xz) contains the exact session
helpers and logs. Its [index](preparation-evidence.index.json) lists all 68
members with sizes and SHA-256 values. The archive is 1,454,836 bytes and has
SHA-256 `bb22cab18391ef851086a02d18edf67e0e5d0cd628ccef726174974973c87650`.
Extract it into a separate preparation directory, retaining the original
archive. The helpers at its root are:

- `restore_local.py`: this session's wrapper around the generic restorer; it
  reuses an already downloaded, fully verified SDK archive.
- `fetch_dictionary.py` and `fetch_morph.py`: fetch and verify catalog-pinned
  AyaSpell and morphology data; the latter also prepares pinned native sources.
- `prepare_native.py`: run the current Hunspell builder, install its outputs,
  compile all three ownership fixtures and capture Poppler provenance.
- `prepare_morph.py`: run the current morphology builder and install its output.
- `bind_native.py`: verify prepared inputs and augment the new runtime receipt
  with the complete Hunspell/morphology environments.

These archived helpers record this session's absolute workspace paths. For a
different workspace, copy them into scratch and change their root/path constants
to the new checkout and runtime locations before execution; keep the immutable
version, length and hash checks intact. Prepare the pinned CMake wheel in that
scratch directory and place its `cmake/data/bin` directory on `PATH`. Run
`fetch_dictionary.py` and `fetch_morph.py` to completion before the native build
helpers, then run `bind_native.py` after the generic restorer is ready. The
archive includes the CMake download receipt, exact compiler commands and all
build/install receipts. A new machine gets a new runtime receipt; it must not
reuse this session's absolute paths or claim this session's execution results.

## Frozen-source command for this workspace

After source and plans are committed and the checkpoint is saved remotely:

```bash
python docs/validation/office-continuation-20261119/run_validation.py \
  --head <published-source-commit> \
  --base b070e228a749e22cc8ce2098029a76ab5fb8eccb \
  --runtime /workspace/scratch/688e1d3b1ee4/runtime/test \
  --output /workspace/scratch/688e1d3b1ee4/qualification-final
```

The driver reads both native environments from the receipt and rejects missing
libraries, incomplete data bindings, disabled live-download tests or a changed
operational receipt. Reproduction with a new runtime requires committing that
new receipt in this directory before its own source freeze. Output must be a new
directory outside both checkout and runtime. The driver invokes Poppler from
an output-local working directory and keeps temporary/cache directories outside
the checkout. No GitHub Actions API, job, status or workflow is queried.
