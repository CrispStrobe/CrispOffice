# enough_mail fork local verification

Date: 2026-11-18. Runtime: checksum-verified official Flutter 3.47.8 / Dart 3.13.7,
Linux x64. Dependency resolution uses the Quds root workspace lock, with
`test` 1.31.1. `receipt.json` records identities and log digests.

| Check | Actual result |
| --- | --- |
| `dart analyze lib --fatal-infos` | PASS, no issues; includes the old native API source |
| Focused native MIME/codec/builder/account regressions | PASS, 168 tests across 14 files |
| Public `mime_core.dart` JavaScript compilation | PASS |
| Original fixture projected in native Dart and Node JS | PASS, identical JSON |
| Chromium runtime tests | BLOCKED before fixture execution by executor sandbox socket policy |

Seven fork-specific tests cover portable fixture parsing, redacted diagnostics,
concurrent diagnostic scope isolation, strict charset failures, explicit
unsupported CJK encodings and RFC 2231 multibyte continuation/error behavior.
The remaining tests exercise existing upstream parsing, header handling,
transfer codecs, message building and account settings affected by the fork.

These results are specific to the source hashes in `PORTABLE_CLOSURE.json` and
the preserved log files. They are not existing Office-suite totals, generic
socket/browser support, HTML rendering qualification or App Store evidence.
No GitHub Actions job was awaited or used for these results.

## Reproduction

Resolve the **root workspace** using the repository's Flutter pin. Run from
`third_party/enough_mail` for upstream tests: its native builder fixtures use
paths relative to that directory. Select the root workspace package config so
that the same lock is used. A separate `pub get` in the fork is unnecessary.

The verified test file list is:

```text
test/quds_portable_mime_test.dart
test/mime_message_test.dart
test/mime_robustness_test.dart
test/mime_boundary_test.dart
test/mime_bare_lf_test.dart
test/folding_test.dart
test/header_injection_test.dart
test/remove_header_test.dart
test/mail_address_parser_test.dart
test/codecs/base64_mail_codec_test.dart
test/codecs/quoted_printable_mail_codec_test.dart
test/codecs/mail_codec_test.dart
test/message_builder_test.dart
test/mail/mail_account_test.dart
```

The execution used the resolved `test` package's `bin/test.dart` with
`dart --packages=<root>/.dart_tool/package_config.json`, the paths above and
`--reporter expanded`. This avoids resolving the upstream development tool
graph separately from the Quds workspace.

Compile `tool/portable_smoke.dart` with `dart compile js`, using that same
package config. Execute the source in native Dart and the compiled output in
Node; compare the JSON projections. `portable_js_compile.log`,
`portable_native.json` and `portable_node.json` retain the actual output.

The first Chromium attempt exited before tests because the sandbox denied the
browser's process-singleton socket. `browser_attempt.log` retains that observed
failure. Actual browser tests and runtime network observation remain required
in an environment that can launch the browser; the passing Node projection is
reported separately. No sandbox permissions were widened.
