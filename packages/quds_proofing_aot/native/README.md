# Daemon-free AOT runtime

`quds_aot_worker` calls the real AOT syntax and morphology libraries in a local,
application-owned child process. It reads JSON lines from stdin and writes JSON
lines to stdout. It has no listening port, HTTP client, background service,
automatic downloads, or shell execution. Closing stdin exits; cancelling the
Dart transport kills its own worker.

The existing HTTP transport is an independent, optional backend. This native
worker neither builds nor launches `SynanDaemon`.

## Build once

On Debian/Ubuntu, the build prerequisites are:

```sh
sudo apt-get install build-essential cmake flex libfl-dev bison zlib1g-dev git python3
```

From the Quds repository root:

```sh
python3 packages/quds_proofing_aot/tool/build_native.py --jobs 4
```

This explicit setup command obtains pinned AOT and nlp_base sources, builds the
engine and all three morphology dictionaries without Qt, and assembles a runtime
under `.dart_tool/quds_aot_native/runtime`. It then exercises the assembled worker
with synthetic German/Russian syntax, German/Russian/English morphology, protocol
errors, resource bounds and a missing-data case. Installation is replaced only
after this smoke succeeds. An existing installation remains available if the
new build or smoke fails.

Use `--install /absolute/destination` to choose a different runtime destination.
Keep its `Bin`, `Dicts`, `Thes`, `notices` and manifest together. Put `runtime/Bin`
on `PATH`, or configure the application with the worker's full executable path.
The worker discovers its data beside itself; exporting `RML` is unnecessary for
the assembled layout. An explicit `RML` environment value overrides discovery.

Use an already downloaded, exact pinned checkout without fetching:

```sh
python3 packages/quds_proofing_aot/tool/build_native.py \
  --source /absolute/path/to/aot \
  --build-dir /absolute/path/to/build-cache \
  --install /absolute/path/to/runtime
```

The source checkout must have its `Source/nlp_base` submodule initialized. The
script verifies both commit IDs and rejects modifications to tracked source
files. Upstream dictionary generators create ignored output files inside that
checkout. CMake 3.24+, a C++17 compiler, flex plus its `FlexLexer.h` header, bison
and zlib development files are required. Nonstandard tool locations can use
`PATH`, `CMAKE_INCLUDE_PATH` and normal CMake discovery variables.

Linux x86-64 has been built and exercised locally. The source includes macOS and
Windows executable-path discovery and CMake tool names, but those native builds
require platform validation before distribution. Browser builds cannot spawn
this executable; hosts can use the separately configured HTTP backend there.

## Verify the installed runtime

```sh
.dart_tool/quds_aot_native/runtime/Bin/quds_aot_worker --version
python3 packages/quds_proofing_aot/tool/smoke_native.py \
  --executable .dart_tool/quds_aot_native/runtime/Bin/quds_aot_worker
```

The JSON `manifest.json` records exact source revisions, executable and build
source hashes, both upstream patches, and real-engine smoke results. `smoke.json`
contains the same finite test evidence separately. These checks establish local
operation and bounded protocol behavior; they do not measure general grammar
accuracy or performance on every platform.

## Protocol 1

Request fields are `id` (a nonnegative integer no larger than 2^53−1), `action`
(`syntax` or `morph`), `langua` (`German`, `Russian` or `English`), `query` (UTF-8
JSON text) and optional boolean `withparadigms`. English syntax is unsupported.

```json
{"id":1,"action":"syntax","langua":"German","query":"Ich geht."}
{"id":2,"action":"morph","langua":"German","query":"gehen","withparadigms":true}
```

Success returns `{"id":1,"result":...}` with the existing AOT JSON value
embedded directly. An error returns `{"id":1,"code":"...","error":"..."}`.
Messages are fixed and do not include document text or raw engine diagnostics.
Invalid JSON, duplicate keys, incorrect field types, unsupported languages and
size limits are rejected explicitly. Requests are processed in order. Loading
failures terminate the worker after its error response, avoiding reuse of
partially initialized global upstream state.

Each input line is bounded to 256 KiB, each query to 32,768 UTF-16 code units, and
each response to 4 MiB. The Dart transport additionally enforces admission,
deadline, output-stream and lifecycle bounds. Upstream dictionaries load lazily
once per requested language for the lifetime of the process.

### Exact native source metadata

Syntax words may add `sourceStart`, `sourceEnd` (original UTF-16 offsets) and
`sourceText`, while `str` retains the analyzer's potentially normalized surface.
The worker maps retained native offsets through the pinned engine's one-byte-per-
Unicode-scalar conversion and verifies every token against an original graphan
snapshot and the untouched input. Only whitespace may separate verified tokens.

The German transformation `zu helfen` → `zu-helfen` is mapped only when the
original `zu` and `helfen` tokens, their exact source positions and the engine's
explicit infinitive reading all agree. If the serializer retains a separate
`zu` token, it keeps its own span and `zu-helfen` maps to the original `helfen`.
If the prefix is omitted, the verified contiguous pair may own `zu helfen`.
Source text is preserved, including intervening whitespace. Other transformations, missing tokens and unsupported
characters cause metadata to stop at the uncertain position. No prefix is
blindly removed and no source location is guessed. Dart independently validates
the exact substring, ordering and grapheme boundaries before using the metadata.

## Document privacy and licenses

The upstream engine can print words in diagnostic messages. The worker isolates
protocol stdout and suppresses those diagnostics. The headless build removes
one unconditional upstream `input.lem` write in an exact, validated generated
copy of `Parser.cpp`; the original pinned checkout remains unchanged. The
native smoke checks that analysis creates no working-directory files. A second
exact build-copy patch makes syntax group descriptions own their JSON strings,
preventing dangling references when temporary per-clause groups are destroyed.

The separately built engine and language data retain their upstream licenses.
Read [NOTICE.md](NOTICE.md) before redistributing a runtime. The repository stores
the reproducible wrapper/build sources, not generated engine binaries or data.
