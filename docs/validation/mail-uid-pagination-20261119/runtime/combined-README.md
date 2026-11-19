# Combined Mail, Arabic and Hunspell runtime preparation

The existing verified Flutter 3.47.8 / Dart 3.13.7 SDK and 176-package download
cache were reused. No SDK or dependency version was replaced. Offline enforced
workspace resolution now verifies 132 package names after adding the Hunspell
workspace member. The original [runtime receipt](runtime.json) and original
[restoration archive](restore-evidence.tar.xz) remain unchanged.

This is preparation for a fresh combined gate. It does not retroactively extend
the earlier qualification at `960fb72f` to the incoming implementation.

## Additional verified inputs

| Input | Identity or result |
| --- | --- |
| CMake | 3.31.10, isolated wheel installation; executable version checked |
| CMake wheel | 27,808,794 bytes; SHA-256 `2f766bb46367e5e0559fa33184653754bce044583a06014dcaebf8e6dff8a1f1`, matched official PyPI release metadata before extraction/execution |
| Native compiler | Debian g++ 14.2.0-19; executable SHA-256 recorded |
| Hunspell source archive | 1.7.2, 1,536,202 bytes; SHA-256 `11ddfa39afe28c28539fe65fc4f1592d410c1e9b6dd7d8a91ca25d85e9ec65b8` |
| Compiled component inputs | All 28 source/header members match the checked-in license manifest |
| Actual native backend | Built by checked-in `tool/build.py --native`; SHA-256 `648084ab2ea47b23da91c8e865cc8e2523322eb87d9fb921e4568dd3092e9338` |
| AyaSpell dictionary | All eight catalog files at immutable revision `e9ace7cca3844bef906d8d9fc5431c4e15bd2740`; 7,332,691 bytes in total, each length and SHA-256 verified |
| Native lifecycle fixture | Separately compiled deterministic C ABI fixture; SHA-256 `56e553c3e89f6d74e3d71e105e85c4473a7dd9e4cbf2f5f3821b1f4362f5c9b6` |

The real Hunspell build preserved all 29 captured package inputs. The native
lifecycle fixture is separate from the production backend and exists to observe
native ownership, pending-work shutdown and close counts through real Dart FFI
and isolate boundaries. It does not replace the actual backend/dictionary tests.

The first CMake metadata lookup requested version 3.31.8, which PyPI did not
publish. It failed before downloading or executing a wheel. Official metadata
then identified 3.31.10; that pinned wheel was verified and executed. Both logs
remain distinctly labelled in the preparation archive.

## Runtime binding and execution environment

The [augmented receipt](combined-runtime.json) binds the unchanged 11,142 SDK and
hosted-package records plus 24 additional native, Node, dictionary, compiler,
tool and provenance files. Its source preparation records remain separate from
the final qualified source commit.

The driver derives these variables from that hash-bound receipt and refuses a
missing library, incomplete dictionary binding or disabled live-download test:

```text
QUDS_HUNSPELL_TEST_LIBRARY=<built native backend>
QUDS_HUNSPELL_TEST_DICTIONARY=<verified eight-file dictionary directory>
QUDS_HUNSPELL_LIFECYCLE_LIBRARY=<built deterministic lifecycle fixture>
QUDS_HUNSPELL_LIVE_DOWNLOAD=1
```

The native suite therefore exercises the actual backend, local installer tests
and a genuine download from the immutable public Hugging Face revision. It
cannot silently pass by skipping those tests. The Node provider test uses its
explicit scripted transport. The separate Dart web-entry compilation and
`node --check` of the worker establish compilation/syntax only; neither runs an
actual browser Worker or Wasm backend. No live Mail account is used.

## Verbatim upstream license notices

The checked-in `COPYING.MPL`, `license.hunspell` and `license.myspell` notices
preserve the upstream release's trailing spaces and final blank line. The
[notice verification](upstream-notice-preservation.json) records each file's
SHA-256 and Git blob identity, verified byte for byte against both the pinned
Hunspell 1.7.2 archive and the checked-in license manifest. Both gate plans name
only these three exact files. The shared runner accepts only their fixed blob
identities outside captured validation evidence, so a changed notice or any
other package path remains subject to the whitespace gate. Three new offline
controls cover accepted pins, changed pins and arbitrary package paths.

## Reproduction and retained evidence

Use the original runtime restoration instructions for a new machine, then run
offline lock enforcement after selecting the combined source. Prepare CMake
from the recorded release wheel and verify the dictionary against the current
catalog before invoking the checked-in native builder:

```bash
python3 packages/quds_proofing_hunspell/tool/build.py --native --jobs 2 \
  --output /absolute/path/to/runtime/hunspell/build
g++ -std=c++14 -shared -fPIC -pthread \
  -o /absolute/path/to/runtime/hunspell/lifecycle/libquds_hunspell_lifecycle.so \
  packages/quds_proofing_hunspell/test/fixtures/lifecycle_hunspell.cpp
```

Retain the compiler/tool, dictionary, build and lifecycle receipts in the layout
shown in the augmented receipt. The [refresh helper](refresh_runtime.py) checks
those prepared inputs and the authoritative package graph, preserves the prior
runtime receipt, and writes the augmented binding. It performs no download or
installation itself.

The [preparation archive](combined-preparation.tar.xz) contains original logs,
source snapshots, compiler/tool metadata, build receipts, the two native
libraries and the session preparation script. That script records this
session's absolute paths and is provenance, not a claim of an independently
executed portable installer. The [member index](combined-preparation.index.json)
records every member's size and SHA-256. SDK binaries, the CMake wheel and the
dictionary bytes are not duplicated in this archive; their immutable source
URLs, lengths and hashes are retained.
