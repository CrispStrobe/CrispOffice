# Harper local validation after recovery

The resumed source passed all eight command groups in `receipt.json`. No
GitHub Actions result is used by this record. The source and generated-file
SHA-256 maps in that receipt and `build-receipt.json` identify exactly what was
checked; the commands reject changed source or changed built assets before and
after execution.

| Check | Observed result |
| --- | --- |
| Rust release unit tests | 5 passed; the empty doctest phase also completed |
| Dart static analysis | Passed with `--fatal-infos`, no issues |
| Dart VM tests with actual native library | 10 passed, no skipped native integration |
| Dart adapter tests compiled to JavaScript and run with Node | 7 passed |
| Exact shipped module worker and real Wasm | 5 integration checks passed |
| Compiled Dart web transport through the shipped worker and real Wasm | 8 checks passed; all 3 created workers terminated |
| License regression tests | 3 tests passed, covering permitted alternatives, forbidden/malformed terms and stale original-notice provenance |
| Audited distribution records | 226 packages, 3 original MPL source archives, byte-verified notices and source members |
| Host installation | Native and web files, notices and build receipts copied byte for byte; an unlisted stale output file was excluded |

The native tests include simultaneous requests with independent ignored rules,
source UTF-16 offsets after an emoji, missing-library availability, and disposal
while the isolate starts. The web-transport checks exercise the actual compiled
Dart adapter rather than only a replacement transport. Its Node harness supplies
browser-compatible Worker messaging and local file fetch only.

## Reproduce

Install the package's pinned Rust toolchain and matching `wasm-bindgen` CLI,
resolve the Dart workspace with the repository's Flutter version, then run from
the repository root:

```sh
python3 packages/quds_proofing_harper/tool/build.py --native --web
python3 packages/quds_proofing_harper/tool/verify.py \
  --output /path/to/harper-validation
```

Use the build helper's `--install-web` and `--install-native` options when
packaging an opted-in host. Each destination receives the license manifest,
original notices and MPL source archive, and source-bound build receipt.

The concrete commands, working directories, output hashes and elapsed times
are in `receipt.json`. `environment.json` records the executables' versions.
The initial native build's tests passed but its doctest runner could not create
a directory under this environment's absent `/tmp`; the recorded successful
run uses a writable scratch `TMPDIR` and includes the doctest phase.

## Remaining acceptance boundary

Local Chromium aborted before loading any page because its process singleton
could not create a socket in this environment (exit 134). The diagnostic is
preserved in `chromium-probe.log` and `chromium-probe.json`. These results
therefore establish the real native and Wasm engines, both Dart adapters,
worker lifecycle and distribution packaging. They do not establish browser
CSP/HTTP hosting or non-Linux native hosts. Mobile platform spelling is a
separate optional editor provider and is not credited to this suite.
