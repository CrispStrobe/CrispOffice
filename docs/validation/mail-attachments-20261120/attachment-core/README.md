# Independent Studio attachment MIME probe

This is a new, reproducible qualification of the combined product source. It
does not recreate or claim credit for an unpublished historical run.

## Result

`run-01` passed on 20 November 2026 using Dart 3.13.7 and the repository's resolved
locked dependencies. Its local source commit was
`75083ea738d08be3eb9a3d983ac80a7f05a6201b`, tree
`6aff53dc9b5e2c29854ad05703038c7362fdcc1f`. All 191 recorded source/configuration/
probe inputs were identical before and after execution.

The identical complete tree was published as remote checkpoint
[`2c3479838721632167933eb99b78beaac285e862`](https://github.com/CrispStrobe/quds_office_suite/commit/2c3479838721632167933eb99b78beaac285e862).
The [publication ledger](../resumed/publication-checkpoints.json) records this
local-to-remote mapping; the final source audit checks the relevant inputs again
after later unrelated Office integration.

The production `buildStudioMailMessage` function created each message. The
production `QudsMimeCodec` recovered the body and exact attachment hashes, and
an independent receiver using Python 3.12.14's `email.parser.BytesParser`
verified every MIME part and original fixture byte. Both receivers passed all
three scenarios. The Python parser reported no defects.

| Scenario | Coverage | Canonical message bytes |
| --- | --- | ---: |
| Unicode and binary | Unicode/Arabic/emoji, quotes, semicolon and percent in filenames; a 255-byte filename; binary and opaque text bytes; empty files; duplicate filenames; body whitespace and newline normalization | 9,716 |
| Plain control | Existing multipart/alternative shape without attachments, escaped HTML and Unicode body | 865 |
| Maximum bound | Ten files totaling exactly 10 MiB and a 1 MiB body consisting entirely of quotes, with 6,291,463 bytes of escaped HTML | 21,986,572 |

Every scenario checks visible From/To/Cc, absent canonical Bcc, the retained
hidden recipient in the separate submission envelope, and exact reply headers.
It also checks ASCII wire bytes, CRLF line endings, the 998-byte line ceiling,
76-column quoted-printable lines, declared attachment sizes, base64 transfer
encoding, no guessed attachment charset, and owned snapshots after mutation of
the caller's source byte arrays.

The maximum case is below the 22 MiB canonical wire guard (23,068,672 bytes).
Its exact outer-base64 size is 29,315,432 bytes, below the 32 MiB default cloud
request budget (33,554,432 bytes). The receiver report also gives a separate
29,316,492-byte estimate after adding this fixture's private Bcc header and a
1 KiB request-wrapper allowance. That field is a sizing estimate, not a
captured provider HTTP request or a proof for every possible wrapper/recipient
combination. Full provider behavior belongs to the transport and host suites.

## Reproduce

Use the repository's pinned runtime and its actual, already resolved workspace
package configuration. The script performs no dependency resolution, network
request, or message submission.

```bash
python run_probe.py \
  --repo /path/to/quds_office_suite \
  --dart /path/to/pinned/dart \
  --output /path/to/new-run-directory
```

The driver generates deterministic synthetic fixtures, runs the adjacent Dart
probe against the production packages, verifies the generated EML independently,
and saves source hashes, command lines, versions, logs and receiver receipts.
Choose a fresh output directory to preserve earlier runs. The generated EML
contains nondeterministic message IDs/dates/boundaries; payload and body hashes
are deterministic, while the receipt records each actual message's hash.

`run-01.tar.gz` retains the raw accepted run, including synthetic input bytes and
the complete generated EML. `run-01.index.json` records every archived file's
length and SHA-256 plus the archive digest. The readable scripts and receipts
can be retained separately without committing uncompressed large fixtures.

This qualifies local serialization, decoding and sizing. It does not establish
live delivery, real mailbox privacy, native picker interoperability, installed
Office compatibility, durable drafts, or background sending.
