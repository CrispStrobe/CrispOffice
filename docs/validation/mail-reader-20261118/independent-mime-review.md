# Independent MIME implementation review

Date: 2026-11-18. The review examined the new `quds_mail_mime` reader separately
from its implementation, plus the portable `enough_mail` entry and the strict
decoding behaviour it exposes. All reproductions use independently authored,
synthetic messages. No private mailbox data or CrispCloud source was used.

## Findings and corrections

| Finding | Observed behaviour before correction | Correction and regression coverage |
| --- | --- | --- |
| Valid RFC 2047 Q word rejected when its first byte is escaped | `Subject: =?utf-8?Q?=E2=82=AC?=` returned a partial result and an empty subject. The encoded-word end search matched the `?=` spanning the encoding separator and first escape. | The scanner locates the charset and encoding separators before searching for the closing delimiter. The facade regression verifies the subject is `€` with no diagnostic. |
| Rendered text quota reset for each MIME part | Two Latin-1 alternatives, each containing `=E9=E9`, projected four UTF-8 bytes apiece. A six-byte message render limit accepted both because the counter was local to each part. | Rendered text accounting belongs to the reader operation. The focused regression rejects the combined eight bytes under a seven-byte limit; the independent six-byte reproduction is also rejected. |
| Invalid dates normalized into different valid instants | February 31 became March 3; an hour value of 99 advanced the date by four days. Both were exposed as complete parses with apparently valid timestamps. | The fork validates calendar days, clock components, numeric timezone digits/ranges and an optional weekday before constructing `DateTime`. Invalid values emit `invalidDate`; the facade leaves the timestamp absent and retains the original message. |
| Undefined single-byte charset entries replaced silently | Windows-1252 byte `0x81` became `?` with a complete parse, despite using the dependency's `allowInvalid: false` option. Its lookup table stores replacement placeholders independently of that option. | The strict fork helper rejects undefined non-ASCII table slots with `malformedCharacterData` and `null`. The facade exposes a partial result with `malformedEncoding` and no fabricated body. Focused tests cover Windows-1252, Windows-1253 and ISO-8859-3; a real ASCII `?` remains valid. |

Facade corrections and their two dedicated tests are in
[`mime_review_regressions_test.dart`](../../../packages/quds_mail_mime/test/mime_review_regressions_test.dart).
Date and charset corrections, including signed/hexadecimal numeric components
and malformed timezone components,
are covered in
[`quds_portable_mime_test.dart`](../../../third_party/enough_mail/test/quds_portable_mime_test.dart).
The fork's exact changes and provenance are documented in
[`QUDS_PATCHES.md`](../../../third_party/enough_mail/QUDS_PATCHES.md).

The date policy also treats leap-second values as unsupported rather than
silently normalizing them: Dart cannot represent a leap second exactly. A
missing timezone retains the upstream helper's UTC fallback with an
`invalidDate` diagnostic, allowing the facade to suppress an uncertain
timestamp. A valid leap day with a nonzero numeric timezone remains covered.

## Independent reproduction after correction

A direct Dart probe passed the same five cases through the public
`QudsMimeCodec.parse` API after both facade and fork changes:

| Case | Parse status | Projected field | Diagnostic |
| --- | --- | --- | --- |
| Leading Q escape | `complete` | subject `€` | none |
| February 31 | `partial` | timestamp absent; plain body retained | `invalidDate` |
| Hour 99 | `partial` | timestamp absent; plain body retained | `invalidDate` |
| Undefined Windows-1252 byte | `partial` | plain and HTML bodies absent | `malformedEncoding` |
| Two four-byte alternatives under a six-byte render limit | `rejected` | message projection absent | `renderLimit` |

## Boundaries examined

The review followed byte ownership and allocation order through `codec.dart`,
`scan.dart` and `transfer.dart`. The raw-byte budget is checked before creating
the reader's immutable source snapshot. Header size and cumulative header
budgets are checked before passing bounded header blocks to the upstream
parser. Part count, nesting depth, decoded bytes, attachment bytes and render
bytes have separate counters. The corrected render counter is cumulative
across the operation.

Identity-encoded attachment bodies use the original byte ranges instead of
the upstream helper that removes CRLF pairs. Multipart framing removes the
boundary's framing newline without rewriting the remaining payload. Nested
`message/rfc822` bodies remain opaque attachments in this first reader slice,
so they do not enter an unbounded recursive MIME parser. The transfer decoder
checks Base64 alphabet, padding and unused bits before decoding; malformed or
unsupported text encodings produce diagnostics instead of an exact-looking
replacement body.

The selected portable source closure contains 21 local files and 87 files in
total. Its Dart SDK imports are `async`, `collection`, `convert`, `math` and
`typed_data`; it contains no `dart:io` or native protocol-client import. The
30 selected `enough_convert` files are restricted to the reviewed
Latin/Windows/KOI8 entries and shared code. GBK, GB2312, GB18030 and Big5 are
explicitly unsupported pending their separate donor-source review. Static
closure inspection establishes this source boundary; it does not establish
that an application made no runtime network requests.

## Verification and remaining gates

The corrected fork passed **170 native tests across 14 files** and
`dart analyze lib --fatal-infos` with no issues using checksum-verified
Flutter 3.47.8 / Dart 3.13.7. Its public portable entry compiled to JavaScript,
and the original fixture produced identical JSON in native Dart and Node.
The exact source closure, compiler output, test output and digests are retained
in the fork's
[`verification` directory](../../../third_party/enough_mail/verification/README.md).
The two dedicated facade regressions also passed locally. Full facade and UI
suite results are recorded in their own validation receipts.

Chromium did not execute the fixture: the executor denied its process
singleton socket before tests could start. The blocked attempt is preserved
separately from the passing Node projection. Actual browser execution and
runtime observation of network activity remain qualification gates. Native
protocol logging, live account operations, HTML rendering and sanitizer
behaviour were outside this source review. No GitHub Actions result or product
release approval is inferred from these checks.
