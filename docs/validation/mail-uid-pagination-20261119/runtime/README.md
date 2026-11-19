# Fresh local runtime

The checked-in Notes-review runtime restorer completed successfully with
`--node-tests` on 19 November 2026. The full official SDK stream was verified
before any extracted executable was invoked. This is fresh environment
preparation, not a new product acceptance run.

| Input/check | Observed result |
| --- | --- |
| Flutter | 3.47.8, framework `737ba8f885dc774b53b442759999a312c9461e4e` |
| Dart | 3.13.7 |
| Full SDK archive | 1,581,444,364 bytes; SHA-256 `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2` |
| Retained SDK selection | 551,242,378 bytes, including Dart-to-JavaScript compiler |
| Hosted package archives | 176 verified against the pinned dependency locks |
| Flutter tools and workspace resolution | Offline enforced lock checks passed |
| Workspace package identities | 131 resolved names match authoritative workspace/lock inputs |
| SQLite native hook | 3.54.1; in-memory FTS5 round trip passed |
| Node | v24.22.3, bound by executable SHA-256 |
| Retained SDK/dependency inputs | 11,142 |
| Restorer tooling controls | 16 passed |

The [runtime receipt](runtime.json) records exact command, executable and library
identities and session-local paths. Its SHA-256 is
`dce4d5fec2c7bfabdc6d9298327a098bb3418486b37316881a9802a8a0d0fa20`.
The unchanged workspace lock SHA-256 is
`35d1ef372908f4ab278973355ec6a957cd3240bea115d615056c5b9e398df974`.

The [restoration archive](restore-evidence.tar.xz) retains the original logs,
receipt, selected/omitted input manifests, verified hosted archive receipt,
environment setup and restorer-control output. Every member is listed with its
size and SHA-256 in the [archive index](restore-evidence.index.json). It contains
no SDK or dependency binaries. Reproduction creates a new receipt for the new
machine; the original session receipt remains historical evidence.

This selected SDK supports local VM Flutter tests, AOT analysis and Dart-to-JavaScript
Node tests. It omits the complete native and Flutter web build toolchains.
